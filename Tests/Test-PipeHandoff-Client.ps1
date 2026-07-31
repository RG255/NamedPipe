#!/usr/bin/env pwsh
# Hand-off CLIENT helper (the "terminal"): a separate process that reconnects to an existing server via a
# PID HANDIN (no nonce passed to it), receives the nonce over the PID-verified channel, and runs a request.
# Writes its outcome to ResultFile: 'handin-ok' on success, 'REFUSED' if the server would not admit it.
param(
    [Parameter(Mandatory)][String]$PipeName,
    [Parameter(Mandatory)][String]$ResultFile
)
$ErrorActionPreference = 'Stop'
try {
    Remove-Module NamedPipe -Force -ErrorAction SilentlyContinue
    Import-Module NamedPipe -RequiredVersion 0.12 -Force -ErrorAction Stop

    # Build a client that connects to the EXISTING pipe by name and does a HANDIN (no nonce of its own).
    $scp = Set-ObjectParams -Server -Dataset $StrServerClientParams -MyParameters @{ PipeName = $PipeName; Handin = $true }
    $scp = Set-ObjectParams -Client -Dataset $StrServerClientParams -MyParameters $scp
    $srp = Set-ObjectParams -Dataset $StrSendRequestParams -MyParameters $scp
    $mod = Get-Module NamedPipe | Where-Object { $_.Version -eq [version]'0.12' } | Select-Object -First 1
    $scp.$StrPipeInfo = $mod.Invoke({ param($d) Start-PipeServerOrClient -SerialData $d }, (ConvertTo-Serial -Object $scp))
    $srp.$StrPipeInfo = $scp.$StrPipeInfo

    if ($scp.$StrPipeInfo.$StrError -or -not $scp.$StrPipeInfo.$StrPipe.IsConnected) {
        Set-Content -Path $ResultFile -Value 'REFUSED' -NoNewline; exit 1
    }
    $srp.$StrType = $StrScriptBlock
    $srp.$StrDataObject = 'Write-Output "handin-ok"' | Send-Request @srp
    if ($srp.$StrDataObject.$StrError) { Set-Content -Path $ResultFile -Value ('ERR:' + $srp.$StrDataObject.$StrError) -NoNewline }
    else { Set-Content -Path $ResultFile -Value ([string]$srp.$StrDataObject.$StrResult) -NoNewline }
    $srp.$StrType = $StrExitPipe; $srp.$StrDataObject = '' | Send-Request @srp
    exit 0
}
catch { Set-Content -Path $ResultFile -Value ('EXC:' + $_.Exception.Message) -NoNewline; exit 20 }
