<#
	.SYNOPSIS
	NamedPipe example 1: the minimal round trip - start a session, run one command, stop the session.

	.DESCRIPTION
	Start here. This is the smallest useful NamedPipe consumer: no elevation, no custom options, just
	Start-PipeSession -> Send-Request -> Stop-PipeSession. See the module's Tests\Start-PipeTest.ps1
	for a full regression harness (health checks, re-listen, hand-off, policy demo) - this script is
	deliberately NOT that; it shows one thing only, so its use is obvious.

	.EXAMPLE
	powershell.exe -NoProfile -File .\01-Basic-Session.ps1
#>

Remove-Module -Name NamedPipe -Force -ErrorAction SilentlyContinue
Import-Module -Name NamedPipe -Force -RequiredVersion 0.15 -ErrorAction Stop

Write-Host 'Starting a non-elevated pipe session...' -ForegroundColor Cyan
$Session = Start-PipeSession -MyParameters @{} -Options @{}
$ServerClientParams = $Session.$StrServerClientParams
$SendRequestParams  = $Session.$StrSendRequestParams
$SendRequestParams.$StrType = $StrScriptBlock

try
{
	Write-Host 'Sending one request: Get-Date' -ForegroundColor Cyan
	$SendRequestParams.$StrDataObject = 'Get-Date' | Send-Request @SendRequestParams

	If ($SendRequestParams.$StrDataObject.$StrError)
	{ Write-Host ('Server error: {0}' -f $SendRequestParams.$StrDataObject.$StrError) -ForegroundColor Red }
	Else
	{ Write-Host ('Server returned: {0}' -f $SendRequestParams.$StrDataObject.$StrResult) -ForegroundColor Green }
}
finally
{
	Write-Host 'Stopping the pipe session...' -ForegroundColor Cyan
	Stop-PipeSession -SendRequestParams $SendRequestParams -PipeInfo $ServerClientParams.$StrPipeInfo
}
