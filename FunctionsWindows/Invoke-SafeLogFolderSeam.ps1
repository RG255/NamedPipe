Function Invoke-SafeLogFolderSeam
{
	<#
		.SYNOPSIS
		Intentionally empty: marks the moment between preparing the log folder and opening it (Open-SafeLogFolder) so tests can act there.
	#>
	[CmdletBinding()]
	Param ()
	If (1 -band ($env:MyFunctionTraceEnabled -as [Int])) { Write-MyFunctionTrace }
}
