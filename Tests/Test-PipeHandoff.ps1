#!/usr/bin/env pwsh
#requires -Version 5.0
<#
    .SYNOPSIS
    Module regression for the 0.12 PID hand-off through a REAL spawned server. A "GUI" session arms the
    child terminal's PID (HANDOFF), disconnects; the child (separate process) reconnects via HANDIN, is
    admitted ONLY on a matching kernel-verified PID, receives the nonce, and runs a request. Non-elevated.

    Cases: (1) correct PID armed -> child admitted, request runs; (2) WRONG PID armed -> child refused.
    Proves the nonce is delivered over a PID-verified channel with nothing passed to the child out-of-band.
#>
[CmdletBinding()]
Param ()
Remove-Module NamedPipe -Force -ErrorAction SilentlyContinue
Import-Module NamedPipe -RequiredVersion 0.12 -Force -ErrorAction Stop

$Script:Pass = $true
function Assert-Case { param([string]$L, [bool]$C) if ($C) { Write-Host "[PASS] $L" -ForegroundColor Green } else { Write-Host "[FAIL] $L" -ForegroundColor Red; $Script:Pass = $false } }
$ClientScript = Join-Path $PSScriptRoot 'Test-PipeHandoff-Client.ps1'

function Invoke-HandoffCase {
    param([string]$Label, [bool]$ArmWrong, [bool]$ExpectAdmit)

    $mo = Set-ObjectParams -Dataset $StrMyOptions -MyParameters @{}
    $mo.$StrWindowStyle = $StrHidden
    $Session = Start-PipeSession -MyParameters $mo          # the "GUI" - connected, holds the nonce
    $scp = $Session.$StrServerClientParams
    $srp = $Session.$StrSendRequestParams
    $PipeName = $scp.$StrPipeInfo.$StrName
    $ResultFile = Join-Path $env:TEMP ('handoff-' + [Guid]::NewGuid().ToString('N') + '.txt')

    # Spawn the terminal FIRST (learn its PID). It will block on Connect (single instance) until the GUI yields.
    $Child = Start-Process -FilePath 'pwsh.exe' -PassThru -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-File', $ClientScript, '-PipeName', $PipeName, '-ResultFile', $ResultFile)
    $ArmPid = if ($ArmWrong) { $PID } else { $Child.Id }   # wrong = this rig's own PID (never the child)

    # Arm the server over the authenticated GUI connection, then yield (Disconnect + drop the client handle).
    $srp.$StrType = $StrHandoff
    $srp.$StrDataObject = ("{0}" -f $ArmPid) | Send-Request @srp
    $srp.$StrType = $StrDisconnect
    $srp.$StrDataObject = '' | Send-Request @srp
    try { $scp.$StrPipeInfo.$StrWriter.Dispose() } catch { $null = $_ }
    try { $scp.$StrPipeInfo.$StrReader.Dispose() } catch { $null = $_ }
    try { $scp.$StrPipeInfo.$StrPipe.Dispose() } catch { $null = $_ }

    $Child.WaitForExit(20000) | Out-Null
    $Got = if (Test-Path $ResultFile) { (Get-Content $ResultFile -Raw) } else { '' }
    Remove-Item $ResultFile -Force -ErrorAction SilentlyContinue

    Write-Host ("       armed PID {0} (child {1}, rig {2}) -> child result: [{3}]" -f $ArmPid, $Child.Id, $PID, $Got) -ForegroundColor DarkGray
    if ($ExpectAdmit) { Assert-Case $Label ($Got -eq 'handin-ok') }
    else { Assert-Case $Label ($Got -eq 'REFUSED' -or $Got -like 'ERR:*' -or $Got -eq '') }
}

Write-Host "`n=== PID hand-off module regression (real spawned server) ===" -ForegroundColor Magenta
Invoke-HandoffCase -Label 'Correct PID armed -> terminal admitted via HANDIN, request runs' -ArmWrong $false -ExpectAdmit $true
Invoke-HandoffCase -Label 'WRONG PID armed -> terminal refused'                            -ArmWrong $true  -ExpectAdmit $false

Write-Host ''
if ($Script:Pass) { Write-Host '=== PID HAND-OFF MODULE: ALL PASSED ===' -ForegroundColor Green; exit 0 }
else { Write-Host '=== PID HAND-OFF MODULE: FAILURES ABOVE ===' -ForegroundColor Red; exit 1 }
