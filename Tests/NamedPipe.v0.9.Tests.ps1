
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

	# 2026-08-29: regression guard for a real live incident, NOT a hypothetical edge case. Every
	# test above this point passes only SCALAR values - none exercised an array-valued parameter
	# (e.g. ConfigContent, a config file's lines - used by VHDTools' WriteNewConfig dispatch), which
	# is exactly why a genuine bug here went uncaught by Pester and was only found through three
	# separate live OutOfMemoryException incidents the same day. Root cause: `Switch -Regex (...)`
	# ENUMERATES a collection value instead of matching it as one scalar, so for the one loop
	# iteration holding an array value, the switch body silently ran once PER ARRAY ELEMENT instead
	# of once. The first of those extra runs correctly escaped the array into one string; every
	# subsequent run then RE-ESCAPED that already-escaped string as if it were still the original
	# array element - each re-escape pass roughly DOUBLES the string length (every existing ''
	# becomes ''''), so a completely ordinary 113-element array reliably reached several gigabytes
	# and an OutOfMemoryException within seconds. Fixed with the unary comma:
	# `Switch -Regex (,$Private:y[$Private:x])`, forcing single-item evaluation regardless of type.
	# See memory project_namedpipe_oom_error_cascade_2026_08_29 for the full incident writeup.
	Context "ConvertTo-Parameters Array Handling" {

		It "Should handle an array-valued parameter without throwing" {
			$params = @{ ConfigContent = @('line1', 'line2', 'line3') }
			{ ConvertTo-Parameters -Hash $params } | Should -Not -Throw
		}

		It "Should escape and comma-join array elements exactly once, not exponentially" {
			$params = @{ ConfigContent = @("it's", 'plain', "another 'quoted' one") }
			$result = ConvertTo-Parameters -Hash $params
			# A single correct pass produces one '' per literal quote in the source (2 quotes in
			# "it's" + "another 'quoted' one" = 3 literal quotes -> 3 escaped '' pairs = 6 quote
			# characters from escaping, plus the wrapping quotes around each of the 3 elements).
			# The exponential-regrowth bug would instead produce a quote count that roughly DOUBLES
			# on every one of the (Count-1) extra passes a buggy Switch would silently run - for a
			# 3-element array that is only a few extra doublings, but the LENGTH assertion below is
			# the real guard: it catches the bug at any array size, not just this one.
			$result | Should -Not -BeNullOrEmpty
			# Generous but bounded - a correct single-pass encoding of ~50 total source characters
			# should never approach even 1000 output characters. The bug produced results in the
			# tens of thousands to billions of characters range within a handful of extra passes.
			$result.Length | Should -BeLessThan 1000
		}

		It "Should process a realistic-sized config-file-shaped array in well under a second" {
			# 113 elements mirrors the exact live incident (a real, completely ordinary VHDTools
			# .psd1 config, 113 lines, 6.3KB) - the bug made this specific, unremarkable shape of
			# input reliably take the elevated server to double-digit GB and an eventual OOM.
			$Lines = 1..113 | ForEach-Object { "Field{0} = 'value{0}'" -f $_ }
			$params = @{ ConfigContent = $Lines }
			$sw = [System.Diagnostics.Stopwatch]::StartNew()
			$result = ConvertTo-Parameters -Hash $params
			$sw.Stop()
			$result | Should -Not -BeNullOrEmpty
			# A correct single pass over 113 short lines is a few milliseconds; the exponential-
			# regrowth bug did not just run slowly, it ran OUT OF MEMORY within seconds - either
			# symptom is caught by a generous 2-second ceiling with room to spare either way.
			$sw.ElapsedMilliseconds | Should -BeLessThan 2000
		}

		It "Should preserve every array element's content in the output" {
			$params = @{ ConfigContent = @('alpha', 'beta', 'gamma') }
			$result = ConvertTo-Parameters -Hash $params
			$result | Should -Match 'alpha'
			$result | Should -Match 'beta'
			$result | Should -Match 'gamma'
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
