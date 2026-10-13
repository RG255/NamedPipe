<#
	.SYNOPSIS
	NamedPipe example 9 (0.16): the server no longer waits for input it can never receive, and Wait now ends.

	.DESCRIPTION
	Two changes that remove the commonest ways a hidden server window used to hang:

	  1. The server is started with -NonInteractive. A request that calls Read-Host or 'pause' fails at once
	     with an ordinary error instead of blocking for ever on a window nobody is looking at.
	     (Raw console reads such as [Console]::ReadKey are not covered - see example 8.)

	  2. The Wait option (keep the server window open after the pipe exits so you can read it) used 'Pause',
	     which waits for ever. It is now a bounded wait: WaitSeconds (default 300, 1..3600), ended early by a
	     keypress. This script sets 5 seconds and measures how long the server process really lives.

	The server window is brought to the front for the wait, so a minimised window will pop up for 5 seconds.

	.EXAMPLE
	powershell.exe -NoProfile -File .\09-NonInteractive-And-Bounded-Wait.ps1
#>

Remove-Module -Name NamedPipe -Force -ErrorAction SilentlyContinue
Import-Module -Name NamedPipe -Force -RequiredVersion 0.16 -ErrorAction Stop

$Session = Start-PipeSession -MyParameters @{} -Options @{
	$StrWindowStyle = $StrMinimized
	$StrWait        = $true
	$StrWaitSeconds = 5
}
$ServerClientParams = $Session.$StrServerClientParams
$SendRequestParams  = $Session.$StrSendRequestParams
$SendRequestParams.$StrType = $StrScriptBlock
$Private:ServerPid = [int]$SendRequestParams.$StrDataObject.$StrServerPID

try
{
	Write-Host "`n[1] how the server was launched" -ForegroundColor Cyan
	$Private:CommandLine = (Get-CimInstance -ClassName Win32_Process -Filter ('ProcessId={0}' -f $Private:ServerPid)).CommandLine
	Write-Host ('    -NonInteractive present: {0}' -f ($Private:CommandLine -match '-NonInteractive'))

	Write-Host "`n[2] a request that asks the console for input" -ForegroundColor Cyan
	$Private:Watch = [Diagnostics.Stopwatch]::StartNew()
	$SendRequestParams.$StrDataObject = 'Read-Host -Prompt "anyone there"' | Send-Request @SendRequestParams
	$Private:Watch.Stop()
	$Private:Reason = [regex]::Match([string]$SendRequestParams.$StrDataObject.$StrError, '[^\r\n]*NonInteractive[^\r\n]*').Value.Trim()
	Write-Host ('    returned after {0:N1} s instead of hanging' -f $Private:Watch.Elapsed.TotalSeconds) -ForegroundColor Green
	Write-Host ('    reason: {0}' -f $Private:Reason)

	$SendRequestParams.$StrDataObject = 'Write-Output "the session is fine"' | Send-Request @SendRequestParams
	Write-Host ('    next request: {0}' -f $SendRequestParams.$StrDataObject.$StrResult)
}
finally
{
	Write-Host "`n[3] closing the session; the server window should stay up for about 5 s, then close by itself" -ForegroundColor Cyan
	$Private:Closed = [Diagnostics.Stopwatch]::StartNew()
	Stop-PipeSession -SendRequestParams $SendRequestParams -PipeInfo $ServerClientParams.$StrPipeInfo
	while ((Get-Process -Id $Private:ServerPid -ErrorAction SilentlyContinue) -and $Private:Closed.Elapsed.TotalSeconds -lt 30)
	{ Start-Sleep -Milliseconds 200 }
	$Private:Closed.Stop()
	Write-Host ('    the server process lived {0:N1} s after the session was closed' -f $Private:Closed.Elapsed.TotalSeconds) -ForegroundColor Green
}
