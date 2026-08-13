#!/usr/bin/env powershell
#requires -Version 5.0
[CmdletBinding()]
Param (
	[Parameter(DontShow = $True)]
	[String]$PipeName = $Null,
	[Parameter(Dontshow = $True)]
	[String[]]$AccessIdentifier = @(),
	[Parameter(DontShow = $False)]
	[Switch]$AdminRequired,
	[Parameter(DontShow = $False)]
	[Switch]$Wait,
	[Parameter(HelpMessage = 'Bitmask: 0=silent, 1=server/client progress, 2=Show-VerboseData, 4=debug, 8=keep clean-run log (15=all)')]
	[ValidateRange(0, 15)]
	[int]$InfoDisplay = 0,
	[Parameter(DontShow = $False)]
	[Switch]$NoExitOnError,
	[Parameter(HelpMessage = 'Serialization depth. Default 2. Increase for deeply nested objects (avoid high values for ACL objects)')]
	[ValidateRange(1, 100)]
	[int]$Depth = 2,
	[ValidateRange(1024, 65535)]
	[int]$ChunkSize = 32768,
	[ValidateRange(1, [Int32]::MaxValue)]
	$ServerWaitTimeout = 60,
	[ValidateRange(1, [Int32]::MaxValue)]
	$ClientConnectTimeout=10000,
	[Parameter(HelpMessage = '0.10: turn ON the request allowlist. Allows only Set-Window + Write-Host (what this harness uses) and DEMOnstrates blocked requests.')]
	[Switch]$DemoPolicy

)

