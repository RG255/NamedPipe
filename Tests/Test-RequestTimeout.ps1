#!/usr/bin/env pwsh
#requires -Version 5.0
<#
    .SYNOPSIS
    End-to-end test for the 0.16 Send-Request timeouts (-TimeoutSeconds inactivity, -MaxRuntimeSeconds absolute,
    -CancelGraceSeconds, -NoKillOnTimeout) and the Stop-PipeServer / Stop-PipeSession -Force escalation.
    Uses the SOURCE tree of this version (no deploy needed). Each destructive case gets its own session.

    Run under powershell.exe (5.1) and pwsh.exe (7).
#>
[CmdletBinding()]
Param (
	[ValidateRange(0, 15)]
	[int]$InfoDisplay = 0
)

Remove-Module -Name NamedPipe -Force -ErrorAction SilentlyContinue
$Script:ModuleManifest = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'NamedPipe.psd1'
Import-Module -Name $Script:ModuleManifest -Force -ErrorAction Stop

$Script:Pass = $true
function Assert-Case
{
	param([string]$Label, [bool]$Condition)
	if ($Condition)
	{ Write-Host ('[PASS] {0}' -f $Label) -ForegroundColor Green }
	else
	{ Write-Host ('[FAIL] {0}' -f $Label) -ForegroundColor Red; $Script:Pass = $false }
}

$Script:Servers = [System.Collections.Generic.List[int]]::new()
function New-TestSession
{
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test helper that opens a throwaway pipe session; -WhatIf has no meaning here.')]
	[CmdletBinding()]
	Param()
	$opts = Set-ObjectParameterSet -Dataset $StrMyOptions -MyParameters @{}
	$opts.$StrWindowStyle = $StrMinimized
	$opts.$StrModuleToLoad = @{ Name = 'NamedPipe'; Version = '0.16'; Path = $Script:ModuleManifest }
	$s = Start-PipeSession -MyParameters $opts
	$pid2 = $s.$StrSendRequestParams.$StrDataObject.$StrServerPID
	$Script:Servers.Add([int]$pid2)
	[PSCustomObject]@{
		Params    = $s.$StrSendRequestParams
		PipeInfo  = $s.$StrServerClientParams.$StrPipeInfo
		Scp       = $s.$StrServerClientParams
		ServerPid = [int]$pid2
	}
}
function Invoke-TestRequest
{
	param($S, [string]$Request, [hashtable]$Extra = @{})
	$S.Params.$StrType = $StrScriptBlock
	$p = $S.Params
	$S.Params.$StrDataObject = $Request | Send-Request @p @Extra
	$S.Params.$StrDataObject
}
function Wait-ProcessGone
{
	param([int]$ProcessId, [int]$Seconds = 6)
	for ($i = 0; $i -lt ($Seconds * 5); $i++)
	{
		if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { return $true }
		Start-Sleep -Milliseconds 200
	}
	$false
}

Write-Host ("`n=== NamedPipe 0.16 request timeouts ({0} {1}) ===" -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion) -ForegroundColor Magenta

