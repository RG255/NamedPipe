#!/usr/bin/env pwsh
#requires -Version 5.0
<#
    .SYNOPSIS
    Regression for the 0.11 connect-deadline (hardening 4.3): an UNCLAIMED elevated server self-terminates
    quickly (~ClientConnectTimeout budget) instead of lingering the full 60s re-listen window, and logs a
    `timed-out-unclaimed` failure. Spawns a REAL server WITHOUT connecting a client. Non-elevated (no UAC).
#>
[CmdletBinding()]
Param ()

Remove-Module NamedPipe -Force -ErrorAction SilentlyContinue
Import-Module NamedPipe -RequiredVersion 0.13 -Force -ErrorAction Stop

$pass = $true
function Check($l, $c) { if ($c) { Write-Host "[PASS] $l" -ForegroundColor Green } else { Write-Host "[FAIL] $l" -ForegroundColor Red; $script:pass = $false } }

# Build a SERVER with a short ClientConnectTimeout so the budget (=CCT+2000) is ~5s, then spawn WITHOUT a client.
$mo = Set-ObjectParams -Dataset $StrMyOptions -MyParameters @{}
$mo.$StrClientConnectTimeout = 3000
$mo.$StrWindowStyle          = $StrHidden
$mo.$StrAccessIdentifier     = @(('{0}:Allow:ReadWrite' -f [Security.Principal.WindowsIdentity]::GetCurrent().Name))
$scp = Set-ObjectParams -Server -Dataset $StrServerClientParams -MyParameters $mo
$pipeName = $scp.$StrPipeInfo.$StrName

Write-Host ("`n=== Connect-deadline test (budget ~{0}ms, pipe {1}) ===" -f ($mo.$StrClientConnectTimeout + 2000), $pipeName) -ForegroundColor Magenta

$mod = Get-Module NamedPipe | Where-Object { $_.Version -eq [version]'0.13' } | Select-Object -First 1
$sw  = [System.Diagnostics.Stopwatch]::StartNew()
$srvPid = $mod.Invoke({ param($d) Start-PipeServerOrClient -SerialData $d }, (ConvertTo-Serial -Object $scp))
$srvPid = [int]($srvPid | Select-Object -Last 1)

# Deliberately DO NOT connect. Poll until the server process exits (cap 30s).
$exited = $false
while ($sw.Elapsed.TotalSeconds -lt 30) {
    Start-Sleep -Milliseconds 400
    if (-not (Get-Process -Id $srvPid -ErrorAction SilentlyContinue)) { $exited = $true; break }
}
$elapsed = [math]::Round($sw.Elapsed.TotalSeconds, 1)

Check ('unclaimed server self-terminated (PID {0})' -f $srvPid) $exited
Check ('self-terminated FAST (~budget, well under the old 60s): {0}s' -f $elapsed) ($exited -and $elapsed -lt 15)

Start-Sleep -Seconds 1
$log = @(Get-PipeServerLog -PipeName $pipeName -Newest 1)
Check 'wrote a timed-out-unclaimed failure log' ($log.Count -ge 1 -and ((Get-Content $log[0].FullName -Raw) -match 'timed-out-unclaimed'))
if ($log.Count -ge 1) { Remove-Item $log[0].FullName -Force -ErrorAction SilentlyContinue }

Write-Host ''
if ($pass) { Write-Host '=== CONNECT-DEADLINE: ALL PASSED ===' -ForegroundColor Green; exit 0 } else { Write-Host '=== CONNECT-DEADLINE: FAILURES ===' -ForegroundColor Red; exit 1 }
