Function Set-ObjectParams
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
			Set-ObjectParams -MyParameters Value -Dataset Value
			Sets up the requested dataset

			.OUTPUTS
			The initialised dataset requested.
	#>

	[cmdletbinding(DefaultParameterSetName = 'Either')]
	Param(
		[Parameter(Mandatory,ParameterSetName = 'Server',HelpMessage = 'Please state the dataset to initialise')]
		[Parameter(Mandatory,ParameterSetName = 'Client',HelpMessage = 'Please state the dataset to initialise')]
		[Parameter(Mandatory,ParameterSetName = 'Either',HelpMessage = 'Please state the dataset to initialise')]
		[validateset('PipeParams', 'DataObject','ServerClientParams','SendRequestParams','PipeInfo','MyOptions','BreakPoint')]
		[validatescript({
					$_ -imatch $StrPipeParams -or 
					$_ -imatch $StrDataObject -or
					$_ -imatch $StrMyOptions -or
					$_ -imatch $StrServerClientParams -or
					$_ -imatch $StrSendRequestParams -or
					$_ -imatch $StrPipeInfo -or
					$_ -imatch $StrBreakpoint
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
	Switch ($Dataset)
	{
		$StrBreakpoint 
		{
			[Ordered] @{
				BPInfo   = If ($BPList)
				{$BPList}
				Else
				{@{}}
				FullName = $Null
				IDNoList = @()
				Name     = $Null
				Lines    = @{}
				Command  = @{}
				Variable = @{}
			}
		}
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
					$StrPipeInfo = Set-ObjectParams -Dataset $StrPipeInfo -MyParameters $MyParameters -Server
					$StrPipeParams = Set-ObjectParams -Dataset $StrPipeParams -MyParameters $MyParameters
					$StrAccessIdentifier = if ($MyParameters.$StrAccessIdentifier)
					{$MyParameters.$StrAccessIdentifier| Test-UserOrGroupExists}
					Elseif ($Accesslist)
					{$Accesslist | Test-UserOrGroupExists}
					else
					{('{0}:Allow:ReadWrite' -f [Security.Principal.WindowsIdentity]::GetCurrent().Name) | Test-UserOrGroupExists}
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
					{Set-ObjectParams -Dataset $StrPipeParams -MyParameters $MyParameters}
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
			[Ordered]@{
				$Strtype = $StrScriptBlock
				$StrNoExitOnError = if ($ServerClientParams.$StrNoExitOnError)
				{$True}
				Else
				{$False}
				$StrPipeInfo = if ($ServerClientParams.$StrPipeInfo)
				{$ServerClientParams.$StrPipeInfo}
				Else
				{$Null}
				$StrDataObject = Set-ObjectParams -Dataset $StrDataObject
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
