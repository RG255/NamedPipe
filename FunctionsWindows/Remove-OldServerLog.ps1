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
	if ($RetentionDays -le 0) { return }   # 0 = keep forever
	try
	{
		$Private:LogDir = Join-Path -Path $env:APPDATA -ChildPath 'NamedPipe-Logs'
		if (-not (Test-Path -Path $Private:LogDir)) { return }
		$Private:Cutoff = (Get-Date).AddDays(-$RetentionDays)
		Get-ChildItem -Path $Private:LogDir -Filter 'server-*.log' -File -ErrorAction SilentlyContinue |
			Where-Object { $_.LastWriteTime -lt $Private:Cutoff } |
			ForEach-Object { try { Remove-Item -Path $_.FullName -Force -ErrorAction Stop } catch { $null = $_ } }
	}
	catch { $null = $_ }
}
