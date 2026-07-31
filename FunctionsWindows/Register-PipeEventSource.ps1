Function Register-PipeEventSource
{
	<#
		.SYNOPSIS
		Registers the 'NamedPipe' Windows Event Log source (0.11 hardening 4.5, step 1d). REQUIRES ADMIN.

		.DESCRIPTION
		Creates the source under the Application log so the elevated pipe server can write a one-line FAILURE
		pointer (crash / unclaimed-timeout) that references the full diagnostics-log file (see Save-ServerLog).
		The Event Log is the searchable INDEX; the file is the detail.

		One-time and idempotent. Normally run by Deploy-Modules.ps1 (which already elevates), but can be called
		manually from an elevated session. Creating an event source needs admin; WRITING to it afterwards does
		not, so the (possibly non-elevated) server can log once the source exists. If the source is never
		registered, the server silently degrades to file-only.

		.PARAMETER SourceName
		The event source name. Default 'NamedPipe' (what Save-ServerLog writes to). Do not change unless you
		also change the writer.

		.OUTPUTS
		[Bool] $true if the source exists (already, or after creation); $false if it could not be created
		(e.g. not elevated). Never throws.
	#>
	[CmdletBinding()]
	[OutputType([Bool])]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'One-time idempotent event-source registration; returns bool, never prompts.')]
	Param (
		[Parameter()]
		[String]$SourceName = 'NamedPipe'
	)
	try
	{
		$Private:Exists = $false
		try { $Private:Exists = [System.Diagnostics.EventLog]::SourceExists($SourceName) } catch { $Private:Exists = $false }
		if ($Private:Exists) { return $true }
		[System.Diagnostics.EventLog]::CreateEventSource($SourceName, 'Application')
		return $true
	}
	catch
	{
		return $false
	}
}
