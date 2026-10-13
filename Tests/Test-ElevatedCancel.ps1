#!/usr/bin/env pwsh
#requires -Version 5.0
<#
    .SYNOPSIS
    Proves the 0.16 command channel against an ELEVATED server driven from a NON-ELEVATED client - the case the
    channel exists for, since an unelevated process cannot Stop-Process an elevated one.

    Raises ONE UAC prompt (it may be on the taskbar). Uses one session: a timed-out request is cancelled and the
    session reused, then an un-cancellable request escalates to KILL and the elevated server process ends.

    Run from a NON-elevated shell under powershell.exe or pwsh.exe. Uses the source tree of this version.
#>
[CmdletBinding()]
Param ()

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

$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if ($me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
{
	Write-Host 'SKIP: this shell is already elevated, so it would prove nothing. Run from a non-elevated shell.' -ForegroundColor Yellow
	exit 0
}

$ServerPid = 0
try
{
	$opts = Set-ObjectParameterSet -Dataset $StrMyOptions -MyParameters @{}
	$opts.$StrModuleToLoad = @{ Name = 'NamedPipe'; Version = '0.16'; Path = $Script:ModuleManifest }
	$Session = Start-PipeSession -MyParameters $opts -Options @{ $StrAdminRequired = $true; $StrWindowStyle = $StrMinimized }
	$Params   = $Session.$StrSendRequestParams
	$PipeInfo = $Session.$StrServerClientParams.$StrPipeInfo
	$ServerPid = [int]$Params.$StrDataObject.$StrServerPID
	Write-Host ("`n=== NamedPipe 0.16 elevated server, non-elevated client ({0} {1}) ===" -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion) -ForegroundColor Magenta
	Write-Host ('  server PID: {0}' -f $ServerPid) -ForegroundColor DarkGray

	function Send-Test
	{
		param([string]$Request, [hashtable]$Extra = @{})
		$Params.$StrType = $StrScriptBlock
		$p = $Params
		$Params.$StrDataObject = $Request | Send-Request @p @Extra
		$Params.$StrDataObject
	}

	$r = Send-Test '([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)'
	Assert-Case 'Server really is elevated' ($r.$StrResult -eq $true)
	Assert-Case 'Client really is NOT elevated' (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))

	$sw = [Diagnostics.Stopwatch]::StartNew()
	$r = Send-Test 'Start-Sleep -Seconds 120' @{ TimeoutSeconds = 3 }
	$sw.Stop()
	Assert-Case ('Elevated server: stuck request cancelled by the non-elevated client ({0:N1} s)' -f $sw.Elapsed.TotalSeconds) ($r.$StrCancelled -eq $true -and $sw.Elapsed.TotalSeconds -lt 15)
	$r = Send-Test 'Write-Output elevated-still-alive'
	Assert-Case 'Elevated session still usable after the cancel' ($r.$StrResult -eq 'elevated-still-alive')
	$st = Get-PipeRequestStatus -PipeInfo $PipeInfo
	Assert-Case 'Get-PipeRequestStatus works against the elevated server' ($st.State -eq 'Idle')

	$r = Send-Test '[Console]::ReadKey($true)' @{ TimeoutSeconds = 3; CancelGraceSeconds = 2 }
	Assert-Case 'Un-cancellable request on the elevated server escalates to KILL' ($r.$StrTimedOut -eq 'ServerKilled')
	$gone = $false
	for ($i = 0; $i -lt 30 -and -not $gone; $i++)
	{
		Start-Sleep -Milliseconds 200
		$gone = -not (Get-Process -Id $ServerPid -ErrorAction SilentlyContinue)
	}
	Assert-Case 'The ELEVATED server process was terminated from the non-elevated client' $gone
}
catch
{
	Write-Host ('[FAIL] unexpected error: {0}' -f $_.Exception.Message) -ForegroundColor Red
	$Script:Pass = $false
}
finally
{
	# A non-elevated shell cannot stop an elevated process directly, so ask the server via its own channel.
	if ($ServerPid -and (Get-Process -Id $ServerPid -ErrorAction SilentlyContinue) -and $PipeInfo)
	{ $null = Stop-PipeServer -PipeInfo $PipeInfo }
}

Write-Host ''
if ($Script:Pass) { Write-Host 'ALL PASSED' -ForegroundColor Green; exit 0 }
else { Write-Host 'FAILURES - see above' -ForegroundColor Red; exit 1 }
