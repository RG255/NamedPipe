# VENDORED from CommonScripts\0.2\Functions\Get-MyCatchAuditSpillPath.ps1 by Sync-SharedUtilities [SHA256 060F01139E65458656723966A33E6A086B13010EEF547262688D0ECF94D05AE4] - DO NOT EDIT (edit the master; Deploy-Modules re-syncs).
Function Get-MyCatchAuditSpillPath
{
	<#
		.SYNOPSIS
		Internal: resolves the catch-audit SPILL folder (or this process's spill file inside it).

		.DESCRIPTION
		2026-11-08. The persisted catch-audit log (see Get-MyCatchAuditPersistPath) is created by whichever process
		writes first; once an elevated process has created it, an ordinary process is denied. Such an entry used to
		be queued in memory only and was lost when the process ended without relaying it. Write-MyCatchAudit now
		writes it IMMEDIATELY to a spill file in a folder that anything can add a file to:

		    <ProgramData>\CatchAudit\Spill\Spill-<user>-<PID>.jsonl

		ProgramData and not %LOCALAPPDATA%, because the elevation account is often a different account from the
		daily one, so an elevated process cannot see the daily user's profile. One file per process (user + PID) so
		writers never collide. The folder's ACL is the FunctionTrace pattern (see Protect-MyCatchAuditSpillFolder):
		Users may list it and add a file, nothing more; each writer owns, and so can modify, only its own files;
		SYSTEM and Administrators have full control. Deploy-Modules asserts it on every deploy.

		Spill files are IMPORTED into the persisted log by an elevated Get-MyCatchAuditLog,
		Show-MyCatchAuditSummary, Invoke-MyCatchAuditTriage or Deploy-Modules (Import-MyCatchAuditSpill).

		The folder-creation catch is deliberately silent and NOT routed through Write-MyCatchAudit (this runs inside
		Write-MyCatchAudit's own failure path): a missing folder simply makes the spill write fail, which the caller
		handles.

		Not exported - internal plumbing shared by the writer, reader, importer and the ACL helper so they agree on
		one path.

		.PARAMETER File
		Return this process's spill file instead of the folder.

		.PARAMETER NoCreate
		Do not create the folder if it is missing (readers and the ACL checker use this).

		.OUTPUTS
		[String] the folder, or with -File the file path (the file may not exist yet).
	#>
	[CmdletBinding()]
	[OutputType([String])]
	Param ([Switch]$File, [Switch]$NoCreate)

	$Folder = Join-Path -Path (Join-Path -Path $env:ProgramData -ChildPath 'CatchAudit') -ChildPath 'Spill'
	If (-not $NoCreate -and -not (Test-Path -LiteralPath $Folder -PathType Container))
	{
		Try { $null = New-Item -Path $Folder -ItemType Directory -Force -ErrorAction Stop }
		# SILENT-OK: best-effort folder creation inside Write-MyCatchAudit's failure path - cannot call
		# Write-MyCatchAudit from here (recursion); a still-missing folder just makes the spill write fail, which
		# the caller handles by falling back to the in-memory queue.
		Catch { $null = $_ }
	}
	If (-not $File) { Return $Folder }

	$UserPart = ([Environment]::UserName -replace '[^A-Za-z0-9._-]', '_')
	If ($UserPart.Length -gt 64) { $UserPart = $UserPart.Substring(0, 64) }
	If (-not $UserPart) { $UserPart = 'unknown' }
	Return (Join-Path -Path $Folder -ChildPath ('Spill-{0}-{1}.jsonl' -f $UserPart, $PID))
}
