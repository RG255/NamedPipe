# VENDORED from CommonScripts\0.2\Functions\ConvertTo-Serial.ps1 by Sync-SharedUtilities [SHA256 2131AF0470639941AF74A265B9B2F1C54CB06B1153ACB7A34A1D949A36210260] - DO NOT EDIT (edit the master; Deploy-Modules re-syncs).
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

		2026-09-15: promoted from NamedPipe\0.14\Functions\ConvertTo-Serial.ps1 into CommonScripts -
		nothing in this function is NamedPipe-specific (no IO.Pipes types, pure object/string
		manipulation), and the capability ("move a large PowerShell object across a size-limited
		channel") is generically useful beyond named pipes. Promoted ahead of a second consumer, same
		precedent as Expand-Variable (2026-09-12) - see Modules\Shared-Usage.psd1's own note on that.

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

	Begin
	{
		# -and (Get-Command...) guard: see ConvertFrom-Serial.ps1's own comment (2026-09-15) - this file
		# is vendored into modules that never vendor Write-MyFunctionTrace itself, and the process-scoped
		# $env:MyFunctionTraceEnabled can be '1' there regardless.
		If ((1 -band ($env:MyFunctionTraceEnabled -as [Int])) -and (Get-Command -Name Write-MyFunctionTrace -ErrorAction SilentlyContinue)) { Write-MyFunctionTrace }
	}

	Process
	{
		# Wrapped - PSSerializer.Serialize can throw on non-serializable/malformed objects, with nothing
		# anywhere in this function or ConvertFrom-Serial's own callers to catch it. Re-thrown so callers
		# keep current behavior; the audit trail is what was missing.
		Try
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
		Catch
		{
			Write-MyCatchAudit -Source 'ConvertTo-Serial: failed to serialize/chunk the object' -ErrorRecord $_
			# Re-thrown by design, not swallowed - it is the CALLER's responsibility to wrap this call
			# in a Try/Catch appropriate to their own context. This file is vendored into multiple
			# modules with different transport/error-handling conventions; it makes no assumption about
			# any one of them.
			throw
		}
	}
}