Remove-Module -name NamedPipe -force -ErrorAction SilentlyContinue
# Use the DEPLOYED 0.13 by name+version. Loading source by path timed out because the spawned
# SERVER process re-resolves the module and the source dev folder is not on PSModulePath. Deploy 0.13
# (side-by-side) and re-deploy after each source change before testing.
Import-Module -Name NamedPipe -Force -RequiredVersion 0.13
function Invoke-RequiredActions
{
  <#
      .SYNOPSIS
      Describe purpose of "Invoke-RequiredActions" in 1-2 sentences.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER DataObject
      Describe parameter -DataObject.

      .PARAMETER PipeInfo
      Describe parameter -PipeInfo.

      .EXAMPLE
      Invoke-RequiredActions -DataObject Value -PipeInfo Value
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Invoke-RequiredActions

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>

  # Get the current secirity setting on the pipe
  $SendRequestParams.$StrType = $StrSecurity
  $SendRequestParams.$StrDataObject = '' | 
  Send-Request @SendRequestParams

  If ($ServerClientParams.$StrInfoDisplay -band 2)
  {
    # Display the security setting on the pipe
    '{0}' -f $SendRequestParams.$StrDataObject.$StrResult
    'Client user is: [{0}]' -f $SendRequestParams.$StrDataObject.$StrClientUser
    'Server user is: [{0}]' -f $SendRequestParams.$StrDataObject.$StrServerUser
    $count = $SendRequestParams.$StrDataObject.Result.count-1
    '   Security is:'
    if ($PSVersionTable.PSVersion.Major -gt 5) 
    {$SendRequestParams.$StrDataObject.Result.accesstostring}
    else
    {$SendRequestParams.$StrDataObject.Result[0..$count]}
    Show-VerboseData -Object $SendRequestParams.$StrDataObject -Display -Title 'Data Object After Security call'
  }
	
  $SendRequestParams.$StrType = $StrScriptBlock
	
  #Remove-Breakpoints -All
  #$BPList = Initialize-BPList -AddModules
	
  #$BPList.'Start-PipeServerorClient'.lines.line = 140
  #$BPList.'Start-PipeServerorClient'.lines.Script = $BPList.'Start-PipeServerorClient'.Fullname
  #$BPList.'Receive-Data'.lines.line = 22
  #$BPList.'Receive-Data'.lines.Script = $BPList.'Receive-Data'.Fullname
  #$BPList.'Get-SBResult'.lines.line=30
  #$BPList.'Get-SBResult'.lines.Script=$BPList.'Get-SBResult'.Fullname

  # Set any defined breakpoints
  #$SendRequestParams.$StrDataObject.$StrData = $BPList
  #$SendRequestParams.$StrDataObject = 'Set-Breakpoints -BPObject $DataObject.data' | 
  #Send-Request @SendRequestParams
  #$BPList = $SendRequestParams.$StrDataObject.$StrResult
	
  #$BPList = Initialize-BPList -AddModules
  #$BPList.'Get-SBResult'.lines.line=12
  #$BPList.'Get-SBResult'.lines.Script=$BPList.'Get-SBResult'.Fullname
  #$BPList.'Show-VerboseData'.lines.line = 106
  #$BPList.'Show-VerboseData'.lines.Script = $BPList.'Show-VerboseData'.Fullname
			
  #$SendRequestParams.$StrDataObject.$StrData = $BPList
  #$SendRequestParams.$StrDataObject = 'Set-Breakpoints -BPObject $DataObject.data' |
  #Send-Request @SendRequestParams
  #$BPList = $SendRequestParams.$StrDataObject.$StrResult
	
  #$SendRequestParams.$StrDataObject.$Strdata = $BPList
  #$SendRequestParams.$StrDataObject = 'Set-Breakpoints -BPObject $DataObject.data' | 
  #Send-Request @SendRequestParams
	
  $SWParam =@{
    Passthru =$true
    Set = $True
  }
	
  $SendRequestParams.$StrDataObject.$StrParameters = $SWParam
  $SendRequestParams.$StrDataObject = 'Set-Window -ProcessId {0} -State {1}' -f $SendRequestParams.$StrDataObject.$StrServerPID, $StrRestore|
  Send-Request @SendRequestParams
	
  if ($SendRequestParams.$StrDataObject.$StrError)
  {write-information -MessageData $SendRequestParams.$StrDataObject.$StrError -InformationAction Continue}
	
  $SendRequestParams.$StrDataObject = 'Write-Host -Object "{0}" -Foreground Green' -f 'Hello World' |
  Send-Request @SendRequestParams
  $SendRequestParams.$StrDataObject = 'Set-Window -ProcessId {0} -State {1} -Set -Passthru' -f $SendRequestParams.$StrDataObject.$StrServerPID, $StrMinimize|
  Send-Request @SendRequestParams
  $null = $SendRequestParams.$StrDataObject.$StrResult

  # ===== REQUEST POLICY DEMO (only when a RequestPolicy is active, i.e. -DemoPolicy) =====
  # Sends one ALLOWED request and several DISALLOWED ones. The server runs the allowed one and refuses
  # the rest BEFORE execution, returning Error = 'Request blocked by pipe request policy: ...'.
  if ($ServerClientParams.RequestPolicy)
  {
    Write-Host ("`n[Policy] RequestPolicy ACTIVE - AllowedCommands: {0}" -f ($ServerClientParams.RequestPolicy.AllowedCommands -join ', ')) -ForegroundColor Cyan

    # (a) ALLOWED - Write-Host is on the allowlist, so it runs on the server (no policy error):
    $SendRequestParams.$StrDataObject = 'Write-Host -Object "[Policy] ALLOWED request executed on the server" -ForegroundColor Green' | Send-Request @SendRequestParams
    Write-Host ("[Policy] ALLOWED (Write-Host)         -> Error: [{0}]" -f $SendRequestParams.$StrDataObject.$StrError) -ForegroundColor Green

    # (b) BLOCKED - Get-Process is not on the allowlist:
    $SendRequestParams.$StrDataObject = 'Get-Process -Name explorer' | Send-Request @SendRequestParams
    Write-Host ("[Policy] BLOCKED (Get-Process)        -> Error: [{0}]" -f $SendRequestParams.$StrDataObject.$StrError) -ForegroundColor Yellow

    # (c) BLOCKED - a direct .NET method call (classic injection):
    $SendRequestParams.$StrDataObject = '[System.IO.File]::WriteAllText("C:\pwn.txt","x")' | Send-Request @SendRequestParams
    Write-Host ("[Policy] BLOCKED (.NET injection)     -> Error: [{0}]" -f $SendRequestParams.$StrDataObject.$StrError) -ForegroundColor Yellow

    # (d) BLOCKED - the language-mode flip (the case a blocklist would MISS; default-deny catches it):
    $SendRequestParams.$StrDataObject = '$ExecutionContext.SessionState.LanguageMode = "FullLanguage"' | Send-Request @SendRequestParams
    Write-Host ("[Policy] BLOCKED (LanguageMode flip)  -> Error: [{0}]" -f $SendRequestParams.$StrDataObject.$StrError) -ForegroundColor Yellow
  }

  # ===== RE-LISTEN TEST =====
  # Send a clean Disconnect request. The server handles $StrDisconnect in the Switch,
  # sends back an OK response, then disposes Reader/Writer, calls Disconnect(), and
  # loops back to WaitForConnection - no exceptions involved.
  $Private:RlPipeName = $ServerClientParams.$StrPipeInfo.$StrName
  Write-Host ("`n[ReListen] Sending Disconnect request - server should re-listen on [{0}]..." -f $Private:RlPipeName) -ForegroundColor Cyan
  $SendRequestParams.$StrType = $StrDisconnect
  $SendRequestParams.$StrDataObject = '' | Send-Request @SendRequestParams
  $SendRequestParams.$StrType = $StrScriptBlock
  try { $ServerClientParams.$StrPipeInfo.$StrWriter.Dispose() } catch { $null = $_ }
  try { $ServerClientParams.$StrPipeInfo.$StrReader.Dispose() } catch { $null = $_ }
  Start-Sleep -Milliseconds 300   # give server time to complete Disconnect() and call WaitForConnection

  Write-Host '[ReListen] Reconnecting to the same pipe server...' -ForegroundColor Cyan
  $Private:RlScp    = Set-ObjectParams -Client -Dataset $StrServerClientParams -MyParameters $ServerClientParams
  $Private:RlModule = Get-Module -Name NamedPipe | Select-Object -First 1
  $Private:RlScp.$StrPipeInfo = $Private:RlModule.Invoke(
    { param($d) Start-PipeServerOrClient -SerialData $d },
    (ConvertTo-Serial -Object $Private:RlScp)
  )

  If ($Private:RlScp.$StrPipeInfo.$StrError -or -not $Private:RlScp.$StrPipeInfo.$StrPipe.IsConnected)
  {
    Write-Host '[ReListen] FAILED - server did not re-listen or connection refused.' -ForegroundColor Red
  }
  Else
  {
    # Update session refs: hashtable mutation propagates $SendRequestParams to caller scope;
    # use Set-Variable for $ServerClientParams so health check and Stop-PipeSession use new connection.
    Set-Variable -Name ServerClientParams -Value $Private:RlScp -Scope 1
    $SendRequestParams.$StrPipeInfo = $Private:RlScp.$StrPipeInfo
    $SendRequestParams.$StrDataObject = 'Write-Host -Object "Re-listen reconnect confirmed" -ForegroundColor Cyan' |
    Send-Request @SendRequestParams
    Write-Host '[ReListen] PASSED - server re-listened and accepted the new connection.' -ForegroundColor Green
  }
  # ===== END RE-LISTEN TEST =====

  # ===== HAND-OFF TEST (0.13 PID hand-off) =====
  # A SEPARATE process (its own PID) reconnects to THIS server via a PID HANDIN and runs a Write-Host on the
  # server, so "Hello world - handoff client" prints on the SAME server window as the other Hello World lines -
  # proving the nonce reached the vouched-for terminal without crossing any out-of-band channel.
  $Private:HoPipeName = $ServerClientParams.$StrPipeInfo.$StrName
  $Private:HoClient   = Join-Path $PSScriptRoot 'Start-PipeTest-HandoffClient.ps1'
  Write-Host "`n[Handoff] Spawning a hand-off terminal; watch the SERVER window for 'Hello world - handoff client'..." -ForegroundColor Cyan
  # 1. Spawn the terminal FIRST to learn its PID; it blocks on Connect (single instance) until we yield.
  $Private:HoChild = Start-Process -FilePath 'pwsh.exe' -PassThru -WindowStyle Hidden -ArgumentList @(
    '-NoProfile', '-File', $Private:HoClient, '-PipeName', $Private:HoPipeName)
  if ($Private:HoChild.HasExited)
  { Write-Host '[Handoff] terminal exited before we could arm it - skipping.' -ForegroundColor Yellow }
  else
  {
    # 2. Arm the server with the terminal's PID over the live (authenticated) session.
    $SendRequestParams.$StrType = $StrHandoff
    $SendRequestParams.$StrDataObject = ('{0}' -f $Private:HoChild.Id) | Send-Request @SendRequestParams
    Write-Host ('[Handoff] armed for terminal PID {0}: {1}' -f $Private:HoChild.Id, $SendRequestParams.$StrDataObject.$StrResult) -ForegroundColor DarkGray
    # 3. Yield: clean Disconnect + fully dispose the client handle so the terminal can take the single instance.
    $SendRequestParams.$StrType = $StrDisconnect
    $SendRequestParams.$StrDataObject = '' | Send-Request @SendRequestParams
    $SendRequestParams.$StrType = $StrScriptBlock
    try { $ServerClientParams.$StrPipeInfo.$StrWriter.Dispose() } catch { $null = $_ }
    try { $ServerClientParams.$StrPipeInfo.$StrReader.Dispose() } catch { $null = $_ }
    try { $ServerClientParams.$StrPipeInfo.$StrPipe.Dispose() } catch { $null = $_ }
    # 4. The terminal connects (HANDIN), gets the nonce, Write-Hosts on the server, then Disconnects.
    $Private:HoChild.WaitForExit(15000) | Out-Null
    Start-Sleep -Milliseconds 300
    # 5. Reconnect the harness (normal nonce path) so the remaining actions + health check + Stop still work.
    $Private:HoScp = Set-ObjectParams -Client -Dataset $StrServerClientParams -MyParameters $ServerClientParams
    $Private:HoMod = Get-Module -Name NamedPipe | Select-Object -First 1
    $Private:HoScp.$StrPipeInfo = $Private:HoMod.Invoke(
      { param($d) Start-PipeServerOrClient -SerialData $d },
      (ConvertTo-Serial -Object $Private:HoScp)
    )
    If ($Private:HoScp.$StrPipeInfo.$StrError -or -not $Private:HoScp.$StrPipeInfo.$StrPipe.IsConnected)
    { Write-Host '[Handoff] FAILED - could not reconnect the harness after the hand-off.' -ForegroundColor Red }
    Else
    {
      Set-Variable -Name ServerClientParams -Value $Private:HoScp -Scope 1
      $SendRequestParams.$StrPipeInfo = $Private:HoScp.$StrPipeInfo
      Write-Host '[Handoff] PASSED - the terminal ran on the server (its Hello World is on the server window) and the harness reconnected.' -ForegroundColor Green
    }
  }
  # ===== END HAND-OFF TEST =====

  $SendRequestParams.$StrDataObject = 'Write-Host -Object "{0}" -Foreground red' -f 'Hello World'|
  Send-Request @SendRequestParams

  $SendRequestParams.$StrDataObject = 'Get-Process -name explorer'|
  Send-Request @SendRequestParams
  Write-Host -Object ('Get-Process rejected: {0}{1}' -f $StrCRLF,$SendRequestParams.$StrDataObject.error) -ForegroundColor Red
  $SendRequestParams.$StrDataObject.result
	
  $SendRequestParams.$StrDataObject = 'Set-Window -ProcessId ${0} -Passthru' -f 'pid'|
  Send-Request @SendRequestParams
  If ($ServerClientParams.$StrInfoDisplay -band 2)
  {Show-VerboseData -Object $SendRequestParams.DataObject -Display -Title 'Data Object Set-Window call'}
	
  $SendRequestParams.$StrDataObject = 'Set-Window -ProcessId {0} -State {1} -Set -Passthru -characters' -f $SendRequestParams.$StrDataObject.$StrServerPID, $StrRestore|
  Send-Request @SendRequestParams
  #start-sleep -Seconds 5
  #$SendRequestParams.DataObject = 'Get-MyDiskInfo -disknumber 0 '| Send-Request @SendRequestParams
  #D:\PowerShellScripts\DisplayMyDisks\Display-MyDisks.ps1 -DiskInfo $SendRequestParams.DataObject.Result -sdisk
	
  #Start-Sleep -Seconds 5
	
  # Remove any defined breakpoints
  #$SendRequestParams.$StrDataObject.data = $BPList
  #$SendRequestParams.$StrDataObject = 'Remove-Breakpoints -BPObject $DataObject.data' |
  #Send-Request @SendRequestParams
	
}

