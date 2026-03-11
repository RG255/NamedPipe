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
	'{0}-{1}' -f $Local:PipeName, $((Get-Date).ToFileTime())
}
