#!/usr/bin/env powershell
#requires -Version 5.0
Function ConvertTo-Serial
{
	<#
		.SYNOPSIS
		Converts any PowerShell object into a serialized Base64 string, with optional chunking for large objects.

		.DESCRIPTION
		Serializes a PowerShell object using PSSerializer, compresses it by removing
		unnecessary whitespace, wraps it in JSON, and encodes as Base64.

		For large objects, the -ChunkSize parameter enables chunked output, returning
		an array of chunk objects that can be transmitted separately and reassembled
		by ConvertFrom-Serial.

		The serialization process:
		1. Object -> CliXml (PSSerializer)
		2. Remove CR/LF/Tab and excess spaces
		3. Wrap in JSON (handles quote escaping)
		4. Encode as Base64
		5. If ChunkSize specified and data exceeds it, split into chunks

		Use ConvertFrom-Serial to restore the original object.

		.PARAMETER Object
		The PowerShell object to serialize. Can be any type.

		.PARAMETER Depth
		The maximum depth of nested objects to serialize. Default is 2.
		WARNING: High values (>10) can cause OutOfMemoryException when serializing
		objects containing ACLs or other deeply nested structures.

		.PARAMETER ChunkSize
		Maximum size (in characters) for each chunk. If the serialized data exceeds
		this size, it will be split into multiple chunks. Default is 32768 (32KB).
		Set to 0 to disable chunking for backward compatibility.

		.EXAMPLE
		ConvertTo-Serial -Object $MyHashtable
		Serializes a hashtable (automatically chunked if > 32KB).

		.EXAMPLE
		ConvertTo-Serial -Object $SmallObject -ChunkSize 0
		Serializes without chunking (backward compatible with v0.1).

		.EXAMPLE
		$Chunks = ConvertTo-Serial -Object $BigData -ChunkSize 65536
		$Chunks | ForEach-Object { Send-Chunk $_ }
		Sends serialized data in chunks.

		.NOTES
		Version: 2.01 2026-02-04
		- Added chunking support for large object transfers
		- Added -ChunkSize parameter (default 32KB for automatic chunking)
		- Chunks include metadata: TransferId, ChunkIndex, TotalChunks, Checksum

		Companion function: ConvertFrom-Serial

		.INPUTS
		Any PowerShell Object.

		.OUTPUTS
		System.String - A Base64 encoded string (if no chunking or data fits in one chunk)
		System.Object[] - Array of chunk objects (if chunking enabled and data exceeds ChunkSize)
	#>

	[CmdletBinding()]
	Param (
		[Parameter(Mandatory, ValueFromPipeline, HelpMessage = 'ConvertTo-Serial: Please supply the Object to Convert')]
		$Object,

		[ValidateRange(1, [int]::MaxValue)]
		[int]$Depth = 2,

		[ValidateRange(0, [int]::MaxValue)]
		[int]$ChunkSize = 32768
	)

	Process
	{
		# Serialize the PowerShell object to XML with specified depth
		$xml = [Management.Automation.PSSerializer]::Serialize($Object, $Depth)

		# Remove carriage returns, line feeds, and tabs for compactness
		$xml = $xml -replace '([\r]|[\n]|[\t])'

		# Remove unnecessary spaces between XML tags
		$xml = $xml -replace '>[ ]+<', '><'

		# Convert to JSON and compress to minimize size
		$json = $xml | ConvertTo-Json -Compress

		# Encode as Unicode bytes then convert to Base64 string
		$bytes = [Text.Encoding]::Unicode.GetBytes($json)
		$base64 = [Convert]::ToBase64String($bytes)

		# If no chunking requested or data fits in one chunk, return as-is
		if ($ChunkSize -le 0 -or $base64.Length -le $ChunkSize)
		{
			return $base64
		}

		# Chunking is needed - split the data
		$transferId = [guid]::NewGuid().ToString()
		$totalLength = $base64.Length
		$totalChunks = [math]::Ceiling($totalLength / $ChunkSize)
		$chunks = [System.Collections.ArrayList]::new()

		# Calculate checksum of complete data for verification
		$sha256 = [System.Security.Cryptography.SHA256]::Create()
		$hashBytes = $sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($base64))
		$checksum = [Convert]::ToBase64String($hashBytes)
		$sha256.Dispose()

		for ($i = 0; $i -lt $totalChunks; $i++)
		{
			$startIndex = $i * $ChunkSize
			$length = [math]::Min($ChunkSize, $totalLength - $startIndex)
			$chunkData = $base64.Substring($startIndex, $length)

			$chunk = [PSCustomObject]@{
				IsChunked   = $true
				TransferId  = $transferId
				ChunkIndex  = $i
				TotalChunks = $totalChunks
				TotalLength = $totalLength
				Data        = $chunkData
				Checksum    = if ($i -eq $totalChunks - 1) { $checksum } else { $null }
			}

			$null = $chunks.Add($chunk)
		}

		# Return array of chunks
		return $chunks.ToArray()
	}
}
