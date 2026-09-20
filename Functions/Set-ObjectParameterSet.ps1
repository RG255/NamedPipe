Function Set-ObjectParameterSet
{
	<#
			.SYNOPSIS
			This function enables easy initialisation of the datasets that are required to make
			use of this module. The calling script may or may not have parameters that define what
			attrributes will be required for the pipe. These must be passed in order to define the correct
			attrribute values where appropriate. ALternativly the caller may define the attributes within their
			own script before initiating the pipe server or client

			.PARAMETER MyParameters
			-MyParameters

			This parameter is optional

			$PSCmdlet.MyInvocation.BoundParameters will pass the currently bound paramters.
			If any of these are required then their value will be preserved when the data structure is initialised

			.PARAMETER Dataset
			-Dataset One of 'PipeParams', 'DataObject','ServerClientParams','SendRequestParams','PipeInfo'.

			.EXAMPLE
			Set-ObjectParameterSet -MyParameters Value -Dataset Value
			Sets up the requested dataset

			.OUTPUTS
			The initialised dataset requested.
	#>

	[cmdletbinding(DefaultParameterSetName = 'Either')]
	Param(
		[Parameter(Mandatory,ParameterSetName = 'Server',HelpMessage = 'Please state the dataset to initialise')]
		[Parameter(Mandatory,ParameterSetName = 'Client',HelpMessage = 'Please state the dataset to initialise')]
		[Parameter(Mandatory,ParameterSetName = 'Either',HelpMessage = 'Please state the dataset to initialise')]
		[validateset('PipeParams', 'DataObject','ServerClientParams','SendRequestParams','PipeInfo','MyOptions')]
		[validatescript({
				$_ -imatch $StrPipeParams -or
				$_ -imatch $StrDataObject -or
				$_ -imatch $StrMyOptions -or
				$_ -imatch $StrServerClientParams -or
				$_ -imatch $StrSendRequestParams -or
				$_ -imatch $StrPipeInfo
			})]
		[String]$Dataset,
		[Parameter(ParameterSetName = 'Server')]
		[Parameter(ParameterSetName = 'Client')]
		[Parameter(ParameterSetName = 'Either')]
		[PSCustomObject]$MyParameters = $Null,
		[Parameter(ParameterSetName = 'Server')]
		[Switch]$Server,
		[Parameter(ParameterSetName = 'Client')]
		[Switch]$Client
	)
	If (1 -band ($env:MyFunctionTraceEnabled -as [Int])) { Write-MyFunctionTrace }

	# 2026-09-15: wrapped in Try/Catch - this function had NO error handling anywhere despite being
	# called by nearly everything (Start-PipeSession, Start-PipeServerOrClient, Send-ProgressInfo,
	# itself recursively). A real path exists: the ServerClientParams/Server branch pipes
	# -AccessIdentifier straight into Test-AccessIdentifier, which throws on an invalid identity/access
	# string, with nothing anywhere in the call chain to catch it. Per the user's own stated principle
	# (2026-09-15): never assume a caller's input/environment is correctly configured, and always catch
	# - even a catch that only reaches Write-MyCatchAudit and re-throws makes an otherwise-invisible
	# failure trackable. Re-throwing (not swallowing) preserves this function's existing behavior for
	# any caller already handling its exceptions - this only ADDS an audit trail, not new error hiding.
	Try
	{

		Switch ($Dataset)
		{
			$StrPipeParams
			{
				[Ordered]@{
					Options         = [IO.Pipes.PipeOptions]::Asynchronous -bor [int][IO.Pipes.PipeOptions]::WriteThrough
					Direction       = [IO.Pipes.PipeDirection]::InOut
					Mode            = [IO.Pipes.PipeTransmissionMode]::Byte
					Instances       = [int]1
					PipeServer      = '.'
					PipeBufferSizeS = [Int]65536  # 64KB - sized to accommodate 32KB chunks with Base64 overhead
					PipeBufferSizeR = [Int]65536  # 64KB - sized to accommodate 32KB chunks with Base64 overhead
				}
			}
			$StrMyOptions
			{
				[Ordered]@{
					$StrAdminRequired = if ($MyParameters.$StrAdminRequired)
					{$True}
					Else
					{$False}
					$StrInfoDisplay = if ($null -ne $MyParameters.$StrInfoDisplay)
					{[int]$MyParameters.$StrInfoDisplay}
					Else
					{[int]0}
					$StrWait = if ($MyParameters.$StrWait)
					{$True}
					Else
					{$False}
					$StrVerbose = if ($MyParameters.$StrVerbose)
					{$True}
					Else
					{$False}
					$StrNoExitOnError = if ($MyParameters.$StrNoExitOnError)
					{$True}
					Else
					{$False}
					$StrWindowStyle = if ($MyParameters.$StrWindowStyle-imatch $StrWindowStyleList)
					{$MyParameters.$StrWindowStyle}
					Else
					{$StrMinimized}
					$StrChunkSize = if ($MyParameters.$StrChunkSize)
					{[int]$MyParameters.$StrChunkSize}
					Else
					{[int]32768}  # Default 32KB chunk size for automatic chunking
					$StrDepth = if ($null -ne $MyParameters.$StrDepth)
					{[int]$MyParameters.$StrDepth}
					Else
					{[int]2}  # Default depth 2 (safe for ACL objects)
					$StrClientConnectTimeout = if ($null -ne $MyParameters.$StrClientConnectTimeout)
					{[int]$MyParameters.$StrClientConnectTimeout}
					Else
					{[int]10000}  # Default time 10000
					$StrServerWaitTimeout = if ($null -ne $MyParameters.$StrServerWaitTimeout)
					{[int]$MyParameters.$StrServerWaitTimeout}
					Else
					{[int]60}  # Default time 60
					$StrChunkReadTimeout = if ($null -ne $MyParameters.$StrChunkReadTimeout)
					{[int]$MyParameters.$StrChunkReadTimeout}
					Else
					{[int]30000}  # Default 30s - see DefineVariablesPipe.ps1 for why only the CHUNK-CONTINUATION read is bounded
					# 2026-09-19 unification: these four used to be absent here and set ONLY via the
					# Server/Client case below (which reads $MyParameters directly, or via Start-PipeSession's
					# -Options merge onto an already-built MyOptions object) - a caller passing one of these
					# through their OWN bound -MyParameters straight into THIS ($StrMyOptions) dataset call
					# would see it silently vanish before the Server/Client build ever ran, since this case's
					# returned object had no property for it to fall back on. Added so all four round-trip
					# through MyOptions the same way InfoDisplay/Depth/etc. already do, regardless of which of
					# the two supported paths (-Options merge, or raw -MyParameters) a caller uses. Defaults
					# match the Server/Client case's own fallback exactly - see those blocks below.
					$StrModuleToLoad = if ($MyParameters.$StrModuleToLoad)
					{ $MyParameters.$StrModuleToLoad }
					Else
					{ $script:DefaultModuleToLoad }
					$StrRedactPattern = if ($MyParameters.$StrRedactPattern)
					{ $MyParameters.$StrRedactPattern }
					Else
					{ $null }
					$StrRedactPotentialSecrets = if ($null -ne $MyParameters.$StrRedactPotentialSecrets)
					{ [bool]$MyParameters.$StrRedactPotentialSecrets }
					Else
					{ $true }
					$StrRequestPolicy = if ($MyParameters.$StrRequestPolicy)
					{ $MyParameters.$StrRequestPolicy }
					Else
					{ $null }
				}
			}
			$StrServerClientParams
			{
				if ($Server)
				{
					[Ordered]@{
						$StrServer = $True
						$StrClient = $False
						$StrPipeName = if ($MyParameters.$StrPipeName)
						{$MyParameters.$StrPipeName}
						Else
						{($pn = Get-NewPipeName)}
						$StrPipeInfo = Set-ObjectParameterSet -Dataset $StrPipeInfo -MyParameters $MyParameters -Server
						$StrPipeParams = Set-ObjectParameterSet -Dataset $StrPipeParams -MyParameters $MyParameters
						$StrAccessIdentifier = if ($MyParameters.$StrAccessIdentifier)
						{$MyParameters.$StrAccessIdentifier| Test-AccessIdentifier}
						Elseif ($Accesslist)
						{$Accesslist | Test-AccessIdentifier}
						else
						{('{0}:Allow:ReadWrite' -f [Security.Principal.WindowsIdentity]::GetCurrent().Name) | Test-AccessIdentifier}
						$StrWindowStyle = if ($MyParameters.$StrWindowStyle -imatch $StrWindowStyleList)
						{$MyParameters.$StrWindowStyle}
						Elseif ($MyOptions.$StrWindowStyle -imatch $StrWindowStyleList)
						{$MyOptions.$StrWindowStyle}
						Else
						{$StrMinimized}
						$StrSpawned = if ($MyParameters.$StrSpawned)
						{$True}
						Else
						{$False}
						$StrAdminRequired = if ($MyParameters.$StrAdminRequired -or $MyOptions.$StrAdminRequired)
						{$True}
						Else
						{$False}
						$StrInfoDisplay = if ($null -ne $MyParameters.$StrInfoDisplay)
						{[int]$MyParameters.$StrInfoDisplay}
						Elseif ($null -ne $MyOptions.$StrInfoDisplay)
						{[int]$MyOptions.$StrInfoDisplay}
						Else
						{[int]0}
						$StrWait = if ($MyParameters.$StrWait -or $MyOptions.$StrWait)
						{$True}
						Else
						{$False}
						$StrVerbose = if ($MyParameters.$StrVerbose -or $MyOptions.$StrVerbose)
						{$True}
						Else
						{$False}
						$StrNoExitOnError = if ($MyParameters.$StrNoExitOnError -or $MyOptions.$StrNoExitOnError)
						{$True}
						Else
						{$False}
						$StrChunkSize = if ($MyParameters.$StrChunkSize)
						{[int]$MyParameters.$StrChunkSize}
						Elseif ($MyOptions.$StrChunkSize)
						{[int]$MyOptions.$StrChunkSize}
						Else
						{[int]32768}  # Default 32KB chunk size
						$StrDepth = if ($null -ne $MyParameters.$StrDepth)
						{[int]$MyParameters.$StrDepth}
						Elseif ($null -ne $MyOptions.$StrDepth)
						{[int]$MyOptions.$StrDepth}
						Else
						{[int]2}  # Default depth 2 (safe for ACL objects)
						$StrClientConnectTimeout = if ($null -ne $MyParameters.$StrClientConnectTimeout)
						{[int]$MyParameters.$StrClientConnectTimeout}
						Elseif ($null -ne $MyOptions.$StrClientConnectTimeout)
						{[int]$MyOptions.$StrClientConnectTimeout}
						Else
						{[int]10000}  # Default time 10000
						$StrServerWaitTimeout = if ($null -ne $MyParameters.$StrServerWaitTimeout)
						{[int]$MyParameters.$StrServerWaitTimeout}
						Elseif ($null -ne $MyOptions.$StrServerWaitTimeout)
						{[int]$MyOptions.$StrServerWaitTimeout}
						Else
						{[int]60}  # Default time 60
						$StrChunkReadTimeout = if ($null -ne $MyParameters.$StrChunkReadTimeout)
						{[int]$MyParameters.$StrChunkReadTimeout}
						Elseif ($null -ne $MyOptions.$StrChunkReadTimeout)
						{[int]$MyOptions.$StrChunkReadTimeout}
						Else
						{[int]30000}  # Default 30s - see DefineVariablesPipe.ps1 for why only the CHUNK-CONTINUATION read is bounded
						$StrModuleToLoad = if ($MyParameters.$StrModuleToLoad)
						{ $MyParameters.$StrModuleToLoad }
						Elseif ($MyOptions.$StrModuleToLoad)
						{ $MyOptions.$StrModuleToLoad }
						Else
						{ $script:DefaultModuleToLoad }
						$StrRedactPattern = if ($MyParameters.$StrRedactPattern)
						{ $MyParameters.$StrRedactPattern }
						Elseif ($MyOptions.$StrRedactPattern)
						{ $MyOptions.$StrRedactPattern }
						Else
						{ $null }
						# 0.15: default $true when unset - see this constant's own Use text
						# (DefineVariablesPipe.ps1) and USERGUIDE.md for the full reasoning.
						$StrRedactPotentialSecrets = if ($null -ne $MyParameters.$StrRedactPotentialSecrets)
						{ [bool]$MyParameters.$StrRedactPotentialSecrets }
						Elseif ($null -ne $MyOptions.$StrRedactPotentialSecrets)
						{ [bool]$MyOptions.$StrRedactPotentialSecrets }
						Else
						{ $true }
						$StrRequestPolicy = if ($MyParameters.$StrRequestPolicy)
						{ $MyParameters.$StrRequestPolicy }
						Elseif ($MyOptions.$StrRequestPolicy)
						{ $MyOptions.$StrRequestPolicy }
						Else
						{ $null }
						# 0.11 hardening (4.2): capability nonce. Generated ONCE here at server-build time.
						# The client build (Set-ObjectParameterSet -Client, built FROM this ServerClientParams)
						# inherits the SAME value via $MyParameters.$StrNonce, so both ends share one secret.
						$StrNonce = if ($MyParameters.$StrNonce)
						{ $MyParameters.$StrNonce }
						Elseif ($MyOptions.$StrNonce)
						{ $MyOptions.$StrNonce }
						Else
						{ [Guid]::NewGuid().ToString('N') }
						$StrLogRetentionDays = if ($null -ne $MyParameters.$StrLogRetentionDays)
						{ [int]$MyParameters.$StrLogRetentionDays }
						Elseif ($null -ne $MyOptions.$StrLogRetentionDays)
						{ [int]$MyOptions.$StrLogRetentionDays }
						Else
						{ [int]14 }
						# 0.13 PID hand-off: preserve the Handin flag through the Server build so the Client build (which is
						# built FROM this ServerClientParams) inherits it - mirrors how $StrNonce flows.
						$StrHandin = if ($MyParameters.$StrHandin -or $MyOptions.$StrHandin)
						{ $True }
						Else
						{ $False }
					}
				}
				ElseIf ($Client)
				{
					[Ordered]@{
						$StrServer = $False
						$StrClient = $True
						$StrPipeName = if ($MyParameters.$StrPipeName)
						{$MyParameters.$StrPipeName}
						Else
						{$Null}
						$StrPipeInfo = if ($MyParameters.$StrPipeInfo)
						{$MyParameters.$StrPipeInfo}
						Else
						{$Null}
						$StrPipeParams = if ($MyParameters.$StrPipeParams)
						{$MyParameters.$StrPipeParams}
						Else
						{Set-ObjectParameterSet -Dataset $StrPipeParams -MyParameters $MyParameters}
						$StrInfoDisplay = if ($null -ne $MyParameters.$StrInfoDisplay)
						{[int]$MyParameters.$StrInfoDisplay}
						Elseif ($null -ne $MyOptions.$StrInfoDisplay)
						{[int]$MyOptions.$StrInfoDisplay}
						Else
						{[int]0}
						$StrWait = if ($MyParameters.$StrWait -or $MyOptions.$StrWait)
						{$True}
						Else
						{$False}
						$StrVerbose = if ($MyParameters.$StrVerbose -or $MyOptions.$StrVerbose)
						{$True}
						Else
						{$False}
						$StrNoExitOnError = if ($MyParameters.$StrNoExitOnError -or $MyOptions.$StrNoExitOnError)
						{$True}
						Else
						{$False}
						$StrChunkSize = if ($MyParameters.$StrChunkSize)
						{[int]$MyParameters.$StrChunkSize}
						Elseif ($MyOptions.$StrChunkSize)
						{[int]$MyOptions.$StrChunkSize}
						Else
						{[int]32768}  # Default 32KB chunk size
						$StrDepth = if ($null -ne $MyParameters.$StrDepth)
						{[int]$MyParameters.$StrDepth}
						Elseif ($null -ne $MyOptions.$StrDepth)
						{[int]$MyOptions.$StrDepth}
						Else
						{[int]2}  # Default depth 2 (safe for ACL objects)
						$StrClientConnectTimeout = if ($null -ne $MyParameters.$StrClientConnectTimeout)
						{[int]$MyParameters.$StrClientConnectTimeout}
						Elseif ($null -ne $MyOptions.$StrClientConnectTimeout)
						{[int]$MyOptions.$StrClientConnectTimeout}
						Else
						{[int]10000}  # Default time 10000
						$StrServerWaitTimeout = if ($null -ne $MyParameters.$StrServerWaitTimeout)
						{[int]$MyParameters.$StrServerWaitTimeout}
						Elseif ($null -ne $MyOptions.$StrServerWaitTimeout)
						{[int]$MyOptions.$StrServerWaitTimeout}
						Else
						{[int]60}  # Default time 60
						$StrChunkReadTimeout = if ($null -ne $MyParameters.$StrChunkReadTimeout)
						{[int]$MyParameters.$StrChunkReadTimeout}
						Elseif ($null -ne $MyOptions.$StrChunkReadTimeout)
						{[int]$MyOptions.$StrChunkReadTimeout}
						Else
						{[int]30000}  # Default 30s - see DefineVariablesPipe.ps1 for why only the CHUNK-CONTINUATION read is bounded
						$StrModuleToLoad = if ($MyParameters.$StrModuleToLoad)
						{ $MyParameters.$StrModuleToLoad }
						Elseif ($MyOptions.$StrModuleToLoad)
						{ $MyOptions.$StrModuleToLoad }
						Else
						{ $script:DefaultModuleToLoad }
						$StrRedactPattern = if ($MyParameters.$StrRedactPattern)
						{ $MyParameters.$StrRedactPattern }
						Elseif ($MyOptions.$StrRedactPattern)
						{ $MyOptions.$StrRedactPattern }
						Else
						{ $null }
						# 0.15: default $true when unset - see this constant's own Use text
						# (DefineVariablesPipe.ps1) and USERGUIDE.md for the full reasoning.
						$StrRedactPotentialSecrets = if ($null -ne $MyParameters.$StrRedactPotentialSecrets)
						{ [bool]$MyParameters.$StrRedactPotentialSecrets }
						Elseif ($null -ne $MyOptions.$StrRedactPotentialSecrets)
						{ [bool]$MyOptions.$StrRedactPotentialSecrets }
						Else
						{ $true }
						$StrRequestPolicy = if ($MyParameters.$StrRequestPolicy)
						{ $MyParameters.$StrRequestPolicy }
						Elseif ($MyOptions.$StrRequestPolicy)
						{ $MyOptions.$StrRequestPolicy }
						Else
						{ $null }
						# 0.11 hardening (4.2): inherit the nonce generated by the server build. When the
						# client is built FROM the server's ServerClientParams (Start-PipeSession step 7),
						# $MyParameters.$StrNonce carries the server's nonce, so the client presents the match.
						$StrNonce = if ($MyParameters.$StrNonce)
						{ $MyParameters.$StrNonce }
						Elseif ($MyOptions.$StrNonce)
						{ $MyOptions.$StrNonce }
						Else
						{ $null }
						# 0.13 PID hand-off: client option. When set (VHDTools hand-off), the client does a HANDIN (send marker,
						# receive the nonce) instead of presenting a nonce it does not have.
						$StrHandin = if ($MyParameters.$StrHandin -or $MyOptions.$StrHandin)
						{ $True }
						Else
						{ $False }
					}
				}
			}
			$StrDataObject
			{
				[Ordered]@{
					$StrError = $Null
					$StrFromServerOrClient = $Null
					$StrClientPID = if ($DataObject.$StrClientPID)
					{$DataObject.$StrClientPID}
					Else
					{$Null}
					$StrClientUser = if ($DataObject.$StrClientUser)
					{$DataObject.$StrClientUser}
					Else
					{$Null}
					$StrServerPID = if ($MyParameters.$StrServer)
					{$Pid}
					ElseIf ($DataObject.$StrServerPID)
					{$DataObject.$StrServerPID}
					Else
					{$Null}
					$StrServerUser = If ($DataObject.$StrServerUser)
					{$DataObject.$StrServerUser}
					Else
					{$Null}
					$Strtype = $Null
					$StrResult = $Null
					$StrRequest = $Null
					$StrProgressInfo = $Null
					$StrQuery = $Null   # RESERVED - server->client needs-input payload (see IMPLEMENTATION_GUIDE.md). Null in normal flow.
					$StrParameters = $Null
					$StrLastRequest = $Null
					$StrLastParameters = $Null
					$StrData = $Null
					$StrLastData = $Null
				}
			}
			$StrSendRequestParams
			{
				# $MyParameters, NOT $ServerClientParams.
				#
				# Start-PipeSession builds this dataset with
				#     Set-ObjectParameterSet -Dataset SendRequestParams -MyParameters $Private:ServerClientParams
				# so the ServerClientParams hashtable arrives as $MyParameters. This branch used to read a
				# variable literally named $ServerClientParams, which is NOT a parameter of this function -
				# it could only ever resolve by dynamic scope to the CALLER's variable, and the caller's is
				# $Private:ServerClientParams, which child scopes cannot see. So it resolved to nothing and
				# BOTH fields below silently took their Else branch, every time.
				#
				# Measured 2026-08-13 by calling this builder directly with sentinels:
				#   NoExitOnError = $true            -> came back False
				#   PipeInfo      = 'SENTINEL'       -> came back $null
				#
				# It hid because neither loss was fatal: Start-PipeSession reassigns PipeInfo immediately
				# afterwards, and NoExitOnError only controls whether Send-Request echoes the error text via
				# Write-Information - the DataObject is returned to the caller either way. The visible effect
				# was that the option could not be set through the session Options at all, which sent
				# consumers (ConfigureDefender) to setting the key on the hashtable by hand.
				#
				# The sibling branches at the ServerClientParams and MyOptions datasets already read
				# $MyParameters / $MyOptions correctly - this was the odd one out.
				[Ordered]@{
					$Strtype = $StrScriptBlock
					$StrNoExitOnError = if ($MyParameters.$StrNoExitOnError)
					{$True}
					Else
					{$False}
					$StrPipeInfo = if ($MyParameters.$StrPipeInfo)
					{$MyParameters.$StrPipeInfo}
					Else
					{$Null}
					$StrDataObject = Set-ObjectParameterSet -Dataset $StrDataObject
				}
			}
			$StrPipeInfo
			{
				[Ordered]@{
					$StrName = if ($MyParameters.$StrName)
					{$MyParameters.$StrName}
					Elseif ($pn)
					{$pn}
					Else
					{$Null}
					$StrPipe = if ($MyParameters.$StrPipe)
					{$MyParameters.$StrPipe}
					Else
					{$Null}
					$StrReader = $Null
					$StrWriter = $Null
					$StrError = $Null
				}
			}
		}

	}
	Catch
	{
		Write-MyCatchAudit -Source 'Set-ObjectParameterSet: unexpected error building/validating a dataset - re-thrown so existing callers keep their current behavior, this only adds a trackable record' -ErrorRecord $_
		# Every real call site in this module (session/dataset SETUP - building ServerClientParams,
		# MyOptions, etc.) runs BEFORE a pipe connection exists, or outside the server's live
		# per-request loop entirely - so a throw here fails setup, it does not collapse an
		# already-established, actively-conversing pipe. If a future call site ever needed this inside
		# the live per-request loop, Start-PipeServerOrClient's own outer per-request Try/Catch would
		# still catch it there too (belt-and-braces).
		throw
	}
}