#############################
# End of Functions
#############################
$Private:MyBoundParameters = $PSCmdlet.MyInvocation.BoundParameters
$Global:Error.Clear()

('Module version is {0}' -f $ModuleVersion) | Write-Host 

#$BPList.'Get-SBResult'.lines.Script=$BPList.'Get-SBResult'.Fullname
#$BPList.'Set-Breakpoints'.lines.line=17
#$BPList.'Set-Breakpoints'.lines.Script=$BPList.'Set-Breakpoints'.Fullname
#Set-PSBreakpoint -Line 12 -Script $BPlist.'Get-SBResult'.Fullname
#$BPList = Initialize-BPList -AddModules

#$BPList.'Start-PipeTest'.lines.Line=145
#$BPList.'Start-PipeTest'.lines.Script=$BPList.'Start-PipeTest'.Fullname

#$BPList.'Send-Request'.lines.Line=32
#$BPList.'Send-Request'.lines.Script=$BPList.'Send-Request'.Fullname

#$BPList.'Set-Breakpoints'.lines.line=17
#$BPList.'Set-Breakpoints'.lines.Script=$BPList.'Set-Breakpoints'.Fullname

#$BPList = Set-Breakpoints -BPObject $BPList
#$BPList = Remove-Breakpoints -BPObject $BPList
$Private:MyOptions = Set-ObjectParams -Dataset $StrMyOptions -MyParameters $Private:MyBoundParameters
# These options can be set to enable various options but can also be part of a script's parameters at startup
#$MyOptions.$StrInfoDisplay = $InfoDisplay # Bitmask: 0=silent, 1=server/client progress, 2=Show-VerboseData, 4=debug output, 8=keep clean-run log (combine: 3=1+2, 15=all)
#$MyOptions.$StrNoExitOnError = $NoExitOnError # The powershell window will not close when an error has occured
#$MyOptions.$StrAdminRequired = $AdminRequired # Set to true in the server process needs to run as administrator
#$MyOptions.$StrVerbose = $False # Will pass the -verbose option if required when true
#$MyOptions.$StrWait = $Wait # Will cause the server window to remain open when the pipe is exited
#$MyOptions.$StrWindowStyle = $StrMinimized
$Private:MyOptions.$StrWindowStyle = $StrNormal

