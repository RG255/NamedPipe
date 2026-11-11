# VENDORED from CommonScripts\0.2\Functions\Show-MyCatchAuditSummary.ps1 by Sync-SharedUtilities [SHA256 FAFFF016DF6941E07E39AB81B862F8EB004408B47597424F336B7C2F2C0AF171] - DO NOT EDIT (edit the master; Deploy-Modules re-syncs).
Function Show-MyCatchAuditSummary
{
	<#
		.SYNOPSIS
		Prints a short, grouped summary of what Write-MyCatchAudit caught - this process only (default),
		or the full PERSISTED log that survives across process restarts.

		.DESCRIPTION
		2026-09-07: since capture is always on (see Write-MyCatchAudit), a run can complete with real
		captured entries that nobody happened to be watching for live. This is the intended place to
		check at the natural end of any CLI script/orchestrator (e.g. as the last step of
		Invoke-ModuleReleaseChecks.ps1) - prints nothing at all on a clean run (nothing was caught), or a
		short one-block summary grouped by ExceptionType (count + one representative Source/Message per
		type) when something was. Deliberately terse - this is a "go look closer" signal, not the full
		diagnostic dump Get-MyError -Return already provides for deep triage.

		2026-09-10: added -Persisted, which answers the gap this doc used to flag as unsolved -
		"a GUI wanting to show 'something was caught last time you ran this' across process launches" -
		by reading the durable on-disk mirror instead of this process's in-memory list. Use this after
		Show-MyCatchAuditPendingNotice (fired automatically at module init) tells you something is
		pending, to see what it actually is before deciding whether to Invoke-MyCatchAuditTriage or
		Clear-MyCatchAuditLog.

		2026-11-08: spill files. Entries that a non-elevated session could not write to the persisted log are saved
		to a spill folder (see Write-MyCatchAudit). When this runs ELEVATED they are first imported into the
		persisted log (via Get-MyCatchAuditLog) and shown like any other entry, with -Persisted counting those
		imported (Origin=Spill). When it runs NON-elevated it imports nothing and says how many are pending import
		and how to import them. Both modes end with that pending line when anything is waiting.

		.PARAMETER Clear
		Default (in-memory) mode only: also empties the log after reporting it. No effect combined with
		-Persisted - see Get-MyCatchAuditLog -Persisted's own doc for why persisted entries are removed
		through Invoke-MyCatchAuditTriage/Clear-MyCatchAuditLog instead, never through this switch.

		.PARAMETER Persisted
		Report on the durable, cross-process, cross-module log from disk instead of this process's
		in-memory one.

		.EXAMPLE
		Show-MyCatchAuditSummary
		# prints nothing if nothing was caught THIS PROCESS; a short grouped block otherwise

		.EXAMPLE
		Show-MyCatchAuditSummary -Persisted
		# same shape, but across every process that has ever run since the log was last cleared/triaged

		.EXAMPLE
		Show-MyCatchAuditSummary -Clear
		# same, then empties the in-memory log so the next run/segment starts clean
	#>
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '',
		Justification = 'Deliberately process-wide, not per-module - reads the shared drop counters Write-MyCatchAudit maintains for every module in the process (see Write-MyCatchAudit''s own DESCRIPTION).')]
	[CmdletBinding()]
	Param ([Switch]$Clear, [Switch]$Persisted)

	$Private:_logDropped = [Int]$Global:MyCatchAuditLogDropped
	# Get-MyCatchAuditLog imports the spill files first when this process is elevated. Whatever is STILL waiting in the
	# spill folder afterwards (a non-elevated caller, or an import that failed) is reported as pending (2026-11-08).
	# @(...) so a single entry is still an array: Windows PowerShell 5.1 unrolls a one-element result, and then .Count is $null.
	$Private:_log = @(If ($Persisted) { Get-MyCatchAuditLog -Persisted } Else { Get-MyCatchAuditLog -Clear:$Clear })
	$Private:_spillPending = 0
	If (Get-Command -Name Read-MyCatchAuditSpill -CommandType Function -ErrorAction SilentlyContinue)
	{ $Private:_spillPending = @((Read-MyCatchAuditSpill).Entries).Count }
	$Private:_spillNote = ('  NOTE: {0} entr(ies) saved by sessions that could not write the persisted log are pending import from the spill folder; run Get-MyCatchAuditLog from an elevated window (or deploy the modules) to import them.' -f $Private:_spillPending)
	If (-not $Private:_log -or $Private:_log.Count -eq 0)
	{
		If ($Private:_spillPending -gt 0) { Write-Output -InputObject $Private:_spillNote }
		return
	}

	Write-Output -InputObject ('{0} unexpected-but-accepted issue(s) {1}:' -f $Private:_log.Count, $(If ($Persisted) { 'are recorded in the persisted log' } Else { 'were caught during this run' }))
	# Grouped by (ExceptionType, Source), not ExceptionType alone (2026-09-10 fix) - a single CLR
	# exception type can cover many genuinely different catch sites, and the old grouping picked
	# ONE arbitrary Source/Message as "the" example for the whole type, silently hiding any others
	# sharing that type. Message is truncated and whitespace-collapsed for this terse view - it is
	# often a multi-line diagnostic dump (icacls output, a full Get-MyError block) that reads as an
	# unreadable wall of text on one console line; Get-MyCatchAuditLog still returns it in full.
	$Private:_maxMessageLength = 100
	$Private:_groups = $Private:_log | Group-Object -Property ExceptionType, Source
	ForEach ($Private:_g in $Private:_groups)
	{
		$Private:_example = $Private:_g.Group[0]
		$Private:_shortType = ($Private:_example.ExceptionType -split '\.')[-1]
		$Private:_flatMessage = ($Private:_example.Message -replace '\s+', ' ').Trim()
		If ($Private:_flatMessage.Length -gt $Private:_maxMessageLength)
		{ $Private:_flatMessage = $Private:_flatMessage.Substring(0, $Private:_maxMessageLength) + '...' }
		Write-Output -InputObject ('  {0} x{1} - {2}' -f $Private:_shortType, $Private:_g.Count, $Private:_example.Source)
		Write-Output -InputObject ('      {0}' -f $Private:_flatMessage)
	}
	# Entries lost to the in-memory caps (oldest log entries; relay-queue overflow). Captured before the call
	# above cleared anything: -Clear resets the log counter only inside Get-MyCatchAuditLog, so read it first.
	If (-not $Persisted -and ($Private:_logDropped -or $Global:MyCatchAuditUnpersistedDropped))
	{
		Write-Output -InputObject ('  NOTE: {0} older in-memory entr(ies) dropped at the 1000-entry cap; {1} entr(ies) not queued for persisting (queue full).' -f [Int]$Private:_logDropped, [Int]$Global:MyCatchAuditUnpersistedDropped)
	}
	If (-not $Persisted -and $Global:MyCatchAuditSpillDropped)
	{
		Write-Output -InputObject ('  NOTE: {0} entr(ies) could not be saved to the spill file (per-process cap of 1000 lines / 1 MB, or the write failed).' -f [Int]$Global:MyCatchAuditSpillDropped)
	}
	If ($Persisted)
	{
		$Private:_imported = @($Private:_log | Where-Object { $_.Origin -eq 'Spill' }).Count
		If ($Private:_imported -gt 0)
		{ Write-Output -InputObject ('  NOTE: {0} of these were imported from spill files (Origin=Spill: saved by a session that could not write this log; SpillOwner names the account that owned the file).' -f $Private:_imported) }
	}
	If ($Private:_spillPending -gt 0) { Write-Output -InputObject $Private:_spillNote }
	If ($Persisted)
	{ Write-Output -InputObject 'Run Get-MyCatchAuditLog -Persisted for full detail, Invoke-MyCatchAuditTriage to resolve individually, or Clear-MyCatchAuditLog to archive all of it.' }
	Else
	{ Write-Output -InputObject 'Run Get-MyCatchAuditLog for full detail on each one.' }
}
