# VENDORED from CommonScripts\0.2\Functions\ConvertFrom-Serial.ps1 by Sync-SharedUtilities [SHA256 26B77A24DFD3D1353A0A21556CE3C08263559A4299483ACEB4863787816C7640] - DO NOT EDIT (edit the master; Deploy-Modules re-syncs).
# Script-level chunk buffer for accumulating chunks across calls
if (-not $Script:ChunkBuffer)
{$Script:ChunkBuffer = @{}}

Function ConvertFrom-Serial
{
	<#
		.SYNOPSIS
		Restores a PowerShell object from serialized Base64 string or chunked data.

		.DESCRIPTION
		Deserializes data produced by ConvertTo-Serial back into the original PowerShell object.
		Supports both single Base64 strings and chunked transfers for large objects.

		For chunked data:
		- Chunks are accumulated in a buffer keyed by TransferId
		- When all chunks are received, data is reassembled and verified
		- Checksum validation ensures data integrity
		- Returns $null until all chunks are received, then returns the object

		2026-09-15: promoted from NamedPipe\0.14\Functions\ConvertFrom-Serial.ps1 into CommonScripts
		alongside ConvertTo-Serial (its companion) - see that file's own promotion note.
		$Script:ChunkBuffer is module-scoped, so each vendored copy gets its own independent buffer in
		whichever module it lands in, same as every other vendored $Script:-scoped utility.

		Companion: Get-ChunkBufferStatus (own file, Get-ChunkBufferStatus.ps1) reads this SAME
		$Script:ChunkBuffer to report in-progress transfer status - the two used to share this one
		file (needing a hand-maintained extra Export-ModuleMember call and a special multi-file entry
		in Shared-Usage.psd1's FunctionFiles map), until that Export-ModuleMember line was accidentally
		stripped once while promoting this pair to CommonScripts, silently breaking Get-ChunkBufferStatus's
		export until caught by a 78-failure Pester cascade. Split into one function per file 2026-09-15
		to remove that whole class of mistake going forward - vendor and update both together.

		.PARAMETER Text
		A Base64 string from ConvertTo-Serial (non-chunked mode).

		.PARAMETER Chunk
		A chunk object from ConvertTo-Serial (chunked mode).
		Chunks are accumulated until all are received.

		.PARAMETER ClearBuffer
		Clears the chunk buffer for a specific TransferId or all buffers if no ID specified.

		.PARAMETER TransferId
		Used with -ClearBuffer to clear a specific transfer's buffer.

		.EXAMPLE
		ConvertFrom-Serial -Text $Base64String
		Deserializes a single Base64 string to an object.

		.EXAMPLE
		$Chunks | ForEach-Object { $Result = ConvertFrom-Serial -Chunk $_ }
		Processes chunks; $Result is $null until complete, then contains the object.

		.EXAMPLE
		ConvertFrom-Serial -ClearBuffer
		Clears all chunk buffers (useful for error recovery).

		.NOTES
		Version: 2.00 2026-02-03
		- Added chunked data support
		- Added -Chunk parameter for receiving chunks
		- Added -ClearBuffer for buffer management
		- Checksum verification for data integrity

		Companion function: ConvertTo-Serial

		.INPUTS
		System.String - Base64 encoded string
		PSCustomObject - Chunk object from ConvertTo-Serial

		.OUTPUTS
		The original PowerShell object, or $null if waiting for more chunks.
	#>

	[CmdletBinding(DefaultParameterSetName = 'Text')]
	Param (
		[Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Text',
			HelpMessage = 'ConvertFrom-Serial: Please supply the String item to convert.')]
		[String]$Text,

		[Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Chunk',
			HelpMessage = 'ConvertFrom-Serial: Please supply a chunk object.')]
		[PSCustomObject]$Chunk,

		[Parameter(ParameterSetName = 'ClearBuffer')]
		[switch]$ClearBuffer,

		[Parameter(ParameterSetName = 'ClearBuffer')]
		[string]$TransferId
	)

	Begin
	{
		# -and (Get-Command...) guard, added 2026-09-15: this file is vendored into modules that never
		# vendor the trace facility itself (Write-MyFunctionTrace/Enable-/Disable-MyFunctionTrace) - a
		# module with only Format-MyTextLine.ps1 or similar utilities, for example. $env:MyFunctionTraceEnabled
		# is process-scoped, so it can be '1' in ANY process descended from a shell where tracing was turned
		# on elsewhere (confirmed live: a VHDTools mount session crashed with "'Write-MyFunctionTrace' is not
		# recognized" purely because an earlier, unrelated NamedPipe test session in the same shell had left
		# it set). The env check alone is not enough to prove the function exists - only Get-Command does.
		If ((1 -band ($env:MyFunctionTraceEnabled -as [Int])) -and (Get-Command -Name Write-MyFunctionTrace -ErrorAction SilentlyContinue)) { Write-MyFunctionTrace }
	}

	Process
	{
		switch ($PSCmdlet.ParameterSetName)
		{
			'Text'
			{
				# Original simple path - single Base64 string
				[Management.Automation.PSSerializer]::Deserialize(
					([Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($Text)) | ConvertFrom-Json)
				)
			}

			'Chunk'
			{
				# Chunked data path
				$tid = $Chunk.TransferId

				# Initialize buffer for this transfer if needed
				if (-not $Script:ChunkBuffer.ContainsKey($tid))
				{
					$Script:ChunkBuffer[$tid] = @{
						Chunks      = @{}
						TotalChunks = $Chunk.TotalChunks
						TotalLength = $Chunk.TotalLength
						Checksum    = $null
						StartTime   = Get-Date
					}
				}

				$buffer = $Script:ChunkBuffer[$tid]

				# Store this chunk - [int] cast is load-bearing: $buffer.Chunks is a plain Hashtable, whose
				# indexer uses strict boxed-type equality, not PowerShell's numeric-coercing -eq. The
				# reassembly loop below always indexes with a plain [Int32] loop counter, so a ChunkIndex
				# that arrives as a WIDER type - confirmed live 2026-09-15: PS7's ConvertFrom-Json returns
				# [Int64] for integer literals where PS5.1's returns [Int32] for the same JSON text - would
				# silently store under a key the [Int32] lookup can never match, making every chunk read
				# back as $null with no error (only a downstream checksum mismatch to show something went
				# wrong). Casting both sides to [int] here is cheaper and more robust than trying to make
				# every caller/serializer agree on exactly one numeric type.
				$buffer.Chunks[[int]$Chunk.ChunkIndex] = $Chunk.Data

				# Store checksum from final chunk
				if ($Chunk.Checksum)
				{$buffer.Checksum = $Chunk.Checksum}

				# Check if all chunks received
				if ($buffer.Chunks.Count -eq $buffer.TotalChunks)
				{
					# Reassemble data in order - [int] cast is load-bearing, and a completely different trap
					# from the ChunkIndex one above: [System.Text.StringBuilder]::new(x) has both an
					# int-capacity overload and a string-value overload, and confirmed live 2026-09-15 that
					# PowerShell's overload resolution picks the STRING overload when x is [Int64] rather
					# than exactly [Int32] (again: PS7's ConvertFrom-Json for TotalLength) - silently seeding
					# the StringBuilder's CONTENT with the literal text "21544" instead of just reserving
					# that much capacity, so every reassembled payload came out prefixed with its own decimal
					# length string. An [Int32] TotalLength (the old, PSSerializer/CliXml-decoded case)
					# happened to bind the intended capacity overload correctly, which is exactly why this
					# was never visible before a caller could hand this function [Int64] fields.
					$reassembled = [System.Text.StringBuilder]::new([int]$buffer.TotalLength)
					for ($i = 0; $i -lt $buffer.TotalChunks; $i++)
					{
						$null = $reassembled.Append($buffer.Chunks[$i])
					}
					$base64 = $reassembled.ToString()

					# Verify checksum if available
					if ($buffer.Checksum)
					{
						$sha256 = [System.Security.Cryptography.SHA256]::Create()
						$hashBytes = $sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($base64))
						$computedChecksum = [Convert]::ToBase64String($hashBytes)
						$sha256.Dispose()

						if ($computedChecksum -ne $buffer.Checksum)
						{
							# Clear buffer and throw error. Deliberate: this re-throws rather than
							# swallowing the failure, so it is the CALLER's responsibility to wrap this
							# call in a Try/Catch appropriate to their own context (this file is vendored
							# into multiple modules with different transport/error-handling conventions -
							# it makes no assumption about any one of them).
							$Script:ChunkBuffer.Remove($tid)
							throw "Checksum mismatch for transfer $tid. Data may be corrupted."
						}
					}

					# Clean up buffer
					$Script:ChunkBuffer.Remove($tid)

					# Deserialize and return
					[Management.Automation.PSSerializer]::Deserialize(
						([Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($base64)) | ConvertFrom-Json)
					)
				}
				else
				{
					# Still waiting for more chunks - return progress info
					$null
				}
			}

			'ClearBuffer'
			{
				if ($TransferId)
				{
					$Script:ChunkBuffer.Remove($TransferId)
				}
				else
				{
					$Script:ChunkBuffer.Clear()
				}
			}
		}
	}
}
