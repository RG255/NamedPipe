Function Send-Data
{
	<#
		.SYNOPSIS
		Serializes and sends a DataObject through the named pipe, with optional chunking for large data.

		.DESCRIPTION
		Takes a DataObject, serializes it, and writes it to the pipe. For large objects,
		chunking can be enabled to split the data into smaller pieces for reliable transfer.

		ChunkSize and Depth values are read from PipeInfo, which inherits them from
		ServerClientParams during pipe setup.

		When chunking is enabled:
		- Data is split into chunks of specified size
		- Each chunk is sent as a separate message
		- Progress can be reported during transfer
		- Receiver reassembles chunks automatically

		.PARAMETER DataObject
		The object containing instructions/data to send. Typically includes request type,
		parameters, and data fields.

		.PARAMETER PipeInfo
		The pipe connection object containing Writer, Reader, ChunkSize, Depth and InfoDisplay.

		.EXAMPLE
		Send-Data -DataObject $MyData -PipeInfo $PipeInfo
		Sends data using ChunkSize and Depth from PipeInfo.

		.NOTES
		Version: 2.04 2026-02-05
		- ChunkSize and Depth now sourced from PipeInfo (set via ServerClientParams)
		- Removed hardcoded parameter defaults in favour of data structure values

		.INPUTS
		DataObject - The data structure to send
		PipeInfo - The pipe connection information (includes ChunkSize, Depth, InfoDisplay)

		.OUTPUTS
		Returns DataObject with results (if client) or sends response (if server).
	#>

	[CmdletBinding(PositionalBinding = $False)]
	Param (
		[Parameter(Mandatory, HelpMessage = 'Please supply the PipeObject Object')]
		$DataObject,

		[Parameter(Mandatory, HelpMessage = 'Please supply the PipeInfo Object')]
		$PipeInfo
	)

	If ($DataObject.$StrServerPID -eq $PID)
	{
		# This is executed for the server
		$DataObject.$StrFromServerOrClient = $StrServer
		$DataObject.$StrLastRequest = $DataObject.$StrRequest
		$DataObject.$StrLastParameters = $DataObject.$StrParameters
		$DataObject.$StrRequest = $Null
		$DataObject.$StrParameters = $Null
		$DataObject.$StrData = $Null
	}
	else
	{
		# This is executed for the client
		$DataObject.$StrFromServerOrClient = $StrClient
		$DataObject.$StrLastRequest = $Null
		$DataObject.$StrLastParameters = $Null
		$DataObject.$StrLastData = $Null
		$DataObject.$StrResult = $Null
		$DataObject.$StrError = $Null
	}

	# Note: Removed pre-serialization size validation (v2.02 > v2.03)
	# Pre-serializing just to check size caused OutOfMemory on complex objects.
	# ConvertTo-Serial handles chunking automatically based on ChunkSize parameter.
	# If ChunkSize=0, data is sent as single message (backward compatible).
	# If ChunkSize>0, data is chunked if it exceeds that size.

	Try
	{
		# InfoDisplay bitmask: 1=server/client progress, 2=Show-VerboseData, 4=debug output
		if ($PipeInfo.$StrInfoDisplay -band $InfoDisplayBitVerbose)
		{
			Show-VerboseData -Object $DataObject -Display -Title 'Send-Data: DataObject'
		}
		if ($PipeInfo.$StrInfoDisplay -band $InfoDisplayBitDebug)
		{
			Write-Host "$(Get-Date -Format 'HH:mm:ss.fff') DEBUG Send-Data: About to serialize (ChunkSize=$($PipeInfo.$StrChunkSize), Depth=$($PipeInfo.$StrDepth))" -ForegroundColor Yellow
		}

		# Serialize with chunking and depth settings from PipeInfo
		$serialized = ConvertTo-Serial -Object $DataObject -ChunkSize $PipeInfo.$StrChunkSize -Depth $PipeInfo.$StrDepth

		if ($PipeInfo.$StrInfoDisplay -band $InfoDisplayBitDebug)
		{
			Write-Host "$(Get-Date -Format 'HH:mm:ss.fff') DEBUG Send-Data: Serialized, type=$($serialized.GetType().Name), length=$($serialized.Length)" -ForegroundColor Yellow
		}

		# Warning if serialized data is suspiciously small (may indicate truncation)
		if ($serialized -is [string] -and $serialized.Length -lt 100 -and $DataObject.Keys.Count -gt 3)
		{
			Write-Warning "Send-Data: Serialized data is very small ($($serialized.Length) chars). Consider increasing Depth if data appears truncated."
		}

		# Check if we got chunks or a single string
		if ($serialized -is [array] -and $serialized[0].IsChunked)
		{
			# Chunked transfer - send each chunk
			$totalChunks = $serialized.Count
			$chunkNum = 0

			if ($PipeInfo.$StrInfoDisplay -band $InfoDisplayBitDebug)
			{
				Write-Host "$(Get-Date -Format 'HH:mm:ss.fff') DEBUG Send-Data: Chunked transfer, $totalChunks chunks" -ForegroundColor Yellow
			}

			foreach ($chunk in $serialized)
			{
				$chunkNum++

				# Serialize the chunk object (small, no need for sub-chunking)
				$chunkLine = ConvertTo-Serial -Object $chunk -ChunkSize 0
				$PipeInfo.$StrWriter.WriteLine($chunkLine)
				$PipeInfo.$StrWriter.Flush()

				# Report progress if InfoDisplay enabled
				if ($PipeInfo.$StrInfoDisplay -band $InfoDisplayBitDebug)
				{
					Write-Host "$(Get-Date -Format 'HH:mm:ss.fff') DEBUG Send-Data: Sent chunk $chunkNum of $totalChunks" -ForegroundColor Cyan
				}
			}
		}
		else
		{
			# Single message - send as-is (backward compatible)
			if ($PipeInfo.$StrInfoDisplay -band $InfoDisplayBitDebug)
			{
				Write-Host "$(Get-Date -Format 'HH:mm:ss.fff') DEBUG Send-Data: Single message, about to WriteLine" -ForegroundColor Yellow
			}
			$PipeInfo.$StrWriter.WriteLine($serialized)
			$PipeInfo.$StrWriter.Flush()
			if ($PipeInfo.$StrInfoDisplay -band $InfoDisplayBitDebug)
			{
				Write-Host "$(Get-Date -Format 'HH:mm:ss.fff') DEBUG Send-Data: Flush done" -ForegroundColor Green
			}
		}

		$DataObject.$StrProgressinfo = $Null

		If ($DataObject.$StrServerPID -ne $PID)
		{
			if ($PipeInfo.$StrInfoDisplay -band $InfoDisplayBitDebug)
			{
				Write-Host "$(Get-Date -Format 'HH:mm:ss.fff') DEBUG Send-Data: Client waiting for response..." -ForegroundColor Yellow
			}
			Receive-Data -PipeInfo $PipeInfo -ErrorAction Stop
		}
		else
		{
			if ($PipeInfo.$StrInfoDisplay -band $InfoDisplayBitDebug)
			{
				Write-Host "$(Get-Date -Format 'HH:mm:ss.fff') DEBUG Send-Data: Server send complete, returning" -ForegroundColor Green
			}
		}
	}
	catch
	{
		$DataObject.$StrError = NamedPipe\Get-MyErrors -Return
		$DataObject
	}
}