try
{
	# --- A. inactivity timeout, honoured cancel: session survives ---
	$A = New-TestSession
	$sw = [Diagnostics.Stopwatch]::StartNew()
	$r = Invoke-TestRequest $A 'Start-Sleep -Seconds 120' @{ TimeoutSeconds = 3 }
	$sw.Stop()
	Assert-Case ('A1 silent request abandoned after the inactivity timeout ({0:N1} s)' -f $sw.Elapsed.TotalSeconds) ($sw.Elapsed.TotalSeconds -ge 2.5 -and $sw.Elapsed.TotalSeconds -lt 15)
	Assert-Case 'A2 response is the server''s Cancelled response' ($r.$StrCancelled -eq $true -and $r.$StrError -match 'cancelled')
	$r = Invoke-TestRequest $A 'Write-Output alive-after-timeout'
	Assert-Case 'A3 SAME session is still usable after the timeout' ($r.$StrResult -eq 'alive-after-timeout' -and -not $r.$StrError)
	Assert-Case 'A4 timeout settings do not leak into the next call' (-not $A.PipeInfo.$StrReadTimeoutMs -and -not $A.PipeInfo.$StrDeadlineTicks -and -not $A.PipeInfo.$StrTimedOut)

	# --- B. progress messages keep an active request alive past the inactivity timeout ---
	$progress = "1..6 | ForEach-Object { Send-ProgressInfo -String ('tick {0}' -f `$_) -Type Console; Start-Sleep -Seconds 1 }`n'finished-with-progress'"
	$sw.Restart()
	$r = Invoke-TestRequest $A $progress @{ TimeoutSeconds = 3 }
	$sw.Stop()
	Assert-Case ('B1 request reporting progress outlives the 3 s inactivity timeout ({0:N1} s)' -f $sw.Elapsed.TotalSeconds) ($r.$StrResult -eq 'finished-with-progress' -and -not $r.$StrError -and $sw.Elapsed.TotalSeconds -gt 5)

	# --- C. absolute cap is NOT extended by progress ---
	$long = "1..60 | ForEach-Object { Send-ProgressInfo -String 'tick' -Type Console; Start-Sleep -Seconds 1 }`n'should-not-finish'"
	$sw.Restart()
	$r = Invoke-TestRequest $A $long @{ TimeoutSeconds = 3; MaxRuntimeSeconds = 5 }
	$sw.Stop()
	Assert-Case ('C1 -MaxRuntimeSeconds stops a request that keeps reporting progress ({0:N1} s)' -f $sw.Elapsed.TotalSeconds) ($r.$StrCancelled -eq $true -and $sw.Elapsed.TotalSeconds -ge 4.5 -and $sw.Elapsed.TotalSeconds -lt 20)
	$r = Invoke-TestRequest $A 'Write-Output still-alive'
	Assert-Case 'C2 session still usable after the max-runtime stop' ($r.$StrResult -eq 'still-alive')

	# --- D. unstoppable request: escalates to KILL ---
	$D = New-TestSession
	$sw.Restart()
	$r = Invoke-TestRequest $D '[Console]::ReadKey($true)' @{ TimeoutSeconds = 3; CancelGraceSeconds = 2 }
	$sw.Stop()
	Assert-Case ('D1 un-cancellable request ends in a returned error ({0:N1} s)' -f $sw.Elapsed.TotalSeconds) ($r.$StrTimedOut -eq 'ServerKilled' -and $r.$StrError -match 'terminated')
	Assert-Case 'D2 the server process was killed' (Wait-ProcessGone -ProcessId $D.ServerPid)
	Assert-Case 'D3 Test-PipeSession reports the session dead' (-not (Test-PipeSession -PipeInfo $D.PipeInfo))

	# --- E. -NoKillOnTimeout leaves the decision (and the server) with the caller ---
	$E = New-TestSession
	$r = Invoke-TestRequest $E '[Console]::ReadKey($true)' @{ TimeoutSeconds = 3; CancelGraceSeconds = 2; NoKillOnTimeout = $true }
	# A console read is normally NOT interruptible, but if the host happens to honour the cancel that is a good
	# outcome too (seen once on PS 5.1, not reproducible in 9 reruns) - accept either, fail on anything else.
	$notHonoured = ($r.$StrTimedOut -eq 'CancelNotHonoured' -and $r.$StrError -match 'not honoured')
	$cancelledOk = ($r.$StrCancelled -eq $true)
	Assert-Case 'E1 -NoKillOnTimeout returns "cancel not honoured" (or the cancel was honoured)' ($notHonoured -or $cancelledOk)
	if (-not $notHonoured)
	{ Write-Host ('   E1 diagnostics: TimedOut=[{0}] Cancelled=[{1}] Error=[{2}] Result=[{3}]' -f $r.$StrTimedOut, $r.$StrCancelled, ($r.$StrError -replace '\s+', ' '), $r.$StrResult) -ForegroundColor Yellow }
	if (-not $notHonoured)
	{
		Write-Host '   note: the console read was cancelled this time; E2-E5 (still-busy / Stop-PipeServer) skipped, KILL path is covered by D.' -ForegroundColor Yellow
		$null = Stop-PipeServer -PipeInfo $E.PipeInfo
		$null = Wait-ProcessGone -ProcessId $E.ServerPid
	}
	else
	{
		Assert-Case 'E2 the server is still running' ([bool](Get-Process -Id $E.ServerPid -ErrorAction SilentlyContinue))
		$st = Get-PipeRequestStatus -PipeInfo $E.PipeInfo
		Assert-Case 'E3 Get-PipeRequestStatus reports it busy' ($st.State -eq 'Busy' -and $st.ElapsedMs -gt 0)
		$k = Stop-PipeServer -PipeInfo $E.PipeInfo
		Assert-Case 'E4 Stop-PipeServer acknowledged' ($k -eq 'KILL:ok')
		Assert-Case 'E5 the server process is gone' (Wait-ProcessGone -ProcessId $E.ServerPid)
	}

	# --- F. Stop-PipeSession -Force on a wedged session ---
	$F = New-TestSession
	# -Force goes straight to KILL, so an idle session is enough to prove the path (a wedged one is covered by D/E).
	$p = $F.Params
	Stop-PipeSession -SendRequestParams $p -PipeInfo $F.PipeInfo -Force
	Assert-Case 'F1 Stop-PipeSession -Force ends the server process' (Wait-ProcessGone -ProcessId $F.ServerPid)

	# --- F2. the whole ServerClientParams passed instead of PipeInfo (the consumer mistake): must still do a
	# normal ExitPipe close rather than silently doing nothing and leaking the server ---
	$F2 = New-TestSession
	$p2 = $F2.Params
	Stop-PipeSession -SendRequestParams $p2 -PipeInfo $F2.Scp
	Assert-Case 'F2 Stop-PipeSession given a whole ServerClientParams still closes the server' (Wait-ProcessGone -ProcessId $F2.ServerPid)

	# --- G. Stop-PipeRequest from outside while a request is blocked ---
	$G = New-TestSession
	$hText = @'
param($PipeInfo, $Mod)
Import-Module -Name $Mod -ErrorAction Stop
Start-Sleep -Milliseconds 1500
Stop-PipeRequest -PipeInfo $PipeInfo
'@
	$hr = [RunspaceFactory]::CreateRunspace(); $hr.Open()
	$hp = [PowerShell]::Create(); $hp.Runspace = $hr
	$null = $hp.AddScript($hText).AddArgument($G.PipeInfo).AddArgument($Script:ModuleManifest)
	$async = $hp.BeginInvoke()
	$sw.Restart()
	$r = Invoke-TestRequest $G 'Start-Sleep -Seconds 120'
	$sw.Stop()
	$h = $hp.EndInvoke($async)
	$hp.Dispose(); $hr.Dispose()
	Assert-Case 'G1 Stop-PipeRequest from another runspace cancels a blocked Send-Request' ($r.$StrCancelled -eq $true -and "$h" -eq 'CANCEL:stopped' -and $sw.Elapsed.TotalSeconds -lt 15)
	$r = Invoke-TestRequest $G 'Write-Output g-alive'
	Assert-Case 'G2 session still usable' ($r.$StrResult -eq 'g-alive')
}
catch
{
	# An unexpected error must fail the run, not end it quietly.
	Write-Host ('[FAIL] unexpected error: {0}' -f $_.Exception.Message) -ForegroundColor Red
	$Script:Pass = $false
}
finally
{
	foreach ($sp in $Script:Servers)
	{
		if (Get-Process -Id $sp -ErrorAction SilentlyContinue) { Stop-Process -Id $sp -Force -ErrorAction SilentlyContinue }
	}
}

Write-Host ''
if ($Script:Pass) { Write-Host 'ALL PASSED' -ForegroundColor Green; exit 0 }
else { Write-Host 'FAILURES - see above' -ForegroundColor Red; exit 1 }
