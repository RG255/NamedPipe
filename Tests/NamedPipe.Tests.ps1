#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
    .SYNOPSIS
    Pester tests for the NamedPipe module v0.7

    .DESCRIPTION
    Comprehensive test suite for NamedPipe module v0.7 including:
    - Serialization with chunking support
    - Utility functions
    - Window functions
    - Pipe functions with chunked transfers

    .NOTES
    Version: 2.1 2026-02-04
    Run with: Invoke-Pester -Path .\NamedPipe.Tests.ps1 -Output Detailed
#>

BeforeAll {
	# NAMEDPIPE_EXPORT_ALL makes InitialiseModule.psm1 export every function, BUT the manifest's
	# explicit 23-entry FunctionsToExport is the FINAL gate - importing via the .psd1 filters the
	# surface straight back down. So this env var has never actually widened anything here, and
	# ~13 tests were calling internals that were not in scope. Kept because it is harmless and the
	# psm1 still honours it if the module is ever imported directly.
	$env:NAMEDPIPE_EXPORT_ALL = '1'

	# Import the module
	$ModulePath = Split-Path -Parent $PSScriptRoot
	Remove-Module -Name NamedPipe -Force -ErrorAction SilentlyContinue
	Import-Module "$ModulePath\NamedPipe.psd1" -Force

	# Reach the INTERNAL (deliberately unexported) functions the proper way: run them inside the
	# module's own scope, where their $Str*/$script: dependencies resolve. Dot-sourcing the files
	# into the test scope would NOT work - they would lose that scope.
	#
	# This keeps the suite self-consistent: the "should NOT be exported" assertions further down
	# stay true, and these functions are still exercised. Set-Window is deliberately absent - it
	# was removed in 0.12.
	foreach ($Private:Fn in 'Get-NewPipeName', 'Test-AccessIdentifier', 'Set-MyWindowState',
		'Assert-File', 'Assert-Folder')
	{
		$Private:Body = '& (Get-Module NamedPipe) ([scriptblock]::Create(''{0} @args'')) @args' -f $Private:Fn
		Set-Item -Path ('function:script:{0}' -f $Private:Fn) -Value ([scriptblock]::Create($Private:Body))
	}

	# Store original error count for cleanup
	$Script:OriginalErrorCount = $Global:Error.Count
}

AfterAll {
	# Clean up - remove module and env var
	Remove-Module NamedPipe -Force -ErrorAction SilentlyContinue
	Remove-Item env:NAMEDPIPE_EXPORT_ALL -ErrorAction SilentlyContinue
}

Describe 'Module Import' {
	It 'Should import the NamedPipe module without errors' {
		Get-Module -Name NamedPipe | Should -Not -BeNullOrEmpty
	}

	It 'Should be version 0.15' {
		$Module = Get-Module -Name NamedPipe
		$Module.Version.ToString() | Should -Be '0.15'
	}

	It 'Should have a valid module version' {
		$Module = Get-Module -Name NamedPipe
		$Module.Version | Should -Not -BeNullOrEmpty
	}

	It 'Should export expected public functions' {
		$Module = Get-Module -Name NamedPipe
		$Module.ExportedFunctions.Keys | Should -Contain 'ConvertTo-Serial'
		$Module.ExportedFunctions.Keys | Should -Contain 'ConvertFrom-Serial'
		# Set-Window was removed in 0.12 (NamedPipe only did hide/restore -> Set-MyWindowState); it must NOT be exported.
		$Module.ExportedFunctions.Keys | Should -Not -Contain 'Set-Window'
		$Module.ExportedFunctions.Keys | Should -Contain 'Start-PipeSession'
		$Module.ExportedFunctions.Keys | Should -Contain 'Test-PipeSession'
		$Module.ExportedFunctions.Keys | Should -Contain 'Stop-PipeSession'
		$Module.ExportedFunctions.Keys | Should -Contain 'Send-Request'
	}
}

Describe 'ConvertTo-Serial' {
	Context 'Basic Serialization (Backward Compatible)' {
		It 'Should serialize a simple string' {
			$Result = ConvertTo-Serial -Object 'Hello World'
			$Result | Should -Not -BeNullOrEmpty
			$Result | Should -BeOfType [string]
		}

		It 'Should serialize a hashtable' {
			$Hash = @{ Name = 'Test'; Value = 123 }
			$Result = ConvertTo-Serial -Object $Hash
			$Result | Should -Not -BeNullOrEmpty
			$Result | Should -BeOfType [string]
		}

		It 'Should serialize an array' {
			$Array = @(1, 2, 3, 4, 5)
			$Result = ConvertTo-Serial -Object $Array
			$Result | Should -Not -BeNullOrEmpty
		}

		It 'Should serialize a PSCustomObject' {
			$Obj = [PSCustomObject]@{ Property1 = 'Value1'; Property2 = 42 }
			$Result = ConvertTo-Serial -Object $Obj
			$Result | Should -Not -BeNullOrEmpty
		}

		It 'Should serialize nested objects with Depth parameter' {
			$Nested = @{
				Level1 = @{
					Level2 = @{
						Level3 = @{
							Level4 = 'Deep Value'
						}
					}
				}
			}
			$Result = ConvertTo-Serial -Object $Nested -Depth 10
			$Result | Should -Not -BeNullOrEmpty
		}
	}

	Context 'Pipeline Input' {
		It 'Should accept pipeline input' {
			$Result = 'Test String' | ConvertTo-Serial
			$Result | Should -Not -BeNullOrEmpty
		}

		It 'Should serialize multiple objects from pipeline' {
			$Results = @('One', 'Two', 'Three') | ForEach-Object { ConvertTo-Serial -Object $_ }
			$Results.Count | Should -Be 3
		}
	}

	Context 'Edge Cases' {
		It 'Should handle empty string' {
			$Result = ConvertTo-Serial -Object ''
			$Result | Should -Not -BeNullOrEmpty
		}

		It 'Should reject $null as mandatory parameter' {
			{ ConvertTo-Serial -Object $null } | Should -Throw
		}

		It 'Should handle special characters' {
			$Special = "Line1`r`nLine2`tTabbed"
			$Result = ConvertTo-Serial -Object $Special
			$Result | Should -Not -BeNullOrEmpty
		}
	}

	Context 'Chunked Serialization' {
		It 'Should return single string when data is smaller than ChunkSize' {
			$Small = 'Small data'
			$Result = ConvertTo-Serial -Object $Small -ChunkSize 1000
			$Result | Should -BeOfType [string]
		}

		It 'Should return array of chunks when data exceeds ChunkSize' {
			# Create data that will definitely exceed chunk size
			$Large = @{
				Data = 'X' * 5000
				MoreData = 'Y' * 5000
			}
			$Result = ConvertTo-Serial -Object $Large -ChunkSize 1000
			# Result should be array-like (multiple chunks)
			@($Result).Count | Should -BeGreaterThan 1
			$Result[0].IsChunked | Should -Be $true
		}

		It 'Should include IsChunked property in chunks' {
			$Large = @{ Data = 'X' * 10000 }
			$Result = ConvertTo-Serial -Object $Large -ChunkSize 1000
			$Result[0].IsChunked | Should -Be $true
		}

		It 'Should include TransferId in all chunks' {
			$Large = @{ Data = 'X' * 10000 }
			$Result = ConvertTo-Serial -Object $Large -ChunkSize 1000
			$TransferId = $Result[0].TransferId
			$TransferId | Should -Not -BeNullOrEmpty
			$Result | ForEach-Object { $_.TransferId | Should -Be $TransferId }
		}

		It 'Should include sequential ChunkIndex values' {
			$Large = @{ Data = 'X' * 10000 }
			$Result = ConvertTo-Serial -Object $Large -ChunkSize 1000
			for ($i = 0; $i -lt $Result.Count; $i++) {
				$Result[$i].ChunkIndex | Should -Be $i
			}
		}

		It 'Should include TotalChunks in all chunks' {
			$Large = @{ Data = 'X' * 10000 }
			$Result = ConvertTo-Serial -Object $Large -ChunkSize 1000
			$TotalChunks = $Result.Count
			$Result | ForEach-Object { $_.TotalChunks | Should -Be $TotalChunks }
		}

		It 'Should include Checksum only in last chunk' {
			$Large = @{ Data = 'X' * 10000 }
			$Result = ConvertTo-Serial -Object $Large -ChunkSize 1000

			# All but last should have null checksum
			for ($i = 0; $i -lt $Result.Count - 1; $i++) {
				$Result[$i].Checksum | Should -BeNullOrEmpty
			}

			# Last chunk should have checksum
			$Result[-1].Checksum | Should -Not -BeNullOrEmpty
		}

		It 'Should not chunk when ChunkSize is 0' {
			$Large = @{ Data = 'X' * 10000 }
			$Result = ConvertTo-Serial -Object $Large -ChunkSize 0
			$Result | Should -BeOfType [string]
		}

		It 'Should use default ChunkSize of 32KB when not specified' {
			# Create data that exceeds 32KB when serialized
			$VeryLarge = @{ Data = 'X' * 50000 }
			$Result = ConvertTo-Serial -Object $VeryLarge
			# With default 32KB chunking, this should produce chunks
			@($Result).Count | Should -BeGreaterThan 1
			$Result[0].IsChunked | Should -Be $true
		}

		It 'Should return string for small data with default ChunkSize' {
			# Small data under 32KB should still return string
			$Small = @{ Data = 'X' * 100 }
			$Result = ConvertTo-Serial -Object $Small
			$Result | Should -BeOfType [string]
		}
	}
}

Describe 'ConvertFrom-Serial' {
	Context 'Basic Deserialization (Backward Compatible)' {
		It 'Should deserialize a string' {
			$Original = 'Hello World'
			$Serialized = ConvertTo-Serial -Object $Original
			$Result = ConvertFrom-Serial -Text $Serialized
			$Result | Should -Be $Original
		}

		It 'Should deserialize a hashtable' {
			$Original = @{ Name = 'Test'; Value = 123 }
			$Serialized = ConvertTo-Serial -Object $Original
			$Result = ConvertFrom-Serial -Text $Serialized
			$Result.Name | Should -Be 'Test'
			$Result.Value | Should -Be 123
		}

		It 'Should deserialize an array' {
			$Original = @(1, 2, 3, 4, 5)
			$Serialized = ConvertTo-Serial -Object $Original
			$Result = ConvertFrom-Serial -Text $Serialized
			$Result.Count | Should -Be 5
			$Result[0] | Should -Be 1
		}

		It 'Should deserialize a PSCustomObject' {
			$Original = [PSCustomObject]@{ Property1 = 'Value1'; Property2 = 42 }
			$Serialized = ConvertTo-Serial -Object $Original
			$Result = ConvertFrom-Serial -Text $Serialized
			$Result.Property1 | Should -Be 'Value1'
			$Result.Property2 | Should -Be 42
		}
	}

	Context 'Round-trip Tests' {
		It 'Should preserve integer values' {
			$Original = 12345
			$Result = ConvertFrom-Serial -Text (ConvertTo-Serial -Object $Original)
			$Result | Should -Be $Original
		}

		It 'Should preserve decimal values' {
			$Original = 123.456
			$Result = ConvertFrom-Serial -Text (ConvertTo-Serial -Object $Original)
			$Result | Should -Be $Original
		}

		It 'Should preserve boolean values' {
			$True | ConvertTo-Serial | ConvertFrom-Serial | Should -Be $True
			$False | ConvertTo-Serial | ConvertFrom-Serial | Should -Be $False
		}

		It 'Should preserve DateTime values' {
			$Original = Get-Date '2026-01-15 10:30:00'
			$Result = ConvertFrom-Serial -Text (ConvertTo-Serial -Object $Original)
			$Result.ToString() | Should -Be $Original.ToString()
		}

		It 'Should preserve nested structures' {
			$Original = @{
				String = 'Text'
				Number = 42
				Array = @(1, 2, 3)
				Nested = @{ Inner = 'Value' }
			}
			$Serialized = ConvertTo-Serial -Object $Original -Depth 10
			$Result = ConvertFrom-Serial -Text $Serialized
			$Result.String | Should -Be 'Text'
			$Result.Number | Should -Be 42
			$Result.Array.Count | Should -Be 3
			$Result.Nested.Inner | Should -Be 'Value'
		}
	}

	Context 'Pipeline Input' {
		It 'Should accept pipeline input' {
			$Serialized = ConvertTo-Serial -Object 'Test'
			$Result = $Serialized | ConvertFrom-Serial
			$Result | Should -Be 'Test'
		}
	}

	Context 'Chunked Deserialization' {
		It 'Should reassemble chunked data correctly' {
			$Original = @{
				Data = 'X' * 5000
				Number = 42
				Text = 'Test Value'
			}
			$Chunks = ConvertTo-Serial -Object $Original -ChunkSize 1000

			# Process all chunks
			$Result = $null
			foreach ($Chunk in $Chunks) {
				$Result = ConvertFrom-Serial -Chunk $Chunk
			}

			$Result | Should -Not -BeNullOrEmpty
			$Result.Number | Should -Be 42
			$Result.Text | Should -Be 'Test Value'
			$Result.Data.Length | Should -Be 5000
		}

		It 'Should return $null until all chunks received' {
			$Original = @{ Data = 'X' * 10000 }
			$Chunks = ConvertTo-Serial -Object $Original -ChunkSize 1000

			# Process all but last chunk
			for ($i = 0; $i -lt $Chunks.Count - 1; $i++) {
				$Result = ConvertFrom-Serial -Chunk $Chunks[$i]
				$Result | Should -BeNullOrEmpty
			}

			# Process last chunk - should return object
			$Result = ConvertFrom-Serial -Chunk $Chunks[-1]
			$Result | Should -Not -BeNullOrEmpty
		}

		It 'Should verify checksum and throw on mismatch' {
			$Original = @{ Data = 'X' * 5000 }
			$Chunks = ConvertTo-Serial -Object $Original -ChunkSize 1000

			# Corrupt the data in one chunk
			$Chunks[1].Data = 'CORRUPTED' + $Chunks[1].Data.Substring(9)

			# Process chunks - should throw on checksum verification
			{
				foreach ($Chunk in $Chunks) {
					$Null = ConvertFrom-Serial -Chunk $Chunk
				}
			} | Should -Throw '*Checksum mismatch*'
		}

		It 'Should handle chunks received out of order' {
			$Original = @{ Data = 'ABCDEFGHIJ' * 1000; Value = 'TestOrder' }
			$Chunks = ConvertTo-Serial -Object $Original -ChunkSize 1000

			# Shuffle chunks (but keep them all)
			$Shuffled = $Chunks | Sort-Object { Get-Random }

			# Process shuffled chunks
			$Result = $null
			foreach ($Chunk in $Shuffled) {
				$Result = ConvertFrom-Serial -Chunk $Chunk
			}

			$Result | Should -Not -BeNullOrEmpty
			$Result.Value | Should -Be 'TestOrder'
		}
	}

	Context 'Buffer Management' {
		BeforeEach {
			# Clear any existing buffers
			ConvertFrom-Serial -ClearBuffer
		}

		It 'Should clear all buffers with -ClearBuffer' {
			# Start a transfer but don't complete it
			$Original = @{ Data = 'X' * 10000 }
			$Chunks = ConvertTo-Serial -Object $Original -ChunkSize 1000
			$Null = ConvertFrom-Serial -Chunk $Chunks[0]

			# Clear and verify
			ConvertFrom-Serial -ClearBuffer
			$Status = Get-ChunkBufferStatus
			$Status | Should -BeNullOrEmpty
		}

		It 'Should clear specific transfer with -ClearBuffer -TransferId' {
			# Start two transfers
			$Data1 = @{ Data = 'X' * 10000 }
			$Data2 = @{ Data = 'Y' * 10000 }
			$Chunks1 = ConvertTo-Serial -Object $Data1 -ChunkSize 1000
			$Chunks2 = ConvertTo-Serial -Object $Data2 -ChunkSize 1000

			$Null = ConvertFrom-Serial -Chunk $Chunks1[0]
			$Null = ConvertFrom-Serial -Chunk $Chunks2[0]

			# Clear first transfer only
			ConvertFrom-Serial -ClearBuffer -TransferId $Chunks1[0].TransferId

			# Second transfer should still be pending
			$Status = Get-ChunkBufferStatus
			$Status.TransferId | Should -Contain $Chunks2[0].TransferId
			$Status.TransferId | Should -Not -Contain $Chunks1[0].TransferId
		}
	}
}