# 0.10 injection hardening: turn ON the request allowlist for this session. It MUST be passed via
# -Options (the supported path): a RequestPolicy set on $MyOptions and handed to -MyParameters is
# DROPPED, because Start-PipeSession rebuilds MyOptions from known fields only and RequestPolicy is not
# one. Allow only the commands this harness sends (Set-Window, Write-Host); every other request is
# refused by the server BEFORE execution. Plain runs (no -DemoPolicy) are unaffected = identical to 0.9.
$Private:SessionOptions = @{}
if ($DemoPolicy)
{
	$Private:SessionOptions.RequestPolicy = @{ AllowedCommands = @('Set-Window', 'Write-Host') }
	Write-Host ("`n[Policy] -DemoPolicy ON. RequestPolicy AllowedCommands = Set-Window, Write-Host. All other requests will be refused.") -ForegroundColor Cyan
}
#$MyOptions.$StrChunkSize = $ChunkSize # Chunk size for large data transfers (32KB default, 0 = no chunking)
#$MyOptions.$StrDepth = $Depth # Serialization depth (default 2, avoid >10 for ACL objects)
#$MyOptions.$StrServerWaitTimeout = $ServerWaitTimeout 
#$MyOptions.$StrClientConnectTimeout=$ClientConnectTimeout

