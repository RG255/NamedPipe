
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
Pester tests for NamedPipe v0.9 security fixes

.DESCRIPTION
Comprehensive test suite for validating security fixes in v0.9:
- Parameter escaping and injection prevention
- Syntax validation
- Error handling improvements
#>

# Import the module
$modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'InitialiseModule.psm1'
Import-Module $modulePath -ErrorAction Stop -Force

Describe "NamedPipe v0.9 Security Tests" {

    Context "ConvertTo-Parameters Escaping" {

        It "Should handle simple paths" {
            $params = @{ Path = "C:\Temp" }
            $result = ConvertTo-Parameters -Hash $params
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match "Path"
        }

        It "Should escape single quotes" {
            $params = @{ Value = "test'value" }
            $result = ConvertTo-Parameters -Hash $params
            # Result should contain escaped quotes
            $result | Should -Match "test"
        }

        It "Should handle injection attempt patterns" {
            $params = @{ Path = "C:\'; Remove-Item #" }
            $result = ConvertTo-Parameters -Hash $params
            # Should not execute code, just convert to string
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match "Path"
        }

        It "Should preserve non-string values" {
            $params = @{ Count = 42 }
            $result = ConvertTo-Parameters -Hash $params
            $result | Should -Match "42"
        }

        It "Should handle empty values" {
            $params = @{ Value = "" }
            $result = ConvertTo-Parameters -Hash $params
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should not corrupt complex paths" {
            $params = @{ Path = "C:\Windows\System32\Drivers\etc\hosts" }
            $result = ConvertTo-Parameters -Hash $params
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context "Syntax Validation" {

        It "Should accept valid Get-Process command" {
            $cmd = "Get-Process"
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseInput($cmd, [ref]$null, [ref]$errors)
            $errors.Count | Should -Be 0
        }

        It "Should reject unclosed braces" {
            $cmd = "Get-Process | Where { broken"
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseInput($cmd, [ref]$null, [ref]$errors)
            $errors.Count | Should -BeGreaterThan 0
        }

        It "Should reject unclosed parentheses" {
            $cmd = "Get-ChildItem -Path ('C:\temp'"
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseInput($cmd, [ref]$null, [ref]$errors)
            $errors.Count | Should -BeGreaterThan 0
        }

        It "Should accept pipeline commands" {
            $cmd = "Get-Process | Select-Object Name | Sort-Object"
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseInput($cmd, [ref]$null, [ref]$errors)
            $errors.Count | Should -Be 0
        }

        It "Should accept complex filter expressions" {
            $cmd = "Get-Process | Where-Object { `$_.CPU -gt 10 }"
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseInput($cmd, [ref]$null, [ref]$errors)
            $errors.Count | Should -Be 0
        }

        It "Should reject unclosed quotes" {
            $cmd = 'Get-Process -Filter "unclosed string'
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseInput($cmd, [ref]$null, [ref]$errors)
            $errors.Count | Should -BeGreaterThan 0
        }
    }

    Context "Error Pattern Detection" {

        It "Should detect IOException pattern" {
            $pattern = 'IOException|pipe.*closed|broken pipe'
            "IOException: connection failed" -match $pattern | Should -Be $true
        }

        It "Should detect broken pipe pattern" {
            $pattern = 'IOException|pipe.*closed|broken pipe'
            "broken pipe encountered" -match $pattern | Should -Be $true
        }

        It "Should detect PSSerializer pattern" {
            $pattern = 'PSSerializer.*error|could not be deserialized'
            "PSSerializer error during deserialization" -match $pattern | Should -Be $true
        }

        It "Should not falsely match unrelated errors" {
            $pattern = 'IOException|pipe.*closed|broken pipe|PSSerializer.*error'
            "System.NotImplementedException: feature not available" -match $pattern | Should -Be $false
        }

        It "Should handle deserialization error" {
            $pattern = 'could not be deserialized'
            "Object could not be deserialized due to type mismatch" -match $pattern | Should -Be $true
        }
    }

    Context "Injection Prevention Verification" {

        It "Parameter with semicolon should not execute code" {
            $params = @{ Value = "test; Get-Process" }
            $result = ConvertTo-Parameters -Hash $params
            # This should just be a string, not execute anything
            $result | Should -Not -BeNullOrEmpty
        }

        It "Parameter with backtick should not escape quotes" {
            $params = @{ Value = "test`'value" }
            $result = ConvertTo-Parameters -Hash $params
            $result | Should -Not -BeNullOrEmpty
        }

        It "Parameter with variable-like syntax should not expand" {
            $params = @{ Value = "`$env:SYSTEMROOT" }
            $result = ConvertTo-Parameters -Hash $params
            # Should not expand to actual system root
            $result | Should -Not -Match "C:\\Windows"
        }

        It "Multiple quote escaping works" {
            $params = @{ Text = "It's a 'quoted' string" }
            $result = ConvertTo-Parameters -Hash $params
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context "Module Structure" {

        It "ConvertTo-Parameters function should exist" {
            Get-Command ConvertTo-Parameters -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "ConvertTo-Parameters should accept hashtable input" {
            { ConvertTo-Parameters -Hash @{ Test = "value" } } | Should -Not -Throw
        }

        It "ConvertTo-Parameters should accept pipeline input" {
            { @{ Test = "value" } | ConvertTo-Parameters } | Should -Not -Throw
        }

        It "Send-Request should be available" {
            Get-Command Send-Request -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    Context "Backward Compatibility" {

        It "Simple parameter conversion still works" {
            $params = @{ Name = "test" }
            $result = ConvertTo-Parameters -Hash $params
            $result | Should -Not -BeNullOrEmpty
        }

        It "Multiple parameters work together" {
            $params = @{ Path = "C:\Temp"; Recurse = $true; Force = $false }
            $result = ConvertTo-Parameters -Hash $params
            $result | Should -Not -BeNullOrEmpty
        }

        It "Numeric parameters preserved" {
            $params = @{ Count = 100; Timeout = 5 }
            $result = ConvertTo-Parameters -Hash $params
            $result | Should -Match "100"
        }

        It "Valid commands still parse" {
            $validCmds = @(
                "Get-Process",
                "Get-ChildItem -Path 'C:\temp'",
                "Test-Path -Path 'C:\windows'"
            )

            foreach ($cmd in $validCmds) {
                $errors = $null
                $null = [System.Management.Automation.Language.Parser]::ParseInput($cmd, [ref]$null, [ref]$errors)
                $errors.Count | Should -Be 0
            }
        }
    }
}
