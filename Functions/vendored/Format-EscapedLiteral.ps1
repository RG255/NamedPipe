# VENDORED from CommonScripts\0.2\Functions\Format-EscapedLiteral.ps1 by Sync-SharedUtilities [SHA256 5D054248C2025FBAECCE8FEC386F01CE76D6E63628F725799C34531F341D2C5A] - DO NOT EDIT (edit the master; Deploy-Modules re-syncs).
Function Format-EscapedLiteral
{
	<#
		.SYNOPSIS
		Escapes a value for safe embedding as a single-quoted PowerShell string literal.

		.DESCRIPTION
		2026-09-15. Extracted after a repo-wide check (prompted by asking whether
		ConvertTo-ParameterSet should be promoted to CommonScripts) found the SAME
		`-replace "'", "''"` single-quote-doubling step hand-rolled independently in at least three
		places, each building a different SHAPE of dynamic command text around it:
		  - ConvertTo-ParameterSet (NamedPipe) - a flat "-Name:Value" splat-suffix string
		  - New-MyScheduledTask.ps1 (this same master) - a `param()` block with literal defaults
		  - Remove-MyScheduledTask.ps1 (this same master) - a literal array expression, `@('a','b')`
		  - VaultFileHelpers.ps1 (VaultTools) - one value substituted into a here-string placeholder
		None of the four could reuse each other's whole function (the surrounding shape genuinely
		differs and is not worth unifying), but the escaping step itself is identical everywhere and
		is exactly the kind of thing worth getting right in ONE place - see the exponential-growth and
		$null-handling bugs ConvertTo-ParameterSet itself already hit and fixed live, which any of the
		other three hand-rolled sites could just as easily reproduce independently.

		Only escapes the value (doubles embedded single quotes); does NOT add surrounding quotes
		unless -Quote is specified, since callers embed the result into differently-shaped
		surroundings (some already have the quotes as part of a template, some do not).

		.PARAMETER Value
		The raw value to escape. Accepts pipeline input. $null is treated as an empty string.

		.PARAMETER Quote
		When specified, wraps the escaped result in single quotes (`'Escaped'`) ready to splice
		directly into a PowerShell string literal position.

		.OUTPUTS
		System.String

		.EXAMPLE
		Format-EscapedLiteral -Value "O'Brien"
		Returns: O''Brien

		.EXAMPLE
		Format-EscapedLiteral -Value "O'Brien" -Quote
		Returns: 'O''Brien'

		.EXAMPLE
		'@(' + (($Names | ForEach-Object { Format-EscapedLiteral -Value $_ -Quote }) -join ',') + ')'
		Builds a literal PowerShell array-of-strings expression from an array of names.
	#>
	[CmdletBinding()]
	[OutputType([String])]
	Param (
		[Parameter(Mandatory, ValueFromPipeline)]
		[AllowNull()]
		[AllowEmptyString()]
		[String]$Value,

		[Switch]$Quote
	)

	Process
	{
		# -and (Get-Command...) guard: see ConvertFrom-Serial.ps1's own comment (2026-09-15) - this file
		# is vendored into modules that never vendor Write-MyFunctionTrace itself, and the process-scoped
		# $env:MyFunctionTraceEnabled can be '1' there regardless.
		If ((1 -band ($env:MyFunctionTraceEnabled -as [Int])) -and (Get-Command -Name Write-MyFunctionTrace -ErrorAction SilentlyContinue)) { Write-MyFunctionTrace }

		$Private:Escaped = If ($null -eq $Value) { '' } Else { $Value -replace "'", "''" }
		If ($Quote) { return "'$Private:Escaped'" }
		return $Private:Escaped
	}
}