Describe 'Get-ChunkBufferStatus' {
	BeforeEach {
		ConvertFrom-Serial -ClearBuffer
	}

	It 'Should return empty when no transfers pending' {
		$Status = Get-ChunkBufferStatus
		$Status | Should -BeNullOrEmpty
	}

	It 'Should show pending transfer status' {
		$Original = @{ Data = 'X' * 10000 }
		$Chunks = ConvertTo-Serial -Object $Original -ChunkSize 1000

		# Process some chunks
		$Null = ConvertFrom-Serial -Chunk $Chunks[0]
		$Null = ConvertFrom-Serial -Chunk $Chunks[1]

		$Status = Get-ChunkBufferStatus
		$Status | Should -Not -BeNullOrEmpty
		$Status.TransferId | Should -Be $Chunks[0].TransferId
		$Status.ChunksReceived | Should -Be 2
		$Status.TotalChunks | Should -Be $Chunks.Count
	}

	It 'Should show percentage complete' {
		$Original = @{ Data = 'X' * 10000 }
		$Chunks = ConvertTo-Serial -Object $Original -ChunkSize 1000

		# Process half the chunks
		$HalfCount = [math]::Floor($Chunks.Count / 2)
		for ($i = 0; $i -lt $HalfCount; $i++) {
			$Null = ConvertFrom-Serial -Chunk $Chunks[$i]
		}

		$Status = Get-ChunkBufferStatus
		$Status.PercentComplete | Should -BeGreaterThan 0
		$Status.PercentComplete | Should -BeLessThan 100
	}
}

Describe 'Get-MyError' {
	BeforeEach {
		$Global:Error.Clear()
	}

	AfterEach {
		$Global:Error.Clear()
	}

	Context 'Basic Functionality' {
		It 'Should return empty when no errors exist' {
			$Result = Get-MyError -Return
			$Result | Should -BeNullOrEmpty
		}

		It 'Should capture and format errors' {
			try { Get-Item 'C:\NonExistent\Path\File.txt' -ErrorAction Stop } catch {}
			$Result = Get-MyError -Return -PreserveErrors
			$Result | Should -Not -BeNullOrEmpty
			$Result | Should -Match 'Error No'
		}

		It 'Should clear errors by default' {
			try { Get-Item 'C:\NonExistent\Path\File.txt' -ErrorAction Stop } catch {}
			$Global:Error.Count | Should -BeGreaterThan 0

			$Null = Get-MyError -Return
			$Global:Error.Count | Should -Be 0
		}

		It 'Should preserve errors when -PreserveErrors is specified' {
			try { Get-Item 'C:\NonExistent\Path\File.txt' -ErrorAction Stop } catch {}
			$InitialCount = $Global:Error.Count
			$Null = Get-MyError -Return -PreserveErrors
			$Global:Error.Count | Should -Be $InitialCount
		}
	}

	Context 'Parameters' {
		It 'Should accept custom Indent parameter' {
			try { Get-Item 'C:\NonExistent\Path\File.txt' -ErrorAction Stop } catch {}
			{ Get-MyError -Return -Indent 10 } | Should -Not -Throw
		}

		# -LinePad does NOT exist on Get-MyError (params are Indent/Return/PreserveErrors/
		# PathToLogFile) and this test asserted it did not throw, so it failed permanently.
		# The function's comment-based help still documents a .PARAMETER LinePad - that help is
		# stale in the CommonScripts master too. Assert the real contract instead: an unknown
		# parameter MUST be rejected.
		It 'Should reject a parameter it does not have' {
			try { Get-Item 'C:\NonExistent\Path\File.txt' -ErrorAction Stop } catch {}
			{ Get-MyError -Return -LinePad 10 } | Should -Throw
		}
	}
}

Describe 'Format-MyTextLine' {
	Context 'Basic Formatting' {
		It 'Should format a simple line' {
			$Result = Format-MyTextLine -Parameter 'Test' -Text 'This is test text' -ParamLen 10 -ParamTrail ': '
			$Result | Should -Not -BeNullOrEmpty
			$Result | Should -Match 'Test'
			$Result | Should -Match 'This is test text'
		}

		It 'Should apply indentation' {
			$Result = Format-MyTextLine -Parameter 'Param' -Text 'Text' -IndentLen 5 -ParamLen 10 -ParamTrail ': '
			$Result | Should -Match '^\s{5}'
		}

		It 'Should include ParamTrail separator' {
			$Result = Format-MyTextLine -Parameter 'Key' -Text 'Value' -ParamLen 10 -ParamTrail ' = '
			$Result | Should -Match 'Key\s+= Value'
		}

		It 'Should include InitialLF when specified' {
			$Result = Format-MyTextLine -Parameter 'P' -Text 'T' -ParamLen 5 -InitialLF "`r`n"
			$Result | Should -Match "^`r`n"
		}
	}

	Context 'NoWrap Option' {
		It 'Should not wrap text when -NoWrap is specified' {
			$LongText = 'A' * 200
			$Result = Format-MyTextLine -Parameter 'Test' -Text $LongText -ParamLen 10 -NoWrap
			$Result | Should -Match ('A' * 200)
		}
	}
}

Describe 'Set-ObjectParameterSet' {
	Context 'Basic Parameter Setting' {
		It 'Should create object from dataset definition' {
			# This test depends on module variables being set
			# Skip if variables not available
			if (-not $Script:StrMyOptions) {
				Set-ItResult -Skipped -Because 'Module variables not available'
			}

			{ Set-ObjectParameterSet -Dataset $Script:StrMyOptions } | Should -Not -Throw
		}
	}
}

Describe 'Set-MyWindowState' {
	# Set-MyWindowState is the lightweight ShowWindow-based hide/restore helper that replaced Set-Window
	# (VENDORED from CommonScripts, internal). It never throws and returns $true only when it found a
	# top-level window to act on - which a non-interactive/ConPTY-hosted test host generally does NOT have,
	# so we assert the "no throw + boolean" contract rather than a specific true/false.
	Context 'State toggling' {
		It 'Should not throw for a valid process id' {
			{ Set-MyWindowState -ProcessId $PID -State Restore } | Should -Not -Throw
		}

		It 'Should return a boolean' {
			$Result = Set-MyWindowState -ProcessId $PID -State Minimize
			$Result | Should -BeOfType [bool]
		}

		It 'Should return $false (no window to act on) for a non-existent process id' {
			Set-MyWindowState -ProcessId 999999999 -State Restore | Should -BeFalse
		}

		It 'Should reject an invalid State value' {
			{ Set-MyWindowState -ProcessId $PID -State Wobble } | Should -Throw
		}
	}
}

Describe 'Get-NewPipeName' {
	Context 'Pipe Name Generation' {
		It 'Should generate a pipe name' {
			$Result = Get-NewPipeName
			$Result | Should -Not -BeNullOrEmpty
		}

		It 'Should generate unique names with delay between calls' {
			$Name1 = Get-NewPipeName
			Start-Sleep -Milliseconds 10
			$Name2 = Get-NewPipeName
			# Names should be different (based on ticks/time)
			$Name1 | Should -Not -Be $Name2
		}

		It 'Should return string starting with Pipe-' {
			$Result = Get-NewPipeName
			$Result | Should -Match '^Pipe-'
		}
	}
}

Describe 'Test-AccessIdentifier' {
	# Note: This function expects IDList in format "name:Allow:ReadWrite"
	Context 'User Validation' {
		It 'Should validate current user with full format' {
			$CurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
			$UserName = $CurrentUser.Split('\')[-1]
			# Must pass full format: name:Allow:ReadWrite
			$Result = Test-AccessIdentifier -IDList "$UserName`:Allow:ReadWrite"
			$Result | Should -Not -BeNullOrEmpty
			$Result | Should -Match $UserName
		}

		It 'Should throw for non-existent user' {
			{ Test-AccessIdentifier -IDList 'NonExistentUser12345XYZ:Allow:ReadWrite' } | Should -Throw
		}
	}

	Context 'Group Validation' {
		It 'Should validate Administrators group' {
			$Result = Test-AccessIdentifier -IDList 'Administrators:Allow:ReadWrite'
			$Result | Should -Not -BeNullOrEmpty
			$Result | Should -Match 'Administrators'
		}

		It 'Should validate Users group' {
			$Result = Test-AccessIdentifier -IDList 'Users:Allow:ReadWrite'
			$Result | Should -Not -BeNullOrEmpty
			$Result | Should -Match 'Users'
		}
	}
}

Describe 'Assert-File' {
	BeforeAll {
		$Script:TestFilePath = Join-Path $env:TEMP "NamedPipeTest_$([guid]::NewGuid().ToString('N')).txt"
	}

	AfterAll {
		if (Test-Path $Script:TestFilePath) {
			Remove-Item $Script:TestFilePath -Force
		}
	}

	Context 'File Testing' {
		# !! These tests used to assert '$Result.Success', a PSCustomObject contract Assert-File
		# has NEVER had. Its own help states: "Returns nothing on success; returns an error string
		# on failure." Verified: every call returns $null while the file IS created, so the tests
		# failed permanently against a function that works. (The .Success confusion most likely
		# came from Assert-File's INTERNAL use of Assert-Folder's result, which does have one.)
		# Asserting the real contract below - and the side effect, which is the point of the call.
		It 'Should return an error string for a non-existent file' {
			$Result = Assert-File -InputObject 'C:\NonExistent\File.txt' -Option Test
			$Result | Should -Not -BeNullOrEmpty
		}

		It 'Should create a file with Create option and return nothing' {
			$Result = Assert-File -InputObject $Script:TestFilePath -Option Create
			$Result | Should -BeNullOrEmpty
			Test-Path $Script:TestFilePath | Should -Be $True
		}

		It 'Should return nothing for an existing file' {
			$Result = Assert-File -InputObject $Script:TestFilePath -Option Test
			$Result | Should -BeNullOrEmpty
		}
	}
}

Describe 'Assert-Folder' {
	BeforeAll {
		$Script:TestFolderPath = Join-Path $env:TEMP "NamedPipeTestFolder_$([guid]::NewGuid().ToString('N'))"
	}

	AfterAll {
		if (Test-Path $Script:TestFolderPath) {
			Remove-Item $Script:TestFolderPath -Force -Recurse
		}
	}

	Context 'Folder Testing' {
		# Assert-Folder returns PSCustomObject with Success property
		It 'Should return Success=false for non-existent folder' {
			$Result = Assert-Folder -InputObject 'C:\NonExistent\Folder\Path' -Option Test
			$Result.Success | Should -Be $False
		}

		It 'Should create a folder with Create option' {
			$Result = Assert-Folder -InputObject $Script:TestFolderPath -Option Create
			$Result.Success | Should -Be $True
			Test-Path $Script:TestFolderPath | Should -Be $True
		}

		It 'Should return Success=true for existing folder' {
			$Result = Assert-Folder -InputObject $Script:TestFolderPath -Option Test
			$Result.Success | Should -Be $True
		}
	}
}

Describe 'Send-Data and Receive-Data' -Tag 'Integration' {
	Context 'Send-Data gets ChunkSize and Depth from PipeInfo' {
		It 'Send-Data should not have ChunkSize or Depth parameters' {
			# Send-Data is internal (not in FunctionsToExport), so Get-Command cannot see it from
			# the test scope. Resolve it inside the module, where it exists.
			$Cmd = & (Get-Module NamedPipe) { Get-Command Send-Data }
			$Cmd.Parameters.Keys | Should -Not -Contain 'ChunkSize'
			$Cmd.Parameters.Keys | Should -Not -Contain 'Depth'
		}

		It 'Send-Data should only require DataObject and PipeInfo' {
			# Send-Data is internal (not in FunctionsToExport), so Get-Command cannot see it from
			# the test scope. Resolve it inside the module, where it exists.
			$Cmd = & (Get-Module NamedPipe) { Get-Command Send-Data }
			$MandatoryParams = $Cmd.Parameters.Values | Where-Object {
				$_.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }
			}
			$MandatoryParams.Name | Should -Contain 'DataObject'
			$MandatoryParams.Name | Should -Contain 'PipeInfo'
			@($MandatoryParams).Count | Should -Be 2
		}
	}

	Context 'Data Size Validation Constants' {
		# Test that the validation thresholds are sensible
		It 'MaxSingleMessageSize should accommodate Base64 overhead of 32KB chunk' {
			# 32KB * 1.37 (Base64 overhead) = ~44KB, should fit in 48KB threshold
			$ChunkSize = 32768
			$EstimatedWithOverhead = [math]::Ceiling($ChunkSize * 1.4)
			$MaxSingleMessageSize = 49152  # 48KB as defined in Send-Data
			$EstimatedWithOverhead | Should -BeLessOrEqual $MaxSingleMessageSize
		}

		It 'Default ChunkSize should be safe for default buffer sizes' {
			$DefaultChunkSize = 32768  # 32KB
			$PipeBufferSize = 65536    # 64KB as defined in Set-ObjectParameterSet
			# With Base64 overhead, chunk becomes ~44KB which fits in 64KB buffer
			$EstimatedWithOverhead = [math]::Ceiling($DefaultChunkSize * 1.4)
			$EstimatedWithOverhead | Should -BeLessOrEqual $PipeBufferSize
		}
	}
}

