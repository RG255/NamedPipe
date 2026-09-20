<#
	.SYNOPSIS
	NamedPipe example 3: the short-secret gap - and the template for closing it yourself.

	.DESCRIPTION
	Bit-1 built-in redaction (see 02-Redaction-BuiltIn.ps1) only strips runs of 40+ characters. A
	short, human-typed secret - a passphrase, a PIN - is NOT that shape, so it sails through
	unredacted with no configuration. This script proves the gap concretely (not just in prose), then
	closes it the supported way: a consumer-supplied RedactPattern.Pattern (bit 2) matching the
	SPECIFIC parameter name at risk. This is the literal template a consumer with credential-shaped
	parameters (e.g. VaultTools) should copy and adapt.

	.EXAMPLE
	powershell.exe -NoProfile -File .\03-Redaction-CustomPattern.ps1
#>

Remove-Module -Name NamedPipe -Force -ErrorAction SilentlyContinue
Import-Module -Name NamedPipe -Force -RequiredVersion 0.15 -ErrorAction Stop

Write-Host '--- Part 1: bit-1 alone MISSES a short secret ---' -ForegroundColor Cyan
$Session1 = Start-PipeSession -MyParameters @{} -Options @{ $StrInfoDisplay = 1 }
$ServerClientParams1 = $Session1.$StrServerClientParams
$SendRequestParams1  = $Session1.$StrSendRequestParams
$SendRequestParams1.$StrType = $StrScriptBlock
try
{
	Write-Host 'Sending a fake short passphrase: -Passphrase abc123' -ForegroundColor Yellow
	Write-Host '(Watch the server console below - this WILL show the raw value.)' -ForegroundColor Yellow
	$SendRequestParams1.$StrDataObject = 'Write-Output "-Passphrase abc123"' | Send-Request @SendRequestParams1
	Start-Sleep -Milliseconds 300
}
finally
{ Stop-PipeSession -SendRequestParams $SendRequestParams1 -PipeInfo $ServerClientParams1.$StrPipeInfo }

Write-Host ''
Write-Host '--- Part 2: adding a bit-2 custom pattern closes the gap ---' -ForegroundColor Cyan
$Private:RedactCfg = @{
	# Option = 3 = (1 -bor 2): keep bit-1's built-in protection AND add a custom pattern.
	# [^"\s]+ (not \S+) deliberately stops before a trailing quote, so a quoted value like
	# "-Passphrase abc123" redacts cleanly to "<redacted>" instead of swallowing the closing quote.
	Option  = 3
	Pattern = '(?i)-Passphrase\s+[^"\s]+'
}
$Session2 = Start-PipeSession -MyParameters @{} -Options @{ $StrInfoDisplay = 1; RedactPattern = $Private:RedactCfg }
$ServerClientParams2 = $Session2.$StrServerClientParams
$SendRequestParams2  = $Session2.$StrSendRequestParams
$SendRequestParams2.$StrType = $StrScriptBlock
try
{
	Write-Host 'Sending the SAME fake short passphrase, now with RedactPattern configured...' -ForegroundColor Yellow
	Write-Host '(Watch the server console below - this now shows <redacted>.)' -ForegroundColor Yellow
	$SendRequestParams2.$StrDataObject = 'Write-Output "-Passphrase abc123"' | Send-Request @SendRequestParams2
	Start-Sleep -Milliseconds 300
}
finally
{ Stop-PipeSession -SendRequestParams $SendRequestParams2 -PipeInfo $ServerClientParams2.$StrPipeInfo }

Write-Host ''
Write-Host 'Copy the $Private:RedactCfg shape above (adjust the Pattern to your own parameter name) for any session that carries a short, human-typed secret.' -ForegroundColor Cyan
