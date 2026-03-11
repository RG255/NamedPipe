#!/usr/bin/env powershell
#requires -Version 5.0

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

				# Store this chunk
				$buffer.Chunks[$Chunk.ChunkIndex] = $Chunk.Data

				# Store checksum from final chunk
				if ($Chunk.Checksum)
				{$buffer.Checksum = $Chunk.Checksum}

				# Check if all chunks received
				if ($buffer.Chunks.Count -eq $buffer.TotalChunks)
				{
					# Reassemble data in order
					$reassembled = [System.Text.StringBuilder]::new($buffer.TotalLength)
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
							# Clear buffer and throw error
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

Function Get-ChunkBufferStatus
{
	<#
		.SYNOPSIS
		Returns the status of pending chunk transfers.

		.DESCRIPTION
		Shows information about incomplete chunked transfers in the buffer,
		including progress and age of each transfer.

		.EXAMPLE
		Get-ChunkBufferStatus
		Returns status of all pending transfers.

		.OUTPUTS
		PSCustomObject with transfer status information.
	#>

	[CmdletBinding()]
	Param()

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

Export-ModuleMember -Function Get-ChunkBufferStatus