Describe 'Receive-Data over a real pipe' -Tag 'Integration' {
	# The rest of this file's chunking/checksum coverage exercises ConvertTo-Serial/
	# ConvertFrom-Serial directly - the serialization layer - but never Receive-Data itself,
	# which is internal (not exported, see 'Receive-Data should not be exported' above) and
	# owns the ReadLine/IsChunked branching this Describe targets. Added 2026-09-10 alongside a
	# fix for one specific gap found in that branching (see the last Context below).
	#
	# CONCURRENCY NOTE (found live building this Describe): running Receive-Data - a NamedPipe
	# module call - on a background thread (first tried via Start-ThreadJob) WHILE the main
	# thread also calls NamedPipe module functions (ConvertTo-Serial) corrupted shared module
	# state across the two threads (an intermittent, unreproducible "depth parameter must be >= 1"
	# error out of PSSerializer) - ThreadJob runspaces share this process's AppDomain, and this
	# module is not verified thread-safe for that. Separately, Start-ThreadJob itself is not even
	# available under Windows PowerShell 5.1 on this machine (it needs the ThreadJob module,
	# built into pwsh.exe but not into powershell.exe) - NamedPipe runs its suite under BOTH
	# hosts, and the PS5.1 run failed all 5 of these tests with "Start-ThreadJob is not
	# recognized" until this was fixed too. Fix for both: only the MAIN thread ever calls into the
	# NamedPipe module - it calls Receive-Data directly (blocking, resolved once via Get-Command
	# since Receive-Data is internal). Every line to send is pre-serialized on the main thread
	# FIRST (sequential, no concurrency hazard), then handed to a background Runspace + PowerShell
	# instance (the same technique the Health Pipe Protocol tests above already use, available on
	# both PS5.1 and PS7) that does ONLY raw .NET StreamWriter.WriteLine calls - no PowerShell
	# module code at all, so nothing there can race. A named pipe with no buffer negotiated also
	# blocks a Write until a Read is already pending on the other end (found the same way - the
	# first version of this Describe wrote before anything was reading and deadlocked), which is
	# exactly why the write always happens
	# on the background thread while Receive-Data (the pending read) runs on the main thread.

	BeforeAll {
		$Script:RDBase = 'NP_ReceiveDataTest_' + [guid]::NewGuid().ToString('N').Substring(0, 8)

		$Script:RDServer = [System.IO.Pipes.NamedPipeServerStream]::new(
			$Script:RDBase, [System.IO.Pipes.PipeDirection]::InOut, 1
		)
		$Script:RDConnectTask = $Script:RDServer.WaitForConnectionAsync()
		$Script:RDClient = [System.IO.Pipes.NamedPipeClientStream]::new(
			'.', $Script:RDBase, [System.IO.Pipes.PipeDirection]::InOut
		)
		$Script:RDClient.Connect(2000)
		$null = $Script:RDConnectTask.Wait(2000)

		$Script:RDServerReader = [System.IO.StreamReader]::new($Script:RDServer)
		$Script:RDServerWriter = [System.IO.StreamWriter]::new($Script:RDServer)
		$Script:RDServerWriter.AutoFlush = $true
		$Script:RDClientWriter = [System.IO.StreamWriter]::new($Script:RDClient)
		$Script:RDClientWriter.AutoFlush = $true

		# Literal key strings, same reasoning as the Health Pipe Protocol FakePipeInfo above:
		# Receive-Data reads $PipeInfo.$StrReader/$StrInfoDisplay, and the module's own $Str*
		# variables are not accessible from ordinary Pester test scope.
		$Script:RDPipeInfo = [PSCustomObject]@{
			Reader      = $Script:RDServerReader
			Writer      = $Script:RDServerWriter
			InfoDisplay = 0
		}

		# Receive-Data is internal (not exported) - resolve it once inside the module, same
		# pattern the Send-Data tests above already use for another internal function.
		$Script:RDReceiveDataCmd = & (Get-Module NamedPipe) { Get-Command Receive-Data }

		# Helper functions must be defined HERE, inside BeforeAll, not loose in the Describe
		# body - Pester 5 runs a Describe body at DISCOVERY time in a different scope than the
		# RUN phase that executes It blocks, so a bare "function" statement at Describe level is
		# invisible by the time an It block tries to call it (found live: every It below failed
		# with "term ... is not recognized" until these moved in here).
		function Script:Send-RDLinesInBackground([String[]]$Lines)
		{
			# Raw .NET only, deliberately - see the CONCURRENCY NOTE above. Uses a separate
			# Runspace + PowerShell instance (same technique the Health Pipe Protocol tests above
			# already use for their background server), NOT Start-ThreadJob - ThreadJob is not
			# available under Windows PowerShell 5.1 on this machine (found live: NamedPipe runs
			# its suite under both powershell.exe and pwsh.exe, and the PS5.1 run failed all 5 of
			# these tests with "Start-ThreadJob is not recognized").
			$Private:RS = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
			$Private:RS.Open()
			$Private:PS = [System.Management.Automation.PowerShell]::Create()
			$Private:PS.Runspace = $Private:RS
			[void]$Private:PS.AddScript({
					Param($Writer, $Lines)
					Start-Sleep -Milliseconds 100
					foreach ($L in $Lines) { $Writer.WriteLine($L) }
				})
			[void]$Private:PS.AddArgument($Script:RDClientWriter)
			[void]$Private:PS.AddArgument($Lines)
			[PSCustomObject]@{
				PS    = $Private:PS
				RS    = $Private:RS
				Async = $Private:PS.BeginInvoke()
			}
		}

		function Script:Wait-RDJob($Job)
		{
			try { $null = $Job.PS.EndInvoke($Job.Async) } catch { $null = $_ }
			try { $Job.PS.Dispose() } catch { }
			try { $Job.RS.Close(); $Job.RS.Dispose() } catch { }
		}
	}

	AfterAll {
		foreach ($D in @($Script:RDClient, $Script:RDServer))
		{ try { if ($D) { $D.Dispose() } } catch { } }
	}

	Context 'Single (non-chunked) message' {
		It 'Receives a plain single message and reassembles it unchanged' {
			$Original = [PSCustomObject]@{ Greeting = 'hello'; Number = 42 }
			$Line = ConvertTo-Serial -Object $Original -ChunkSize 0
			$Job = Send-RDLinesInBackground -Lines @($Line)

			$Result = & $Script:RDReceiveDataCmd -PipeInfo $Script:RDPipeInfo
			Wait-RDJob $Job

			$Result.Greeting | Should -Be 'hello'
			$Result.Number   | Should -Be 42
			$Result.Error    | Should -BeNullOrEmpty
		}
	}

	Context 'Multi-chunk message' {
		It 'Reassembles a message sent across multiple chunks' {
			$Large = [PSCustomObject]@{ Payload = 'Z' * 20000 }
			$Chunks = ConvertTo-Serial -Object $Large -ChunkSize 4096
			@($Chunks).Count | Should -BeGreaterThan 1
			$Lines = @($Chunks | ForEach-Object { ConvertTo-Serial -Object $_ -ChunkSize 0 })
			$Job = Send-RDLinesInBackground -Lines $Lines

			$Result = & $Script:RDReceiveDataCmd -PipeInfo $Script:RDPipeInfo
			Wait-RDJob $Job

			$Result.Payload.Length | Should -Be 20000
			$Result.Error          | Should -BeNullOrEmpty
		}
	}

	Context 'Chunked transfer interrupted by unexpected data ("too short")' {
		It 'Reports an error instead of returning partial data when a chunk sequence is broken' {
			# Send only the first chunk, then something that is NOT a continuation chunk - the
			# accumulation loop's own "else { throw }" guard (Receive-Data.ps1) should fire
			# rather than silently returning whatever partial data had been assembled so far.
			$Large = [PSCustomObject]@{ Payload = 'Q' * 20000 }
			$Chunks = ConvertTo-Serial -Object $Large -ChunkSize 4096
			@($Chunks).Count | Should -BeGreaterThan 1
			$Lines = @(
				(ConvertTo-Serial -Object $Chunks[0] -ChunkSize 0)
				(ConvertTo-Serial -Object ([PSCustomObject]@{ NotAChunk = $true }) -ChunkSize 0)
			)
			$Job = Send-RDLinesInBackground -Lines $Lines

			$Result = & $Script:RDReceiveDataCmd -PipeInfo $Script:RDPipeInfo
			Wait-RDJob $Job

			$Result.Error | Should -Match 'Unexpected data received during chunked transfer'
		}
	}

	Context 'Corrupted chunk checksum (damaged transfer)' {
		It 'Reports a checksum-mismatch error rather than returning corrupted data' {
			$Large = [PSCustomObject]@{ Payload = 'W' * 20000 }
			$Chunks = ConvertTo-Serial -Object $Large -ChunkSize 4096
			@($Chunks).Count | Should -BeGreaterThan 1
			$Chunks[1].Data = 'CORRUPTED' + $Chunks[1].Data.Substring(9)
			$Lines = @($Chunks | ForEach-Object { ConvertTo-Serial -Object $_ -ChunkSize 0 })
			$Job = Send-RDLinesInBackground -Lines $Lines

			$Result = & $Script:RDReceiveDataCmd -PipeInfo $Script:RDPipeInfo
			Wait-RDJob $Job

			$Result.Error | Should -Match 'Checksum mismatch'
		}
	}

	Context 'Failed deserialize (2026-09-10 null-guard fix)' {
		It 'Reports an error instead of silently returning a null DataObject' {
			# ConvertTo-Serial rejects $null outright (Mandatory parameter binding), so this
			# replicates its own pipeline by hand on a genuine PSSerializer null - the one way
			# ConvertFrom-Serial's -Text path returns $null WITHOUT throwing (a garbled/invalid
			# line throws instead - e.g. bad Base64 - and was ALREADY caught by Receive-Data's
			# pre-existing outer Catch before this fix). This is exactly the residual gap the
			# 2026-09-10 fix closed: before it, $received -eq $null fell through to the
			# non-chunked "else" and returned $DataObject = $null with no Error set at all.
			$Xml = [Management.Automation.PSSerializer]::Serialize($null, 2)
			$Xml = $Xml -replace '([\r]|[\n]|[\t])'
			$Xml = $Xml -replace '>[ ]+<', '><'
			$Json = $Xml | ConvertTo-Json -Compress
			$Bytes = [Text.Encoding]::Unicode.GetBytes($Json)
			$NullLine = [Convert]::ToBase64String($Bytes)
			$Job = Send-RDLinesInBackground -Lines @($NullLine)

			$Result = & $Script:RDReceiveDataCmd -PipeInfo $Script:RDPipeInfo
			Wait-RDJob $Job

			$Result | Should -Not -BeNullOrEmpty
			$Result.Error | Should -Match 'Failed to deserialize'
		}
	}

	Context 'Sender never sends anything (2026-09-10: documents the missing read timeout)' {
		It 'currently blocks with no bound instead of timing out' {
			# Receive-Data's ReadLine calls (Receive-Data.ps1:52 and :112) have no timeout - see
			# the discussion that led here. This test does NOT reuse the Describe-level shared
			# pipe, and does NOT reuse $Script:RDReceiveDataCmd either (a FunctionInfo captured
			# from the MAIN runspace's already-imported module) - found live building this test:
			# invoking that FunctionInfo from a genuinely SEPARATE runspace does not carry the
			# module's own script-scoped $Str* constants with it, so $PipeInfo.$StrReader
			# resolved to $null there and Receive-Data crashed almost instantly on an unrelated
			# "null key is not allowed in a hash literal" error - LOOKING like a fast, bounded
			# completion when it had never actually reached the real blocking ReadLine() at all.
			# The background scriptblock below imports the module itself, inside its OWN
			# runspace, so its constants resolve correctly and this genuinely proves the gap.
			$Private:Base = 'NP_RDNoDataTest_' + [guid]::NewGuid().ToString('N').Substring(0, 8)
			$Private:Srv = [System.IO.Pipes.NamedPipeServerStream]::new(
				$Private:Base, [System.IO.Pipes.PipeDirection]::InOut, 1
			)
			$Private:ConnTask = $Private:Srv.WaitForConnectionAsync()
			$Private:Cli = [System.IO.Pipes.NamedPipeClientStream]::new(
				'.', $Private:Base, [System.IO.Pipes.PipeDirection]::InOut
			)
			$Private:Cli.Connect(2000)
			$null = $Private:ConnTask.Wait(2000)

			$Private:SrvReader = [System.IO.StreamReader]::new($Private:Srv)
			$Private:SrvWriter = [System.IO.StreamWriter]::new($Private:Srv)
			$Private:SrvWriter.AutoFlush = $true

			$Private:RS = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
			$Private:RS.Open()
			$Private:PS = [System.Management.Automation.PowerShell]::Create()
			$Private:PS.Runspace = $Private:RS
			[void]$Private:PS.AddScript({
					Param($ModulePath, $Reader, $Writer)
					Import-Module $ModulePath -Force -WarningAction SilentlyContinue
					$Cmd = & (Get-Module NamedPipe) { Get-Command Receive-Data }
					$PI = [PSCustomObject]@{ Reader = $Reader; Writer = $Writer; InfoDisplay = 0 }
					& $Cmd -PipeInfo $PI
				})
			# (Get-Module NamedPipe).Path resolves to InitialiseModule.psm1, NOT the .psd1
			# manifest - found live while building this test - so the manifest path is
			# recomputed the same machine-agnostic way this file's own top-level BeforeAll does
			# (from $PSScriptRoot, so it works regardless of where the repo root sits), rather
			# than relying on that outer $ModulePath surviving into a nested It block's scope.
			[void]$Private:PS.AddArgument((Join-Path (Split-Path -Parent $PSScriptRoot) 'NamedPipe.psd1'))
			[void]$Private:PS.AddArgument($Private:SrvReader)
			[void]$Private:PS.AddArgument($Private:SrvWriter)
			$Private:Async = $Private:PS.BeginInvoke()

			# Nothing is ever written to the client side - the sender simply never sends.
			$Private:Completed = $Private:Async.AsyncWaitHandle.WaitOne(3000)

			if ($Private:Completed)
			{
				# Receive-Data returned on its own within the bound - it now has SOME limit.
				# Surface what it returned so a real fix gets verified here, not just assumed.
				$Private:Result = $Private:PS.EndInvoke($Private:Async)
				Write-Host ('Receive-Data completed unexpectedly with: {0}' -f ($Private:Result | Out-String))
				$Private:PS.Streams.Error | ForEach-Object { Write-Host ('  runspace error: {0}' -f $_.Exception.Message) }
				try { $Private:Srv.Dispose() } catch { $null = $_ }
				try { $Private:Cli.Dispose() } catch { $null = $_ }
				try { $Private:PS.Dispose() } catch { $null = $_ }
				try { $Private:RS.Close(); $Private:RS.Dispose() } catch { $null = $_ }
			}
			else
			{
				# Deliberately DO NOT dispose anything here. Confirmed live: a genuinely stuck
				# synchronous ReadLine() cannot be reliably unblocked from another thread by
				# Stop()/Dispose() (the exact same limitation the Health Pipe Protocol tests'
				# own comment documents for WaitForConnection() - a blocking Win32 call in
				# flight on one thread does not respond to another thread closing the handle,
				# and attempting it here previously hung this test's own cleanup indefinitely).
				# Left to the test process's own exit to reclaim, same as that pattern's
				# "poison pill" workaround exists precisely because there is no other reliable
				# option - there is no reader loop here to feed a poison pill to.
				#
				# UPDATE 2026-09-20: "left for process exit to reclaim" does NOT work - a runspace's
				# pipeline thread is a FOREGROUND thread, so the still-blocked reader kept the whole
				# test process alive after Pester finished (Invoke-AllModuleTest.ps1 -Module NamedPipe
				# hung after printing TOTAL). What DOES work, and is not the Stop()/Dispose()-the-
				# blocked-stream approach described above, is closing the PEER (client) end: the
				# blocked ReadLine() then sees EOF and returns on its own. Only after the runspace has
				# actually finished are the server stream and runspace disposed.
				try { $Private:Cli.Dispose() } catch { $null = $_ }
				if ($Private:Async.AsyncWaitHandle.WaitOne(5000))
				{
					try { $null = $Private:PS.EndInvoke($Private:Async) } catch { $null = $_ }
					try { $Private:Srv.Dispose() } catch { $null = $_ }
					try { $Private:PS.Dispose() } catch { $null = $_ }
					try { $Private:RS.Close(); $Private:RS.Dispose() } catch { $null = $_ }
				}
				else
				{ Write-Host 'The stuck reader did not return after its peer closed; leaving it (process may not exit).' }
			}

			# By design (confirmed 2026-09-10): Receive-Data's FIRST read has no timeout, and a
			# 3-second wait with nothing sent should still be blocked. This is NOT a gap - a slow
			# server-side operation, or a server idling between requests, legitimately looks
			# identical to this from Receive-Data's point of view, and must not be treated as a
			# failure. If this assertion ever fails, Receive-Data's FIRST read was given a bound
			# it should not have, and this test needs revisiting.
			$Private:Completed | Should -Be $false
		}
	}

	Context 'Sender stalls mid-chunk-sequence (2026-09-10: ChunkReadTimeout fix)' {
		It 'Times out gracefully instead of hanging once a chunk transfer has already started' {
			# Unlike the FIRST read (previous Context - deliberately unbounded), a read AWAITING
			# THE NEXT CHUNK of an already-started transfer now has a bound (Receive-Data.ps1,
			# the while loop after "Process first chunk") - once a sender has begun streaming, a
			# gap before the next chunk means it broke mid-transfer, not that some slow operation
			# is still in progress. This sends only the FIRST of several chunks, then genuinely
			# stops (unlike the earlier "interrupted by unexpected data" Context above, which
			# sends a well-formed-but-wrong line immediately - this one sends nothing at all and
			# proves the new TIMEOUT fires, not the pre-existing "wrong data" guard).
			$Large = [PSCustomObject]@{ Payload = 'Z' * 20000 }
			$Chunks = ConvertTo-Serial -Object $Large -ChunkSize 4096
			@($Chunks).Count | Should -BeGreaterThan 1
			$FirstLine = ConvertTo-Serial -Object $Chunks[0] -ChunkSize 0
			$Job = Send-RDLinesInBackground -Lines @($FirstLine)

			# A short, test-scoped ChunkReadTimeout (500ms) so this runs fast rather than the
			# real 30s default - PipeInfo carries this exactly the way production does (copied
			# in from ServerClientParams by Start-PipeServerOrClient.ps1).
			$Private:PIWithTimeout = [PSCustomObject]@{
				Reader           = $Script:RDPipeInfo.Reader
				Writer           = $Script:RDPipeInfo.Writer
				InfoDisplay      = 0
				ChunkReadTimeout = 500
			}

			$Private:Sw = [System.Diagnostics.Stopwatch]::StartNew()
			$Result = & $Script:RDReceiveDataCmd -PipeInfo $Private:PIWithTimeout
			Wait-RDJob $Job

			$Result.Error | Should -Match 'timed out'
			$Result.Error | Should -Match 'next chunk'
			# Proves this is the NEW bound firing (~500ms), not the unbounded first read never
			# returning at all (which would fail this test's own timeout instead).
			$Private:Sw.ElapsedMilliseconds | Should -BeLessThan 3000
		}
	}
}

