#!/usr/bin/env pwsh
#requires -Version 5.0
<#
    .SYNOPSIS
    E2E regression for the 0.11 server diagnostics log (hardening 4.5, step 1a) against a REAL spawned server.

    Proves, through an actual pipe server process:
      1. A normal CLEAN session at InfoDisplay=0 leaves NO log file (discard-on-clean = current behaviour).
      2. A CLEAN session with InfoDisplay bit 8 KEEPS a per-session log naming the pipe, with milestones.
      3. (unit-level failure/redaction rules are covered by C:\Temp\test-serverlog.ps1.)

    Non-elevated (AdminRequired not set) - no UAC. Requires NamedPipe 0.12 DEPLOYED.
#>
[CmdletBinding()]
Param ()

Remove-Module -Name NamedPipe -Force -ErrorAction SilentlyContinue
Import-Module -Name NamedPipe -Force -RequiredVersion 0.12 -ErrorAction Stop

$Script:Pass = $true
function Assert-Case { param([string]$Label, [bool]$Cond)
    if ($Cond) { Write-Host "[PASS] $Label" -ForegroundColor Green }
    else { Write-Host "[FAIL] $Label" -ForegroundColor Red; $Script:Pass = $false } }

$LogDir = Join-Path $env:APPDATA 'NamedPipe-Logs'

function Invoke-LoggedSession {
    param([int]$InfoDisplay)
    $Private:MO = Set-ObjectParams -Dataset $StrMyOptions -MyParameters @{}
    $Private:MO.$StrInfoDisplay = $InfoDisplay
    $Private:MO.$StrWindowStyle = $StrHidden
    $Private:Session = Start-PipeSession -MyParameters $Private:MO
    $Private:SCP = $Private:Session.$StrServerClientParams
    $Private:SRP = $Private:Session.$StrSendRequestParams
    $Private:PipeName = $Private:SCP.$StrPipeInfo.$StrName
    $Private:SRP.$StrType = $StrScriptBlock
    $Private:SRP.$StrDataObject = 'Write-Output "ok"' | Send-Request @Private:SRP
    # Clean shutdown (ExitPipe) - the server flushes/decides its log on the way out.
    Stop-PipeSession -SendRequestParams $Private:SRP -PipeInfo $Private:SCP.$StrPipeInfo
    Start-Sleep -Seconds 2   # allow the separate server process to exit and write (or discard) its log
    return $Private:PipeName
}

Write-Host "`n=== Server-log E2E (real spawned server) ===" -ForegroundColor Magenta

# 1. Clean session, InfoDisplay 0 -> discard
$P0 = Invoke-LoggedSession -InfoDisplay 0
$F0 = @(Get-ChildItem -Path $LogDir -Filter ('server-*-{0}.log' -f $P0) -ErrorAction SilentlyContinue)
Assert-Case ('clean InfoDisplay=0 -> NO log file (pipe {0})' -f $P0) ($F0.Count -eq 0)

# 2. Clean session, InfoDisplay bit 8 -> keep, with milestones
$P8 = Invoke-LoggedSession -InfoDisplay 8
$F8 = @(Get-ChildItem -Path $LogDir -Filter ('server-*-{0}.log' -f $P8) -ErrorAction SilentlyContinue)
Assert-Case ('clean InfoDisplay=8 -> log file kept (pipe {0})' -f $P8) ($F8.Count -ge 1)
if ($F8.Count -ge 1) {
    $Txt = Get-Content -Path $F8[0].FullName -Raw
    Assert-Case 'kept log records outcome exit-pipe' ($Txt -match 'Outcome\s*:\s*exit-pipe')
    Assert-Case 'kept log has the connect milestone' ($Txt -match 'client connected and validated')
    Assert-Case 'kept log contains no drive-letter path' ($Txt -notmatch '[A-Za-z]:\\')
    # tidy up the artifact this test created
    Remove-Item $F8[0].FullName -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($Script:Pass) { Write-Host '=== SERVER-LOG E2E: ALL PASSED ===' -ForegroundColor Green; exit 0 }
else { Write-Host '=== SERVER-LOG E2E: FAILURES ABOVE ===' -ForegroundColor Red; exit 1 }
