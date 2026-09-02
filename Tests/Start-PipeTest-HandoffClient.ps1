#!/usr/bin/env pwsh
# Hand-off demo CLIENT for Start-PipeTest: a SEPARATE process (its own PID) that reconnects to the harness's
# existing server via a PID HANDIN (no nonce passed to it), then runs a Write-Host ON THE SERVER so
# "Hello world - handoff client" prints on the same server window as the harness's other Hello World lines.
# Ends with a clean Disconnect (NOT ExitPipe) so the shared server survives and the harness can reconnect.
param([Parameter(Mandatory)][String]$PipeName)
$ErrorActionPreference = 'Stop'
try {
	Remove-Module NamedPipe -Force -ErrorAction SilentlyContinue
	Import-Module NamedPipe -RequiredVersion 0.13 -Force -ErrorAction Stop
	$scp = Set-ObjectParams -Server -Dataset $StrServerClientParams -MyParameters @{ PipeName = $PipeName; Handin = $true }
	$scp = Set-ObjectParams -Client -Dataset $StrServerClientParams -MyParameters $scp
	$srp = Set-ObjectParams -Dataset $StrSendRequestParams -MyParameters $scp
	$mod = Get-Module NamedPipe | Where-Object { $_.Version -eq [version]'0.13' } | Select-Object -First 1
	$scp.$StrPipeInfo = $mod.Invoke({ param($d) Start-PipeServerOrClient -SerialData $d }, (ConvertTo-Serial -Object $scp))
	$srp.$StrPipeInfo = $scp.$StrPipeInfo
	if (-not $scp.$StrPipeInfo.$StrPipe.IsConnected) { exit 1 }

	$srp.$StrType = $StrScriptBlock
	$srp.$StrDataObject = 'Write-Host -Object "Hello world - handoff client" -ForegroundColor Cyan' | Send-Request @srp

	$srp.$StrType = $StrDisconnect
	$srp.$StrDataObject = '' | Send-Request @srp
	exit 0
}
catch { exit 20 }
