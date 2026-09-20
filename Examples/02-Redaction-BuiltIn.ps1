<#
	.SYNOPSIS
	NamedPipe example 2: built-in redaction masks any structurally-valid base64 value automatically,
	with zero config - and (0.15) leaves ordinary non-secret text alone.

	.DESCRIPTION
	Sends a request that embeds a value that IS structurally valid base64 (the shape of an encrypted
	password blob or a PFX-in-transit value) in a QUOTED parameter and shows it come back masked as
	'<base64 encoded>' in the server's console echo, even though this session configures NO
	RedactPattern at all - controlled by RedactPotentialSecrets (default $true, see USERGUIDE.md).

	IMPORTANT: this mechanism only ever detects SHAPE ("is this valid base64"), never confirmed intent
	("is this actually sensitive") - RedactPotentialSecrets is named that way deliberately. It masks a
	non-secret base64 blob exactly as readily as a real password, and it does NOT catch a real secret
	that isn't base64-encoded at all (see 03-Redaction-CustomPattern.ps1 for that gap). This is also
	why it defaults to $true even ignoring secrecy: a long base64 blob is visually noisy and unhelpful
	to read either way, so masking it keeps the console echo / persistent trace log readable regardless
	of whether the blob turns out to be sensitive.

	0.15 replaced the earlier "any 40+ char base64/hex-shaped run" regex with a real structural check
	that tests each QUOTED STRING VALUE as one atomic unit (see 06-RedactPotentialSecrets-
	QuotedValues.ps1 for the false-positive bug this fixed and why word-fragment matching was wrong).

	.EXAMPLE
	powershell.exe -NoProfile -File .\02-Redaction-BuiltIn.ps1
#>

Remove-Module -Name NamedPipe -Force -ErrorAction SilentlyContinue
Import-Module -Name NamedPipe -Force -RequiredVersion 0.15 -ErrorAction Stop

# -InfoDisplay 1 = server/client progress echo, so the (redacted) request text prints to the console.
# No RedactPattern option is configured anywhere below - deliberately, to prove this needs no config
# (RedactPotentialSecrets defaults to $true).
$Session = Start-PipeSession -MyParameters @{} -Options @{ $StrInfoDisplay = 1 }
$ServerClientParams = $Session.$StrServerClientParams
$SendRequestParams  = $Session.$StrSendRequestParams
$SendRequestParams.$StrType = $StrScriptBlock

try
{
	# A value that IS structurally valid base64, not just a long string that happens to look shaped
	# like one - 0.15's check actually decodes it, so it must be REAL base64 to be caught. Standing in
	# for what a real encrypted password/key blob would look like in transit - the mechanism cannot
	# tell this apart from any OTHER base64-encoded value that carries nothing sensitive at all; it
	# only ever tests shape, never intent. Quoted, matching how ConvertTo-ParameterSet quotes every
	# real string parameter in this codebase.
	$Private:PotentialSecret = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('a value that could be sensitive, base64-encoded in transit'))
	Write-Host ('Potential secret being sent (base64-encoded): {0}' -f $Private:PotentialSecret) -ForegroundColor Yellow
	Write-Host 'Watch the server''s own console window below - it echoes the request it received.' -ForegroundColor Cyan
	Write-Host '(No RedactPattern was configured - this redaction is automatic.)' -ForegroundColor Cyan

	$Private:Cmd = "Write-Output '{0}'" -f $Private:PotentialSecret
	$SendRequestParams.$StrDataObject = $Private:Cmd | Send-Request @SendRequestParams

	Start-Sleep -Milliseconds 300  # let the server's console echo land before this script's own output
	Write-Host ('Actual result value returned to THIS process (unaffected - redaction only applies to the echoed/logged display text): {0}' -f $SendRequestParams.$StrDataObject.$StrResult) -ForegroundColor Green
}
finally
{
	Stop-PipeSession -SendRequestParams $SendRequestParams -PipeInfo $ServerClientParams.$StrPipeInfo
}
