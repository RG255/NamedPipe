<#
	.SYNOPSIS
	NamedPipe example 7 (0.16): get out of a request that does not come back - timeouts and cancel.

	.DESCRIPTION
	Before 0.16 a request that looped, or sat waiting for input in a hidden server window, left Send-Request
	waiting for ever. This script shows the two timeouts and what a cancel looks like from the caller's side:

	  1. -TimeoutSeconds   an INACTIVITY timeout: the longest wait for the next message from the server.
	  2. a request that reports progress is NOT timed out by it - every Send-ProgressInfo message restarts it.
	  3. -MaxRuntimeSeconds an ABSOLUTE cap that progress cannot extend.

	In every case the server cancels the request and answers normally with Cancelled = $true, and the SAME
	session is still open for the next request - the caller decides what to do next.

	Both timeouts default to 0 (unbounded), exactly as before 0.16, so nothing changes unless you pass one.
	A timeout abandons the work; it does not roll it back.

	.EXAMPLE
	powershell.exe -NoProfile -File .\07-Timeout-And-Cancel.ps1
#>

Remove-Module -Name NamedPipe -Force -ErrorAction SilentlyContinue
Import-Module -Name NamedPipe -Force -RequiredVersion 0.16 -ErrorAction Stop

$Session = Start-PipeSession -MyParameters @{} -Options @{ $StrWindowStyle = $StrMinimized }
$ServerClientParams = $Session.$StrServerClientParams
$SendRequestParams  = $Session.$StrSendRequestParams
$SendRequestParams.$StrType = $StrScriptBlock

try
{
	# --- 1. a request that would take a minute, with a 3 second inactivity timeout ---
	Write-Host "`n[1] 'Start-Sleep 60' with -TimeoutSeconds 3" -ForegroundColor Cyan
	$Private:Watch = [Diagnostics.Stopwatch]::StartNew()
	$SendRequestParams.$StrDataObject = 'Start-Sleep -Seconds 60' | Send-Request @SendRequestParams -TimeoutSeconds 3
	$Private:Watch.Stop()
	$Private:Result = $SendRequestParams.$StrDataObject
	Write-Host ('    came back after {0:N1} s' -f $Private:Watch.Elapsed.TotalSeconds)
	Write-Host ('    Cancelled = {0}' -f $Private:Result.$StrCancelled)
	Write-Host ('    Error     = {0}' -f $Private:Result.$StrError)

	# --- the session is still open: ask for something else ---
	Write-Host "`n[2] the SAME session, next request" -ForegroundColor Cyan
	$SendRequestParams.$StrDataObject = 'Write-Output "still here"' | Send-Request @SendRequestParams
	Write-Host ('    result: {0}' -f $SendRequestParams.$StrDataObject.$StrResult) -ForegroundColor Green

	# --- 3. progress keeps a busy request alive past the inactivity timeout ---
	Write-Host "`n[3] 5 seconds of work that reports progress each second, -TimeoutSeconds 3" -ForegroundColor Cyan
	$Private:Work = @'
1..5 | ForEach-Object {
	Send-ProgressInfo -String ('working {0} of 5' -f $_) -Type Console
	Start-Sleep -Seconds 1
}
'finished'
'@
	$Private:Watch.Restart()
	$SendRequestParams.$StrDataObject = $Private:Work | Send-Request @SendRequestParams -TimeoutSeconds 3
	$Private:Watch.Stop()
	Write-Host ('    result: {0} (took {1:N1} s, longer than the 3 s timeout, because it kept reporting)' -f $SendRequestParams.$StrDataObject.$StrResult, $Private:Watch.Elapsed.TotalSeconds) -ForegroundColor Green

	# --- 4. an absolute cap that progress cannot extend ---
	Write-Host "`n[4] the same kind of work, but it would run 30 s - with -MaxRuntimeSeconds 4" -ForegroundColor Cyan
	$Private:Long = $Private:Work.Replace('1..5', '1..30')
	$Private:Watch.Restart()
	$SendRequestParams.$StrDataObject = $Private:Long | Send-Request @SendRequestParams -TimeoutSeconds 3 -MaxRuntimeSeconds 4
	$Private:Watch.Stop()
	Write-Host ('    came back after {0:N1} s, Cancelled = {1}' -f $Private:Watch.Elapsed.TotalSeconds, $SendRequestParams.$StrDataObject.$StrCancelled)
}
finally
{ Stop-PipeSession -SendRequestParams $SendRequestParams -PipeInfo $ServerClientParams.$StrPipeInfo }

Write-Host ''
Write-Host 'A cancel keeps the session. A request that CANNOT be cancelled (for example one blocked in raw console' -ForegroundColor Cyan
Write-Host 'input) gets the server killed instead - see 08-Status-And-Stop-From-Another-Runspace.ps1.' -ForegroundColor Cyan
