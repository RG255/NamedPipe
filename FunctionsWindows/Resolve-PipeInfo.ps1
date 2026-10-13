Function Resolve-PipeInfo
{
	<#
		.SYNOPSIS
		Returns the PipeInfo object from either a PipeInfo or the ServerClientParams that contains it.

		.DESCRIPTION
		0.16. Test-PipeSession, Stop-PipeSession and the command-channel helpers take a PipeInfo. A caller that
		passed the whole ServerClientParams instead (an easy mistake: both come out of the same session object)
		used to get a silent $false from Test-PipeSession - no error, nothing in a log - so a session looked dead
		while it was alive, no ExitPipe was ever sent, and a consumer leaked a hidden elevated server on every
		close until someone noticed (2026-10-12).

		A ServerClientParams is recognised by having a PipeInfo member and no Pipe member of its own; in that case
		the inner PipeInfo is returned. Anything else comes back unchanged, so a genuinely wrong argument still
		fails the caller's own checks exactly as before. Never throws.

		.PARAMETER InputObject
		A PipeInfo, a ServerClientParams, or $null.

		.EXAMPLE
		$PipeInfo = Resolve-PipeInfo -InputObject $PipeInfo

		.OUTPUTS
		The PipeInfo object, or the input unchanged, or $null.
	#>
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory)]
		[AllowNull()]
		$InputObject
	)
	If (1 -band ($env:MyFunctionTraceEnabled -as [Int])) { Write-MyFunctionTrace }

	If ($null -eq $InputObject)
	{ return $null }

	If ($null -eq $InputObject.$StrPipe -and $null -ne $InputObject.$StrPipeInfo)
	{
		Write-Verbose -Message 'Resolve-PipeInfo: a ServerClientParams was passed where PipeInfo is expected; using its PipeInfo.'
		return $InputObject.$StrPipeInfo
	}
	$InputObject
}
