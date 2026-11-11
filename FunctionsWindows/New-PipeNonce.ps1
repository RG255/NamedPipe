Function New-PipeNonce
{
	<#
		.SYNOPSIS
		Returns a new random capability nonce: 32 hexadecimal characters from the operating system's cryptographic generator.

		.DESCRIPTION
		0.18. Used for the session nonce (Set-ObjectParameterSet) and the Test-PipeSession challenge. The value has the same shape as
		the earlier GUID-based nonce (32 hex characters), so nothing that stores or compares it changes.

		.OUTPUTS
		System.String - 32 lower-case hex characters.
	#>
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Returns a random string; changes no state.')]
	[CmdletBinding()]
	[OutputType([string])]
	Param ()
	If (1 -band ($env:MyFunctionTraceEnabled -as [Int])) { Write-MyFunctionTrace }

	$Private:Rng = $null
	Try
	{
		$Private:Rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
		$Private:Bytes = [byte[]]::new(16)
		$Private:Rng.GetBytes($Private:Bytes)
		[BitConverter]::ToString($Private:Bytes).Replace('-', '').ToLowerInvariant()
	}
	Catch
	{
		Write-MyCatchAudit -Source 'New-PipeNonce: generating a random nonce failed - re-thrown, the session is not started without one' -ErrorRecord $_
		throw
	}
	Finally
	{
		If ($Private:Rng) { $Private:Rng.Dispose() }
	}
}
