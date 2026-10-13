#!/usr/bin/env pwsh
#requires -Version 5.0
<#
    .SYNOPSIS
    End-to-end test for the 0.16 command channel on the health pipe (STATUS / CANCEL / KILL) and for the
    nested-pipeline request execution it relies on. Uses the SOURCE tree of this version (no deploy needed:
    the spawned server imports the module by path via the ModuleToLoad.Path option).

    Cases:
      1. a request runs, result shapes survive the nested pipeline, errors reach the client
      2. Send-ProgressInfo from inside a request still reaches the client
      3. STATUS reports idle, then busy (with a request id) during a long request
      4. a wrong token is refused (DENIED) and does not disturb the session
      5. CANCEL stops a busy request; the request returns Cancelled; the SAME session serves the next request
      6. KILL ends the server process

    Run under powershell.exe (5.1) and pwsh.exe (7): the server is spawned with the same host as the client.
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

# One-shot raw health-pipe client: connect, send one line, return the reply line (or $null).
function Invoke-HealthLine
{
	param([string]$PipeName, [string]$Line, [int]$TimeoutMs = 4000)
	$c = [System.IO.Pipes.NamedPipeClientStream]::new('.', ($PipeName + '.Health'), [System.IO.Pipes.PipeDirection]::InOut)
	try
	{
		$c.Connect($TimeoutMs)
		$w = [System.IO.StreamWriter]::new($c); $w.AutoFlush = $true
		$r = [System.IO.StreamReader]::new($c)
		$w.WriteLine($Line)
		$task = $r.ReadLineAsync()
		if ($task.Wait($TimeoutMs)) { $task.Result } else { '<no reply>' }
	}
	catch { '<error: {0}>' -f $_.Exception.Message }
	finally { $c.Dispose() }
}

$Private:MyBoundParameters = $PSCmdlet.MyInvocation.BoundParameters
$Private:MyOptions = Set-ObjectParameterSet -Dataset $StrMyOptions -MyParameters $Private:MyBoundParameters
$Private:MyOptions.$StrWindowStyle = $StrMinimized
$Private:MyOptions.$StrModuleToLoad = @{ Name = 'NamedPipe'; Version = '0.16'; Path = $Script:ModuleManifest }

$Session            = Start-PipeSession -MyParameters $Private:MyOptions
$ServerClientParams = $Session.$StrServerClientParams
$SendRequestParams  = $Session.$StrSendRequestParams
$PipeName           = $ServerClientParams.$StrPipeInfo.$StrName
$Token              = $ServerClientParams.$StrPipeInfo.$StrCommandToken
$ServerPid          = $SendRequestParams.$StrDataObject.$StrServerPID

Write-Host ("`n=== NamedPipe 0.16 command channel ({0} {1}) ===" -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion) -ForegroundColor Magenta
Write-Host ('  pipe: {0}   server PID: {1}' -f $PipeName, $ServerPid) -ForegroundColor DarkGray

function Send-Test
{
	param([string]$Request)
	$SendRequestParams.$StrType = $StrScriptBlock
	$SendRequestParams.$StrDataObject = $Request | Send-Request @SendRequestParams
	$SendRequestParams.$StrDataObject
}

