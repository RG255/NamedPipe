# VENDORED from CommonScripts\0.2\Functions\Write-MyCatchAuditSpill.ps1 by Sync-SharedUtilities [SHA256 3589BC2CC36760D9129D89FFD45F27AF561039C03DEB1E93914BE68A21AEAAC3] - DO NOT EDIT (edit the master; Deploy-Modules re-syncs).
Function Write-MyCatchAuditSpill
{
	<#
		.SYNOPSIS
		Internal: appends one catch-audit JSON line to this process's spill file. Returns $true when it was saved.

		.DESCRIPTION
		2026-11-08. Called by Write-MyCatchAudit when the write to the persisted file is DENIED (see
		Get-MyCatchAuditSpillPath for the why and the layout). Written immediately - no exit hook - so the entry
		survives a crash or a process that ends without an elevated session to relay through.

		NEVER throws and never calls Write-MyCatchAudit (it runs inside Write-MyCatchAudit's own failure path):
		any failure answers $false and the caller falls back to the in-memory queue and its warning.

		Caps, so a runaway loop cannot flood the folder (and so the file always stays within what the importer
		accepts): at most 1000 lines and 1,000,000 bytes per process, and one line of at most 16000 characters (an
		over-long Message is cut to 4000 characters in the spill copy; the in-memory entry is unaffected). Entries
		beyond a cap are counted in $Global:MyCatchAuditSpillDropped and reported by Show-MyCatchAuditSummary.
		Counters are per process: $Global:MyCatchAuditSpillLines / $Global:MyCatchAuditSpillBytes.

		Not exported.

		.PARAMETER JsonLine
		The compact JSON text of the entry, exactly as Write-MyCatchAudit builds it for the persisted file.

		.OUTPUTS
		[Bool] $true = saved to the spill file.
	#>
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
		Justification = 'Called from a catch-audit failure path that must never prompt or be cancelled; the append IS the purpose.')]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '',
		Justification = 'Process-wide per-process counters shared by every module in the process, same reasoning as $Global:MyCatchAuditLog.')]
	[CmdletBinding()]
	[OutputType([Bool])]
	Param ([Parameter(Mandatory)][String]$JsonLine)

	Try
	{
		$MaxLines = 1000
		$MaxBytes = 1000000
		$MaxLineChars = 16000
		$MessageCap = 4000

		$Line = $JsonLine
		If ($Line.Length -gt ($MaxLineChars - 1000))
		{
			$Obj = $Line | ConvertFrom-Json -ErrorAction Stop
			If ($Obj.Message -is [String] -and $Obj.Message.Length -gt $MessageCap)
			{ $Obj.Message = $Obj.Message.Substring(0, $MessageCap) + '...[truncated]' }
			$Line = $Obj | ConvertTo-Json -Compress -Depth 3
		}
		If ($Line.Length -gt $MaxLineChars)
		{ $Global:MyCatchAuditSpillDropped = 1 + [Int]$Global:MyCatchAuditSpillDropped; Return $false }

		$LineBytes = [System.Text.Encoding]::UTF8.GetByteCount($Line) + 2
		If ([Int]$Global:MyCatchAuditSpillLines -ge $MaxLines -or ([Int64]$Global:MyCatchAuditSpillBytes + $LineBytes) -gt $MaxBytes)
		{ $Global:MyCatchAuditSpillDropped = 1 + [Int]$Global:MyCatchAuditSpillDropped; Return $false }

		$Path = Get-MyCatchAuditSpillPath -File
		Add-Content -LiteralPath $Path -Value $Line -Encoding utf8 -ErrorAction Stop
		$Global:MyCatchAuditSpillLines = 1 + [Int]$Global:MyCatchAuditSpillLines
		$Global:MyCatchAuditSpillBytes = $LineBytes + [Int64]$Global:MyCatchAuditSpillBytes
		Return $true
	}
	# SILENT-OK: runs inside Write-MyCatchAudit's failure path, which must never throw or recurse; $false makes the
	# caller fall back to the in-memory queue and its warning, so the failure is still surfaced one level up.
	Catch { $null = $_; Return $false }
}
