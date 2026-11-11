# VENDORED from CommonScripts\0.2\Functions\Test-MyCatchAuditElevated.ps1 by Sync-SharedUtilities [SHA256 3C231CD8012E516AE73DC87A0545A330272445AC7D549F11091E246C3E0F0615] - DO NOT EDIT (edit the master; Deploy-Modules re-syncs).
Function Test-MyCatchAuditElevated
{
	<#
		.SYNOPSIS
		Internal: $true when this process runs with the Administrator role (an elevated token).

		.DESCRIPTION
		2026-11-08. The catch-audit spill import (Import-MyCatchAuditSpill) may only run in a process that can
		write the persisted catch-audit file, which in practice means an elevated one: the persisted file is
		usually created by an elevated process and is then writable only by SYSTEM and Administrators. This is the
		one place that question is asked, so a test can mock the answer. Never throws: any failure to read the
		identity answers $false (the safe answer - nothing is imported).

		Not exported - internal plumbing for Read-/Import-MyCatchAuditSpill.

		.OUTPUTS
		[Bool]
	#>
	[CmdletBinding()]
	[OutputType([Bool])]
	Param ()

	Try
	{
		Return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
	}
	# SILENT-OK: an unreadable identity answers $false, the safe answer (nothing gets imported); asking whether
	# we are elevated must never itself become a failure.
	Catch { $null = $_; Return $false }
}
