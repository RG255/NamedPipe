# VENDORED from CommonScripts\0.2\Functions\Get-ChunkBufferStatus.ps1 by Sync-SharedUtilities [SHA256 DB10EA19C0EA703F3E813111F4B3C563D0B82E30350AC042149B92CDC3955F9C] - DO NOT EDIT (edit the master; Deploy-Modules re-syncs).
# Script-level chunk buffer, shared with ConvertFrom-Serial.ps1 (own file) - duplicated here
# idempotently (same guarded init, safe either way) since the two files' load order isn't guaranteed.
if (-not $Script:ChunkBuffer)
{$Script:ChunkBuffer = @{}}

Function Get-ChunkBufferStatus
{
	<#
		.SYNOPSIS
		Returns the status of pending chunk transfers.

		.DESCRIPTION
		Shows information about incomplete chunked transfers in the buffer,
		including progress and age of each transfer.

		Companion to ConvertFrom-Serial (own file, ConvertFrom-Serial.ps1) - this function reads the
		SAME $Script:ChunkBuffer that ConvertFrom-Serial's -Chunk parameter set populates, so the two
		must always ship and vendor together even though each now lives in its own file (split
		2026-09-15 - see ConvertFrom-Serial.ps1's own note on why: the two used to share one file,
		which needed a hand-maintained extra Export-ModuleMember call and a special multi-file entry in
		Shared-Usage.psd1's FunctionFiles map, and that Export-ModuleMember line was accidentally
		stripped once already while promoting this pair to CommonScripts, silently breaking this
		function's export until caught by a 78-failure Pester cascade). One function per file removes
		that whole class of mistake - NamedPipe's (and every other consumer's) loader exports by
		matching each file's own basename to a same-named function, which now just works for both
		without any special-casing.

		.EXAMPLE
		Get-ChunkBufferStatus
		Returns status of all pending transfers.

		.OUTPUTS
		PSCustomObject with transfer status information.
	#>

	[CmdletBinding()]
	Param()

	# -and (Get-Command...) guard: see ConvertFrom-Serial.ps1's own comment (2026-09-15) - this file is
	# vendored into modules that never vendor Write-MyFunctionTrace itself, and the process-scoped
	# $env:MyFunctionTraceEnabled can be '1' there regardless.
	If ((1 -band ($env:MyFunctionTraceEnabled -as [Int])) -and (Get-Command -Name Write-MyFunctionTrace -ErrorAction SilentlyContinue)) { Write-MyFunctionTrace }

	# Wrapped - a genuine risk exists here (TotalChunks=0 divides by zero) that was previously
	# completely unguarded.
	Try
	{
		foreach ($tid in $Script:ChunkBuffer.Keys)
		{
			$buffer = $Script:ChunkBuffer[$tid]
			[PSCustomObject]@{
				TransferId     = $tid
				ChunksReceived = $buffer.Chunks.Count
				TotalChunks    = $buffer.TotalChunks
				PercentComplete = [math]::Round(($buffer.Chunks.Count / $buffer.TotalChunks) * 100, 1)
				Age            = (Get-Date) - $buffer.StartTime
			}
		}
	}
	Catch
	{
		Write-MyCatchAudit -Source 'Get-ChunkBufferStatus: failed to build chunk transfer status' -ErrorRecord $_
	}
}
