<#
	.SYNOPSIS
	NamedPipe example 8 (0.16): ask a busy server what it is doing, and stop it, from OUTSIDE the blocked call.

	.DESCRIPTION
	Send-Request blocks while the server works. The command channel (the server's health pipe) is a separate path,
	so a second runspace can still reach the server:

	  Get-PipeRequestStatus   Idle / Busy (with request id and elapsed time) / Refused / Unreachable
	  Stop-PipeRequest        CANCEL the running request - the session stays open
	  Stop-PipeServer         KILL the server process - the session is lost

	It works against an ELEVATED server from a non-elevated caller, which is the case an operating-system kill
	cannot cover.

	Part A cancels an ordinary long request from a helper runspace.
	Part B shows a request that cannot be cancelled ([Console]::ReadKey blocks in native console input): the
	timeout fails to cancel it, -NoKillOnTimeout leaves the decision with you, and Stop-PipeServer ends it.

	.EXAMPLE
	powershell.exe -NoProfile -File .\08-Status-And-Stop-From-Another-Runspace.ps1
#>

Remove-Module -Name NamedPipe -Force -ErrorAction SilentlyContinue
Import-Module -Name NamedPipe -Force -RequiredVersion 0.16 -ErrorAction Stop

$Session = Start-PipeSession -MyParameters @{} -Options @{ $StrWindowStyle = $StrMinimized }
$ServerClientParams = $Session.$StrServerClientParams
$SendRequestParams  = $Session.$StrSendRequestParams
$SendRequestParams.$StrType = $StrScriptBlock
$Private:PipeInfo  = $ServerClientParams.$StrPipeInfo
$Private:ServerPid = [int]$SendRequestParams.$StrDataObject.$StrServerPID

try
{
	Write-Host "`n[A] status, then cancel a long request from another runspace" -ForegroundColor Cyan
	Write-Host ('    idle status: {0}' -f (Get-PipeRequestStatus -PipeInfo $Private:PipeInfo).State)

	# A second runspace waits 2 s, looks at the server, then cancels. (It needs the module too.)
	$Private:HelperScript = @'
param($PipeInfo)
Import-Module -Name NamedPipe -RequiredVersion 0.16 -ErrorAction Stop
Start-Sleep -Seconds 2
$s = Get-PipeRequestStatus -PipeInfo $PipeInfo
$c = Stop-PipeRequest -PipeInfo $PipeInfo
'status seen by the helper: {0} (request {1}, {2} ms in); cancel reply: {3}' -f $s.State, $s.RequestId, $s.ElapsedMs, $c
'@
	$Private:Runspace = [RunspaceFactory]::CreateRunspace()
	$Private:Runspace.Open()
	$Private:Helper = [PowerShell]::Create()
	$Private:Helper.Runspace = $Private:Runspace
	$null = $Private:Helper.AddScript($Private:HelperScript).AddArgument($Private:PipeInfo)
	$Private:Async = $Private:Helper.BeginInvoke()

	# No timeout at all here: this call would block for 2 minutes if nothing intervened.
	$Private:Watch = [Diagnostics.Stopwatch]::StartNew()
	$SendRequestParams.$StrDataObject = 'Start-Sleep -Seconds 120' | Send-Request @SendRequestParams
	$Private:Watch.Stop()
	Write-Host ('    the blocked Send-Request returned after {0:N1} s, Cancelled = {1}' -f $Private:Watch.Elapsed.TotalSeconds, $SendRequestParams.$StrDataObject.$StrCancelled)
	Write-Host ('    {0}' -f ($Private:Helper.EndInvoke($Private:Async) -join ' '))
	$Private:Helper.Dispose()
	$Private:Runspace.Dispose()

	Write-Host "`n[B] a request that cannot be cancelled" -ForegroundColor Cyan
	$SendRequestParams.$StrDataObject = '[Console]::ReadKey($true)' | Send-Request @SendRequestParams -TimeoutSeconds 3 -CancelGraceSeconds 2 -NoKillOnTimeout
	Write-Host ('    TimedOut = {0}' -f $SendRequestParams.$StrDataObject.$StrTimedOut)
	Write-Host ('    Error    = {0}' -f $SendRequestParams.$StrDataObject.$StrError)
	$Private:Status = Get-PipeRequestStatus -PipeInfo $Private:PipeInfo
	Write-Host ('    the server is still {0} ({1} ms into the request) - your decision' -f $Private:Status.State, $Private:Status.ElapsedMs)

	Write-Host '    ending it with Stop-PipeServer...'
	Write-Host ('    reply: {0}' -f (Stop-PipeServer -PipeInfo $Private:PipeInfo))
	$Private:Gone = $false
	for ($Private:i = 0; $Private:i -lt 25 -and -not $Private:Gone; $Private:i++)
	{
		Start-Sleep -Milliseconds 200
		$Private:Gone = -not (Get-Process -Id $Private:ServerPid -ErrorAction SilentlyContinue)
	}
	Write-Host ('    server process gone: {0}' -f $Private:Gone) -ForegroundColor $(if ($Private:Gone) { 'Green' } else { 'Red' })
}
finally
{
	# Nothing may be left running. -Force goes straight to KILL if the normal exit cannot be delivered.
	if (Get-Process -Id $Private:ServerPid -ErrorAction SilentlyContinue)
	{ Stop-PipeSession -SendRequestParams $SendRequestParams -PipeInfo $Private:PipeInfo -Force }
}
