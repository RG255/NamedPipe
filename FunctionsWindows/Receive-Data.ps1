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

	If (1 -band ($env:MyFunctionTraceEnabled -as [Int])) { Write-MyFunctionTrace }

	$Private:MyBoundParameters = $PSCmdlet.MyInvocation.BoundParameters

	Try
	{
		# Read first line
		if ($PipeInfo.$StrInfoDisplay -band $InfoDisplayBitDebug)
		{
			Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') DEBUG Receive-Data: About to ReadLine (blocking)..." -ForegroundColor Cyan
		}
		$line = $PipeInfo.$StrReader.ReadLine()
		if ($PipeInfo.$StrInfoDisplay -band $InfoDisplayBitDebug)
		{
			Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') DEBUG Receive-Data: ReadLine returned, length=$($line.Length)" -ForegroundColor Cyan
		}
		# ReadLine returns $null when the peer closes the pipe cleanly (no bytes left).
		# Short-circuit here with a Disconnect marker so the server's re-listen branch
		# handles it. Without this, the catch block below would emit a stale $DataObject
		# from dynamic scope (the previous request), causing the server main loop to
		# treat it as a new ScriptBlock request and write to the broken pipe.
		if ($null -eq $line)
		{
			if ($PipeInfo.$StrInfoDisplay -band $InfoDisplayBitDebug)
			{ Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') DEBUG Receive-Data: Peer closed pipe (ReadLine=`$null) - returning Disconnect marker" -ForegroundColor Yellow }
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
		{ Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') DEBUG Receive-Data: About to deserialize" -ForegroundColor Cyan }
		# A 'JCHUNK:' prefix means Send-Data wrote this chunk WRAPPER via the lightweight ConvertTo-Json
		# path (2026-09-15, see Send-Data's own comment) - decode it the matching cheap way. Anything
		# without that prefix is the original, non-chunked ConvertTo-Serial output (raw Base64 text, which
		# never legitimately starts with 'JCHUNK:') and still needs the full ConvertFrom-Serial path.
		$received = If ($line.StartsWith('JCHUNK:')) { $line.Substring(7) | ConvertFrom-Json }
		Else { ConvertFrom-Serial -Text $line }
		if ($PipeInfo.$StrInfoDisplay -band $InfoDisplayBitDebug)
		{
			Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') DEBUG Receive-Data: Deserialized OK" -ForegroundColor Green
		}

		# ConvertFrom-Serial's -Text path (unlike its -Chunk path) never legitimately returns
		# $null - a Base64/JSON payload that fails to deserialize is the only way $received
		# ends up $null here, and without this check that silently fell through to the
		# non-chunked "else" below (since $null.IsChunked -eq $true is $false), producing a
		# $DataObject of $null with no Error set - the one gap the checksum-mismatch path below
		# does NOT have (that one already throws and is caught by the outer Catch). Throwing
		# here routes it through the same established Catch -> $StrError convention.
		if ($null -eq $received)
		{ throw "Failed to deserialize received data." }

		# Check if this is a chunk object
		if ($received.IsChunked -eq $true)
		{
			# Chunked transfer - accumulate chunks
			$transferId = $received.TransferId
			$totalChunks = $received.TotalChunks
			$chunksReceived = 1

			if ($PipeInfo.$StrInfoDisplay -band $InfoDisplayBitDebug)
			{
				Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') DEBUG Receive-Data: Receiving chunked transfer: $transferId ($totalChunks chunks)" -ForegroundColor Cyan
			}

			# Process first chunk
			$DataObject = ConvertFrom-Serial -Chunk $received

			# Keep reading until we get the complete object. Bounded (unlike the FIRST read
			# above, which stays unbounded on purpose - see ChunkReadTimeout's own definition
			# in DefineVariablesPipe.ps1): once the sender has already started streaming a
			# chunked transfer, there is no legitimate reason for a large gap before the NEXT
			# chunk - it is already computed, just being written. A stall here means the sender
			# broke mid-transfer, not that some slow operation is still in progress. Falls back
			# to 30s when PipeInfo carries no ChunkReadTimeout (e.g. a PipeInfo built by hand,
			# as several tests do), matching Set-ObjectParameterSet' own default for this field.
			while ($null -eq $DataObject)
			{
				$Private:_chunkTimeoutMs = if ($null -ne $PipeInfo.$StrChunkReadTimeout)
				{ [int]$PipeInfo.$StrChunkReadTimeout } Else { 30000 }
				$Private:_lineTask = $PipeInfo.$StrReader.ReadLineAsync()
				# Caught by this function's own outer Catch (below) and converted to $DataObject.$StrError
				# - never escapes to crash the process. The caller (Start-PipeServerOrClient's main loop,
				# or a client's own Send-Data) still gets a normal returned DataObject to inspect.
				If (-not $Private:_lineTask.Wait($Private:_chunkTimeoutMs))
				{ throw "Receive-Data: timed out after $Private:_chunkTimeoutMs ms waiting for the next chunk of transfer $transferId." }
				$line = $Private:_lineTask.Result
				# Same 'JCHUNK:' prefix check as the first read above - every line from here on is a
				# chunk continuation, so this always takes the lightweight branch in practice, but the
				# check stays symmetric with the first read rather than assuming it.
				$chunk = If ($line.StartsWith('JCHUNK:')) { $line.Substring(7) | ConvertFrom-Json }
				Else { ConvertFrom-Serial -Text $line }

				if ($chunk.IsChunked -and $chunk.TransferId -eq $transferId)
				{
					$chunksReceived++
					$DataObject = ConvertFrom-Serial -Chunk $chunk

					if ($PipeInfo.$StrInfoDisplay -band $InfoDisplayBitDebug)
					{
						Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') DEBUG Receive-Data: Received chunk $chunksReceived of $totalChunks" -ForegroundColor Cyan
					}
				}
				else
				{
					# Unexpected data - could be an error or different transfer. Same as the timeout
					# throw above: caught by this function's own outer Catch, converted to
					# $DataObject.$StrError - does not crash the process or collapse the pipe.
					throw "Unexpected data received during chunked transfer $transferId"
				}
			}

			if ($PipeInfo.$StrInfoDisplay -band $InfoDisplayBitDebug)
			{
				Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') DEBUG Receive-Data: Chunked transfer complete: $transferId" -ForegroundColor Green
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
				$StrError = NamedPipe\Get-MyError -Return
			}
		}
		else
		{
			$null = Set-MyWindowState -ProcessId $DataObject.$StrServerPID -State Restore
			$DataObject.$StrError = NamedPipe\Get-MyError -Return
		}
	}

	$DataObject
}