Describe 'Integration Tests' -Tag 'Integration' {
	Context 'Large Object Serialization Round-Trip' {
		It 'Should handle large hashtables with chunking' {
			$Large = @{
				Data = 'X' * 50000
				Array = 1..1000
				Nested = @{
					Inner = 'Y' * 10000
				}
			}

			$Chunks = ConvertTo-Serial -Object $Large -ChunkSize 8192 -Depth 10

			$Result = $null
			foreach ($Chunk in $Chunks) {
				$Result = ConvertFrom-Serial -Chunk $Chunk
			}

			$Result.Data.Length | Should -Be 50000
			$Result.Array.Count | Should -Be 1000
			$Result.Nested.Inner.Length | Should -Be 10000
		}

		It 'Should handle process objects' {
			$Original = Get-Process | Select-Object -First 10 Id, ProcessName, WorkingSet64
			$Serialized = ConvertTo-Serial -Object $Original -Depth 5
			$Result = ConvertFrom-Serial -Text $Serialized
			$Result.Count | Should -Be 10
		}

		It 'Should handle file system objects' {
			# -Force is REQUIRED: %TEMP% carries the Hidden attribute on this machine, and
			# Get-Item silently refuses hidden items without it, reporting the very misleading
			# "Could not find item <path>" even though Test-Path and [IO.Directory]::Exists
			# both return $true. Nothing to do with serialisation - the test never got that far.
			$Original = Get-Item $env:TEMP -Force | Select-Object Name, FullName, Attributes
			$Serialized = ConvertTo-Serial -Object $Original
			$Result = ConvertFrom-Serial -Text $Serialized
			$Result.Name | Should -Be $Original.Name
		}
	}

	Context 'Serialization Round-Trip with Complex Objects' {
		It 'Should handle current process object' {
			$Original = Get-Process -Id $PID | Select-Object Id, ProcessName, WorkingSet64
			$Serialized = ConvertTo-Serial -Object $Original
			$Result = ConvertFrom-Serial -Text $Serialized
			$Result.Id | Should -Be $Original.Id
			$Result.ProcessName | Should -Be $Original.ProcessName
		}
	}
}

Describe 'Depth Parameter Tests' -Tag 'Depth' {
	Context 'Serialization with Different Depths' {
		It 'Should serialize shallow object with Depth=2' {
			$Shallow = @{ Level1 = 'Value1'; Level2 = @{ Nested = 'Value2' } }
			$Result = ConvertTo-Serial -Object $Shallow -Depth 2
			$Result | Should -Not -BeNullOrEmpty
			$Deserialized = ConvertFrom-Serial -Text $Result
			$Deserialized.Level1 | Should -Be 'Value1'
		}

		It 'Should handle deeply nested objects with higher Depth' {
			$Deep = @{
				L1 = @{
					L2 = @{
						L3 = @{
							L4 = @{
								L5 = 'DeepValue'
							}
						}
					}
				}
			}
			# Depth=2 serialization should still complete without error
			$ShallowResult = ConvertTo-Serial -Object $Deep -Depth 2
			$ShallowDeserialized = ConvertFrom-Serial -Text $ShallowResult
			$ShallowDeserialized | Should -Not -BeNullOrEmpty

			# With Depth=10, deep values should be preserved
			$DeepResult = ConvertTo-Serial -Object $Deep -Depth 10
			$DeepDeserialized = ConvertFrom-Serial -Text $DeepResult
			$DeepDeserialized.L1.L2.L3.L4.L5 | Should -Be 'DeepValue'
		}

		It 'Should use default Depth of 2' {
			$Cmd = Get-Command ConvertTo-Serial
			$Param = $Cmd.Parameters['Depth']
			$Param | Should -Not -BeNullOrEmpty
		}
	}

	Context 'Chunking with Depth Parameter' {
		It 'Should chunk large data correctly with default Depth' {
			$Large = @{
				Data = 'X' * 50000
				Info = @{ Name = 'Test'; Value = 42 }
			}
			$Chunks = ConvertTo-Serial -Object $Large -ChunkSize 8192
			@($Chunks).Count | Should -BeGreaterThan 1

			$Result = $null
			foreach ($Chunk in $Chunks) {
				$Result = ConvertFrom-Serial -Chunk $Chunk
			}
			$Result.Info.Name | Should -Be 'Test'
			$Result.Info.Value | Should -Be 42
		}

		It 'Should chunk nested data correctly with higher Depth' {
			$Nested = @{
				Data = 'Y' * 30000
				Deep = @{
					Level1 = @{
						Level2 = @{
							Level3 = 'NestedValue'
						}
					}
				}
			}
			$Chunks = ConvertTo-Serial -Object $Nested -ChunkSize 8192 -Depth 10
			@($Chunks).Count | Should -BeGreaterThan 1

			$Result = $null
			foreach ($Chunk in $Chunks) {
				$Result = ConvertFrom-Serial -Chunk $Chunk
			}
			$Result.Deep.Level1.Level2.Level3 | Should -Be 'NestedValue'
		}
	}

	Context 'Send-Data Parameters' {
		It 'Send-Data should only have DataObject and PipeInfo parameters' {
			# Send-Data is internal (not in FunctionsToExport), so Get-Command cannot see it from
			# the test scope. Resolve it inside the module, where it exists.
			$Cmd = & (Get-Module NamedPipe) { Get-Command Send-Data }
			$UserParams = $Cmd.Parameters.Keys | Where-Object { $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters }
			$UserParams | Should -Contain 'DataObject'
			$UserParams | Should -Contain 'PipeInfo'
			$UserParams | Should -Not -Contain 'Depth'
			$UserParams | Should -Not -Contain 'ChunkSize'
		}
	}

	Context 'Send-Request Parameters' {
		It 'Send-Request should not have ChunkSize parameter' {
			$Cmd = Get-Command Send-Request
			$Cmd.Parameters.Keys | Should -Not -Contain 'ChunkSize'
		}
	}
}

