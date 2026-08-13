Function Save-ServerLog
{
	<#
		.SYNOPSIS
		Flushes (or discards) the in-memory server diagnostics buffer to a per-session log file (0.11 hardening 4.5, step 1a).

		.DESCRIPTION
		Internal. Called at each server exit path. Decision:
		- FAILURE outcome (crashed / timed-out-unclaimed / unknown-exit) -> ALWAYS write the file (the safety
		  net; not opt-in).
		- CLEAN outcome (exit-pipe / relisten-timeout) -> write ONLY if InfoDisplay bit 8 is set; otherwise
		  DISCARD (no file, no disk I/O). Since clean exits write nothing today, discard-on-clean is identical
		  to current behaviour for every existing consumer.

		Idempotent: the first call wins (sets $Script:ServerLogSaved); later calls return immediately, so the
		timeout/crash/clean/finally paths can each call it without producing duplicate files.

		One file PER server initiation: server-<yyyyMMdd-HHmmss>-<pipename>.log under %APPDATA%\NamedPipe-Logs.
		The server elevates as the SAME user, so that folder is the launching user's own profile - a non-admin
		consumer can read it. Because a same-user attacker could read it too, the content is kept secrets-free:
		milestones carry no nonce/arguments, and drive-letter paths are redacted here as a backstop.

		.PARAMETER Outcome
		How the server ended: crashed | timed-out-unclaimed | unknown-exit | exit-pipe | relisten-timeout.

		.PARAMETER InfoDisplay
		The session InfoDisplay bitmask. Bit 8 (=8) keeps the log on a CLEAN exit; failures ignore it.

		.PARAMETER PipeName
		The data pipe Name (used verbatim in the filename; no consumer identity is added).

		.OUTPUTS
		[String] full path of the written log, or $null if discarded / on error. Never throws.
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Writes a diagnostics log file; must never prompt or throw inside server teardown.')]
	[OutputType([String])]
	Param (
		[Parameter(Mandatory, HelpMessage = 'Server exit outcome')]
		[String]$Outcome,
		[Parameter(Mandatory, HelpMessage = 'Session InfoDisplay bitmask')]
		[int]$InfoDisplay,
		[Parameter(Mandatory, HelpMessage = 'Data pipe Name')]
		[AllowEmptyString()]
		[String]$PipeName
	)

	# Idempotent - first exit path to reach here owns the flush.
	if ($Script:ServerLogSaved) { return $null }

	$Private:Failure   = $Outcome -in @('crashed', 'timed-out-unclaimed', 'unknown-exit')
	$Private:KeepClean = [bool]($InfoDisplay -band 8)
	# Discard a boring clean exit (bit 8 off) - no file, no disk I/O. This is the common path.
	#
	# !! 0.13 FIX - the flag used to be set ABOVE this test, i.e. before we knew whether anything
	# would actually be written. A DISCARDED clean exit therefore claimed ownership of the flush and
	# permanently suppressed every later call. The real server hits exactly that sequence:
	# Start-PipeServerOrClient calls Save-ServerLog -Outcome 'exit-pipe' after the re-listen loop
	# (discarded when bit 8 is off, which is the default), and if anything then throws, the Catch's
	# Save-ServerLog -Outcome 'crashed' and the Finally's 'unknown-exit' BOTH returned $null.
	# Net effect: a genuine crash produced NO LOG AT ALL.
	# Measured 2026-08-11 by exercising the extracted function - crash-alone wrote a log, but
	# clean-exit-then-crash wrote nothing (with bit 8 on, both wrote, which is why this hid for so long).
	# Consequence for diagnosis: "no server log was written" is NOT evidence that a server died hard.
	# The 2026-08-08 investigation into the reverted Get-SBResult changes rests on exactly that
	# inference - see the note in Get-SBResult.ps1.
	# The flag is now set ONLY when a log is genuinely written (below), so discarding a clean exit
	# leaves a later failure free to log.
	if (-not $Private:Failure -and -not $Private:KeepClean) { return $null }

	$Script:ServerLogSaved = $true

	try
	{
		$Private:LogDir = Join-Path -Path $env:APPDATA -ChildPath 'NamedPipe-Logs'
		if (-not (Test-Path -Path $Private:LogDir))
		{ $null = New-Item -ItemType Directory -Path $Private:LogDir -Force }

		# Pipe Name is already unique per session (Get-NewPipeName = Prefix-<FileTime>). Sanitise for a filename.
		$Private:Safe = if ($PipeName) { $PipeName -replace '[^A-Za-z0-9._-]', '_' } else { 'unknown' }
		$Private:LogFile = Join-Path -Path $Private:LogDir -ChildPath ('server-{0}-{1}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $Private:Safe)

		$Private:Out = [System.Collections.Generic.List[string]]::new()
		$Private:Out.Add('=== NamedPipe server diagnostics log ===')
		$Private:Out.Add(('Outcome     : {0}' -f $Outcome))
		$Private:Out.Add(('Pipe        : {0}' -f $PipeName))
		$Private:Out.Add(('ServerPID   : {0}' -f $PID))
		$Private:Out.Add(('Written     : {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
		if ($Script:NonceRejectCount -gt 0)
		{ $Private:Out.Add(('NonceReject : {0} connection(s) presented a wrong/absent nonce' -f $Script:NonceRejectCount)) }
		$Private:Out.Add('--- milestones ---')
		if ($Script:ServerLogBuffer)
		{ foreach ($Private:Line in $Script:ServerLogBuffer) { $Private:Out.Add($Private:Line) } }

		$Private:Text = ($Private:Out -join [Environment]::NewLine)
		# Backstop redaction: strip drive-letter paths so the log never leaks filesystem layout / arg paths.
		# Literal replacement string (no $ tokens), so no .NET regex substitution risk.
		$Private:Text = [regex]::Replace($Private:Text, '[A-Za-z]:\\[^\r\n]*', '<path-redacted>')

		[System.IO.File]::WriteAllText($Private:LogFile, $Private:Text, [System.Text.UTF8Encoding]::new($false))
		# 0.11 hardening (4.5 step 1d): on a FAILURE, also drop a Windows Event Log pointer at this file.
		# Wrapped - if the 'NamedPipe' source is not registered (Register-PipeEventSource / Deploy-Modules) or
		# we lack permission, degrade silently to file-only. .NET API is used (Write-EventLog is absent in PS7).
		if ($Private:Failure)
		{
			try
			{
				$Private:EvType = if ($Outcome -eq 'crashed') { [System.Diagnostics.EventLogEntryType]::Error } else { [System.Diagnostics.EventLogEntryType]::Warning }
				$Private:EvId   = switch ($Outcome) { 'crashed' { 4501 } 'timed-out-unclaimed' { 4502 } default { 4503 } }
				$Private:EvMsg  = 'NamedPipe server {0} (pipe {1}, PID {2}). Details: {3}' -f $Outcome, $PipeName, $PID, $Private:LogFile
				$Private:EvLog  = [System.Diagnostics.EventLog]::new('Application')
				$Private:EvLog.Source = 'NamedPipe'
				$Private:EvLog.WriteEntry($Private:EvMsg, $Private:EvType, $Private:EvId)
				$Private:EvLog.Dispose()
			}
			catch { $null = $_ }
		}
		return $Private:LogFile
	}
	catch
	{
		# Logging must never affect the session - swallow any failure.
		return $null
	}
}