# The serverClientParams dataset is populated with MyOptions as this dataset already contains any script supplied parameters

$Session = Start-PipeSession -MyParameters $Private:MyOptions -Options $Private:SessionOptions
$ServerClientParams = $Session.$StrServerClientParams
$SendRequestParams  = $Session.$StrSendRequestParams


# ===== HEALTH PIPE CHECK =====

Write-Host ("`n[Health] Testing health pipe for [{0}]..." -f $ServerClientParams.$StrPipeInfo.$StrName) -ForegroundColor Cyan

$HealthResult = Test-PipeSession -PipeInfo $ServerClientParams.$StrPipeInfo

If ($HealthResult)

{ Write-Host "[Health] PING/PONG OK - server process confirmed alive." -ForegroundColor Green }

Else

{ Write-Host "[Health] PING/PONG FAILED - server may not be responding." -ForegroundColor Red }

# ===== 4.1b REGRESSION CHECK: the DATA pipe must carry the Medium mandatory integrity label =====
# The server applies it automatically (Set-PipeIntegrityLabel). Read it off the connected client handle
# via GetSecurityInfo(LABEL) - no privilege. Full low-IL blocking proof is Tests\Test-PipeIntegrityLabel.ps1.
if (-not ('PipeTestLabelRead' -as [type])) {
	Add-Type @"
using System; using System.Runtime.InteropServices;
public static class PipeTestLabelRead {
  [DllImport("advapi32.dll", SetLastError=true)]
  public static extern uint GetSecurityInfo(IntPtr h,int ot,uint si,IntPtr o,IntPtr g,IntPtr d,IntPtr s,out IntPtr sd);
  [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool ConvertSecurityDescriptorToStringSecurityDescriptor(IntPtr sd,uint rev,uint si,out IntPtr str,out int len);
  [DllImport("kernel32.dll")] public static extern IntPtr LocalFree(IntPtr p);
}
"@
}
try {
	$Private:LblH  = $ServerClientParams.$StrPipeInfo.$StrPipe.SafePipeHandle.DangerousGetHandle()
	$Private:LblSd = [IntPtr]::Zero
	$Private:LblRc = [PipeTestLabelRead]::GetSecurityInfo($Private:LblH,6,0x10,[IntPtr]::Zero,[IntPtr]::Zero,[IntPtr]::Zero,[IntPtr]::Zero,[ref]$Private:LblSd)
	$Private:LblSddl = ''
	if ($Private:LblRc -eq 0) {
		$Private:LblStr=[IntPtr]::Zero; $Private:LblLen=0
		[void][PipeTestLabelRead]::ConvertSecurityDescriptorToStringSecurityDescriptor($Private:LblSd,1,0x10,[ref]$Private:LblStr,[ref]$Private:LblLen)
		$Private:LblSddl=[System.Runtime.InteropServices.Marshal]::PtrToStringUni($Private:LblStr)
		[void][PipeTestLabelRead]::LocalFree($Private:LblStr); [void][PipeTestLabelRead]::LocalFree($Private:LblSd)
	}
	if ($Private:LblSddl -match 'ML;.*;ME') {
		Write-Host ("[Label] 4.1b OK - DATA pipe carries the Medium integrity label [{0}]." -f $Private:LblSddl) -ForegroundColor Green
	} else {
		Write-Host ("[Label] 4.1b REGRESSION? - DATA pipe has no Medium integrity label (got '[{0}]')." -f $Private:LblSddl) -ForegroundColor Red
	}
} catch {
	Write-Host ("[Label] 4.1b - could not read the pipe label: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
}

Invoke-RequiredActions



# ===== POST-ACTION HEALTH CHECK =====

Write-Host "`n[Health] Post-action health check..." -ForegroundColor Cyan

$HealthResult2 = Test-PipeSession -PipeInfo $ServerClientParams.$StrPipeInfo

If ($HealthResult2)
{ Write-Host "[Health] Server still alive after actions completed." -ForegroundColor Green }
Else
{ Write-Host "[Health] Post-action health check FAILED." -ForegroundColor Red }

Show-VerboseData -Object $SendRequestParams.PipeInfo -Display -Title 'PipeName'

Stop-PipeSession -SendRequestParams $SendRequestParams -PipeInfo $ServerClientParams.$StrPipeInfo

Get-PSBreakpoint
# Remove-Breakpoints -All