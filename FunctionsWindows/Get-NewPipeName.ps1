Function Get-NewPipeName
{
	<#
			.SYNOPSIS
			Generates a unique name for a named pipe instance.

			.DESCRIPTION
			Creates a unique pipe name by combining an optional prefix with a timestamp
			derived from the current date/time (ToFileTime). This ensures each pipe
			instance has a distinct name to avoid conflicts.

			If no custom prefix is provided, 'Pipe' is used as the default prefix.

			.PARAMETER PipeName
			An optional prefix for the pipe name. Default is 'Pipe'.

			.EXAMPLE
			Get-NewPipeName
			Returns a unique pipe name, e.g.: Pipe-133650124358579021

			.EXAMPLE
			Get-NewPipeName -PipeName 'MyApp'
			Returns a unique pipe name with custom prefix, e.g.: MyApp-133650124358579021

			.INPUTS
			None.

			.OUTPUTS
			System.String - A unique pipe name in the format 'Prefix-Timestamp'.
	#>
	[CmdletBinding()]
	Param (
		[Parameter()]
		[String]$PipeName = 'Pipe'
	)
	If (1 -band ($env:MyFunctionTraceEnabled -as [Int])) { Write-MyFunctionTrace }

	# 2026-09-15: wrapped even though this looks trivial - per the user's own stated principle, never
	# assume the environment is correctly configured; re-thrown so callers keep current behavior, this
	# only adds a trackable record if Get-Date/formatting ever genuinely fails.
	Try
	{
		'{0}-{1}' -f $Local:PipeName, $((Get-Date).ToFileTime())
	}
	Catch
	{
		Write-MyCatchAudit -Source 'Get-NewPipeName: failed to build a pipe name' -ErrorRecord $_
		# Only ever called while BUILDING a pipe name (Set-ObjectParameterSet's ServerClientParams
		# setup), before any pipe exists - a throw here fails setup, it cannot collapse an
		# already-established, actively-conversing pipe.
		throw
	}
}
