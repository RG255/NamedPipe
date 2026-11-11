# VENDORED from CommonScripts\0.2\Functions\Invoke-MyCatchAuditTriage.ps1 by Sync-SharedUtilities [SHA256 E95B2C644DDCAE5AA2FB254D40A07D5003E70B7FB711FA2F5E4F5A5124F93867] - DO NOT EDIT (edit the master; Deploy-Modules re-syncs).
Function Invoke-MyCatchAuditTriage
{
	<#
		.SYNOPSIS
		Interactively review the PERSISTED catch-audit log one recurring issue at a time, and remove
		only the ones you resolve - everything else stays pending for next time.

		.DESCRIPTION
		2026-09-10. Groups persisted entries by (ExceptionType, Source) - the natural "this is one
		recurring, already-understood issue" unit, since the same catch site firing 40 times is one
		thing to triage, not 40. For each group, shows a representative entry (first/last seen, how
		many times, one example message) and prompts:

			[R]esolve  - remove every entry in this group from the persisted log (you understand it,
			             nothing further to do - or you have already fixed the underlying cause)
			[S]kip     - leave this group's entries exactly as they are, for a future pass
			[Q]uit     - stop reviewing; entries already marked Resolve in THIS run are still removed,
			             everything else (including the group you quit on) stays pending

		Unlike Clear-MyCatchAuditLog (which archives the WHOLE file at once), this lets a log holding
		both "yes, expected, ignore" and "wait, that's new" entries be triaged down to just the second
		kind, without losing track of what you have not looked at yet.

		2026-11-08: run from an ELEVATED window, the spill files are imported first (it reads the log through
		Get-MyCatchAuditLog -Persisted, which calls Import-MyCatchAuditSpill), so entries that non-elevated
		sessions saved there are triaged like any other; imported ones carry Origin=Spill. Non-elevated, nothing
		is imported and the spill files are left alone.

		Rewrites the persisted log via a temp-file-then-swap (Move-Item), never a direct in-place edit -
		a crash mid-rewrite leaves either the untouched original or the fully-written replacement, never
		a half-written file. Does not touch the in-memory $Global:MyCatchAuditLog (a separate,
		process-scoped view - see Get-MyCatchAuditLog's own doc).

		.EXAMPLE
		Invoke-MyCatchAuditTriage
		# walks each recurring issue, asks Resolve/Skip/Quit, then reports how many were removed vs
		# left pending
	#>
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'State change (rewriting the log) is the explicit purpose of this function; the interactive Resolve/Skip/Quit prompt IS the confirmation')]
	[CmdletBinding(SupportsShouldProcess)]
	Param ()

	# Get-MyCatchAuditLog -Persisted imports the spill files first when this process is elevated (2026-11-08).
	$Private:_all = @(Get-MyCatchAuditLog -Persisted)
	If ($Private:_all.Count -eq 0)
	{ Write-Output -InputObject 'Invoke-MyCatchAuditTriage: the persisted log is empty - nothing to triage.'; return }

	$Private:_groups = @($Private:_all | Group-Object -Property ExceptionType, Source | Sort-Object -Property { $_.Group[0].Timestamp })
	$Private:_resolvedIds = [System.Collections.Generic.HashSet[String]]::new()
	$Private:_quit = $false

	Write-Output -InputObject ('{0} recurring issue(s) across {1} total entr{2} to triage.' -f `
			$Private:_groups.Count, $Private:_all.Count, $(If ($Private:_all.Count -eq 1) { 'y' } Else { 'ies' }))

	ForEach ($Private:_g in $Private:_groups)
	{
		If ($Private:_quit) { break }
		$Private:_sorted = @($Private:_g.Group | Sort-Object -Property Timestamp)
		$Private:_first = $Private:_sorted[0]
		$Private:_last = $Private:_sorted[-1]

		Write-Output -InputObject ''
		Write-Output -InputObject ('[{0}] x{1}' -f $Private:_first.ExceptionType, $Private:_sorted.Count)
		Write-Output -InputObject ('  Source : {0}' -f $Private:_first.Source)
		Write-Output -InputObject ('  Where  : {0}' -f $Private:_first.CallerLocation)
		Write-Output -InputObject ('  First  : {0}' -f $Private:_first.Timestamp)
		Write-Output -InputObject ('  Last   : {0}' -f $Private:_last.Timestamp)
		Write-Output -InputObject ('  Example: {0}' -f $Private:_first.Message)

		$Private:_choice = (Read-Host '  [R]esolve / [S]kip / [Q]uit').Trim().ToUpperInvariant()
		Switch ($Private:_choice)
		{
			'R'
			{
				ForEach ($Private:_e in $Private:_sorted) { $null = $Private:_resolvedIds.Add([String]$Private:_e.Id) }
				Write-Output -InputObject ('  Marked {0} entr{1} resolved.' -f $Private:_sorted.Count, $(If ($Private:_sorted.Count -eq 1) { 'y' } Else { 'ies' }))
			}
			'Q'
			{ $Private:_quit = $true; Write-Output -InputObject '  Stopping - anything already marked resolved above will still be removed.' }
			Default
			{ Write-Output -InputObject '  Left pending.' }
		}
	}

	If ($Private:_resolvedIds.Count -eq 0)
	{ Write-Output -InputObject ''; Write-Output -InputObject 'Nothing resolved - the persisted log is unchanged.'; return }

	$Private:_path = Get-MyCatchAuditPersistPath

	If ($PSCmdlet.ShouldProcess($Private:_path, ('Remove {0} resolved entr{1} from the persisted catch-audit log' -f $Private:_resolvedIds.Count, $(If ($Private:_resolvedIds.Count -eq 1) { 'y' } Else { 'ies' }))))
	{
		Try
		{
			$Private:_tempPath = $Private:_path + ('.tmp-{0}' -f [Guid]::NewGuid().ToString('N'))
			# Re-read the file NOW and drop only the resolved Ids, keeping every other line as written: other processes
			# append while the prompts are open, and rewriting from the snapshot taken at the start would delete those.
			$Private:_remaining = @(Get-Content -LiteralPath $Private:_path -ErrorAction Stop | Where-Object { $_ -and $_.Trim() } | Where-Object {
					$Private:_lineId = $null
					Try { $Private:_lineId = [String](($_ | ConvertFrom-Json -ErrorAction Stop).Id) }
					# SILENT-OK: a line that does not parse is kept untouched, never dropped.
					Catch { $Private:_lineId = $null }
					-not ($Private:_lineId -and $Private:_resolvedIds.Contains($Private:_lineId))
				})
			If ($Private:_remaining.Count -gt 0)
			{
				$Private:_remaining | Set-Content -LiteralPath $Private:_tempPath -Encoding utf8 -ErrorAction Stop
			}
			Else
			{ $null = New-Item -Path $Private:_tempPath -ItemType File -Force -ErrorAction Stop }
			Move-Item -LiteralPath $Private:_tempPath -Destination $Private:_path -Force -ErrorAction Stop

			Write-Output -InputObject ''
			Write-Output -InputObject ('Removed {0} resolved entr{1}; {2} still pending.' -f `
					$Private:_resolvedIds.Count, $(If ($Private:_resolvedIds.Count -eq 1) { 'y' } Else { 'ies' }), $Private:_remaining.Count)
		}
		Catch
		{ Write-Warning -Message ('Invoke-MyCatchAuditTriage: could not rewrite the persisted log: {0}' -f $_.Exception.Message) }
	}
}
