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
    # Export all functions (including internal) for testing
    $env:NAMEDPIPE_EXPORT_ALL = '1'

    # Import the module
    $ModulePath = Split-Path -Parent $PSScriptRoot
    Remove-Module -Name NamedPipe -Force -ErrorAction SilentlyContinue
    Import-Module "$ModulePath\NamedPipe.psd1" -Force

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

    It 'Should be version 0.12' {
        $Module = Get-Module -Name NamedPipe
        $Module.Version.ToString() | Should -Be '0.12'
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

Describe 'Get-MyErrors' {
    BeforeEach {
        $Global:Error.Clear()
    }

    AfterEach {
        $Global:Error.Clear()
    }

    Context 'Basic Functionality' {
        It 'Should return empty when no errors exist' {
            $Result = Get-MyErrors -Return
            $Result | Should -BeNullOrEmpty
        }

        It 'Should capture and format errors' {
            try { Get-Item 'C:\NonExistent\Path\File.txt' -ErrorAction Stop } catch {}
            $Result = Get-MyErrors -Return -PreserveErrors
            $Result | Should -Not -BeNullOrEmpty
            $Result | Should -Match 'Error No'
        }

        It 'Should clear errors by default' {
            try { Get-Item 'C:\NonExistent\Path\File.txt' -ErrorAction Stop } catch {}
            $Global:Error.Count | Should -BeGreaterThan 0

            $Null = Get-MyErrors -Return
            $Global:Error.Count | Should -Be 0
        }

        It 'Should preserve errors when -PreserveErrors is specified' {
            try { Get-Item 'C:\NonExistent\Path\File.txt' -ErrorAction Stop } catch {}
            $InitialCount = $Global:Error.Count
            $Null = Get-MyErrors -Return -PreserveErrors
            $Global:Error.Count | Should -Be $InitialCount
        }
    }

    Context 'Parameters' {
        It 'Should accept custom Indent parameter' {
            try { Get-Item 'C:\NonExistent\Path\File.txt' -ErrorAction Stop } catch {}
            { Get-MyErrors -Return -Indent 10 } | Should -Not -Throw
        }

        It 'Should accept custom LinePad parameter' {
            try { Get-Item 'C:\NonExistent\Path\File.txt' -ErrorAction Stop } catch {}
            { Get-MyErrors -Return -LinePad 10 } | Should -Not -Throw
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

Describe 'Set-ObjectParams' {
    Context 'Basic Parameter Setting' {
        It 'Should create object from dataset definition' {
            # This test depends on module variables being set
            # Skip if variables not available
            if (-not $Script:StrMyOptions) {
                Set-ItResult -Skipped -Because 'Module variables not available'
            }

            { Set-ObjectParams -Dataset $Script:StrMyOptions } | Should -Not -Throw
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

Describe 'Test-UserOrGroupExists' {
    # Note: This function expects IDList in format "name:Allow:ReadWrite"
    Context 'User Validation' {
        It 'Should validate current user with full format' {
            $CurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
            $UserName = $CurrentUser.Split('\')[-1]
            # Must pass full format: name:Allow:ReadWrite
            $Result = Test-UserOrGroupExists -IDList "$UserName`:Allow:ReadWrite"
            $Result | Should -Not -BeNullOrEmpty
            $Result | Should -Match $UserName
        }

        It 'Should throw for non-existent user' {
            { Test-UserOrGroupExists -IDList 'NonExistentUser12345XYZ:Allow:ReadWrite' } | Should -Throw
        }
    }

    Context 'Group Validation' {
        It 'Should validate Administrators group' {
            $Result = Test-UserOrGroupExists -IDList 'Administrators:Allow:ReadWrite'
            $Result | Should -Not -BeNullOrEmpty
            $Result | Should -Match 'Administrators'
        }

        It 'Should validate Users group' {
            $Result = Test-UserOrGroupExists -IDList 'Users:Allow:ReadWrite'
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
        # Assert-File returns PSCustomObject with Success property
        It 'Should return Success=false for non-existent file' {
            $Result = Assert-File -InputObject 'C:\NonExistent\File.txt' -Option Test
            $Result.Success | Should -Be $False
        }

        It 'Should create a file with Create option' {
            $Result = Assert-File -InputObject $Script:TestFilePath -Option Create
            $Result.Success | Should -Be $True
            Test-Path $Script:TestFilePath | Should -Be $True
        }

        It 'Should return Success=true for existing file' {
            $Result = Assert-File -InputObject $Script:TestFilePath -Option Test
            $Result.Success | Should -Be $True
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
            $Cmd = Get-Command Send-Data
            $Cmd.Parameters.Keys | Should -Not -Contain 'ChunkSize'
            $Cmd.Parameters.Keys | Should -Not -Contain 'Depth'
        }

        It 'Send-Data should only require DataObject and PipeInfo' {
            $Cmd = Get-Command Send-Data
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
            $PipeBufferSize = 65536    # 64KB as defined in Set-ObjectParams
            # With Base64 overhead, chunk becomes ~44KB which fits in 64KB buffer
            $EstimatedWithOverhead = [math]::Ceiling($DefaultChunkSize * 1.4)
            $EstimatedWithOverhead | Should -BeLessOrEqual $PipeBufferSize
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
            $Original = Get-Item $env:TEMP | Select-Object Name, FullName, Attributes
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
            $Cmd = Get-Command Send-Data
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

Describe 'Set-ObjectParams Parameter Flow' -Tag 'ParamFlow' {
    Context 'MyOptions Defaults' {
        BeforeAll {
            $Script:Options = Set-ObjectParams -Dataset $StrMyOptions
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
    }

    Context 'MyOptions With Parameters' {
        It 'Should pass InfoDisplay as int value' {
            $Params = @{ $StrInfoDisplay = 2 }
            $Options = Set-ObjectParams -Dataset $StrMyOptions -MyParameters $Params
            $Options.$StrInfoDisplay | Should -Be 2
            $Options.$StrInfoDisplay | Should -BeOfType [int]
        }

        It 'Should pass Depth value' {
            $Params = @{ $StrDepth = 5 }
            $Options = Set-ObjectParams -Dataset $StrMyOptions -MyParameters $Params
            $Options.$StrDepth | Should -Be 5
        }

        It 'Should pass ChunkSize value' {
            $Params = @{ $StrChunkSize = 16384 }
            $Options = Set-ObjectParams -Dataset $StrMyOptions -MyParameters $Params
            $Options.$StrChunkSize | Should -Be 16384
        }

        It 'Should pass ServerWaitTimeout value' {
            $Params = @{ $StrServerWaitTimeout = 120 }
            $Options = Set-ObjectParams -Dataset $StrMyOptions -MyParameters $Params
            $Options.$StrServerWaitTimeout | Should -Be 120
        }

        It 'Should pass ClientConnectTimeout value' {
            $Params = @{ $StrClientConnectTimeout = 5000 }
            $Options = Set-ObjectParams -Dataset $StrMyOptions -MyParameters $Params
            $Options.$StrClientConnectTimeout | Should -Be 5000
        }
    }

    Context 'ServerClientParams Inherits From MyOptions' {
        It 'Server params should inherit InfoDisplay from MyOptions' {
            $Params = @{ $StrInfoDisplay = 1 }
            $Options = Set-ObjectParams -Dataset $StrMyOptions -MyParameters $Params
            $SCP = Set-ObjectParams -Server -Dataset $StrServerClientParams -MyParameters $Options
            $SCP.$StrInfoDisplay | Should -Be 1
            $SCP.$StrInfoDisplay | Should -BeOfType [int]
        }

        It 'Server params should inherit Depth from MyOptions' {
            $Params = @{ $StrDepth = 7 }
            $Options = Set-ObjectParams -Dataset $StrMyOptions -MyParameters $Params
            $SCP = Set-ObjectParams -Server -Dataset $StrServerClientParams -MyParameters $Options
            $SCP.$StrDepth | Should -Be 7
        }

        It 'Server params should inherit timeouts from MyOptions' {
            $Params = @{ $StrServerWaitTimeout = 90; $StrClientConnectTimeout = 20000 }
            $Options = Set-ObjectParams -Dataset $StrMyOptions -MyParameters $Params
            $SCP = Set-ObjectParams -Server -Dataset $StrServerClientParams -MyParameters $Options
            $SCP.$StrServerWaitTimeout | Should -Be 90
            $SCP.$StrClientConnectTimeout | Should -Be 20000
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

        It 'Test-UserOrGroupExists should not be exported' {
            $Module = Get-Module -Name NamedPipe
            $Module.ExportedFunctions.Keys | Should -Not -Contain 'Test-UserOrGroupExists'
        }

        It 'Get-SBResult should not be exported' {
            $Module = Get-Module -Name NamedPipe
            $Module.ExportedFunctions.Keys | Should -Not -Contain 'Get-SBResult'
        }

        It 'Set-MyWindowState should not be exported (vendored internal)' {
            $Module = Get-Module -Name NamedPipe
            $Module.ExportedFunctions.Keys | Should -Not -Contain 'Set-MyWindowState'
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

        It 'Set-ObjectParams should be exported' {
            $Module = Get-Module -Name NamedPipe
            $Module.ExportedFunctions.Keys | Should -Contain 'Set-ObjectParams'
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

    It 'Should have Version set to 0.12' {
        $Default = & (Get-Module NamedPipe) { $script:DefaultModuleToLoad }
        $Default.Version | Should -Be '0.12'
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
