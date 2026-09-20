Function Write-HealthPipeCatchRecord
{
	<#
		.SYNOPSIS
		Disk-only, cross-runspace-safe analog of Write-MyCatchAudit, for the health-pipe listener only.

		.DESCRIPTION
		2026-09-11. Start-PipeServerOrClient's PING/PONG health-pipe listener runs inside a bare
		[RunspaceFactory]::CreateRunspace() runspace with no module functions loaded into it -
		Write-MyCatchAudit genuinely cannot be called there (the function isn't loaded, and even a
		dot-sourced copy would append into that runspace's OWN separate $Global:MyCatchAuditLog, which
		nothing else ever reads). This function is dot-sourced INTO that runspace at runtime (its own
		file path is handed in as a plain string via .AddArgument(), since only argument values - not
		function definitions - cross a runspace boundary) and persists straight to the shared JSONL log,
		bypassing $Global: capture entirely - there is nothing reachable to capture into from here.

		Mirrors Write-MyCatchAudit's persisted-record shape exactly (same field names, so a reader
		expecting that schema sees nothing unusual), plus one additive field, Origin, so these entries
		are identifiable as having come from the isolated health-pipe runspace rather than the module's
		normal call sites.

		Must never throw - it runs inside a background listener loop that has to keep looping regardless
		of what happens here, same contract as Write-MyCatchAudit itself.

		.PARAMETER PersistPath
		Full path to the shared catch-audit JSONL log (resolved ONCE in the main runspace via
		Get-MyCatchAuditPersistPath - that function is not callable from inside the health-pipe
		runspace, so its result is handed in as a plain string instead).

		.PARAMETER Source
		Free-text reason this catch is accepted - same purpose as Write-MyCatchAudit's own -Source.

		.PARAMETER ErrorRecord
		The caught error - pass $_ from inside the Catch block.

		.PARAMETER Teardown
		Same meaning as Write-MyCatchAudit's -Teardown: pass this for a catch inside the health-pipe
		loop's own Finally/Dispose teardown. Live-echo (see below) never fires when this is set,
		regardless of $env:MyCatchAuditVerbose.

		.EXAMPLE
		Write-HealthPipeCatchRecord -PersistPath $PersistPath -Source 'Health pipe listener: WaitForConnection/read/respond cycle' -ErrorRecord $_
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory)]
		[String]$PersistPath,
		[Parameter(Mandatory)]
		[String]$Source,
		[Parameter(Mandatory)]
		[System.Management.Automation.ErrorRecord]$ErrorRecord,
		[Switch]$Teardown
	)

	# Deliberately NOT traced (2026-09-15): this function is dot-sourced into a bare
	# [RunspaceFactory]::CreateRunspace() runspace with NO module functions loaded into it (see
	# .DESCRIPTION) - Write-MyFunctionTrace, like Write-MyCatchAudit, genuinely is not callable from
	# there. Same permanent-exclusion category as the trace facility's own machinery.

	# Must never throw - see .DESCRIPTION.
	Try
	{
		$Private:_callerFrame = (Get-PSCallStack)[1]
		$Private:_callerLocation = If ($Private:_callerFrame)
		{ '{0} ({1})' -f $Private:_callerFrame.Command, $Private:_callerFrame.Location }
		Else { '<unknown caller>' }

		$Private:_exceptionTypeFull = $ErrorRecord.Exception.GetType().FullName
		$Private:_exceptionTypeName = $ErrorRecord.Exception.GetType().Name
		# 2026-09-11, found live: Split-Path -Path '' throws a ParameterBindingValidationException that
		# -ErrorAction SilentlyContinue does NOT suppress (binding validation runs before a cmdlet's own
		# ErrorAction takes effect) - and ScriptName IS an empty string (not $null) for an error raised
		# inside an anonymous scriptblock with no backing .ps1 file, exactly the health-pipe listener's
		# own AddScript block. Explicit empty-check avoids this rather than trusting -ErrorAction alone.
		$Private:_scriptLeaf = If ([String]::IsNullOrEmpty($ErrorRecord.InvocationInfo.ScriptName)) { $null }
		Else { Split-Path -Path $ErrorRecord.InvocationInfo.ScriptName -Leaf -ErrorAction SilentlyContinue }
		$Private:_id = [Guid]::NewGuid().ToString('N').Substring(0, 8)
		$Private:_timestamp = Get-Date

		Try
		{
			$Private:_jsonLine = [PSCustomObject]@{
				Id             = $Private:_id
				Timestamp      = $Private:_timestamp.ToUniversalTime().ToString('o')
				Source         = $Source
				CallerLocation = $Private:_callerLocation
				ExceptionType  = $Private:_exceptionTypeFull
				Message        = $ErrorRecord.Exception.Message
				ScriptName     = $Private:_scriptLeaf
				LineNumber     = $ErrorRecord.InvocationInfo.ScriptLineNumber
				ProcessId      = $PID
				UserName       = [System.Environment]::UserName
				MachineName    = [System.Environment]::MachineName
				IsTeardown     = [Bool]$Teardown
				Origin         = 'HealthPipeListener'
			} | ConvertTo-Json -Compress -Depth 3
			Add-Content -LiteralPath $PersistPath -Value $Private:_jsonLine -Encoding utf8 -ErrorAction Stop
		}
		# SILENT-OK: a full disk, a locked-down ProgramData, or any other write failure must never turn
		# a health-pipe catch into a thrown exception inside a background listener loop. Unlike
		# Write-MyCatchAudit, there is no recursive-call-itself fallback available here (this function
		# has no in-memory capture to fall back to reporting through) - a persist failure is simply lost,
		# same as the pre-2026-09-11 behavior for this exact site.
		Catch { $null = $_ }

		# Live-echo tier, matching Write-MyCatchAudit exactly. $env: variables are OS-process-level, not
		# runspace-scoped (unlike $Global:/$Script:), so this correctly reads the same toggle
		# Enable-MyCatchAudit/Disable-MyCatchAudit sets, with no extra plumbing needed.
		If (-not $Teardown -and $env:MyCatchAuditVerbose -eq '1')
		{
			$Private:_message = "CatchAudit (HealthPipe) :: {0}`n  at {1}`n  {2}: {3}`n  (error raised at {4}:{5})" -f
			$Source, $Private:_callerLocation, $Private:_exceptionTypeName, $ErrorRecord.Exception.Message,
			$Private:_scriptLeaf, $ErrorRecord.InvocationInfo.ScriptLineNumber

			Try { [Console]::Error.WriteLine($Private:_message) }
			# SILENT-OK: same reasoning as Write-MyCatchAudit's own equivalent guard.
			Catch { $null = $_ }

			Try { Write-Warning -Message $Private:_message }
			# SILENT-OK: same reasoning as Write-MyCatchAudit's own equivalent guard.
			Catch { $null = $_ }
		}
	}
	# SILENT-OK: this function must never throw - see .DESCRIPTION.
	Catch { $null = $_ }
}