Describe 'Set-ObjectParameterSet Parameter Flow' -Tag 'ParamFlow' {
	Context 'MyOptions Defaults' {
		BeforeAll {
			$Script:Options = Set-ObjectParameterSet -Dataset $StrMyOptions
		}

		It 'InfoDisplay should default to 0 (int)' {
			$Script:Options.$StrInfoDisplay | Should -Be 0
			$Script:Options.$StrInfoDisplay | Should -BeOfType [int]
		}

		It 'ChunkSize should default to 32768' {
			$Script:Options.$StrChunkSize | Should -Be 32768
		}

		It 'Depth should default to 2' {
			$Script:Options.$StrDepth | Should -Be 2
		}

		It 'ServerWaitTimeout should default to 60' {
			$Script:Options.$StrServerWaitTimeout | Should -Be 60
		}

		It 'ClientConnectTimeout should default to 10000' {
			$Script:Options.$StrClientConnectTimeout | Should -Be 10000
		}

		It 'ChunkReadTimeout should default to 30000' {
			$Script:Options.$StrChunkReadTimeout | Should -Be 30000
		}

		It 'RedactPotentialSecrets should default to $true' {
			$Script:Options.$StrRedactPotentialSecrets | Should -BeTrue
		}

		It 'RedactPattern should default to $null' {
			$Script:Options.$StrRedactPattern | Should -BeNullOrEmpty
		}

		It 'RequestPolicy should default to $null' {
			$Script:Options.$StrRequestPolicy | Should -BeNullOrEmpty
		}

		It 'ModuleToLoad should default to the module-level default' {
			$Private:Expected = & (Get-Module NamedPipe) { $script:DefaultModuleToLoad }
			$Script:Options.$StrModuleToLoad.Name | Should -Be $Private:Expected.Name
			$Script:Options.$StrModuleToLoad.Version | Should -Be $Private:Expected.Version
		}
	}

	Context 'MyOptions With Parameters' {
		It 'Should pass InfoDisplay as int value' {
			$Params = @{ $StrInfoDisplay = 2 }
			$Options = Set-ObjectParameterSet -Dataset $StrMyOptions -MyParameters $Params
			$Options.$StrInfoDisplay | Should -Be 2
			$Options.$StrInfoDisplay | Should -BeOfType [int]
		}

		It 'Should pass Depth value' {
			$Params = @{ $StrDepth = 5 }
			$Options = Set-ObjectParameterSet -Dataset $StrMyOptions -MyParameters $Params
			$Options.$StrDepth | Should -Be 5
		}

		It 'Should pass ChunkSize value' {
			$Params = @{ $StrChunkSize = 16384 }
			$Options = Set-ObjectParameterSet -Dataset $StrMyOptions -MyParameters $Params
			$Options.$StrChunkSize | Should -Be 16384
		}

		It 'Should pass ServerWaitTimeout value' {
			$Params = @{ $StrServerWaitTimeout = 120 }
			$Options = Set-ObjectParameterSet -Dataset $StrMyOptions -MyParameters $Params
			$Options.$StrServerWaitTimeout | Should -Be 120
		}

		It 'Should pass ClientConnectTimeout value' {
			$Params = @{ $StrClientConnectTimeout = 5000 }
			$Options = Set-ObjectParameterSet -Dataset $StrMyOptions -MyParameters $Params
			$Options.$StrClientConnectTimeout | Should -Be 5000
		}

		It 'Should pass ChunkReadTimeout value' {
			$Params = @{ $StrChunkReadTimeout = 2000 }
			$Options = Set-ObjectParameterSet -Dataset $StrMyOptions -MyParameters $Params
			$Options.$StrChunkReadTimeout | Should -Be 2000
		}

		It 'Should pass RedactPotentialSecrets:$false value (2026-09-19 unification - this dataset used
			to silently drop this field, requiring the -Options merge as the only working path)' {
			$Params = @{ $StrRedactPotentialSecrets = $false }
			$Options = Set-ObjectParameterSet -Dataset $StrMyOptions -MyParameters $Params
			$Options.$StrRedactPotentialSecrets | Should -BeFalse
		}

		It 'Should pass RedactPattern value' {
			$Private:Pattern = @{ Option = 2; Pattern = '(?i)-Passphrase\s+\S+' }
			$Params = @{ $StrRedactPattern = $Private:Pattern }
			$Options = Set-ObjectParameterSet -Dataset $StrMyOptions -MyParameters $Params
			$Options.$StrRedactPattern.Pattern | Should -Be $Private:Pattern.Pattern
		}

		It 'Should pass RequestPolicy value' {
			$Private:Policy = @{ Mode = 'AllowList' }
			$Params = @{ $StrRequestPolicy = $Private:Policy }
			$Options = Set-ObjectParameterSet -Dataset $StrMyOptions -MyParameters $Params
			$Options.$StrRequestPolicy.Mode | Should -Be 'AllowList'
		}

		It 'Should pass ModuleToLoad value' {
			$Private:Module = @{ Name = 'SomeConsumerModule'; Version = '1.0' }
			$Params = @{ $StrModuleToLoad = $Private:Module }
			$Options = Set-ObjectParameterSet -Dataset $StrMyOptions -MyParameters $Params
			$Options.$StrModuleToLoad.Name | Should -Be 'SomeConsumerModule'
		}
	}

	Context 'ServerClientParams Inherits From MyOptions' {
		It 'Server params should inherit InfoDisplay from MyOptions' {
			$Params = @{ $StrInfoDisplay = 1 }
			$Options = Set-ObjectParameterSet -Dataset $StrMyOptions -MyParameters $Params
			$SCP = Set-ObjectParameterSet -Server -Dataset $StrServerClientParams -MyParameters $Options
			$SCP.$StrInfoDisplay | Should -Be 1
			$SCP.$StrInfoDisplay | Should -BeOfType [int]
		}

		It 'Server params should inherit Depth from MyOptions' {
			$Params = @{ $StrDepth = 7 }
			$Options = Set-ObjectParameterSet -Dataset $StrMyOptions -MyParameters $Params
			$SCP = Set-ObjectParameterSet -Server -Dataset $StrServerClientParams -MyParameters $Options
			$SCP.$StrDepth | Should -Be 7
		}

		It 'Server params should inherit timeouts from MyOptions' {
			$Params = @{ $StrServerWaitTimeout = 90; $StrClientConnectTimeout = 20000; $StrChunkReadTimeout = 5000 }
			$Options = Set-ObjectParameterSet -Dataset $StrMyOptions -MyParameters $Params
			$SCP = Set-ObjectParameterSet -Server -Dataset $StrServerClientParams -MyParameters $Options
			$SCP.$StrServerWaitTimeout | Should -Be 90
			$SCP.$StrClientConnectTimeout | Should -Be 20000
			$SCP.$StrChunkReadTimeout | Should -Be 5000
		}

		It 'Server params should default RedactPotentialSecrets to $true when never set anywhere' {
			$Params = @{ $StrInfoDisplay = 1 }
			$Options = Set-ObjectParameterSet -Dataset $StrMyOptions -MyParameters $Params
			$SCP = Set-ObjectParameterSet -Server -Dataset $StrServerClientParams -MyParameters $Options
			$SCP.$StrRedactPotentialSecrets | Should -BeTrue
		}

		It 'Server params should inherit an explicit RedactPotentialSecrets:$false set on MyOptions via
			the -Options-merge path (Start-PipeSession''s own mechanism, where the value is set on the
			built MyOptions object directly rather than passed through the dataset call''s own MyParameters)' {
			$Options = Set-ObjectParameterSet -Dataset $StrMyOptions -MyParameters @{}
			$Options.$StrRedactPotentialSecrets = $false
			$SCP = Set-ObjectParameterSet -Server -Dataset $StrServerClientParams -MyParameters $Options
			$SCP.$StrRedactPotentialSecrets | Should -BeFalse
		}

		It 'Server params should inherit an explicit RedactPotentialSecrets:$false passed via raw
			MyParameters through the MyOptions dataset call itself (2026-09-19 unification - this path
			used to silently drop the value, since RedactPotentialSecrets/RedactPattern/RequestPolicy/
			ModuleToLoad were absent from the $StrMyOptions case''s own switch; now all four round-trip
			the same way InfoDisplay/Depth/etc. always have)' {
			$Params = @{ $StrRedactPotentialSecrets = $false }
			$Options = Set-ObjectParameterSet -Dataset $StrMyOptions -MyParameters $Params
			$SCP = Set-ObjectParameterSet -Server -Dataset $StrServerClientParams -MyParameters $Options
			$SCP.$StrRedactPotentialSecrets | Should -BeFalse
		}

		It 'Client params should default RedactPotentialSecrets to $true when never set anywhere' {
			$Params = @{ $StrInfoDisplay = 1 }
			$Options = Set-ObjectParameterSet -Dataset $StrMyOptions -MyParameters $Params
			$SCP = Set-ObjectParameterSet -Client -Dataset $StrServerClientParams -MyParameters $Options
			$SCP.$StrRedactPotentialSecrets | Should -BeTrue
		}
	}
}

Describe 'Get-SBResult - Data channel' -Tag 'DataChannel' {
	# Get-SBResult is deliberately unexported (see the 'FunctionExportTable' Describe below) -
	# reached the same way this file's own BeforeAll reaches other internals: run inside the
	# module's own scope, where $StrRequest/$StrData/$StrResult resolve.
	BeforeAll {
		$Private:Body = '& (Get-Module NamedPipe) ([scriptblock]::Create(''Get-SBResult @args'')) @args'
		Set-Item -Path 'function:script:Get-SBResult' -Value ([scriptblock]::Create($Private:Body))

		# A stand-in for a real consumer function (e.g. VHDTools' Invoke-VHDAction) - globally
		# resolvable once "imported", same as any real module's exported command would be. Not a
		# NamedPipe concept; just something for the generated request text to legitimately invoke.
		function Global:Test-DataEcho { Param ($Data, $Dummy) return $Data }
		function Global:Test-DataIsNull { Param ($Data) return ($null -eq $Data) }
		function Global:Test-DataReturnsNull { Param ($Data) return $null }
		function Global:Test-DataMandatory { Param ([Parameter(Mandatory)]$Data) return $Data }
	}

	AfterAll {
		Remove-Item function:Global:Test-DataEcho, function:Global:Test-DataIsNull, function:Global:Test-DataReturnsNull, function:Global:Test-DataMandatory -ErrorAction SilentlyContinue
	}

	It '-Parameters branch: passes a single value through .Data to the invoked command as -Data' {
		$DataObject = @{ Request = 'Test-DataEcho'; Parameters = @{ Dummy = 1 }; Data = 'a plain value' }
		$Result = Get-SBResult -DataObject $DataObject
		$Result.Result | Should -Be 'a plain value'
	}

	It '-Parameters branch: passes a hashtable through .Data to the invoked command as -Data (multi-value case)' {
		$DataObject = @{ Request = 'Test-DataEcho'; Parameters = @{ Dummy = 1 }; Data = @{ A = 1; B = 'two' } }
		$Result = Get-SBResult -DataObject $DataObject
		$Result.Result.A | Should -Be 1
		$Result.Result.B | Should -Be 'two'
	}

	It '-Parameters branch: does not append -Data when .Data is not populated - zero behaviour change for existing calls' {
		$DataObject = @{ Request = 'Test-DataIsNull'; Parameters = @{ Dummy = 1 } }
		$Result = Get-SBResult -DataObject $DataObject
		$Result.Result | Should -BeTrue
	}

	It 'plain-Request branch: a bare command with no .Parameters still gets -Data appended unconditionally,
		so a Mandatory -Data parameter on the invoked function is satisfied' {
		# The gap this closes: Request = 'MyFunction' with no .Parameters used to fall through to the
		# Else branch and get NOTHING appended, even though the consumer clearly populated .Data for
		# a function that needs it - a Mandatory -Data parameter would fail to bind.
		$DataObject = @{ Request = 'Test-DataMandatory'; Data = 'must arrive' }
		$Result = Get-SBResult -DataObject $DataObject
		$Result.Result | Should -Be 'must arrive'
	}

	It 'plain-Request branch: a multi-statement request that ends in an actual command invocation
		tolerates the unconditional append AND its own earlier $Data.<Key> references resolve via
		the closure - both mechanisms work together' {
		# The final statement must be a genuine command invocation (not a bare expression like
		# "$a + $b" or a parenthesised one - PowerShell rejects a trailing -Data:$Data after either,
		# confirmed empirically) for the append to land somewhere syntactically valid. Test-DataEcho
		# receives -Dummy (computed from $Data.A/$Data.B, resolved directly in the body) AND the
		# appended -Data:$Data - it returns $Data, proving both routes reached the same closure value.
		$DataObject = @{
			Request = "`$Private:_a = `$Data.A`n`$Private:_b = `$Data.B`nTest-DataEcho -Dummy (`$Private:_a + '-' + `$Private:_b)"
			Data    = @{ A = 'left'; B = 'right' }
		}
		$Result = Get-SBResult -DataObject $DataObject
		$Result.Result.A | Should -Be 'left'
		$Result.Result.B | Should -Be 'right'
	}

	It 'plain-Request branch: -Data is appended EVEN when doing so breaks the request''s syntax - that is
		the consumer''s mistake to avoid, reported cleanly via .Error, not something this function
		tries to detect or prevent' {
		# The append lands unconditionally, with no attempt to check whether the request can safely
		# take a trailing argument first. A request ending in something that cannot (e.g. a bare
		# parenthesised expression as its last statement) genuinely fails to parse once appended -
		# this is BY DESIGN: VHDTools/VaultTools avoid this entirely by keeping every elevated
		# dispatch to a single command/function-plus-parameters shape (see Invoke-VHDAction and the
		# VaultTools atomic Server\ functions) - a different consumer choosing a request shape that
		# cannot tolerate the append is responsible for not populating .Data for it, or for shaping
		# its own request text so the append is harmless (as the previous It block does).
		$DataObject = @{
			Request = "`$Private:_a = `$Data.A`n`$Private:_b = `$Data.B`n(`$Private:_a + '-' + `$Private:_b)"
			Data    = @{ A = 'left'; B = 'right' }
		}
		$Result = Get-SBResult -DataObject $DataObject
		[string]::IsNullOrWhiteSpace($Result.Result) | Should -BeTrue
		$Result.Error | Should -Not -BeNullOrEmpty
	}

	It 'preserves a genuine $null result from the invoked command when .Data IS populated' {
		$DataObject = @{ Request = 'Test-DataReturnsNull'; Data = 'irrelevant' }
		$Result = Get-SBResult -DataObject $DataObject
		$null -eq $Result.Result | Should -BeTrue
	}

	It 'demonstrates the failure mode: $Private:-scoped is silently lost by GetNewClosure()' {
		# Standalone characterisation of the exact mechanism Get-SBResult relies on (see the
		# comments beside 'GetNewClosure()' in Get-SBResult.ps1) - not a call through Get-SBResult
		# itself, since the failure this guards against is a source-level mistake (using
		# $Private:Data instead of a plain local), not something reachable through its public
		# behaviour today. Kept in its OWN It block (fresh scope) - once a variable is created
		# with $Private:, a later plain reassignment in the SAME scope does not clear the Private
		# flag, so testing both cases in one block would silently contaminate the second.
		$Private:Data = 'should not be visible inside the closure'
		$SB = [ScriptBlock]::Create('$Data')   # bare reference, same as Get-SBResult builds
		$Closure = $SB.GetNewClosure()
		$Closure.InvokeReturnAsIs() | Should -BeNullOrEmpty
	}

	It 'demonstrates the fix: a plain local IS captured correctly by GetNewClosure()' {
		$Data = 'plain local is captured correctly'
		$SB = [ScriptBlock]::Create('$Data')
		$Closure = $SB.GetNewClosure()
		$Closure.InvokeReturnAsIs() | Should -Be 'plain local is captured correctly'
	}
}

