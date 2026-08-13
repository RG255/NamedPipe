Function Show-PipeServerLog
{
	<#
		.SYNOPSIS
		Prints the most recent NamedPipe server diagnostics log (0.11 hardening 4.5, step 1c).

		.DESCRIPTION
		Convenience wrapper over Get-PipeServerLog: writes the newest matching server log to the host, with a
		header naming the file. Use -PipeName to target one session.

		.PARAMETER PipeName
		Optional. Restrict to the newest log for this pipe Name.

		.EXAMPLE
		Show-PipeServerLog
		Print the most recent server diagnostics log.
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive diagnostic display for the operator.')]
	Param (
		[Parameter()]
		[String]$PipeName
	)
	$Private:File = @(Get-PipeServerLog -PipeName $PipeName -Newest 1)
	if ($Private:File.Count -eq 0)
	{
		Write-Host 'No NamedPipe server diagnostics log found.' -ForegroundColor Yellow
		return
	}
	Write-Host ('=== {0} ===' -f $Private:File[0].Name) -ForegroundColor Cyan
	Get-Content -Path $Private:File[0].FullName
}
