Function Remove-OldServerLog
{
	<#
		.SYNOPSIS
		Prunes old server diagnostics logs from %APPDATA%\NamedPipe-Logs (0.11 hardening 4.5, step 1c).

		.DESCRIPTION
		Internal. Called ONCE at server startup. Deletes server-*.log files older than RetentionDays. This is
		the backstop for whatever the flush-on-interesting rule (Save-ServerLog) chooses to keep. Never throws -
		logging housekeeping must not affect the session; per-file deletes are wrapped so two servers starting
		together cannot fail each other on a shared file.

		.PARAMETER RetentionDays
		Age threshold in days. 0 (or less) = keep forever (no pruning).
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Housekeeping delete of old log files; must never prompt or throw at server startup.')]
	Param (
		[Parameter(Mandatory, HelpMessage = 'Age threshold in days; 0 = keep forever')]
		[int]$RetentionDays
	)
	If (1 -band ($env:MyFunctionTraceEnabled -as [Int])) { Write-MyFunctionTrace }

	if ($RetentionDays -le 0) { return }   # 0 = keep forever
	$Private:Folder = $null
	try
	{
		$Private:LogDir = Join-Path -Path $env:APPDATA -ChildPath 'NamedPipe-Logs'
		# Deletes go through the folder handle and a handle per file, so a junction or link swapped in cannot redirect them
		# (see Open-SafeLogFolder). A redirected folder is refused and audited there; a missing folder means nothing to prune.
		try { $Private:Folder = Open-SafeLogFolder -Path $Private:LogDir }
		catch [System.IO.DirectoryNotFoundException] { return }
		$null = $Private:Folder.RemoveOlderThan('server-*.log', (Get-Date).AddDays(-$RetentionDays).ToUniversalTime())
		foreach ($Private:Skipped in $Private:Folder.Refused)
		{ Write-MyCatchAudit -Source ('Remove-OldServerLog: left a log entry alone because it is not an ordinary file in the log folder - {0}' -f $Private:Skipped) -ErrorRecord ([System.Management.Automation.ErrorRecord]::new([System.IO.IOException]::new($Private:Skipped), 'LogEntryRefused', [System.Management.Automation.ErrorCategory]::SecurityError, $null)) }
		foreach ($Private:Failed in $Private:Folder.Errors)
		{ Write-MyCatchAudit -Source 'Remove-OldServerLog: delete one expired log file - best-effort retention cleanup, one locked/undeletable file must not stop the rest' -ErrorRecord ([System.Management.Automation.ErrorRecord]::new([System.IO.IOException]::new($Private:Failed), 'LogDeleteFailed', [System.Management.Automation.ErrorCategory]::WriteError, $null)) }
	}
	catch { Write-MyCatchAudit -Source 'Remove-OldServerLog: best-effort log-retention sweep - a failure here (e.g. cannot enumerate the log folder) just means old logs are not pruned this run' -ErrorRecord $_ }
	finally { if ($Private:Folder) { $Private:Folder.Dispose() } }
}