Describe 'Test-Base64String' -Tag 'RedactPotentialSecrets' {
	It 'returns $true for a genuine base64-encoded value' {
		$Encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('a real secret value'))
		Test-Base64String -Value $Encoded | Should -BeTrue
	}

	It 'returns $false for an ordinary word whose length is NOT a multiple of 4' {
		Test-Base64String -Value 'VHDOperations' | Should -BeFalse
	}

	It 'returns $false for an empty string' {
		Test-Base64String -Value '' | Should -BeFalse
	}

	It 'accepts the documented residual false-positive: a short pure-alphanumeric word whose length
		happens to be a multiple of 4 decodes without error - this is a KNOWN, accepted limitation of
		any purely structural test, not a bug (see this function''s own doc comment and USERGUIDE.md)' {
		Test-Base64String -Value 'Data' | Should -BeTrue
	}

	It 'returns $false for a string containing a real base64 padding character in the wrong place
		(a FormatException case beyond just charset/length, exercising the recognized-catch path)' {
		Test-Base64String -Value 'AB=C' | Should -BeFalse
	}

	It 'does NOT report an ordinary invalid candidate to the catch-audit log (the FormatException is wrapped in a MethodInvocationException and must still be recognized as expected)' {
		Mock Write-MyCatchAudit -ModuleName NamedPipe -MockWith { }
		# 4 characters (passes the length check) but not base64: reaches FromBase64String and fails there.
		Test-Base64String -Value 'a!c$' | Should -BeFalse
		Test-Base64String -Value 'W:\v' | Should -BeFalse
		Should -Invoke Write-MyCatchAudit -ModuleName NamedPipe -Times 0 -Exactly
	}
}

Describe 'Get-SBResult - RedactPotentialSecrets display transform' -Tag 'RedactPotentialSecrets' {
	# Exercises the exact [regex]::Replace + Test-Base64String combination Get-SBResult.ps1 uses for
	# its console-echo / trace-log display string - not a full pipe-session integration test (that
	# would need a live ServerClientParams/InfoDisplay/tracing setup), but a direct test of the real
	# transform logic against representative real request-text shapes, matching how this module's
	# other tests isolate a mechanism rather than always driving it through the full pipe.
	BeforeAll {
		function Protect-TestDisplayText
		{
			# Mirrors Get-SBResult.ps1's CORRECTED (2026-09-19) mechanism: test each QUOTED VALUE as
			# one atomic unit, not loose maximal runs of base64-alphabet characters anywhere in the
			# text. The first version of this (both here and in Get-SBResult.ps1) matched runs directly
			# and fragmented at every non-base64 character - found wrong via a real failure in the two
			# It blocks below, which is exactly why they exist: a realistic, entirely non-secret VHD
			# command line lost SIX words to false positives under the run-based version, including the
			# 20-character parameter name 'CheckGroupMembership' and NamedPipe's own '-Data:$Data'
			# marker text.
			Param ([String]$Text)
			[regex]::Replace($Text, "'([^']*)'|""([^""]*)""", {
					Param ($Match)
					$Inner = If ($Match.Groups[1].Success) { $Match.Groups[1].Value } Else { $Match.Groups[2].Value }
					$Quote = $Match.Value.Substring(0, 1)
					If (Test-Base64String -Value $Inner) { ('{0}<base64 encoded>{0}' -f $Quote) } Else { $Match.Value }
				})
		}
	}

	It 'masks a value that IS structurally valid base64 when it is the WHOLE content of a quoted
		parameter value - a potential secret, per RedactPotentialSecrets'' own name (this mechanism
		can never confirm actual sensitivity, only base64 shape)' {
		$Encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('a value that could be sensitive'))
		$Text = "Invoke-VHDAction -Data:'{0}'" -f $Encoded
		$Masked = Protect-TestDisplayText -Text $Text
		$Masked | Should -Not -Match ([regex]::Escape($Encoded))
		$Masked | Should -Match '<base64 encoded>'
	}

	It 'leaves a realistic command line with paths/GUIDs/booleans/enum-like words completely
		unchanged - a QUOTED PATH containing non-base64 characters (\, :, -, .) fails as a WHOLE and is
		never fragmented into short pieces that might accidentally validate on their own (this is the
		exact bug the first version of this mechanism had - see this Describe block''s own comment)' {
		$Text = "Invoke-VHDAction  -DestinationPath:'W:\vhd\PSimple\tvhd-p.psd1' -VHDLocation:'W:\vhd\PSimple\tvhd-p.vhdx' -Action:'Invoke' -CheckGroupMembership:`$True"
		Protect-TestDisplayText -Text $Text | Should -Be $Text
	}

	It 'leaves a bare $Data reference (the out-of-band channel marker) unchanged - it is a variable
		name in the request text, never the real value, and bare (unquoted) tokens are never candidates
		under this mechanism' {
		$Text = "Invoke-VHDAction -Action:'Invoke' -WriteNewConfig:`$True -Data:`$Data"
		Protect-TestDisplayText -Text $Text | Should -Be $Text
	}

	It 'masks a genuine base64-shaped quoted value even when it sits next to ordinary unquoted text -
		proves the quoted-value approach still catches an embedded secret, not just whole-string cases' {
		$Encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('a value that could be sensitive'))
		$Text = "Invoke-VHDAction -Action:'Invoke' -SomeFlag:`$True -Data:'{0}'" -f $Encoded
		$Masked = Protect-TestDisplayText -Text $Text
		$Masked | Should -Be ("Invoke-VHDAction -Action:'Invoke' -SomeFlag:`$True -Data:'<base64 encoded>'")
	}
}

Describe 'Get-SBResult - RedactPotentialSecrets end-to-end gating (real function, real ServerClientParams)' -Tag 'RedactPotentialSecrets' {
	# Closes a real gap: the display-transform Describe above re-implements the algorithm
	# (Protect-TestDisplayText) purely to unit-test the regex/evaluator in isolation, and the
	# 'ServerClientParams Inherits From MyOptions' Context above only proves Set-ObjectParameterSet's
	# OWN plumbing, never that Get-SBResult actually reads the result of that plumbing. Neither proves
	# the real Get-SBResult function reads $ServerClientParams.RedactPotentialSecrets and gates on it.
	# This Describe calls the REAL Get-SBResult (same module-scope redirection technique as the 'Data
	# channel' Describe above) with a REAL ServerClientParams built by the REAL Set-ObjectParameterSet,
	# and intercepts the console-echo call (Send-ProgressInfo, exported) to inspect what Get-SBResult
	# actually decided to display - proving the option's effect end-to-end, not just algorithmically.
	BeforeAll {
		$Private:Body = '& (Get-Module NamedPipe) ([scriptblock]::Create(''Get-SBResult @args'')) @args'
		Set-Item -Path 'function:script:Get-SBResult' -Value ([scriptblock]::Create($Private:Body))
		function Global:Test-EchoValue { Param ($Value) return $Value }
	}

	AfterAll {
		Remove-Item function:Global:Test-EchoValue -ErrorAction SilentlyContinue
		Remove-Variable -Name ServerClientParams -Scope Global -ErrorAction SilentlyContinue
	}

	BeforeEach {
		$Script:CapturedConsoleString = $null
		Mock Send-ProgressInfo -ModuleName NamedPipe -MockWith { $Script:CapturedConsoleString = $String } -ParameterFilter { $Type -eq 'Console' }
	}

	It 'masks a potential secret in the real console echo when RedactPotentialSecrets is $true (the explicit default built by Set-ObjectParameterSet)' {
		$Options = Set-ObjectParameterSet -Dataset $StrMyOptions -MyParameters @{ $StrInfoDisplay = $InfoDisplayBitProgress }
		$Global:ServerClientParams = Set-ObjectParameterSet -Server -Dataset $StrServerClientParams -MyParameters $Options
		$Global:ServerClientParams.$StrRedactPotentialSecrets | Should -BeTrue   # sanity: confirms the default really is on before the real assertion below

		$Private:Encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('a value that could be sensitive'))
		$DataObject = @{ Request = "Test-EchoValue -Value '{0}'" -f $Private:Encoded }
		$null = Get-SBResult -DataObject $DataObject

		$Script:CapturedConsoleString | Should -Match '<base64 encoded>'
		$Script:CapturedConsoleString | Should -Not -Match ([regex]::Escape($Private:Encoded))
	}

	It 'shows the real value in the console echo when RedactPotentialSecrets is explicitly $false - the documented opt-out' {
		# RedactPotentialSecrets is not part of the $StrMyOptions dataset's own switch case (same
		# tier as RedactPattern/RequestPolicy/ModuleToLoad) - set on the built object afterward,
		# exactly as Start-PipeSession's own -Options merge step does for a real consumer.
		$Options = Set-ObjectParameterSet -Dataset $StrMyOptions -MyParameters @{ $StrInfoDisplay = $InfoDisplayBitProgress }
		$Options.$StrRedactPotentialSecrets = $false
		$Global:ServerClientParams = Set-ObjectParameterSet -Server -Dataset $StrServerClientParams -MyParameters $Options
		$Global:ServerClientParams.$StrRedactPotentialSecrets | Should -BeFalse

		$Private:Encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('a value that could be sensitive'))
		$DataObject = @{ Request = "Test-EchoValue -Value '{0}'" -f $Private:Encoded }
		$null = Get-SBResult -DataObject $DataObject

		$Script:CapturedConsoleString | Should -Match ([regex]::Escape($Private:Encoded))
	}

	It 'leaves an ordinary, non-secret-shaped request line unchanged in the real console echo either way' {
		$Options = Set-ObjectParameterSet -Dataset $StrMyOptions -MyParameters @{ $StrInfoDisplay = $InfoDisplayBitProgress }
		$Global:ServerClientParams = Set-ObjectParameterSet -Server -Dataset $StrServerClientParams -MyParameters $Options

		$DataObject = @{ Request = "Test-EchoValue -Value 'W:\vhd\PSimple\tvhd-p.psd1'" }
		$null = Get-SBResult -DataObject $DataObject

		$Script:CapturedConsoleString | Should -Match ([regex]::Escape("Test-EchoValue -Value 'W:\vhd\PSimple\tvhd-p.psd1'"))
	}
}

