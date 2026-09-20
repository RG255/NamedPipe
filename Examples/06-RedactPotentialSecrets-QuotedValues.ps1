<#
	.SYNOPSIS
	NamedPipe example 6: RedactPotentialSecrets tests whole QUOTED VALUES, not loose word fragments -
	why that matters, and how to see the real value when you need to.

	.DESCRIPTION
	0.15 replaced the old "any 40+ char base64/hex-shaped run" regex with a real structural base64
	check, gated behind the new RedactPotentialSecrets option (default $true). The FIRST version of
	that check matched maximal runs of base64-alphabet characters ANYWHERE in the display text - this
	was wrong, found live via a real Pester failure: a run-based match fragments at every non-base64
	character (\, :, -, ., $), so an ordinary, obviously-non-secret quoted PATH like
	'W:\vhd\PSimple\tvhd-p.psd1' got broken into pieces ('tvhd', 'psd1'...) and several short fragments
	happened to decode without error on their own - a single realistic command line lost SIX separate
	words to false positives this way, including a 20-character parameter name
	(CheckGroupMembership) and NamedPipe's own '-Data:$Data' marker text.

	The FIX (what this example demonstrates): test each QUOTED STRING VALUE as one atomic unit, not
	loose fragments within it. A real secret in this codebase's request text is always an ENTIRE
	quoted string value - ConvertTo-ParameterSet quotes every string parameter - so nothing legitimate
	should ever need to be pulled apart to find a "hidden" match inside it. A path/GUID/parameter name
	containing ANY character outside the base64 alphabet fails as a WHOLE, correctly, and nothing
	inside it is ever tested in isolation. Bare (unquoted) tokens - parameter names, $True/$False, a
	bare $Data reference - are never candidates at all, since a real secret value here is never passed
	unquoted.

	IMPORTANT DISTINCTION this example is also here to make explicit: this mechanism can only ever
	detect "is this a STRUCTURALLY VALID base64 string" - it has no way to know whether a matched value
	is actually sensitive. A base64-encoded value that is NOT a secret at all (a hash, a non-secret
	blob) gets masked identically to a real password, and a real secret that is NOT base64-encoded (a
	plain-text passphrase typed by a human) is not caught by this at all. "RedactPotentialSecrets" is
	named that way deliberately - POTENTIAL, not confirmed. Treat a masked value as "this was base64
	and MIGHT be worth checking," never as proof of anything.

	This is also WHY the option defaults to $true even for non-secret data: a long base64 blob (a
	config file, an encoded credential, anything bulky) is visually noisy and unhelpful to read in the
	console echo or the persistent trace log either way - masking it to '<base64 encoded>' keeps that
	log genuinely readable, whether or not the blob turns out to be sensitive. Turning this option OFF
	trades that readability for full visibility - the right trade when you specifically need to see or
	decode a value, not the default you want for routine auditing.

	This example sends TWO requests back to back: one with an entirely ordinary, non-secret command
	line (proving it now survives completely unchanged), and one with a value that IS structurally
	valid base64 - standing in for what a real encrypted password/key blob would look like in transit -
	embedded in a quoted parameter (proving that shape still gets caught, regardless of whether this
	particular value is actually sensitive). It then shows the same request a third time with
	RedactPotentialSecrets turned OFF, so you can see exactly what "turn it off to see the real value"
	(see this module's USERGUIDE.md) looks like in practice.

	.EXAMPLE
	powershell.exe -NoProfile -File .\06-RedactPotentialSecrets-QuotedValues.ps1
#>

Remove-Module -Name NamedPipe -Force -ErrorAction SilentlyContinue
Import-Module -Name NamedPipe -Force -RequiredVersion 0.15 -ErrorAction Stop

Function Global:Test-EchoValue { Param ($Value) return $Value }

Try
{
	Write-Host '=== 1. An ordinary, non-secret command line - should print UNCHANGED ===' -ForegroundColor Cyan
	$Session1 = Start-PipeSession -MyParameters @{} -Options @{ $StrInfoDisplay = 1 }
	$ServerClientParams1 = $Session1.$StrServerClientParams
	$SendRequestParams1  = $Session1.$StrSendRequestParams
	$SendRequestParams1.$StrType = $StrScriptBlock
	Try
	{
		# Deliberately shaped like this module's own real elevated dispatch requests - a path, a GUID-
		# free parameter name, and a boolean - none of which are secrets, all of which are quoted or
		# bare exactly as a real VHDTools/VaultTools request would build them.
		$Private:Cmd = "Test-EchoValue -Value 'W:\vhd\PSimple\tvhd-p.psd1'"
		Write-Host ('Sending: {0}' -f $Private:Cmd) -ForegroundColor Yellow
		Write-Host 'Watch the server''s own console window - the echoed request should read IDENTICAL to the line above.' -ForegroundColor Cyan
		$SendRequestParams1.$StrDataObject = $Private:Cmd | Send-Request @SendRequestParams1
		Start-Sleep -Milliseconds 300
	}
	Finally
	{ Stop-PipeSession -SendRequestParams $SendRequestParams1 -PipeInfo $ServerClientParams1.$StrPipeInfo }

	Write-Host ''
	Write-Host '=== 2. A value that IS structurally valid base64 (a POTENTIAL secret - the mechanism' -ForegroundColor Cyan
	Write-Host '    cannot know for certain either way) - gets masked regardless ===' -ForegroundColor Cyan
	$Session2 = Start-PipeSession -MyParameters @{} -Options @{ $StrInfoDisplay = 1 }
	$ServerClientParams2 = $Session2.$StrServerClientParams
	$SendRequestParams2  = $Session2.$StrSendRequestParams
	$SendRequestParams2.$StrType = $StrScriptBlock
	Try
	{
		# Standing in for what a real encrypted password/key blob would look like in transit. The
		# mechanism cannot tell this apart from any OTHER base64-encoded value that happens to carry
		# nothing sensitive at all (a hash, a non-secret blob) - it only ever tests SHAPE, never intent.
		$Private:PotentialSecret = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('a value that could be sensitive'))
		$Private:Cmd = "Test-EchoValue -Value '{0}'" -f $Private:PotentialSecret
		Write-Host ('Sending (base64-encoded value): {0}' -f $Private:Cmd) -ForegroundColor Yellow
		Write-Host 'Watch the server''s own console window - the quoted value should now read <base64 encoded>.' -ForegroundColor Cyan
		$SendRequestParams2.$StrDataObject = $Private:Cmd | Send-Request @SendRequestParams2
		Start-Sleep -Milliseconds 300
		Write-Host ('Actual result value returned to THIS process (unaffected - redaction only touches the echoed/logged display text): {0}' -f $SendRequestParams2.$StrDataObject.$StrResult) -ForegroundColor Green
	}
	Finally
	{ Stop-PipeSession -SendRequestParams $SendRequestParams2 -PipeInfo $ServerClientParams2.$StrPipeInfo }

	Write-Host ''
	Write-Host '=== 3. Same request, RedactPotentialSecrets turned OFF - see the real value in the log ===' -ForegroundColor Cyan
	$Session3 = Start-PipeSession -MyParameters @{} -Options @{ $StrInfoDisplay = 1; $StrRedactPotentialSecrets = $false }
	$ServerClientParams3 = $Session3.$StrServerClientParams
	$SendRequestParams3  = $Session3.$StrSendRequestParams
	$SendRequestParams3.$StrType = $StrScriptBlock
	Try
	{
		Write-Host 'RedactPotentialSecrets = $false - this is the consumer''s own explicit choice to see full, undisguised output (e.g. to copy a value out and decode it elsewhere, or to confirm a masked value was never actually sensitive). Watch the server console: the value now shows in full.' -ForegroundColor Cyan
		$SendRequestParams3.$StrDataObject = $Private:Cmd | Send-Request @SendRequestParams3
		Start-Sleep -Milliseconds 300
	}
	Finally
	{ Stop-PipeSession -SendRequestParams $SendRequestParams3 -PipeInfo $ServerClientParams3.$StrPipeInfo }
}
Finally
{ Remove-Item function:Global:Test-EchoValue -ErrorAction SilentlyContinue }
