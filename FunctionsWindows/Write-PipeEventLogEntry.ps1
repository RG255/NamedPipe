Function Write-PipeEventLogEntry
{
	<#
		.SYNOPSIS
		Writes one entry to the Application Event Log under the NamedPipe source. Never throws.

		.DESCRIPTION
		0.18. A thin wrapper so callers (and tests) have one place that touches the Event Log. If the source is not registered or the log
		is unavailable the failure is recorded in the catch audit and the caller carries on.

		.PARAMETER EventId
		The event id (4514 = request policy Audit mode record).

		.PARAMETER Text
		The message text.

		.PARAMETER EntryType
		Information, Warning or Error. Default Warning.

		.OUTPUTS
		None.
	#>
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Writes one log entry; there is nothing to preview.')]
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory)]
		[Int]$EventId,

		[Parameter(Mandatory)]
		[String]$Text,

		[ValidateSet('Information', 'Warning', 'Error')]
		[String]$EntryType = 'Warning'
	)
	If (1 -band ($env:MyFunctionTraceEnabled -as [Int])) { Write-MyFunctionTrace }

	$Private:Ev = $null
	Try
	{
		$Private:Ev = [System.Diagnostics.EventLog]::new('Application')
		$Private:Ev.Source = 'NamedPipe'
		$Private:Ev.WriteEntry($Text, [System.Diagnostics.EventLogEntryType]$EntryType, $EventId)
	}
	Catch
	{
		Write-MyCatchAudit -Source 'Write-PipeEventLogEntry: writing the Event Log entry failed (source not registered or log unavailable) - diagnostics only, the caller carries on' -ErrorRecord $_
	}
	Finally
	{
		If ($Private:Ev) { $Private:Ev.Dispose() }
	}
}