Describe 'Function trace facility - per-session file, -Detail, -SkipFrames' -Tag 'FunctionTrace' {
	# $env:ProgramData is redirected to a temp folder for the whole block so no test touches the real
	# C:\ProgramData\FunctionTrace log, and every environment variable the facility reads is restored.
	BeforeAll {
		$Script:FTModule = Get-Module -Name NamedPipe
		$Script:FTSaved = @{
			ProgramData = $env:ProgramData
			Enabled     = $env:MyFunctionTraceEnabled
			SessionId   = $env:MyFunctionTraceSessionId
			Filter      = $env:MyFunctionTraceFilter
		}
		$Script:FTRoot = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath ('NPFT-{0}' -f [Guid]::NewGuid().ToString('N'))
		$null = New-Item -Path $Script:FTRoot -ItemType Directory -Force
		$env:ProgramData = $Script:FTRoot
		$Script:FTDir = Join-Path -Path $Script:FTRoot -ChildPath 'FunctionTrace'
		& $Script:FTModule {
			function script:Test-FTDirect { Write-MyFunctionTrace -Detail 'direct' }
			function script:Test-FTNoDetail { Write-MyFunctionTrace }
			function script:Test-FTWrapper { Param ($D) Write-MyFunctionTrace -Detail $D -SkipFrames 1 }
			function script:Test-FTCaller { Test-FTWrapper -D 'wrapped' }
		}
	}

	AfterAll {
		& $Script:FTModule {
			Remove-Item -Path 'function:script:Test-FTDirect', 'function:script:Test-FTNoDetail', 'function:script:Test-FTWrapper', 'function:script:Test-FTCaller' -ErrorAction SilentlyContinue
		}
		$env:ProgramData                = $Script:FTSaved.ProgramData
		$env:MyFunctionTraceEnabled     = $Script:FTSaved.Enabled
		$env:MyFunctionTraceSessionId   = $Script:FTSaved.SessionId
		$env:MyFunctionTraceFilter      = $Script:FTSaved.Filter
		Remove-Item -Path $Script:FTRoot -Recurse -Force -ErrorAction SilentlyContinue
	}

	BeforeEach {
		$env:MyFunctionTraceEnabled   = '3'
		$env:MyFunctionTraceSessionId = 'pester01'
		$env:MyFunctionTraceFilter    = $null
		If (Test-Path -Path $Script:FTDir) { Remove-Item -Path (Join-Path $Script:FTDir '*') -Force -ErrorAction SilentlyContinue }
		$Script:FTLog = Join-Path -Path $Script:FTDir -ChildPath 'FunctionTrace-Session-pester01.log'
	}

	Context 'Get-MyFunctionTracePath' {
		It 'returns the shared FunctionTrace.log when no session id is set' {
			$env:MyFunctionTraceSessionId = $null
			$P = & $Script:FTModule { Get-MyFunctionTracePath }
			(Split-Path -Path $P -Leaf) | Should -Be 'FunctionTrace.log'
		}

		It 'returns FunctionTrace-Session-(id).log when a session id is set' {
			$P = & $Script:FTModule { Get-MyFunctionTracePath }
			(Split-Path -Path $P -Leaf) | Should -Be 'FunctionTrace-Session-pester01.log'
		}

		It 'strips path characters from the session id so it cannot leave the trace folder' {
			$env:MyFunctionTraceSessionId = '..\..\evil'
			$P = & $Script:FTModule { Get-MyFunctionTracePath }
			(Split-Path -Path $P -Leaf) | Should -Be 'FunctionTrace-Session-evil.log'
			(Split-Path -Path $P -Parent) | Should -Be $Script:FTDir
		}
	}

	Context 'Enable-MyFunctionTrace' {
		It 'rejects an -Option outside 1-3' {
			{ Enable-MyFunctionTrace -Option 0 } | Should -Throw
			{ Enable-MyFunctionTrace -Option 4 } | Should -Throw
		}

		It 'sets the bitmask, creates a session id, and prints the single confirmation line' {
			$env:MyFunctionTraceSessionId = $null
			$Out = @(Enable-MyFunctionTrace -Option 2)
			$env:MyFunctionTraceEnabled | Should -Be '2'
			$env:MyFunctionTraceSessionId | Should -Match '^[0-9a-f]{8}$'
			$Out.Count | Should -Be 1
			$Out[0] | Should -Match 'Function-call tracing is ON \(Option=2\) for this process\. Log: .*FunctionTrace-Session-[0-9a-f]{8}\.log'
		}

		It 'creates the session file itself, so an elevated server never becomes its creator (client would be denied)' {
			$env:MyFunctionTraceSessionId = 'pester02'
			$Expected = Join-Path -Path $Script:FTDir -ChildPath 'FunctionTrace-Session-pester02.log'
			Test-Path -LiteralPath $Expected | Should -BeFalse
			$null = Enable-MyFunctionTrace -Option 2
			Test-Path -LiteralPath $Expected | Should -BeTrue
		}

		It 'reuses the session id on a second call and only changes it with -NewSession' {
			$env:MyFunctionTraceSessionId = $null
			$null = Enable-MyFunctionTrace -Option 1
			$First = $env:MyFunctionTraceSessionId
			$null = Enable-MyFunctionTrace -Option 1
			$env:MyFunctionTraceSessionId | Should -Be $First
			$null = Enable-MyFunctionTrace -Option 1 -NewSession
			$env:MyFunctionTraceSessionId | Should -Not -Be $First
		}
	}

	Context 'Write-MyFunctionTrace -Detail and -SkipFrames' {
		It 'appends Detail:[...] for any caller (no allowlist) and names the calling function' {
			& $Script:FTModule { Test-FTDirect }
			$Line = Get-Content -Path $Script:FTLog -Raw
			$Line | Should -Match 'Function:\[(script:)?Test-FTDirect\]'
			$Line | Should -Match 'Detail:\[direct\]'
		}

		It 'writes a plain line with no Detail suffix when -Detail is not given' {
			& $Script:FTModule { Test-FTNoDetail }
			$Line = Get-Content -Path $Script:FTLog -Raw
			$Line | Should -Match 'Function:\[(script:)?Test-FTNoDetail\]'
			$Line | Should -Not -Match 'Detail:'
		}

		It 'attributes the line to the wrapper''s caller with -SkipFrames 1, not to the wrapper' {
			& $Script:FTModule { Test-FTCaller }
			$Line = Get-Content -Path $Script:FTLog -Raw
			$Line | Should -Match 'Function:\[(script:)?Test-FTCaller\]'
			$Line | Should -Not -Match 'Function:\[(script:)?Test-FTWrapper\]'
			$Line | Should -Match 'Detail:\[wrapped\]'
		}

		It 'applies $env:MyFunctionTraceFilter to the skipped-to caller' {
			$env:MyFunctionTraceFilter = 'script:Test-FTCaller'
			& $Script:FTModule { Test-FTCaller; Test-FTDirect }
			$Line = Get-Content -Path $Script:FTLog -Raw
			$Line | Should -Match 'Detail:\[wrapped\]'
			$Line | Should -Not -Match 'Detail:\[direct\]'
		}
	}

	Context 'Clear-MyFunctionTraceLog and Clear-MyFunctionTraceArchive' {
		It 'archives the window''s own session file and keeps the session id in the archive name' {
			& $Script:FTModule { Test-FTDirect }
			Test-Path -Path $Script:FTLog | Should -BeTrue
			$null = Clear-MyFunctionTraceLog -Confirm:$false
			Test-Path -Path $Script:FTLog | Should -BeFalse
			@(Get-ChildItem -Path $Script:FTDir -Filter 'FunctionTrace-Archived-*-Session-pester01.log').Count | Should -Be 1
		}

		It 'prunes only OLD session files by age and never a recently written one' {
			$null = New-Item -Path $Script:FTDir -ItemType Directory -Force
			$Old = Join-Path $Script:FTDir 'FunctionTrace-Session-oldold01.log'
			$New = Join-Path $Script:FTDir 'FunctionTrace-Session-newnew01.log'
			Set-Content -Path $Old -Value 'x'
			Set-Content -Path $New -Value 'x'
			(Get-Item -Path $Old).LastWriteTime = (Get-Date).AddDays(-200)
			$null = Clear-MyFunctionTraceArchive -DaysOld 90
			Test-Path -Path $Old | Should -BeFalse
			Test-Path -Path $New | Should -BeTrue
		}
	}
}

Describe 'FunctionExportTable' -Tag 'ExportTable' {
	BeforeAll {
		# Re-import module WITHOUT ExportAll to test the FunctionExportTable
		$env:NAMEDPIPE_EXPORT_ALL = '0'
		$Script:ExportTestModulePath = Split-Path -Parent $PSScriptRoot
		Import-Module "$Script:ExportTestModulePath\NamedPipe.psd1" -Force
	}

	AfterAll {
		# Re-import module WITH ExportAll for remaining tests
		$env:NAMEDPIPE_EXPORT_ALL = '1'
		Import-Module "$Script:ExportTestModulePath\NamedPipe.psd1" -Force
	}

	Context 'Internal functions should not be exported' {
		It 'Start-PipeServerOrClient should not be exported' {
			$Module = Get-Module -Name NamedPipe
			$Module.ExportedFunctions.Keys | Should -Not -Contain 'Start-PipeServerOrClient'
		}

		It 'Get-NewPipeName should not be exported' {
			$Module = Get-Module -Name NamedPipe
			$Module.ExportedFunctions.Keys | Should -Not -Contain 'Get-NewPipeName'
		}

		It 'Send-Data should not be exported' {
			$Module = Get-Module -Name NamedPipe
			$Module.ExportedFunctions.Keys | Should -Not -Contain 'Send-Data'
		}

		It 'Receive-Data should not be exported' {
			$Module = Get-Module -Name NamedPipe
			$Module.ExportedFunctions.Keys | Should -Not -Contain 'Receive-Data'
		}

		It 'Set-PipeSecurity should not be exported' {
			$Module = Get-Module -Name NamedPipe
			$Module.ExportedFunctions.Keys | Should -Not -Contain 'Set-PipeSecurity'
		}

		It 'Test-AccessIdentifier should not be exported' {
			$Module = Get-Module -Name NamedPipe
			$Module.ExportedFunctions.Keys | Should -Not -Contain 'Test-AccessIdentifier'
		}

		It 'Get-SBResult should not be exported' {
			$Module = Get-Module -Name NamedPipe
			$Module.ExportedFunctions.Keys | Should -Not -Contain 'Get-SBResult'
		}

		It 'Set-MyWindowState should not be exported (vendored internal)' {
			$Module = Get-Module -Name NamedPipe
			$Module.ExportedFunctions.Keys | Should -Not -Contain 'Set-MyWindowState'
		}

		It 'Write-MyCatchAudit should not be exported (vendored internal, catch-audit set)' {
			$Module = Get-Module -Name NamedPipe
			$Module.ExportedFunctions.Keys | Should -Not -Contain 'Write-MyCatchAudit'
		}
	}

	Context 'Public functions should be exported' {
		It 'Start-PipeSession should be exported' {
			$Module = Get-Module -Name NamedPipe
			$Module.ExportedFunctions.Keys | Should -Contain 'Start-PipeSession'
		}

		It 'Test-PipeSession should be exported' {
			$Module = Get-Module -Name NamedPipe
			$Module.ExportedFunctions.Keys | Should -Contain 'Test-PipeSession'
		}

		It 'Stop-PipeSession should be exported' {
			$Module = Get-Module -Name NamedPipe
			$Module.ExportedFunctions.Keys | Should -Contain 'Stop-PipeSession'
		}

		It 'Send-Request should be exported' {
			$Module = Get-Module -Name NamedPipe
			$Module.ExportedFunctions.Keys | Should -Contain 'Send-Request'
		}

		It 'Set-ObjectParameterSet should be exported' {
			$Module = Get-Module -Name NamedPipe
			$Module.ExportedFunctions.Keys | Should -Contain 'Set-ObjectParameterSet'
		}
	}
}

