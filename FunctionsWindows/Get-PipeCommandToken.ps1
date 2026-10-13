Function Get-PipeCommandToken
{
	<#
		.SYNOPSIS
		Derives the health-pipe command token from a session's capability nonce.

		.DESCRIPTION
		0.16. The health pipe accepts STATUS / CANCEL / KILL commands from the client that owns the
		session. They are authenticated with this token rather than with the capability nonce itself:
		the nonce grants the data pipe (arbitrary code in the server), whereas this token can only
		cancel the running request or end the server. It is a one-way SHA-256 of the nonce under a
		fixed label, so the server and the client each derive the same value independently and the
		nonce cannot be recovered from a leaked token (for example from a verbose PipeInfo dump).

		.PARAMETER Nonce
		The session's capability nonce (ServerClientParams.Nonce). An empty value returns $null,
		which the server treats as "commands disabled".

		.EXAMPLE
		$Token = Get-PipeCommandToken -Nonce $ServerClientParams.$StrNonce

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
		$Private:Bytes = $Private:Sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes('NamedPipe.command|' + $Nonce))
		([BitConverter]::ToString($Private:Bytes) -replace '-', '').ToLowerInvariant()
	}
	Catch
	{
		Write-MyCatchAudit -Source 'Get-PipeCommandToken: SHA-256 derivation failed - re-thrown, the caller treats a missing token as commands-disabled' -ErrorRecord $_
		throw
	}
	Finally
	{
		If ($Private:Sha) { $Private:Sha.Dispose() }
	}
}
