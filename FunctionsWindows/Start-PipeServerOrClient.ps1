[CmdletBinding(PositionalBinding = $False,DefaultParameterSetName = 'Default')]
Param (
	[Parameter(ParameterSetName = 'Spawned',DontShow = $True)]
	[Switch]$Spawned,
	[Parameter(Mandatory,HelpMessage = 'Provide the Serial Data to use',ParameterSetName = 'Spawned',DontShow = $True)]
	[Parameter(DontShow = $True)]
	[String]$SerialData
)
If ($Spawned)
{
	$Private:MyBoundParameters = $PSCmdlet.MyInvocation.BoundParameters
	# Bootstrap: $PSScriptRoot resolves to this script's installed FunctionsWindows\ directory.
	# Import the owning NamedPipe manifest so ConvertFrom-Serial is available before we
	# deserialise ServerClientParams. Works independently of profile or PSModulePath state.
	Import-Module -Name (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'NamedPipe.psd1') -ErrorAction Stop
	$ServerClientParams = ConvertFrom-Serial -Text $SerialData
	# Import the consumer module (e.g. VHD). NamedPipe is already loaded above; importing
	# VHD (which RequiredModules NamedPipe) or NamedPipe again are both no-ops for NamedPipe.
	# Prefer full path import (works even when $PSModulePath excludes network/OneDrive drives).
	$Private:mtl = $ServerClientParams.ModuleToLoad
	if ($Private:mtl.Path -and (Test-Path -Path $Private:mtl.Path))
	{ Import-Module -Name $Private:mtl.Path -ErrorAction Stop }
	else
	{ Import-Module -Name $Private:mtl.Name -RequiredVersion $Private:mtl.Version -ErrorAction Stop }
	# InfoDisplay bitmask: 1=server/client progress, 2=Show-VerboseData, 4=debug output
	if ($ServerClientParams.$StrInfoDisplay -band 4)
	{
		Write-Host -Object ('DEBUG SPAWN: Server process started, PS version = {0}' -f $PSVersionTable.PSVersion) -ForegroundColor Yellow
		Write-Host -Object ('DEBUG SPAWN: Imported {0} v{1}' -f $ServerClientParams.ModuleToLoad.Name, $ServerClientParams.ModuleToLoad.version) -ForegroundColor Green
	}
	if ($ServerClientParams.$StrInfoDisplay -band 2)
	{
		Show-VerboseData -Object $ServerClientParams -Display -Title 'ServerClientParams'
		Show-VerboseData -Object $ServerClientParams.$StrModuleToLoad -Display -Title 'Module to load in Spawned process'
	}
	
	$ServerClientParams.$StrSpawned = $True
	# Call via NamedPipe module scope because Start-PipeServerOrClient is internal (not exported)
	# Always use 'NamedPipe' here regardless of $ModuleName - the function lives in NamedPipe's scope
	# Match by path: find the NamedPipe module whose ModuleBase contains this script file.
	# This correctly identifies the owning version even when a newer NamedPipe version is
	# simultaneously loaded (e.g. profile auto-imports v0.5, consumer module imports v0.7).
	$Private:module = Get-Module -Name NamedPipe | Where-Object { $PSScriptRoot -like "$($_.ModuleBase)\*" } | Select-Object -First 1
	if (-not $Private:module)
	{
		# Fallback: highest loaded version (shouldn't be reached in normal operation)
		$Private:module = Get-Module -Name NamedPipe | Sort-Object -Property Version -Descending | Select-Object -First 1
	}
	$Private:module.Invoke({
			param($data)
			Start-PipeServerOrClient -SerialData $data
	}, (ConvertTo-Serial -Object $ServerClientParams))
}
Function Start-PipeServerOrClient
{
	<#
			.SYNOPSIS
			Establishes and manages both the server and client ends of a named pipe connection.

			.DESCRIPTION
			This script/function has a dual role:

			1. As a FUNCTION (Start-PipeServerOrClient): Called from the user's script to set up
			either the server or client side of the pipe, based on the ServerClientParams
			data structure passed via serialized data.

			2. As a SCRIPT (.ps1 file): When spawning the server, this file is executed in a
			separate PowerShell process. The -Spawned parameter indicates the script is
			running as a detached server process. It imports the NamedPipe module,
			deserializes the configuration, and calls itself as a function.

			Server behaviour:
			- First call (not spawned): Launches a new PowerShell process running this script
			with the -Spawned flag. Returns the server process ID.
			- Second call (spawned): Creates the NamedPipeServerStream, waits for the client
			to connect, then enters a request/response loop processing ScriptBlock,
			Security, and ExitPipe requests.

			Client behaviour:
			- Creates a NamedPipeClientStream, connects to the server, sets up StreamReader
			and StreamWriter, and returns the PipeInfo object for use with Send-Request.

			Configuration (ChunkSize, Depth, InfoDisplay, timeouts) flows from
			ServerClientParams into PipeInfo so that Send-Data/Receive-Data can access it.

			.PARAMETER SerialData
			A serialized (Base64) string containing the ServerClientParams data structure.
			Created by: ConvertTo-Serial -Object $ServerClientParams

			.EXAMPLE
			# Start the server (returns server PID)
			$ServerPID = Start-PipeServerOrClient -SerialData (ConvertTo-Serial -Object $ServerClientParams)

			.EXAMPLE
			# Start the client (returns PipeInfo with connection)
			$PipeInfo = Start-PipeServerOrClient -SerialData (ConvertTo-Serial -Object $ServerClientParams)

			.INPUTS
			System.String - Serialized ServerClientParams data structure.

			.OUTPUTS
			Server (first call): Process ID of the spawned server process.
			Server (spawned): No output (runs request loop until ExitPipe received).
			Client: PipeInfo object containing Pipe, Reader, Writer, and connection metadata.
	#>


	[CmdletBinding(PositionalBinding = $False)]
	Param (
		[Parameter(Mandatory,HelpMessage = 'Provide the Serial Data to use',DontShow = $True)]
		[String]$SerialData
	)

	$Private:MyBoundParameters = $PSCmdlet.MyInvocation.BoundParameters
	$ServerClientParams = ConvertFrom-Serial -Text $SerialData
	$DataObject = Set-ObjectParams -Dataset 'DataObject' -MyParameters $Private:MyBoundParameters

	If ($ServerClientParams.$StrInfoDisplay -band 2)
	{
		Show-VerboseData -Object $ServerClientParams -Display -Title ('ServerClientParams on Entry Server:[{0}] Client: [{1}] Spawned: [{2}]' -f $ServerClientParams.Server, $ServerClientParams.Client, $ServerClientParams.Spawned)
		Show-VerboseData -Object $ServerClientParams.$StrPipeInfo -Display -Title ('PipeInfo on Entry Server:[{0}] Client: [{1}] Spawned: [{2}]' -f $ServerClientParams.Server, $ServerClientParams.Client, $ServerClientParams.Spawned)
		Show-VerboseData -Object $ServerClientParams.$StrPipeParams -Display -Title ('PipeParams on Entry Server:[{0}] Client: [{1}] Spawned: [{2}]' -f $ServerClientParams.Server, $ServerClientParams.Client, $ServerClientParams.Spawned)
	}
	
	if($ServerClientParams.Server)
	{
		If (-Not $ServerClientParams.Spawned)
		{	
			If ($PSVersionTable.PSVersion.Major -gt [int]5)
			{$Executable = Join-Path -Path ('{0}' -f $PSHome) -ChildPath 'pwsh.exe'}
			else
			{$Executable = Join-Path -Path ('{0}' -f $PSHome) -ChildPath 'Powershell.exe'}
			$ProcessVerb = 'Open'
			If (-not $Administrator -and $ServerClientParams.AdminRequired)
			{$ProcessVerb = 'RunAs'}
			$ServerClientParams.$StrAdminRequired = $False
			$Private:npModule     = Get-Module -Name NamedPipe | Sort-Object -Property Version -Descending | Select-Object -First 1
			$Private:ServerScript = Join-Path $Private:npModule.ModuleBase 'FunctionsWindows\Start-PipeServerOrClient.ps1'
			# Launch the server with -File and the script path DOUBLE-QUOTED inside a single argument
			# string, so a module path containing a space (e.g. under C:\Program Files\...) is passed
			# intact. Notes on why other forms fail here:
			#   * '-Command &{ <path> ... }' : the quotes are consumed when -Command's args are rejoined,
			#     leaving a bare spaced path -> the spawned process ran 'C:\Program' and died early.
			#   * an ARRAY -ArgumentList : Windows PowerShell 5.1 Start-Process -Verb (ShellExecute) does
			#     not quote array elements, it just space-joins them, so the path splits again.
			# With -File the path is a discrete parameter value, so the double quotes survive.
			$Private:ServerArgs = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Spawned -SerialData {1}' -f $Private:ServerScript, (ConvertTo-Serial -Object $ServerClientParams)
			$ProcessInfo = @{
				FilePath     = $Executable
				Passthru     = $True
				WindowStyle  = $ServerClientParams.$StrWindowStyle
				wait         = $False
				Verb         = $ProcessVerb
				Argumentlist = $Private:ServerArgs
			}
			If ($ServerClientParams.$Strverbose)
			{Show-VerboseData -Object $ProcessInfo -Display -Title 'ProcessInfo Starting the Server'}	
			# Start the Server
			Try
			{
				(Start-Process @ProcessInfo).Id
			}
			Catch
			{
				throw ('Failed to start server process: {0}' -f $_.Exception.Message)
			}
		}
		Else
		{
			Try
			{
				#Server:
				if ($PSVersionTable.PSVersion.Major -gt 5)
				{
					$ServerClientParams.$StrPipeInfo.$StrPipe  = [IO.Pipes.NamedPipeServerStreamacl]::Create(
						$ServerClientParams.$StrPipeInfo.Name,
						$ServerClientParams.$StrPipeParams.Direction,
						$ServerClientParams.$StrPipeParams.Instances,
						$ServerClientParams.$StrPipeParams.Mode,
						$ServerClientParams.$StrPipeParams.Options,
						$ServerClientParams.$StrPipeParams.PipeBufferSizeR,
						$ServerClientParams.$StrPipeParams.PipeBufferSizeS,
						(Set-PipeSecurity -AccessIdentifier $ServerClientParams.$StrAccessIdentifier)
					)
				}
				Else
				{
					$ServerClientParams.$StrPipeInfo.$StrPipe  = [IO.Pipes.NamedPipeServerStream]::new(
						$ServerClientParams.$StrPipeInfo.Name,
						$ServerClientParams.$StrPipeParams.Direction,
						$ServerClientParams.$StrPipeParams.Instances,
						$ServerClientParams.$StrPipeParams.Mode,
						$ServerClientParams.$StrPipeParams.Options,
						$ServerClientParams.$StrPipeParams.PipeBufferSizeR,
						$ServerClientParams.$StrPipeParams.PipeBufferSizeS,
						(Set-PipeSecurity -AccessIdentifier $ServerClientParams.AccessIdentifier)
					)
				}
				# 0.11 hardening (4.1b): apply a Medium mandatory integrity label to the DATA pipe so a
				# LOW-integrity process cannot connect. Post-create, needs no privilege, graceful (never
				# fails creation - returns $false and the DACL-only pipe stands). See Set-PipeIntegrityLabel.
				$null = Set-PipeIntegrityLabel -Pipe $ServerClientParams.$StrPipeInfo.$StrPipe
				# 0.11 hardening (4.5 step 1a): server diagnostics log. Buffer milestones; flush on failure, discard a clean exit unless InfoDisplay bit 8.
				$Private:EverConnected    = $false
				$Script:ServerLogBuffer   = [System.Collections.Generic.List[string]]::new()
				$Script:ServerLogSaved    = $false
				$Script:NonceRejectCount  = 0
				Add-ServerLogEntry -Message ('data pipe created: {0}' -f $ServerClientParams.$StrPipeInfo.$StrName)
				$null = Remove-OldServerLog -RetentionDays $ServerClientParams.$StrLogRetentionDays
				# 0.11 hardening (4.5 step 1d): self-provision the Event Log source when THIS server is elevated, so a
				# git-cloned module (never run through Deploy-Modules) still gets the failure-pointer source. Idempotent;
				# needs admin to CREATE (hence the $Administrator gate) - writing to it later needs none.
				if ($Administrator) { $null = Register-PipeEventSource }

				# 0.11 hardening (4.3): first-connect deadline budget (from pipe creation) + PowerShell.Exiting teardown.
				$Private:FirstConnectDeadlineMs = [int]$ServerClientParams.$StrClientConnectTimeout + 2000
				$Private:FirstConnectSw         = [System.Diagnostics.Stopwatch]::StartNew()
				# Belt-and-braces: dispose the pipe on an abnormal engine exit (the Finally covers normal exits and the OS
				# closes the handle on process exit; this is defence in depth). Closure captures the pipe reference.
				$Private:PipeForExit = $ServerClientParams.$StrPipeInfo.$StrPipe
				$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action ({
					try { if ($PipeForExit) { $PipeForExit.Dispose() } } catch { $null = $_ }
				}.GetNewClosure())
				# 0.12 PID hand-off: state + P/Invoke to read a connecting client's real (kernel-set) PID.
				$Private:ExpectedHandinPid = [uint32]0
				if (-not ('NamedPipe.PidQuery' -as [type]))
				{
					Add-Type -Namespace 'NamedPipe' -Name 'PidQuery' -MemberDefinition '[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)] public static extern bool GetNamedPipeClientProcessId(System.IntPtr Pipe, out uint ClientProcessId);' -ErrorAction SilentlyContinue
				}
				$Private:ExitRequested = $false
				While (-not $Private:ExitRequested)
				{
					If (-not $Private:EverConnected)
					{
						# First-connect phase (4.3): an OVERALL budget (~ClientConnectTimeout, measured from pipe creation) for a
						# FIRST nonce-validated client. A wrong-nonce squatter that reconnects does NOT reset it (stopwatch, not
						# per-wait), so an unclaimed elevated server dies in ~ClientConnectTimeout, not the 60s re-listen window.
						$Private:RemainingMs = $Private:FirstConnectDeadlineMs - $Private:FirstConnectSw.ElapsedMilliseconds
						If ($Private:RemainingMs -le 0)
						{
							Add-ServerLogEntry -Message ('no validated client within the {0}ms first-connect deadline - self-terminating' -f $Private:FirstConnectDeadlineMs)
							$null = Save-ServerLog -Outcome 'timed-out-unclaimed' -InfoDisplay $ServerClientParams.$StrInfoDisplay -PipeName $ServerClientParams.$StrPipeInfo.$StrName
							$Private:ExitRequested = $true
							break
						}
						$timeout = [timespan]::FromMilliseconds([double]$Private:RemainingMs)
					}
					Else
					{
						# Re-listen phase (after a validated session): wait the configurable re-listen window.
						$timeout = [timespan]::FromSeconds($ServerClientParams.$StrServerWaitTimeout)
					}
					$source = [Threading.CancellationTokenSource]::new($timeout)
					$conn = $ServerClientParams.$StrPipeInfo.$StrPipe.WaitForConnectionAsync($source.token)
					do
					{
						# some other stuff here while waiting for connection
						Start-Sleep -Milliseconds 500
					}
					until ($conn.IsCompleted)
					If ($conn.IsCanceled -or $conn.IsFaulted -or -not $ServerClientParams.$StrPipeInfo.$StrPipe.IsConnected)
					{
						# Timed out or faulted - no new client arrived, stop re-listening
						Add-ServerLogEntry -Message ('no connection within {0}s wait' -f $ServerClientParams.$StrServerWaitTimeout)
						$null = Save-ServerLog -Outcome $(If ($Private:EverConnected) { 'relisten-timeout' } Else { 'timed-out-unclaimed' }) -InfoDisplay $ServerClientParams.$StrInfoDisplay -PipeName $ServerClientParams.$StrPipeInfo.$StrName
						$Private:ExitRequested = $true
						break
					}
					# leaveOpen=$true prevents Dispose() from closing the underlying NamedPipeServerStream
					# so Disconnect()+WaitForConnectionAsync() remain usable for re-listen cycles
					$ServerClientParams.$StrPipeInfo.$StrReader = [IO.StreamReader]::new(
						$ServerClientParams.$StrPipeInfo.$StrPipe,
						([System.Text.UTF8Encoding]::new($false)),
						$false,
						1024,
						$true
					)
				$ServerClientParams.$StrPipeInfo.$StrWriter = [IO.StreamWriter]::new(
					$ServerClientParams.$StrPipeInfo.$StrPipe,
					([System.Text.UTF8Encoding]::new($false)),
					1024,
					$true
				)
				$ServerClientParams.$StrPipeInfo.$StrWriter.AutoFlush = $True
				# Copy InfoDisplay, ChunkSize, Depth to PipeInfo so Send-Data/Receive-Data can access them
				$ServerClientParams.$StrPipeInfo.$StrInfoDisplay = $ServerClientParams.$StrInfoDisplay
				$ServerClientParams.$StrPipeInfo.$StrChunkSize = $ServerClientParams.$StrChunkSize
				$ServerClientParams.$StrPipeInfo.$StrDepth = $ServerClientParams.$StrDepth
				# === 0.11 hardening (4.2): capability-nonce handshake ===
				# The client's FIRST line on a fresh connection must equal the nonce handed to this
				# server at spawn. This gates admission WITHOUT pinning to a PID, so the VHDTools
				# GUI->terminal hand-off (a DIFFERENT process presenting the same nonce) still works.
				# Wrong or absent first line -> reject and re-listen (same teardown as a Disconnect).
				# No nonce configured (older caller) -> skip the check for backward compatibility.
				If ($ServerClientParams.$StrNonce)
				{
					$Private:PresentedNonce = $null
					Try
					{
						$Private:NonceReadTask = $ServerClientParams.$StrPipeInfo.$StrReader.ReadLineAsync()
						If ($Private:NonceReadTask.Wait([int]$ServerClientParams.$StrClientConnectTimeout))
						{$Private:PresentedNonce = $Private:NonceReadTask.Result}
					}
					Catch
					{$Private:PresentedNonce = $null}
					$Private:_admit = $false
					If ($Private:PresentedNonce -eq $StrHandinMarker)
					{
						# 0.12 PID hand-off: a reconnecting terminal claims a hand-off. Admit ONLY if the authenticated client
						# armed an expected PID (via a Handoff request) and the kernel-reported connecting PID matches; then hand
						# it the nonce over this PID-verified channel so it becomes a normal client.
						If ($Private:ExpectedHandinPid -ne 0)
						{
							$Private:_connPid = [uint32]0
							Try { [void][NamedPipe.PidQuery]::GetNamedPipeClientProcessId($ServerClientParams.$StrPipeInfo.$StrPipe.SafePipeHandle.DangerousGetHandle(), [ref]$Private:_connPid) } Catch { $Private:_connPid = [uint32]0 }
							If ($Private:_connPid -ne 0 -and $Private:_connPid -eq $Private:ExpectedHandinPid)
							{
								$ServerClientParams.$StrPipeInfo.$StrWriter.WriteLine($ServerClientParams.$StrNonce)
								$Private:ExpectedHandinPid = [uint32]0
								$Private:_admit = $true
								Add-ServerLogEntry -Message ('hand-in accepted from PID {0}' -f $Private:_connPid)
								If ($ServerClientParams.$StrInfoDisplay -band 4)
								{Write-Host ('DEBUG SERVER: hand-in accepted from PID {0}' -f $Private:_connPid) -ForegroundColor Green}
							}
						}
					}
					ElseIf ($Private:PresentedNonce -eq $ServerClientParams.$StrNonce)
					{
						$Private:_admit = $true
						If ($ServerClientParams.$StrInfoDisplay -band 4)
						{Write-Host 'DEBUG SERVER: nonce accepted' -ForegroundColor Green}
					}
					If (-not $Private:_admit)
					{
						If ($ServerClientParams.$StrInfoDisplay -band 4)
						{Write-Host 'DEBUG SERVER: connection rejected (bad nonce / hand-in) - re-listening' -ForegroundColor Red}
						try { $ServerClientParams.$StrPipeInfo.$StrReader.Dispose() } catch { $null = $_ }
						try { $ServerClientParams.$StrPipeInfo.$StrWriter.Dispose() } catch { $null = $_ }
						$ServerClientParams.$StrPipeInfo.$StrReader = $null
						$ServerClientParams.$StrPipeInfo.$StrWriter = $null
						try { $ServerClientParams.$StrPipeInfo.$StrPipe.Disconnect() } catch { $null = $_ }
						$Script:NonceRejectCount++
						Add-ServerLogEntry -Message 'connection rejected: wrong nonce or failed hand-in'
						Continue
					}
				}
				# === End capability-nonce handshake ===
				$Private:EverConnected = $true
				Add-ServerLogEntry -Message 'client connected and validated'
				Function Stop-HealthPipe
				{
					[CmdletBinding(PositionalBinding = $False)]
					Param (
						[Parameter(Mandatory,HelpMessage = 'Provide the HealthPipeName')]
						[String]$HealthPipeName,
						[Parameter(Mandatory,HelpMessage = 'Provide the HealthRunspace')]
						$HealthRunSpace,
						[Parameter(Mandatory,HelpMessage = 'Provide the HealthPS')]
						$HealthPS,
						[Parameter(Mandatory,HelpMessage = 'Provide the HealthCts')]
						$HealthCts
					)
					# Send STOP poison pill to unblock WaitForConnection in the health runspace.
					# The health pipe ACL includes the server identity so this works even when elevated.
					try
					{
						$StopClient = [System.IO.Pipes.NamedPipeClientStream]::new('.', $HealthPipeName, [System.IO.Pipes.PipeDirection]::InOut)
						$StopClient.Connect(1000)
						$StopWriter = [System.IO.StreamWriter]::new($StopClient)
						$StopWriter.AutoFlush = $true
						$StopWriter.WriteLine('STOP')
						$StopClient.Dispose()
					}
					catch
					{
						if ($ServerClientParams.$StrInfoDisplay -band $InfoDisplayBitDebug)
						{ Write-Host "DEBUG Stop-HealthPipe: Failed to send STOP: $($_.Exception.Message)" -ForegroundColor DarkYellow }
					}
					Start-Sleep -Milliseconds 200
					if ($HealthCts)
					{
						try { $HealthCts.Cancel() } catch
						{
							if ($ServerClientParams.$StrInfoDisplay -band $InfoDisplayBitDebug)
							{ Write-Host "DEBUG Stop-HealthPipe: Failed to cancel CTS: $($_.Exception.Message)" -ForegroundColor DarkYellow }
						}
						try { $HealthCts.Dispose() } catch { $null = $_ }
					}
					if ($HealthPS)
					{
						try { $HealthPS.Dispose() } catch
						{
							if ($ServerClientParams.$StrInfoDisplay -band $InfoDisplayBitDebug)
							{ Write-Host "DEBUG Stop-HealthPipe: Failed to dispose PowerShell: $($_.Exception.Message)" -ForegroundColor DarkYellow }
						}
					}
					if ($HealthRunspace)
					{
						try { $HealthRunspace.Close() } catch { $null = $_ }
						try { $HealthRunspace.Dispose() } catch { $null = $_ }
					}
				}
				
					# === Health pipe listener ===
					# Start a background runspace that listens on PipeName.Health for PING/PONG
					# health checks. Pipe security is built inside the runspace from the
					# AccessIdentifier string array to avoid cross-runspace PipeSecurity object issues.
					# The loop exits when a client connects and sends the literal string 'STOP'
					# (the "poison pill"). The Finally block sends this signal before disposing
					# the runspace. WaitForConnection() is synchronous and cannot be interrupted
					# by CancellationToken in .NET Framework, so the poison pill is the only
					# reliable way to unblock it.
					$HealthPipeName = $ServerClientParams.$StrPipeInfo.$StrName + '.Health'
					# Include server identity so Stop-HealthPipe can connect back even when elevated
					$Private:HealthAccess = @($ServerClientParams.$StrAccessIdentifier) + @('{0}:Allow:ReadWrite' -f [Security.Principal.WindowsIdentity]::GetCurrent().Name)
					$HealthRunspace = [RunspaceFactory]::CreateRunspace()
					$HealthCts = [System.Threading.CancellationTokenSource]::new()
					$HealthRunspace.Open()
					$HealthPS = [PowerShell]::Create()
					$HealthPS.Runspace = $HealthRunspace
					$null = $HealthPS.AddScript({
							param($hpn, $acc, $psVer, $Cts)
							# Build pipe security inside the runspace from the AccessIdentifier string
							# array. Building here avoids cross-runspace PipeSecurity object issues.
							# 0.10 (hardening 4.1a): the empty-$acc fallback grants the CURRENT USER's own
							# SID, NEVER the Interactive SID (S-1-5-4 = ANY interactive user). The launching
							# user (same user as the client) can still health-check the elevated server; no
							# other interactive user can. In practice $acc is never empty - HealthAccess
							# always appends the current identity - so this is a defence-in-depth tighten.
							$sec = $null
							try
							{
								$sec = [System.IO.Pipes.PipeSecurity]::new()
								if ($acc -and @($acc).Count -gt 0)
								{
									foreach ($entry in $acc)
									{
										$parts   = $entry.Split(':')
										$id      = $parts[0]
										$access  = if ($parts.Count -gt 2) {$parts[2]} else {'ReadWrite'}
										$control = if ($parts.Count -gt 1) {$parts[1]} else {'Allow'}
										$sec.AddAccessRule([System.IO.Pipes.PipeAccessRule]::new($id, $access, $control))
									}
								}
								else
								{
									$ownSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
									$sec.AddAccessRule([System.IO.Pipes.PipeAccessRule]::new($ownSid, 'ReadWrite', 'Allow'))
								}
							}
							catch { $sec = $null }
							while ($true)
							{
								$pipe = $null
								try
								{
									if ($psVer -gt 5)
									{
										if ($sec)
										{
											$pipe = [System.IO.Pipes.NamedPipeServerStreamAcl]::Create(
												$hpn,
												[System.IO.Pipes.PipeDirection]::InOut,
												[System.IO.Pipes.NamedPipeServerStream]::MaxAllowedServerInstances,
												[System.IO.Pipes.PipeTransmissionMode]::Byte,
												[System.IO.Pipes.PipeOptions]::None,
												0, 0, $sec
											)
										}
										else
										{
											$pipe = [System.IO.Pipes.NamedPipeServerStream]::new(
												$hpn,
												[System.IO.Pipes.PipeDirection]::InOut,
												[System.IO.Pipes.NamedPipeServerStream]::MaxAllowedServerInstances,
												[System.IO.Pipes.PipeTransmissionMode]::Byte,
												[System.IO.Pipes.PipeOptions]::None
											)
										}
									}
									else
									{
										if ($sec)
										{
											$pipe = [System.IO.Pipes.NamedPipeServerStream]::new(
												$hpn,
												[System.IO.Pipes.PipeDirection]::InOut,
												[System.IO.Pipes.NamedPipeServerStream]::MaxAllowedServerInstances,
												[System.IO.Pipes.PipeTransmissionMode]::Byte,
												[System.IO.Pipes.PipeOptions]::None,
												0, 0, $sec
											)
										}
										else
										{
											$pipe = [System.IO.Pipes.NamedPipeServerStream]::new(
												$hpn,
												[System.IO.Pipes.PipeDirection]::InOut,
												[System.IO.Pipes.NamedPipeServerStream]::MaxAllowedServerInstances,
												[System.IO.Pipes.PipeTransmissionMode]::Byte,
												[System.IO.Pipes.PipeOptions]::None
											)
										}
									}
									$pipe.WaitForConnection()
									$hReader = [System.IO.StreamReader]::new($pipe)
									$hWriter = [System.IO.StreamWriter]::new($pipe)
									$hWriter.AutoFlush = $true
									$msg = $hReader.ReadLine()
									if ($msg -eq 'STOP')
									{
										# Poison pill - exit the health loop cleanly.
										break
									}
									if ($msg -and $msg.StartsWith('PING:'))
									{
										$hWriter.WriteLine('PONG:' + $msg.Substring(5))
									}
								}
								catch { $null = $_ }
								finally
								{
									if ($pipe) { try { $pipe.Dispose() } catch { $null = $_ } }
								}
							}
					}).AddArgument($HealthPipeName).AddArgument($Private:HealthAccess).AddArgument($PSVersionTable.PSVersion.Major).AddArgument($HealthCts)
					$null = $HealthPS.BeginInvoke()
					# === End health pipe listener ===

					If ($ServerClientParams.$StrInfoDisplay -band 4)
					{
						Write-Host 'DEBUG SERVER: StreamReader and StreamWriter created' -ForegroundColor Magenta
						Write-Host "DEBUG SERVER: Pipe IsConnected = $($ServerClientParams.$StrPipeInfo.$StrPipe.IsConnected)" -ForegroundColor Magenta
					}
					If ($ServerClientParams.$StrInfoDisplay -band 2)
					{Show-VerboseData -Object $ServerClientParams.$StrPipeInfo -Display -Title 'PipeInfo after connection made'}
					Do
					{
						try
						{
							If ($ServerClientParams.$StrInfoDisplay -band 4)
							{Write-Host 'DEBUG SERVER: Entering main loop, calling Receive-Data...' -ForegroundColor Magenta}
							$DataObject = Receive-Data -PipeInfo $ServerClientParams.$StrPipeInfo
							# Stamp ServerPID on the received request so Send-Data's branch
							# selector (ServerPID -eq $PID) correctly routes the response
							# through the server path (write and return). Normally the client
							# sets ServerPID via Start-PipeSession, but env-var hand-off clients
							# (e.g. VHDTools terminal reconnect) do not know the server PID.
							$DataObject.$StrServerPID = $PID
							If ($ServerClientParams.$StrInfoDisplay -band 4)
							{Write-Host "DEBUG SERVER: Receive-Data returned, Type = $($DataObject.$StrType)" -ForegroundColor Green}
							Switch ($DataObject.$StrType)
							{
								$StrScriptBlock
								{
									If ($ServerClientParams.$StrInfoDisplay -band 4)
									{Write-Host 'DEBUG SERVER: Processing ScriptBlock request' -ForegroundColor Magenta}
									If ($ServerClientParams.$StrInfoDisplay -band 2)
									{
										Show-VerboseData -Object $DataObject -Display -Title ('DataObject.{0}' -f $StrRequest)
										If ($DataObject.$StrParameters)
										{Show-VerboseData -Object $DataObject.$StrParameters -Display -Title ('DataObject.{0}' -f $StrParameters)}
										If ($DataObject.$StrData)
										{Show-VerboseData -Object $DataObject.$StrData -Display -Title ('DataObject.{0}' -f $StrData)}
									}
									$DataObject = Get-SBResult -DataObject $DataObject
									If ($ServerClientParams.$StrInfoDisplay -band 2)
									{
										Show-VerboseData -Object ('Scriptblock Error: {0}' -f $DataObject.$StrError) -Display -Title 'ScriptBlock Error State'
										Show-VerboseData -Object $DataObject.$StrResult -Display -Title ('DataObject.{0} {1}' -f $StrRequest, $StrResult)
									}
									If ($ServerClientParams.$StrInfoDisplay -band 4)
									{Write-Host 'DEBUG SERVER: ScriptBlock processing done' -ForegroundColor Green}
								}
								$StrSecurity
								{
									If ($ServerClientParams.$StrInfoDisplay -band 4)
									{Write-Host 'DEBUG SERVER: Processing Security request' -ForegroundColor Magenta}
									Try
									{
										$DataObject.$StrRequest = $DataObject.$StrType
										if ($PSVersionTable.PSVersion.Major -gt 5)
										{$DataObject.$StrResult =	[IO.Pipes.PipesAclExtensions]::GetAccessControl($ServerClientParams.$StrPipeInfo.$StrPipe)}
										Else
										{$DataObject.$StrResult = $ServerClientParams.$StrPipeInfo.$StrPipe.GetAccessControl().access}
										If ($ServerClientParams.$StrInfoDisplay -band 4)
										{Write-Host 'DEBUG SERVER: Security GetAccessControl done' -ForegroundColor Green}
									}
									catch
									{
										Write-Host "DEBUG SERVER: Security request FAILED: $_" -ForegroundColor Red
										$DataObject.$StrResult = 'An error Occured getting the Pipe Security information'
										$DataObject.$StrError = NamedPipe\Get-MyErrors -Return
									}
								}
								$StrExitPipe
								{
									If ($ServerClientParams.$StrInfoDisplay -band 4)
									{Write-Host 'DEBUG SERVER: Processing ExitPipe request' -ForegroundColor Magenta}
									try
									{
										$DataObject.$StrRequest = $DataObject.$StrType
										$DataObject.$StrResult = ('Server is Exiting')
										If ($ServerClientParams.$StrInfoDisplay -band 4)
										{Write-Host 'DEBUG SERVER: ExitPipe processing done' -ForegroundColor Green}
									}
									catch
									{$DataObject.$StrError = NamedPipe\Get-MyErrors -Return}
								}
								$StrDisconnect
								{
									If ($ServerClientParams.$StrInfoDisplay -band 4)
									{Write-Host 'DEBUG SERVER: Processing Disconnect request - will re-listen' -ForegroundColor Magenta}
									$DataObject.$StrRequest = $DataObject.$StrType
									$DataObject.$StrResult  = 'Server will re-listen'
									If ($ServerClientParams.$StrInfoDisplay -band 4)
									{Write-Host 'DEBUG SERVER: Disconnect acknowledged' -ForegroundColor Green}
								}
								$StrHandoff
								{
									# 0.12 PID hand-off: the authenticated client ARMs the server with the PID that will present the next
									# hand-in (PID in $StrRequest). Only reachable on an already-authenticated connection.
									$Private:_hp = [uint32]0
									If ([uint32]::TryParse([string]$DataObject.$StrRequest, [ref]$Private:_hp)) { $Private:ExpectedHandinPid = $Private:_hp }
									$DataObject.$StrRequest = $DataObject.$StrType
									$DataObject.$StrResult = ('Armed hand-off for PID {0}' -f $Private:ExpectedHandinPid)
									Add-ServerLogEntry -Message ('hand-off armed for PID {0}' -f $Private:ExpectedHandinPid)
									If ($ServerClientParams.$StrInfoDisplay -band 4)
									{Write-Host ('DEBUG SERVER: armed hand-off for PID {0}' -f $Private:ExpectedHandinPid) -ForegroundColor Magenta}
								}
							}
						}
						catch
						{
							Write-Host "DEBUG SERVER: Exception in main loop: $_" -ForegroundColor Red
							If ($DataObject) { $DataObject.$StrError = NamedPipe\Get-MyErrors -Return }
						}
						If ($ServerClientParams.$StrInfoDisplay -band 4)
						{Write-Host 'DEBUG SERVER: About to Send-Data response back to client' -ForegroundColor Magenta}
						try
						{
							Send-Data -DataObject $DataObject -PipeInfo $ServerClientParams.$StrPipeInfo -ErrorAction Stop
						}
						catch
						{
							# Client disconnected before we could respond - IsConnected check below exits the loop
							$null = $_
						}
						If ($ServerClientParams.$StrInfoDisplay -band 4)
						{Write-Host 'DEBUG SERVER: Send-Data completed, looping back' -ForegroundColor Green}
					}
					while ($ServerClientParams.$StrPipeInfo.$StrPipe.IsConnected -and
						   $DataObject.$StrType -inotmatch $StrExitPipe -and
						   $DataObject.$StrType -inotmatch $StrDisconnect)
					If ($DataObject.$StrType -imatch $StrExitPipe)
					{
						# Client sent ExitPipe - server truly exits
						$Private:ExitRequested = $true
					}
					Else
					{
						# Client sent Disconnect or closed unexpectedly - stop health pipe first
						# so the next iteration starts with only one health runspace (not two).
						Stop-HealthPipe -HealthPipeName $HealthPipeName -HealthRunSpace $HealthRunSpace -HealthPS $HealthPS -healthCts $HealthCts
						$HealthRunspace = $null
						$HealthPS       = $null
						$HealthCts      = $null
						# Clean up streams and put the server pipe back to listening state
						try { $ServerClientParams.$StrPipeInfo.$StrReader.Dispose() } catch { $null = $_ }
						try { $ServerClientParams.$StrPipeInfo.$StrWriter.Dispose() } catch { $null = $_ }
						$ServerClientParams.$StrPipeInfo.$StrReader = $null
						$ServerClientParams.$StrPipeInfo.$StrWriter = $null
						try { $ServerClientParams.$StrPipeInfo.$StrPipe.Disconnect() } catch { $null = $_ }
					}
				} # End re-listen While
				if (-not $Script:ServerLogSaved) { $null = Save-ServerLog -Outcome 'exit-pipe' -InfoDisplay $ServerClientParams.$StrInfoDisplay -PipeName $ServerClientParams.$StrPipeInfo.$StrName }
				If ($ServerClientParams.Wait)
					{
						$null = Set-MyWindowState -ProcessId $DataObject.$StrServerPID -State Restore
						Pause
					}
				}
				Catch
				{
					If ($DataObject.$StrServerPID) { $null = Set-MyWindowState -ProcessId $DataObject.$StrServerPID -State Restore }
					$Private:ErrorMsg = $_.Exception.Message
					$Private:StackTrace = $_.ScriptStackTrace
					$Private:FullError = NamedPipe\Get-MyErrors -Return

					# Redact any drive-qualified (C:\...) or UNC (\\server\share\...) path, not just the
					# author's development drive - a hardcoded 'D:\' silently redacted NOTHING on any other
					# machine or for anyone using the public repo, leaking usernames via C:\Users\<name>\...
					$Private:RedactPathPattern = '(?:[A-Za-z]:\\|\\\\)[^"]*'
					$Private:RedactedTrace = $Private:StackTrace -replace $Private:RedactPathPattern, '<path-redacted>'
					$Private:RedactedError = $Private:FullError -replace $Private:RedactPathPattern, '<path-redacted>'

					$Private:CatchMsg = "Pipe Server Exception`nMessage: $Private:ErrorMsg`nStack: $Private:RedactedTrace`nDetails: $Private:RedactedError"

					Add-ServerLogEntry -Message $Private:CatchMsg
					$Private:LogFile = Save-ServerLog -Outcome 'crashed' -InfoDisplay $ServerClientParams.$StrInfoDisplay -PipeName $ServerClientParams.$StrPipeInfo.$StrName
					if ($Private:LogFile) { Write-Host "Server error logged to: $Private:LogFile" -ForegroundColor Yellow }

					Write-Host "Pipe Server crashed: $Private:ErrorMsg" -ForegroundColor Red
					Write-Host "(Use path-redacted stack trace - check logs for details)" -ForegroundColor DarkGray
					If ($ServerClientParams.Wait) { Pause }
				}
				Finally
				{
					if (-not $Script:ServerLogSaved) { $null = Save-ServerLog -Outcome 'unknown-exit' -InfoDisplay $ServerClientParams.$StrInfoDisplay -PipeName $ServerClientParams.$StrPipeInfo.$StrName }
					# Only stop if not already stopped in the re-listen Else branch
					If ($HealthRunspace)
					{
						Stop-HealthPipe -HealthPipeName $HealthPipeName -HealthRunSpace $HealthRunSpace -HealthPS $HealthPS -healthCts $HealthCts
					}
					# Ensure proper cleanup of resources
					if ($ServerClientParams.$StrPipeInfo.$StrReader)
					{
						try 
						{$ServerClientParams.$StrPipeInfo.$StrReader.Dispose()}
						catch 
						{}
					}
					if ($ServerClientParams.$StrPipeInfo.$StrWriter)
					{
						try 
						{$ServerClientParams.$StrPipeInfo.$StrWriter.Dispose()}
						catch 
						{}
					}
					if ($ServerClientParams.$StrPipeInfo.$StrPipe)
					{
						try
						{$ServerClientParams.$StrPipeInfo.$StrPipe.Dispose()}
						catch
						{}
					}
			}
		}
	}
	Elseif($ServerClientParams.$StrClient)
	{
		try
		{
			$ServerClientParams.$StrPipeInfo.$StrPipe = [IO.Pipes.NamedPipeClientStream]::new(
				$ServerClientParams.$StrPipeParams.PipeServer,
				$ServerClientParams.$StrPipeName,$ServerClientParams.$StrPipeParams.Direction
			)
			$DataObject.$StrClientPID = $Pid
			$DataObject.$StrClientUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name

			If ($ServerClientParams.$StrInfoDisplay -band 4)
			{Write-Host 'DEBUG CLIENT: About to connect to pipe...' -ForegroundColor Cyan}
			$ServerClientParams.$StrPipeInfo.$StrPipe.Connect($ServerClientParams.$StrClientConnectTimeout)
			if ($ServerClientParams.$StrPipeInfo.$StrPipe.IsConnected)
			{
				If ($ServerClientParams.$StrInfoDisplay -band 4)
				{Write-Host 'DEBUG CLIENT: Connected, creating StreamReader/Writer' -ForegroundColor Cyan}
				$ServerClientParams.$StrPipeInfo.$StrReader = [IO.StreamReader]::new($ServerClientParams.$StrPipeInfo.$StrPipe)
				$ServerClientParams.$StrPipeInfo.$StrWriter = [IO.StreamWriter]::new($ServerClientParams.$StrPipeInfo.$StrPipe)
				$ServerClientParams.$StrPipeInfo.$StrWriter.AutoFlush = $True
				# Copy InfoDisplay, ChunkSize, Depth to PipeInfo so Send-Data/Receive-Data can access them
				$ServerClientParams.$StrPipeInfo.$StrInfoDisplay = $ServerClientParams.$StrInfoDisplay
				$ServerClientParams.$StrPipeInfo.$StrChunkSize = $ServerClientParams.$StrChunkSize
				$ServerClientParams.$StrPipeInfo.$StrDepth = $ServerClientParams.$StrDepth
				# 0.11 hardening (4.2): present the capability nonce as the FIRST line so the server admits us.
				# A hand-off client (different PID) presenting the same nonce is admitted too.
				If ($ServerClientParams.$StrHandin)
				{
					# 0.12 PID hand-off: send the HANDIN marker, then READ the nonce the server returns after verifying our
					# PID, and store it so this client is normal for any later reconnect.
					$ServerClientParams.$StrPipeInfo.$StrWriter.WriteLine($StrHandinMarker)
					Try
					{
						$Private:_hnTask = $ServerClientParams.$StrPipeInfo.$StrReader.ReadLineAsync()
						If ($Private:_hnTask.Wait([int]$ServerClientParams.$StrClientConnectTimeout))
						{ $ServerClientParams.$StrNonce = [string]$Private:_hnTask.Result }
					}
					Catch { $null = $_ }
					If (-not $ServerClientParams.$StrNonce) { $ServerClientParams.$StrPipeInfo.$StrError = $True }
				}
				ElseIf ($ServerClientParams.$StrNonce)
				{$ServerClientParams.$StrPipeInfo.$StrWriter.WriteLine($ServerClientParams.$StrNonce)}
				If ($ServerClientParams.$StrInfoDisplay -band 4)
				{Write-Host 'DEBUG CLIENT: StreamReader/Writer created successfully' -ForegroundColor Green}
			}
			else
			{Write-Host 'DEBUG CLIENT: IsConnected = False!' -ForegroundColor Red}
		}
		catch
		{
			Write-Host "DEBUG CLIENT: Exception during connection: $_" -ForegroundColor Red
			$ServerClientParams.$StrPipeInfo.$StrError = $True
			NamedPipe\Get-MyErrors -Return
		}
		$ServerClientParams.$StrPipeInfo
	}
}