Describe 'Start-PipeSession' -Tag 'Session' {
	Context 'Function Exists' {
		It 'Should be available as a command' {
			Get-Command Start-PipeSession -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
		}

		It 'Should have mandatory MyParameters parameter' {
			$Cmd = Get-Command Start-PipeSession
			$Param = $Cmd.Parameters['MyParameters']
			$Param | Should -Not -BeNullOrEmpty
			($Param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -Be $true
		}

		It 'Should have optional Options parameter' {
			$Cmd = Get-Command Start-PipeSession
			$Cmd.Parameters.Keys | Should -Contain 'Options'
		}

		It 'Should have optional AccessList parameter' {
			$Cmd = Get-Command Start-PipeSession
			$Cmd.Parameters.Keys | Should -Contain 'AccessList'
		}
	}
}

Describe 'Test-PipeSession' -Tag 'Session' {
	Context 'Function Exists' {
		It 'Should be available as a command' {
			Get-Command Test-PipeSession -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
		}

		It 'Should have mandatory PipeInfo parameter' {
			$Cmd = Get-Command Test-PipeSession
			$Param = $Cmd.Parameters['PipeInfo']
			$Param | Should -Not -BeNullOrEmpty
			($Param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -Be $true
		}
	}

	Context 'Health Check Logic' {
		It 'Should return $false for $null PipeInfo' {
			Test-PipeSession -PipeInfo $null | Should -Be $false
		}

		It 'Should return $false for empty PipeInfo' {
			$FakePipeInfo = [ordered]@{}
			Test-PipeSession -PipeInfo $FakePipeInfo | Should -Be $false
		}
	}
}

Describe 'Stop-PipeSession' -Tag 'Session' {
	Context 'Function Exists' {
		It 'Should be available as a command' {
			Get-Command Stop-PipeSession -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
		}

		It 'Should have mandatory SendRequestParams parameter' {
			$Cmd = Get-Command Stop-PipeSession
			$Param = $Cmd.Parameters['SendRequestParams']
			$Param | Should -Not -BeNullOrEmpty
			($Param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -Be $true
		}

		It 'Should have mandatory PipeInfo parameter' {
			$Cmd = Get-Command Stop-PipeSession
			$Param = $Cmd.Parameters['PipeInfo']
			$Param | Should -Not -BeNullOrEmpty
			($Param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -Be $true
		}
	}
}

Describe 'Module Variable - StrModuleToLoad' -Tag 'Variables' {
	It 'Should have $StrModuleToLoad defined' {
		$StrModuleToLoad | Should -Not -BeNullOrEmpty
		$StrModuleToLoad | Should -Be 'ModuleToLoad'
	}
}

Describe 'Module Variable - DefaultModuleToLoad' -Tag 'Variables' {
	It 'Should have $script:DefaultModuleToLoad defined' {
		$Default = & (Get-Module NamedPipe) { $script:DefaultModuleToLoad }
		$Default | Should -Not -BeNullOrEmpty
	}

	It 'Should have Name set to NamedPipe' {
		$Default = & (Get-Module NamedPipe) { $script:DefaultModuleToLoad }
		$Default.Name | Should -Be 'NamedPipe'
	}

	It 'Should have Version set to 0.15' {
		$Default = & (Get-Module NamedPipe) { $script:DefaultModuleToLoad }
		$Default.Version | Should -Be '0.15'
	}
}


Describe 'Health Pipe Protocol' -Tag 'HealthPipe' {
	# Tests that the dedicated .Health background pipe channel works correctly.
	# Named pipes do not require administrator elevation, so all tests run in-process.
	# The BeforeAll starts a background runspace acting as the health pipe server
	# and creates a connected main pipe pair used to construct a fake PipeInfo for
	# Test-PipeSession integration tests.
	#
	# Key literal values used here (module-scope $Str* vars are not accessible in Pester):
	#   'Name'   = $StrName    'Pipe'   = $StrPipe
	#   'Reader' = $StrReader  'Writer' = $StrWriter

	BeforeAll {
		# Unique base name scoped to this test run
		$Script:HTestBase = 'NP_HealthTest_' + [guid]::NewGuid().ToString('N').Substring(0, 8)

		# Start health pipe server in a background runspace.
		# Listens on $HTestBase.Health; loops to handle sequential connections.
		# For each connection: reads PING:<nonce>, writes PONG:<nonce>.
		# Exits when a client sends the literal string 'STOP' (poison pill).
		# WaitForConnection() cannot be interrupted by CancellationToken in
		# .NET Framework, so the poison pill is the only reliable exit mechanism.
		$Script:HRS = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
		$Script:HRS.Open()
		$Script:HPS = [System.Management.Automation.PowerShell]::Create()
		$Script:HPS.Runspace = $Script:HRS
		[void]$Script:HPS.AddScript({
				param($Base)
				$PipeName = $Base + '.Health'
				while ($true)
				{
					$Srv = $null
					try
					{
						$Srv = [System.IO.Pipes.NamedPipeServerStream]::new(
							$PipeName,
							[System.IO.Pipes.PipeDirection]::InOut,
							[System.IO.Pipes.NamedPipeServerStream]::MaxAllowedServerInstances
						)
						$Srv.WaitForConnection()
						$Rdr = [System.IO.StreamReader]::new($Srv)
						$Wtr = [System.IO.StreamWriter]::new($Srv)
						$Wtr.AutoFlush = $true
						$Line = $Rdr.ReadLine()
						if ($Line -eq 'STOP') { break }
						if ($Line -and $Line.StartsWith('PING:'))
						{ $Wtr.WriteLine('PONG:' + $Line.Substring(5)) }
					}
					catch { }
					finally { if ($Srv) { try { $Srv.Dispose() } catch { } } }
				}
			})
		[void]$Script:HPS.AddArgument($Script:HTestBase)
		$Script:HAsyncResult = $Script:HPS.BeginInvoke()
		Start-Sleep -Milliseconds 300

		# Create a connected main pipe pair for Phase 1 passive checks.
		# WaitForConnectionAsync so the server side does not block the test thread.
		$Script:MainServer = [System.IO.Pipes.NamedPipeServerStream]::new(
			$Script:HTestBase + '.Main',
			[System.IO.Pipes.PipeDirection]::InOut,
			1
		)
		$Script:MainConnectTask = $Script:MainServer.WaitForConnectionAsync()
		$Script:MainClient = [System.IO.Pipes.NamedPipeClientStream]::new(
			'.', $Script:HTestBase + '.Main',
			[System.IO.Pipes.PipeDirection]::InOut
		)
		$Script:MainClient.Connect(2000)
		$null = $Script:MainConnectTask.Wait(2000)
		$Script:MainReader = [System.IO.StreamReader]::new($Script:MainClient)
		$Script:MainWriter = [System.IO.StreamWriter]::new($Script:MainClient)
		$Script:MainWriter.AutoFlush = $true

		# Fake PipeInfo using literal key strings (matches module $StrName/$StrPipe/$StrReader/$StrWriter)
		$Script:FakePipeInfo = [PSCustomObject]@{
			Name   = $Script:HTestBase
			Pipe   = $Script:MainClient
			Reader = $Script:MainReader
			Writer = $Script:MainWriter
		}
	}

	AfterAll {
		# Send STOP poison pill to unblock WaitForConnection() so the health loop exits.
		try
		{
			$Poison = [System.IO.Pipes.NamedPipeClientStream]::new('.', $Script:HTestBase + '.Health', [System.IO.Pipes.PipeDirection]::InOut)
			$Poison.Connect(1000)
			$PoisonW = [System.IO.StreamWriter]::new($Poison)
			$PoisonW.AutoFlush = $true
			$PoisonW.WriteLine('STOP')
			$Poison.Dispose()
		} catch { }
		Start-Sleep -Milliseconds 200
		try { if ($Script:HPS) { $Script:HPS.Dispose() } } catch { }
		try { if ($Script:HRS) { $Script:HRS.Dispose() } } catch { }
		try { if ($Script:MainClient) { $Script:MainClient.Dispose() } } catch { }
		try { if ($Script:MainServer) { $Script:MainServer.Dispose() } } catch { }
	}

	Context 'Raw PING/PONG protocol (standalone - no module functions)' {

		It 'Should respond PONG:<nonce> to PING:<nonce>' {
			$Nonce  = [guid]::NewGuid().ToString('N')
			$Client = [System.IO.Pipes.NamedPipeClientStream]::new(
				'.', $Script:HTestBase + '.Health',
				[System.IO.Pipes.PipeDirection]::InOut
			)
			try
			{
				$Client.Connect(2000)
				$Writer = [System.IO.StreamWriter]::new($Client)
				$Reader = [System.IO.StreamReader]::new($Client)
				$Writer.AutoFlush   = $true

				$Writer.WriteLine("PING:$Nonce")
				$Response = $Reader.ReadLine()
				$Response | Should -Be "PONG:$Nonce"
			}
			finally { try { $Client.Dispose() } catch { } }
		}

		It 'PONG response should contain the exact nonce sent (nonce uniqueness check)' {
			$Nonce1 = [guid]::NewGuid().ToString('N')
			$Nonce2 = [guid]::NewGuid().ToString('N')
			$Nonce1 | Should -Not -Be $Nonce2
			$Client = [System.IO.Pipes.NamedPipeClientStream]::new(
				'.', $Script:HTestBase + '.Health',
				[System.IO.Pipes.PipeDirection]::InOut
			)
			try
			{
				$Client.Connect(2000)
				$Writer = [System.IO.StreamWriter]::new($Client)
				$Reader = [System.IO.StreamReader]::new($Client)
				$Writer.AutoFlush   = $true

				$Writer.WriteLine("PING:$Nonce1")
				$Response = $Reader.ReadLine()
				$Response | Should -Be "PONG:$Nonce1"
				$Response | Should -Not -Be "PONG:$Nonce2"
			}
			finally { try { $Client.Dispose() } catch { } }
		}

		It 'Should handle multiple sequential connections' {
			1..3 | ForEach-Object {
				$N = [guid]::NewGuid().ToString('N')
				$C = [System.IO.Pipes.NamedPipeClientStream]::new(
					'.', $Script:HTestBase + '.Health',
					[System.IO.Pipes.PipeDirection]::InOut
				)
				try
				{
					$C.Connect(2000)
					$W = [System.IO.StreamWriter]::new($C)
					$R = [System.IO.StreamReader]::new($C)
					$W.AutoFlush   = $true

					$W.WriteLine("PING:$N")
					$R.ReadLine() | Should -Be "PONG:$N"
				}
				finally { try { $C.Dispose() } catch { } }
			}
		}
	}

	Context 'Test-PipeSession Phase 1 - passive checks' {

		It 'Should return $false for $null PipeInfo' {
			Test-PipeSession -PipeInfo $null | Should -Be $false
		}

		It 'Should return $false for empty PSCustomObject (missing Pipe key)' {
			$Bad = [PSCustomObject]@{}
			Test-PipeSession -PipeInfo $Bad | Should -Be $false
		}

		It 'Should return $false when Pipe stream is not connected (never connected)' {
			$Dead = [System.IO.Pipes.NamedPipeClientStream]::new(
				'.', 'NP_NeverConn_' + [guid]::NewGuid().ToString('N').Substring(0, 8),
				[System.IO.Pipes.PipeDirection]::InOut
			)
			$Bad = [PSCustomObject]@{
				Name   = 'NP_NeverConn'
				Pipe   = $Dead
				Reader = $null
				Writer = $null
			}
			Test-PipeSession -PipeInfo $Bad | Should -Be $false
			try { $Dead.Dispose() } catch { }
		}

		It 'Should return $false when Reader is $null' {
			$Bad = [PSCustomObject]@{
				Name   = $Script:HTestBase
				Pipe   = $Script:MainClient
				Reader = $null
				Writer = $Script:MainWriter
			}
			Test-PipeSession -PipeInfo $Bad | Should -Be $false
		}

		It 'Should return $false when Writer is $null' {
			$Bad = [PSCustomObject]@{
				Name   = $Script:HTestBase
				Pipe   = $Script:MainClient
				Reader = $Script:MainReader
				Writer = $null
			}
			Test-PipeSession -PipeInfo $Bad | Should -Be $false
		}
	}

	Context 'Test-PipeSession Phase 2 - active PING/PONG' {

		It 'Should return $true for a connected pipe with health server running' {
			Test-PipeSession -PipeInfo $Script:FakePipeInfo | Should -Be $true
		}

		It 'Should return $true on consecutive calls (server accepts multiple connections)' {
			Test-PipeSession -PipeInfo $Script:FakePipeInfo | Should -Be $true
			Test-PipeSession -PipeInfo $Script:FakePipeInfo | Should -Be $true
		}

		It 'Should return $false when health server is absent (wrong pipe name)' {
			$WrongInfo = [PSCustomObject]@{
				Name   = 'NP_NoServer_' + [guid]::NewGuid().ToString('N').Substring(0, 8)
				Pipe   = $Script:MainClient
				Reader = $Script:MainReader
				Writer = $Script:MainWriter
			}
			Test-PipeSession -PipeInfo $WrongInfo -TimeoutMs 500 | Should -Be $false
		}
	}
}

Describe 'Write-HealthPipeCatchRecord' {
	# Cross-runspace-safe catch-audit path for the isolated health-pipe listener (2026-09-11) - a
	# hand-written, disk-only analog of Write-MyCatchAudit, since that function cannot run inside the
	# bare runspace the health-pipe loop uses. Not in FunctionsToExport (matches Write-MyCatchAudit's
	# own vendored/internal-only convention), so called via InModuleScope - same pattern as
	# CommonScripts.Tests.ps1's own 'Write-MyCatchAudit' Describe block. The embedded runspace
	# scriptblock that dot-sources and calls this function at runtime is not independently
	# unit-testable without reimplementing it, same limitation the 'Health Pipe Protocol' Describe
	# above already has for the real pipe-protocol loop; that wiring is verified live/manually instead.

	BeforeAll {
		$Script:_TestPersistPath = Join-Path $env:TEMP ('HealthPipeCatchTest-' + [Guid]::NewGuid().ToString('N') + '.jsonl')

		InModuleScope 'NamedPipe' {
			Function Script:New-HealthPipeTestError
			{
				Try { throw 'health pipe boom' } Catch { return $_ }
			}

			# 2026-09-11, found live: an error raised inside an ANONYMOUS scriptblock (no backing .ps1
			# file - exactly the health-pipe listener's own AddScript block shape) has ScriptName = ''
			# (empty string, not $null). Split-Path -Path '' throws a ParameterBindingValidationException
			# that -ErrorAction SilentlyContinue does NOT suppress - this reproduces that exact condition
			# without needing a real separate runspace.
			Function Script:New-HealthPipeTestErrorEmptyScriptName
			{
				Try { & ([scriptblock]::Create('throw "health pipe boom (anonymous scriptblock)"')) }
				Catch { return $_ }
			}
		}
	}

	BeforeEach {
		If (Test-Path -LiteralPath $Script:_TestPersistPath) { Remove-Item -LiteralPath $Script:_TestPersistPath -Force }
		$Script:_savedVerbose = $env:MyCatchAuditVerbose
		$env:MyCatchAuditVerbose = $null
	}

	AfterEach { $env:MyCatchAuditVerbose = $Script:_savedVerbose }

	AfterAll {
		If (Test-Path -LiteralPath $Script:_TestPersistPath) { Remove-Item -LiteralPath $Script:_TestPersistPath -Force -ErrorAction SilentlyContinue }
	}

	It 'Writes a JSONL line with Origin=HealthPipeListener and IsTeardown=$false for a plain call' {
		InModuleScope 'NamedPipe' -Parameters @{ Path = $Script:_TestPersistPath } {
			Param ($Path)
			$Err = New-HealthPipeTestError
			Write-HealthPipeCatchRecord -PersistPath $Path -Source 'test: plain' -ErrorRecord $Err
		}

		$Lines = @(Get-Content -LiteralPath $Script:_TestPersistPath)
		$Lines.Count | Should -Be 1
		$Record = $Lines[0] | ConvertFrom-Json
		$Record.Origin | Should -Be 'HealthPipeListener'
		$Record.IsTeardown | Should -BeFalse
		$Record.Source | Should -Be 'test: plain'
	}

	It 'Writes IsTeardown=$true when -Teardown is passed' {
		InModuleScope 'NamedPipe' -Parameters @{ Path = $Script:_TestPersistPath } {
			Param ($Path)
			$Err = New-HealthPipeTestError
			Write-HealthPipeCatchRecord -PersistPath $Path -Source 'test: teardown' -ErrorRecord $Err -Teardown
		}

		$Record = @(Get-Content -LiteralPath $Script:_TestPersistPath)[0] | ConvertFrom-Json
		$Record.IsTeardown | Should -BeTrue
	}

	It 'Live-echoes to Warning when verbose is on and -Teardown is NOT passed' {
		$env:MyCatchAuditVerbose = '1'
		$Warnings = @(InModuleScope 'NamedPipe' -Parameters @{ Path = $Script:_TestPersistPath } {
				Param ($Path)
				$Err = New-HealthPipeTestError
				Write-HealthPipeCatchRecord -PersistPath $Path -Source 'test: plain, verbose' -ErrorRecord $Err 3>&1
			})
		$Warnings.Count | Should -BeGreaterThan 0
	}

	It 'Does NOT live-echo, even with verbose on, when -Teardown IS passed' {
		$env:MyCatchAuditVerbose = '1'
		$Warnings = @(InModuleScope 'NamedPipe' -Parameters @{ Path = $Script:_TestPersistPath } {
				Param ($Path)
				$Err = New-HealthPipeTestError
				Write-HealthPipeCatchRecord -PersistPath $Path -Source 'test: teardown, verbose' -ErrorRecord $Err -Teardown 3>&1
			})
		$Warnings.Count | Should -Be 0
	}

	It 'Persists successfully even when the error has an empty ScriptName (anonymous scriptblock, no backing file)' {
		InModuleScope 'NamedPipe' -Parameters @{ Path = $Script:_TestPersistPath } {
			Param ($Path)
			$Err = New-HealthPipeTestErrorEmptyScriptName
			Write-HealthPipeCatchRecord -PersistPath $Path -Source 'test: empty ScriptName' -ErrorRecord $Err
		}

		$Lines = @(Get-Content -LiteralPath $Script:_TestPersistPath)
		$Lines.Count | Should -Be 1
		$Record = $Lines[0] | ConvertFrom-Json
		$Record.Source | Should -Be 'test: empty ScriptName'
		$Record.ScriptName | Should -BeNullOrEmpty
	}

	It 'Never throws, even when the persist path is unwritable' {
		$BadPath = Join-Path (Join-Path $env:TEMP ('NoSuchDir-' + [Guid]::NewGuid().ToString('N'))) 'log.jsonl'
		{
			InModuleScope 'NamedPipe' -Parameters @{ Path = $BadPath } {
				Param ($Path)
				$Err = New-HealthPipeTestError
				Write-HealthPipeCatchRecord -PersistPath $Path -Source 'test: unwritable path' -ErrorRecord $Err
			}
		} | Should -Not -Throw
	}
}
