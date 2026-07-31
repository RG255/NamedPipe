Function Receive-Data
{
	<#
		.SYNOPSIS
		Receives and deserializes data from the named pipe, with automatic chunk reassembly.

		.DESCRIPTION
		Reads serialized data from the pipe and converts it back into a DataObject.
		Automatically handles both single messages and chunked transfers.

		For chunked data:
		- Detects chunk objects by their IsChunked property
		- Accumulates chunks until transfer is complete
		- Verifies checksum for data integrity
		- Returns the reassembled DataObject

		.PARAMETER PipeInfo
		The pipe connection object containing Reader and Writer streams.

		.EXAMPLE
		$DataObject = Receive-Data -PipeInfo $PipeInfo
		Receives data (automatically handles chunked or non-chunked).

		.NOTES
		Version: 2.00 2026-02-03
		- Added automatic chunk detection and reassembly
		- Checksum verification for chunked transfers
		- Progress reporting for verbose mode

		.INPUTS
		PipeInfo - The pipe connection information

		.OUTPUTS
		Returns the deserialized DataObject.
	#>

	[CmdletBinding(PositionalBinding = $False)]
	Param (
		[Parameter(Mandatory, HelpMessage = 'Please supply the PipeInfo Object')]
		$PipeInfo
	)

	$Private:MyBoundParameters = $PSCmdlet.MyInvocation.BoundParameters

	Try
	{
		# Read first line
		if ($PipeInfo.$StrInfoDisplay -band $InfoDisplayBitDebug)
		{
			Write-Host "DEBUG Receive-Data: About to ReadLine (blocking)..." -ForegroundColor Cyan
		}
		$line = $PipeInfo.$StrReader.ReadLine()
		if ($PipeInfo.$StrInfoDisplay -band $InfoDisplayBitDebug)
		{
			Write-Host "DEBUG Receive-Data: ReadLine returned, length=$($line.Length)" -ForegroundColor Cyan
		}
		# ReadLine returns $null when the peer closes the pipe cleanly (no bytes left).
		# Short-circuit here with a Disconnect marker so the server's re-listen branch
		# handles it. Without this, the catch block below would emit a stale $DataObject
		# from dynamic scope (the previous request), causing the server main loop to
		# treat it as a new ScriptBlock request and write to the broken pipe.
		if ($null -eq $line)
		{
			if ($PipeInfo.$StrInfoDisplay -band $InfoDisplayBitDebug)
			{ Write-Host 'DEBUG Receive-Data: Peer closed pipe (ReadLine=$null) - returning Disconnect marker' -ForegroundColor Yellow }
			return [Ordered]@{
				$StrError             = $Null
				$StrFromServerOrClient = $Null
				$StrClientPID         = $Null
				$StrClientUser        = $Null
				$StrServerPID         = $Null
				$StrServerUser        = $Null
				$StrType              = $StrDisconnect
				$StrResult            = $Null
				$StrRequest           = $Null
				$StrProgressInfo      = $Null
				$StrQuery             = $Null
				$StrParameters        = $Null
				$StrLastRequest       = $Null
				$StrLastParameters    = $Null
				$StrData              = $Null
				$StrLastData          = $Null
			}
		}
		if ($PipeInfo.$StrInfoDisplay -band $InfoDisplayBitDebug)
		{ Write-Host "DEBUG Receive-Data: About to deserialize" -ForegroundColor Cyan }
		$received = ConvertFrom-Serial -Text $line
		if ($PipeInfo.$StrInfoDisplay -band $InfoDisplayBitDebug)
		{
			Write-Host "DEBUG Receive-Data: Deserialized OK" -ForegroundColor Green
		}

		# Check if this is a chunk object
		if ($received.IsChunked -eq $true)
		{
			# Chunked transfer - accumulate chunks
			$transferId = $received.TransferId
			$totalChunks = $received.TotalChunks
			$chunksReceived = 1

			if ($PipeInfo.$StrInfoDisplay -band $InfoDisplayBitDebug)
			{
				Write-Host "DEBUG Receive-Data: Receiving chunked transfer: $transferId ($totalChunks chunks)" -ForegroundColor Cyan
			}

			# Process first chunk
			$DataObject = ConvertFrom-Serial -Chunk $received

			# Keep reading until we get the complete object
			while ($null -eq $DataObject)
			{
				$line = $PipeInfo.$StrReader.ReadLine()
				$chunk = ConvertFrom-Serial -Text $line

				if ($chunk.IsChunked -and $chunk.TransferId -eq $transferId)
				{
					$chunksReceived++
					$DataObject = ConvertFrom-Serial -Chunk $chunk

					if ($PipeInfo.$StrInfoDisplay -band $InfoDisplayBitDebug)
					{
						Write-Host "DEBUG Receive-Data: Received chunk $chunksReceived of $totalChunks" -ForegroundColor Cyan
					}
				}
				else
				{
					# Unexpected data - could be an error or different transfer
					throw "Unexpected data received during chunked transfer $transferId"
				}
			}

			if ($PipeInfo.$StrInfoDisplay -band $InfoDisplayBitDebug)
			{
				Write-Host "DEBUG Receive-Data: Chunked transfer complete: $transferId" -ForegroundColor Green
			}
		}
		else
		{
			# Single message (non-chunked) - already deserialized
			$DataObject = $received
		}

		# Set server user if this is the server receiving
		if (-not $DataObject.$StrServerUser -and $DataObject.$StrServerPID -eq $PID)
		{
			$DataObject.$StrServerUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
		}

		# InfoDisplay bitmask: 2 = Show-VerboseData
		if ($PipeInfo.$StrInfoDisplay -band $InfoDisplayBitVerbose)
		{
			Show-VerboseData -Object $DataObject -Display -Title 'Receive-Data: DataObject'
		}
	}
	Catch
	{
		# If deserialization failed, $DataObject may not exist
		# Create a minimal error object to return
		if (-not $DataObject)
		{
			$DataObject = @{
				$StrError = NamedPipe\Get-MyErrors -Return
			}
		}
		else
		{
			$null = Set-MyWindowState -ProcessId $DataObject.$StrServerPID -State Restore
			$DataObject.$StrError = NamedPipe\Get-MyErrors -Return
		}
	}

	$DataObject
}
