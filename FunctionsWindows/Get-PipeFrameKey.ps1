Function Get-PipeFrameKey
{
	<#
		.SYNOPSIS
		Derives the pipe frame MAC key from a session's capability nonce.

		.DESCRIPTION
		0.17. Both ends of a session know the capability nonce, so each derives the same key independently: SHA-256 of the nonce under a
		fixed label that differs from the one Get-PipeCommandToken uses, so a leaked command token cannot be used to forge frames and
		the nonce cannot be recovered from this key. The key is used by Get-PipeFrameMac as an HMAC-SHA256 key, which turns the frame's
		hash into an authentication code that only a holder of the nonce can compute.

		.PARAMETER Nonce
		The session's capability nonce (ServerClientParams.Nonce). An empty value returns $null: a session started without a nonce
		(an older caller) falls back to an UNKEYED SHA-256, which still detects accidental damage but not deliberate tampering.

		.OUTPUTS
		System.String - 64 lower-case hex characters, or $null when no nonce is available.
	#>
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory)]
		[AllowEmptyString()]
		[AllowNull()]
		[String]$Nonce
	)
	If (1 -band ($env:MyFunctionTraceEnabled -as [Int])) { Write-MyFunctionTrace }

	If ([String]::IsNullOrEmpty($Nonce))
	{ return $null }

	$Private:Sha = $null
	Try
	{
		$Private:Sha = [System.Security.Cryptography.SHA256]::Create()
		$Private:Bytes = $Private:Sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes('NamedPipe.frame|' + $Nonce))
		([BitConverter]::ToString($Private:Bytes) -replace '-', '').ToLowerInvariant()
	}
	Catch
	{
		Write-MyCatchAudit -Source 'Get-PipeFrameKey: SHA-256 derivation failed - re-thrown, the caller treats a missing key as unkeyed framing' -ErrorRecord $_
		throw
	}
	Finally
	{
		If ($Private:Sha) { $Private:Sha.Dispose() }
	}
}
