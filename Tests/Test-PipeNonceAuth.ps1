#!/usr/bin/env pwsh
#requires -Version 5.0
<#
    .SYNOPSIS
    Regression test for the 0.11 capability-nonce handshake (hardening 4.2) against the REAL deployed
    NamedPipe server (not a stand-in). Proves:

      1. POSITIVE / hand-off: Start-PipeSession's own client - a DIFFERENT process than the spawned
         server - is admitted because it presents the auto-generated nonce, and a request runs.
      2. NEGATIVE: after the client disconnects (server re-listens), a RAW client that connects to the
         same pipe but presents a WRONG first line is REFUSED (server disconnects it and keeps listening).
      3. RECOVERY: a legitimate reconnect presenting the CORRECT nonce is then admitted, proving the
         server kept re-listening after rejecting the impostor.

    The standalone method proof is C:\Temp\nonce-authtest.ps1; THIS exercises the module end to end.
    Run under pwsh (PS7). Requires NamedPipe 0.13 DEPLOYED (the server self-spawns by module name).
#>
[CmdletBinding()]
Param (
	[ValidateRange(0, 15)]
	[int]$InfoDisplay = 0
)

Remove-Module -Name NamedPipe -Force -ErrorAction SilentlyContinue
Import-Module -Name NamedPipe -Force -RequiredVersion 0.13 -ErrorAction Stop

$Script:Pass = $true
function Assert-Case
{
	param([string]$Label, [bool]$Condition)
	if ($Condition)
	{ Write-Host ("[PASS] {0}" -f $Label) -ForegroundColor Green }
	else
	{ Write-Host ("[FAIL] {0}" -f $Label) -ForegroundColor Red; $Script:Pass = $false }
}

$Private:MyBoundParameters = $PSCmdlet.MyInvocation.BoundParameters
$Private:MyOptions = Set-ObjectParams -Dataset $StrMyOptions -MyParameters $Private:MyBoundParameters
$Private:MyOptions.$StrWindowStyle = $StrMinimized

$Session            = Start-PipeSession -MyParameters $Private:MyOptions
$ServerClientParams = $Session.$StrServerClientParams
$SendRequestParams  = $Session.$StrSendRequestParams

$Script:RealNonce = $ServerClientParams.$StrNonce
$Script:PipeName  = $ServerClientParams.$StrPipeInfo.$StrName
Write-Host ("`n=== Nonce-auth module regression ===") -ForegroundColor Magenta
Write-Host ("  pipe      : {0}" -f $Script:PipeName)  -ForegroundColor DarkGray
Write-Host ("  nonce set : {0}" -f [bool]$Script:RealNonce) -ForegroundColor DarkGray

try
{
	# --- 1. POSITIVE / hand-off: the module's own (different-PID) client presented the nonce and is in. ---
	Assert-Case 'Session established (nonce auto-generated and present)' ([bool]$Script:RealNonce)
	$SendRequestParams.$StrType = $StrScriptBlock
	$SendRequestParams.$StrDataObject = 'Write-Output "ok"' | Send-Request @SendRequestParams
	Assert-Case 'Nonce-admitted client can run a request' (
		$SendRequestParams.$StrDataObject.$StrResult -eq 'ok' -and -not $SendRequestParams.$StrDataObject.$StrError)

	# --- Put the server into re-listen state via a clean Disconnect. ---
	$SendRequestParams.$StrType = $StrDisconnect
	$SendRequestParams.$StrDataObject = '' | Send-Request @SendRequestParams
	$SendRequestParams.$StrType = $StrScriptBlock
	try { $ServerClientParams.$StrPipeInfo.$StrWriter.Dispose() } catch { $null = $_ }
	try { $ServerClientParams.$StrPipeInfo.$StrReader.Dispose() } catch { $null = $_ }
	Start-Sleep -Milliseconds 400   # let the server complete Disconnect() and re-enter WaitForConnection

	# --- 2. NEGATIVE: raw client, WRONG first line -> server must refuse and keep listening. ---
	$Private:Refused = $false
	$Private:Raw = [System.IO.Pipes.NamedPipeClientStream]::new('.', $Script:PipeName, [System.IO.Pipes.PipeDirection]::InOut)
	try
	{
		$Private:Raw.Connect(5000)
		$Private:RawW = [System.IO.StreamWriter]::new($Private:Raw)
		$Private:RawW.AutoFlush = $true
		$Private:RawW.WriteLine('WRONG-' + [Guid]::NewGuid().ToString('N'))   # not the nonce
		$Private:RawR = [System.IO.StreamReader]::new($Private:Raw)
		# The server sends no handshake ACK. If it rejected us it Disconnect()ed -> our ReadLine hits EOF
		# (returns $null) promptly. If it (wrongly) admitted us it would block waiting for a request.
		$Private:RawTask = $Private:RawR.ReadLineAsync()
		if ($Private:RawTask.Wait(4000))
		{ $Private:Refused = ($null -eq $Private:RawTask.Result) }   # EOF = server closed us out
		else
		{ $Private:Refused = $false }                                # still waiting = NOT refused
	}
	catch
	{ $Private:Refused = $true }   # broken-pipe on our side also means the server refused us
	finally
	{ try { $Private:Raw.Dispose() } catch { $null = $_ } }
	Assert-Case 'Raw client with WRONG nonce is refused (server disconnects it)' $Private:Refused
	Start-Sleep -Milliseconds 400   # let the server re-enter WaitForConnection after rejecting the impostor

	# --- 3. RECOVERY: legit reconnect with the CORRECT nonce is admitted (server kept re-listening). ---
	$Private:Recovered = $false
	$Private:RlScp = Set-ObjectParams -Client -Dataset $StrServerClientParams -MyParameters $ServerClientParams
	$Private:RlMod = Get-Module -Name NamedPipe | Where-Object { $_.Version -eq [version]'0.13' } | Select-Object -First 1
	$Private:RlScp.$StrPipeInfo = $Private:RlMod.Invoke(
		{ param($d) Start-PipeServerOrClient -SerialData $d },
		(ConvertTo-Serial -Object $Private:RlScp))
	if (-not $Private:RlScp.$StrPipeInfo.$StrError -and $Private:RlScp.$StrPipeInfo.$StrPipe.IsConnected)
	{
		$SendRequestParams.$StrPipeInfo = $Private:RlScp.$StrPipeInfo
		$SendRequestParams.$StrDataObject = 'Write-Output "recovered"' | Send-Request @SendRequestParams
		$Private:Recovered = ($SendRequestParams.$StrDataObject.$StrResult -eq 'recovered')
		Set-Variable -Name ServerClientParams -Value $Private:RlScp
	}
	Assert-Case 'Correct-nonce reconnect is admitted after the impostor (server still listening)' $Private:Recovered
}
finally
{
	try { Stop-PipeSession -SendRequestParams $SendRequestParams -PipeInfo $ServerClientParams.$StrPipeInfo } catch { $null = $_ }
}

Write-Host ''
if ($Script:Pass)
{ Write-Host '=== NONCE-AUTH REGRESSION: ALL PASSED ===' -ForegroundColor Green; exit 0 }
else
{ Write-Host '=== NONCE-AUTH REGRESSION: FAILURES ABOVE ===' -ForegroundColor Red; exit 1 }