try
{
	Assert-Case 'Command token derived on the client (64 hex)' ($Token -match '^[0-9a-f]{64}$')
	Assert-Case 'Command token is NOT the nonce' ($Token -ne $ServerClientParams.$StrNonce)

	# --- 1. basic request + shapes + error ---
	$r = Send-Test 'Write-Output ok'
	Assert-Case 'Request runs on the nested pipeline' ($r.$StrResult -eq 'ok' -and -not $r.$StrError)
	$r = Send-Test '@(1,2,3)'
	Assert-Case 'Array result keeps its shape (3 elements)' (@($r.$StrResult).Count -eq 3 -and $r.$StrResult[2] -eq 3)
	$r = Send-Test '$null'
	Assert-Case '$null result stays $null' ($null -eq $r.$StrResult -and -not $r.$StrError)
	# Object-shaped results: a [PSCustomObject]'s properties live on its PSObject wrapper, so an unwrap that takes
	# .PSObject.BaseObject returns an EMPTY object (VHDTools hit this on its first real mount, 2026-10-13).
	$r = Send-Test "[PSCustomObject]@{ DiskNumber = 3; PartitionNumber = 2; Type = 'Basic' }"
	Assert-Case 'PSCustomObject result keeps its properties' ($r.$StrResult.DiskNumber -eq 3 -and $r.$StrResult.PartitionNumber -eq 2 -and $r.$StrResult.Type -eq 'Basic')
	$r = Send-Test "[PSCustomObject]@{ Outer = 1; Inner = [PSCustomObject]@{ Deep = 'x' } }"
	Assert-Case 'Nested PSCustomObject keeps its properties' ($r.$StrResult.Outer -eq 1 -and $r.$StrResult.Inner.Deep -eq 'x')
	$r = Send-Test '@([PSCustomObject]@{ N = 1 }, [PSCustomObject]@{ N = 2 })'
	Assert-Case 'Array of PSCustomObject keeps every element and property' (@($r.$StrResult).Count -eq 2 -and $r.$StrResult[0].N -eq 1 -and $r.$StrResult[1].N -eq 2)
	$r = Send-Test "`$s = 'text'; Add-Member -InputObject `$s -NotePropertyName Extra -NotePropertyValue 7 -PassThru"
	Assert-Case 'A value with an Add-Member note property keeps the note property' ("$($r.$StrResult)" -eq 'text' -and $r.$StrResult.Extra -eq 7)
	$r = Send-Test '[ordered]@{ A = 1; B = 2 }'
	Assert-Case 'Ordered dictionary result keeps its keys' ($r.$StrResult.A -eq 1 -and $r.$StrResult.B -eq 2)
	$r = Send-Test 'Get-Date -Year 2001 -Month 2 -Day 3 -Hour 4 -Minute 5 -Second 6'
	Assert-Case 'DateTime result keeps its value' ($r.$StrResult.Year -eq 2001 -and $r.$StrResult.Month -eq 2)

	# The nine result shapes from Tools\Tests\Test-InvokeResultShape.ps1 (the regression oracle for the original
	# error-propagation work) plus two more, each compared with what NamedPipe 0.15 returned for the same request.
	# 0.16 runs requests in a nested pipeline, so every one of these has to be re-proven through the real pipe.
	function Get-Shape
	{
		param($Value)
		if ($null -eq $Value) { return 'null' }
		$isArr = $Value -is [System.Array]
		$cnt = if ($isArr -or $Value -is [System.Collections.IList]) { $Value.Count } else { 1 }
		'{0}|arr={1}|n={2}' -f $Value.GetType().Name, $isArr, $cnt
	}
	$nineShapes = [ordered]@{
		'single PSCustomObject' = "[PSCustomObject]@{ A = 1; B = 'two' }"
		'array of 3 ints'       = '1, 2, 3'
		'single-element array'  = ', @(42)'
		'empty array'           = ', @()'
		'null'                  = '$null'
		'hashtable'             = "@{ K = 'v' }"
		'string'                = "'hello'"
		'nested array'          = ', @(, @(1, 2), , @(3, 4))'
		'int'                   = '42'
		'two outputs'           = "'a'; 'b'"
		'array of PSCustomObject' = '@([PSCustomObject]@{ N = 1 }, [PSCustomObject]@{ N = 2 })'
	}
	# What NamedPipe 0.15 returns for each, MEASURED through the real pipe (not a local InvokeReturnAsIs - the
	# serialiser turns arrays into ArrayList on 0.15 as well, so a local oracle gives the wrong answer). 0.16 must match.
	$expectedShapes = @{
		'single PSCustomObject'   = 'PSCustomObject|arr=False|n=1'
		'array of 3 ints'         = 'ArrayList|arr=False|n=3'
		'single-element array'    = 'ArrayList|arr=False|n=1'
		'empty array'             = 'ArrayList|arr=False|n=0'
		'null'                    = 'null'
		'hashtable'               = 'Hashtable|arr=False|n=1'
		'string'                  = 'String|arr=False|n=1'
		'nested array'            = 'ArrayList|arr=False|n=2'
		'int'                     = 'Int32|arr=False|n=1'
		'two outputs'             = 'ArrayList|arr=False|n=2'
		'array of PSCustomObject' = 'ArrayList|arr=False|n=2'
	}
	foreach ($shapeName in $nineShapes.Keys)
	{
		$shapeText = $nineShapes[$shapeName]
		$expected = $expectedShapes[$shapeName]
		$r = Send-Test $shapeText
		$actual = Get-Shape $r.$StrResult
		Assert-Case ('Result shape [{0}] matches NamedPipe 0.15 through the pipe ({1})' -f $shapeName, $expected) ($expected -eq $actual -and -not $r.$StrError)
		if ($expected -ne $actual) { Write-Host ('   expected [{0}] got [{1}]' -f $expected, $actual) -ForegroundColor Yellow }
	}
	$r = Send-Test "throw 'boom-test'"
	Assert-Case 'A throwing request reports the error to the client' ($r.$StrError -match 'boom-test' -and -not $r.$StrCancelled)

	# --- 2. progress info still arrives from inside the nested pipeline ---
	$SendRequestParams.$StrType = $StrScriptBlock
	$iv = $null
	$SendRequestParams.$StrDataObject = "Send-ProgressInfo -String 'progress-marker' -Type Console`n'progress-done'" | Send-Request @SendRequestParams -InformationVariable iv
	$r = $SendRequestParams.$StrDataObject
	Assert-Case 'Progress message delivered from inside a request' (($iv | ForEach-Object { "$_" }) -match 'progress-marker')
	Assert-Case 'Request with progress still returns its result' ($r.$StrResult -eq 'progress-done')

	# --- 2b. -NonInteractive: console-input requests fail fast instead of wedging the server ---
	$cmdLine = (Get-CimInstance -ClassName Win32_Process -Filter ('ProcessId={0}' -f $ServerPid)).CommandLine
	Assert-Case 'Server was launched with -NonInteractive' ($cmdLine -match '-NonInteractive')
	$sw = [Diagnostics.Stopwatch]::StartNew()
	$r = Send-Test "Read-Host 'x'"
	Assert-Case 'Read-Host returns an error promptly instead of hanging' ($r.$StrError -match 'NonInteractive' -and $sw.Elapsed.TotalSeconds -lt 10)
	$r = Send-Test 'pause'
	Assert-Case 'pause returns an error promptly instead of hanging' ($r.$StrError -match 'NonInteractive')
	$r = Send-Test 'Write-Output after-readhost'
	Assert-Case 'Session still healthy after console-input requests' ($r.$StrResult -eq 'after-readhost')

	# --- 2c. bounded Wait (replaces Pause) ends by itself; works without console input ---
	$sw = [Diagnostics.Stopwatch]::StartNew()
	& (Get-Module -Name NamedPipe) { Wait-PipeServerExit -Seconds 2 } 6>$null
	$sw.Stop()
	Assert-Case ('Wait-PipeServerExit ends on its own after ~2 s ({0:N1} s)' -f $sw.Elapsed.TotalSeconds) ($sw.Elapsed.TotalSeconds -ge 1.5 -and $sw.Elapsed.TotalSeconds -lt 8)

	# --- 3. STATUS idle ---
	$s = Invoke-HealthLine -PipeName $PipeName -Line ('STATUS:{0}' -f $Token)
	Assert-Case 'STATUS reports idle between requests' ($s -eq 'STATUS:idle')

	# --- 3b. a caller that passes the WHOLE ServerClientParams where PipeInfo is expected (the mistake that leaked
	# hidden elevated servers in a consumer, 2026-10-12): it must be unwrapped, not silently answered with $false ---
	Assert-Case 'Test-PipeSession accepts the whole ServerClientParams (unwrapped to its PipeInfo)' ([bool](Test-PipeSession -PipeInfo $ServerClientParams))
	$st = Get-PipeRequestStatus -PipeInfo $ServerClientParams
	Assert-Case 'Get-PipeRequestStatus accepts the whole ServerClientParams too' ($st.State -eq 'Idle')
	Assert-Case 'A genuinely wrong argument is still just $false (no throw)' (-not (Test-PipeSession -PipeInfo ([PSCustomObject]@{ Unrelated = 1 })))

	# --- 4. wrong token refused ---
	$bad = ('0' * 64)
	$s = Invoke-HealthLine -PipeName $PipeName -Line ('KILL:{0}' -f $bad)
	Assert-Case 'KILL with a wrong token is refused (DENIED)' ($s -eq 'DENIED')
	$s = Invoke-HealthLine -PipeName $PipeName -Line 'CANCEL:short'
	Assert-Case 'CANCEL with a malformed token is refused (DENIED)' ($s -eq 'DENIED')
	$r = Send-Test 'Write-Output still-alive'
	Assert-Case 'Session unaffected by refused commands' ($r.$StrResult -eq 'still-alive')

	# --- 5. STATUS busy + CANCEL on a long request, from a helper runspace ---
	$helperText = @'
param($PipeName, $Token)
function Ask($line)
{
	$c = [System.IO.Pipes.NamedPipeClientStream]::new('.', ($PipeName + '.Health'), [System.IO.Pipes.PipeDirection]::InOut)
	try
	{
		$c.Connect(4000)
		$w = [System.IO.StreamWriter]::new($c); $w.AutoFlush = $true
		$r = [System.IO.StreamReader]::new($c)
		$w.WriteLine($line)
		$t = $r.ReadLineAsync()
		if ($t.Wait(8000)) { $t.Result } else { '<no reply>' }
	}
	catch { '<error: ' + $_.Exception.Message + '>' }
	finally { $c.Dispose() }
}
Start-Sleep -Milliseconds 1500
$out = @{}
$out.Status = Ask ('STATUS:' + $Token)
$out.Cancel = Ask ('CANCEL:' + $Token)
$out
'@
	$hr = [RunspaceFactory]::CreateRunspace(); $hr.Open()
	$hp = [PowerShell]::Create(); $hp.Runspace = $hr
	$null = $hp.AddScript($helperText).AddArgument($PipeName).AddArgument($Token)
	$async = $hp.BeginInvoke()

	$sw = [Diagnostics.Stopwatch]::StartNew()
	$r = Send-Test 'Start-Sleep -Seconds 120'
	$sw.Stop()
	$helperOut = $hp.EndInvoke($async)
	$hp.Dispose(); $hr.Dispose()
	$h = $helperOut[0]

	Assert-Case 'STATUS reported busy with a request id during the long request' ($h.Status -match '^STATUS:busy;id=\d+;elapsedMs=\d+$')
	Assert-Case 'CANCEL acknowledged as stopped' ($h.Cancel -eq 'CANCEL:stopped')
	Assert-Case ('Long request returned promptly after CANCEL ({0:N1} s)' -f $sw.Elapsed.TotalSeconds) ($sw.Elapsed.TotalSeconds -lt 15)
	Assert-Case 'Cancelled request is flagged Cancelled with an explanation' ($r.$StrCancelled -eq $true -and $r.$StrError -match 'cancelled')
	$r = Send-Test 'Write-Output after-cancel'
	Assert-Case 'SAME session serves the next request after a cancel' ($r.$StrResult -eq 'after-cancel' -and -not $r.$StrError)
	Assert-Case 'Session reports healthy after a cancel' (Test-PipeSession -PipeInfo $ServerClientParams.$StrPipeInfo)

	# --- 6. KILL ends the server process ---
	$s = Invoke-HealthLine -PipeName $PipeName -Line ('KILL:{0}' -f $Token)
	Assert-Case 'KILL acknowledged' ($s -eq 'KILL:ok')
	$gone = $false
	for ($i = 0; $i -lt 30 -and -not $gone; $i++)
	{
		Start-Sleep -Milliseconds 200
		$gone = -not (Get-Process -Id $ServerPid -ErrorAction SilentlyContinue)
	}
	Assert-Case 'Server process is gone after KILL' $gone
	Assert-Case 'Test-PipeSession reports the session dead after KILL' (-not (Test-PipeSession -PipeInfo $ServerClientParams.$StrPipeInfo))
}
catch
{
	# An unexpected error must fail the run, not end it quietly.
	Write-Host ('[FAIL] unexpected error: {0}' -f $_.Exception.Message) -ForegroundColor Red
	$Script:Pass = $false
}
finally
{
	# Nothing may be left running: if anything above failed before KILL, end the server explicitly.
	if ($ServerPid -and (Get-Process -Id $ServerPid -ErrorAction SilentlyContinue))
	{ Stop-Process -Id $ServerPid -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
if ($Script:Pass) { Write-Host 'ALL PASSED' -ForegroundColor Green; exit 0 }
else { Write-Host 'FAILURES - see above' -ForegroundColor Red; exit 1 }
