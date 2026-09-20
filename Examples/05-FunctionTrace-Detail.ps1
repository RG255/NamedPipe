<#
	.SYNOPSIS
	NamedPipe example 5: seeing the redacted pipe-request text in the shared function-trace log.

	.DESCRIPTION
	Turns on function tracing with BOTH bits set (Option 3 = ordinary tracing + Get-SBResult's
	request-detail logging - see Enable-MyFunctionTrace's own doc, 2026-09-16), dispatches one request,
	then reads back the last few lines of the shared trace log and shows the new
	Detail:[Request:[...]] line for Get-SBResult next to an ordinary entry-trace line, for comparison.
	Requires the core function-trace facility (CommonScripts 0.2) to already be deployed alongside this
	module version.

	.EXAMPLE
	powershell.exe -NoProfile -File .\05-FunctionTrace-Detail.ps1
#>

Remove-Module -Name NamedPipe -Force -ErrorAction SilentlyContinue
Import-Module -Name NamedPipe -Force -RequiredVersion 0.15 -ErrorAction Stop

Write-Host 'Turning on function tracing (Option 3 = ordinary tracing + Get-SBResult request detail)...' -ForegroundColor Cyan
Enable-MyFunctionTrace -Option 3
# Each window traces to its own file, named from the session id Enable-MyFunctionTrace just created.
$Private:TracePath = Join-Path -Path $env:ProgramData -ChildPath ('FunctionTrace\FunctionTrace-Session-{0}.log' -f $env:MyFunctionTraceSessionId)

try
{
	$Session = Start-PipeSession -MyParameters @{} -Options @{}
	$ServerClientParams = $Session.$StrServerClientParams
	$SendRequestParams  = $Session.$StrSendRequestParams
	$SendRequestParams.$StrType = $StrScriptBlock

	try
	{
		Write-Host 'Sending one request with a base64-looking quoted value (should be masked in the log)...' -ForegroundColor Cyan
		$Private:PotentialSecret = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('a value that could be sensitive'))
		$Private:Cmd = "Write-Output '{0}'" -f $Private:PotentialSecret
		$SendRequestParams.$StrDataObject = $Private:Cmd | Send-Request @SendRequestParams
	}
	finally
	{ Stop-PipeSession -SendRequestParams $SendRequestParams -PipeInfo $ServerClientParams.$StrPipeInfo }

	Start-Sleep -Milliseconds 500  # let the elevated server's log write land

	Write-Host ''
	Write-Host ('Get-SBResult lines from {0} (a full pipe round trip traces dozens of other' -f $Private:TracePath) -ForegroundColor Cyan
	Write-Host 'infrastructure functions too - Send-Data, Receive-Data, ConvertTo-Serial, etc. -' -ForegroundColor Cyan
	Write-Host 'filtered out here so the two lines that matter are not lost in that noise:' -ForegroundColor Cyan
	If (Test-Path -LiteralPath $Private:TracePath)
	{
		$Private:SBLines = Get-Content -LiteralPath $Private:TracePath -Tail 500 |
			Where-Object { $_ -match '\[Get-SBResult\]' } | Select-Object -Last 2
		If ($Private:SBLines)
		{
			$Private:SBLines | ForEach-Object {
				If ($_ -match 'Detail:') { Write-Host $_ -ForegroundColor Green }
				Else { Write-Host $_ -ForegroundColor DarkGray }
			}
			Write-Host ''
			Write-Host 'The green line is the new Detail:[Request:[...]] line - the grey line above it is the' -ForegroundColor Cyan
			Write-Host 'ordinary entry-trace line for the same call, for comparison. The base64-looking' -ForegroundColor Cyan
			Write-Host 'value should show as <base64 encoded>, not in the clear (see RedactPotentialSecrets in the USERGUIDE).' -ForegroundColor Cyan
		}
		Else
		{ Write-Host 'No Get-SBResult lines found in the last 500 log lines - try increasing -Tail above.' -ForegroundColor Yellow }
	}
	Else
	{ Write-Host 'Trace log not found yet - no instrumented function has written to it in this process.' -ForegroundColor Yellow }
}
finally
{
	Write-Host ''
	Write-Host 'Turning tracing back off.' -ForegroundColor Cyan
	Disable-MyFunctionTrace
}
