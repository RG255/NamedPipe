Function Test-ConstantTimeEqual
{
	<#
		.SYNOPSIS
		Compares two strings without stopping at the first difference.

		.DESCRIPTION
		Used for secrets (the capability nonce). The comparison is case-sensitive and always
		inspects every character of the longer string, so the time taken does not reveal how many
		leading characters matched.

		.PARAMETER Left
		First string.

		.PARAMETER Right
		Second string.

		.EXAMPLE
		Test-ConstantTimeEqual -Left $Presented -Right $Expected

		.OUTPUTS
		System.Boolean
	#>
	[CmdletBinding()]
	[OutputType([Boolean])]
	Param(
		[Parameter(Mandatory)][AllowEmptyString()][AllowNull()][String]$Left,
		[Parameter(Mandatory)][AllowEmptyString()][AllowNull()][String]$Right
	)
	If (1 -band ($env:MyFunctionTraceEnabled -as [Int])) { Write-MyFunctionTrace }

	$Private:A = [String]$Left
	$Private:B = [String]$Right
	$Private:Diff = $Private:A.Length -bxor $Private:B.Length
	$Private:Max = [Math]::Max($Private:A.Length, $Private:B.Length)
	For ($Private:i = 0; $Private:i -lt $Private:Max; $Private:i++)
	{
		$Private:x = If ($Private:i -lt $Private:A.Length) { [Int]$Private:A[$Private:i] } Else { 0 }
		$Private:y = If ($Private:i -lt $Private:B.Length) { [Int]$Private:B[$Private:i] } Else { 0 }
		$Private:Diff = $Private:Diff -bor ($Private:x -bxor $Private:y)
	}
	$Private:Diff -eq 0
}
