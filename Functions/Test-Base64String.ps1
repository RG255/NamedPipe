Function Test-Base64String
{
	<#
		.SYNOPSIS
		Tests whether a string is genuinely valid base64 (structural check, not a shape guess).

		.DESCRIPTION
		Used by Get-SBResult's RedactPotentialSecrets check (0.15) to replace the earlier blind
		"40+ char base64/hex-shaped run" regex, which could not tell a real secret from a legitimate
		long value that merely looked base64-shaped, and missed short secrets entirely.

		A cheap length-modulo-4 check runs first (rejects most ordinary words immediately, no decode
		attempt needed) before the real decode via [Convert]::FromBase64String - this confirms genuine
		base64 structure rather than charset-and-length luck. The caller is expected to have already
		restricted the candidate to the base64 alphabet (e.g. by splitting the source text on
		'[^A-Za-z0-9+/=]') - this function does not re-check the character set itself, only length and
		decodability.

		Residual false-positive class, inherent to ANY purely structural test and not fixable without
		semantic knowledge of content: a short pure-alphanumeric word whose length happens to be a
		multiple of 4 ('Data', 'Path', 'Test', 'True', 'None') decodes without error and will read as
		valid here. Accepted as a known, narrow limitation - see USERGUIDE.md.

		The Catch below distinguishes the EXPECTED outcome (not valid base64 - a FormatException, true
		for most candidates since only a genuine blob actually decodes) from a genuinely unexpected
		exception, per this repo's own "recognize a known-expected failure inside the catch" convention
		- routing every ordinary non-match through Write-MyCatchAudit would flood the audit log with
		noise for completely normal behaviour.

		.PARAMETER Value
		The candidate substring to test.

		.OUTPUTS
		[Bool] - $true only if Value is both a multiple of 4 in length and genuinely decodes as base64.
	#>
	[CmdletBinding()]
	[OutputType([Bool])]
	Param ([Parameter(Mandatory)][AllowEmptyString()][String]$Value)

	If (1 -band ($env:MyFunctionTraceEnabled -as [Int])) { Write-MyFunctionTrace }
	If ($Value.Length -eq 0 -or ($Value.Length % 4) -ne 0) { return $false }
	Try
	{
		[void][Convert]::FromBase64String($Value)
		return $true
	}
	Catch
	{
		# A .NET method called from PowerShell surfaces its exception wrapped in a
		# MethodInvocationException, with the real FormatException as the InnerException - testing
		# only $_.Exception (as the first 0.15 version did) never matched, so every ordinary invalid
		# candidate was reported to the catch-audit log as "unexpected" (21 entries before this fix).
		If ($_.Exception -is [System.FormatException] -or $_.Exception.InnerException -is [System.FormatException])
		{ return $false } # BY DESIGN: not valid base64 - the expected outcome for most candidates
		Write-MyCatchAudit -Source 'Test-Base64String: unexpected exception type validating a candidate' -ErrorRecord $_
		return $false
	}
}
