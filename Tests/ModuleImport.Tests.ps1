#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
    .SYNOPSIS
    Pester tests for the module loader (InitialiseModule.psm1): a variable that cannot be created stops the import with a clear
    error, and each operating-system loop tests its own information flag.

    .DESCRIPTION
    The import tests run in child processes of the current host against a throwaway copy of the module (code folders only), so
    nothing here touches the loaded module, the deployed copy or the real catch-audit locations.

    Run with: Invoke-Pester -Path .\ModuleImport.Tests.ps1 -Output Detailed
#>

BeforeAll {
	$Script:ModulePath = Split-Path -Parent $PSScriptRoot
	$Script:HostExe = (Get-Process -Id $PID).Path
	$Script:Scratch = Join-Path ([System.IO.Path]::GetTempPath()) ('np18imp-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
	# Module name and version come from the folder names, so the copy keeps <Scratch>\<case>\NamedPipe\0.18.
	$Script:NewCopy = {
		param([string]$Case)
		$Dest = Join-Path (Join-Path (Join-Path $Script:Scratch $Case) 'NamedPipe') '0.18'
		$null = New-Item -ItemType Directory -Path $Dest -Force
		foreach ($Item in 'Functions', 'FunctionsLinux', 'FunctionsMacOS', 'FunctionsWindows', 'InitialiseModule.psm1', 'NamedPipe.psd1')
		{ Copy-Item -LiteralPath (Join-Path $Script:ModulePath $Item) -Destination $Dest -Recurse -Force }
		$Dest
	}
	$Script:ImportInChild = {
		param([string]$Manifest)
		$Cmd = "try { Import-Module -Name '$Manifest' -Force -ErrorAction Stop -WarningAction SilentlyContinue; 'COUNTS ' + (Get-Command -Module NamedPipe).Count + ' ' + (Get-Module NamedPipe).ExportedVariables.Count } catch { 'FAILED ' + `$_.Exception.Message; exit 3 }"
		$Out = & $Script:HostExe -NoProfile -NonInteractive -Command $Cmd 2>&1
		[pscustomobject]@{ Output = (($Out | ForEach-Object { "$_" }) -join "`n"); ExitCode = $LASTEXITCODE }
	}
}

AfterAll {
	Remove-Item -LiteralPath $Script:Scratch -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Import of the module' {
	It 'succeeds and exports the same commands and variables from a copy as from the source tree' {
		$Copy = & $Script:NewCopy 'ok'
		$Source = & $Script:ImportInChild (Join-Path $Script:ModulePath 'NamedPipe.psd1')
		$Fixture = & $Script:ImportInChild (Join-Path $Copy 'NamedPipe.psd1')
		$Source.ExitCode | Should -Be 0
		$Source.Output | Should -Match 'COUNTS \d+ \d+'
		$Fixture.Output | Should -Be $Source.Output
		$Fixture.Output -match 'COUNTS (\d+) (\d+)' | Should -BeTrue
		[int]$Matches[1] | Should -BeGreaterThan 10
		[int]$Matches[2] | Should -BeGreaterThan 20
	}
	It 'fails with an error naming the module and the variable when a variable cannot be created' {
		$Copy = & $Script:NewCopy 'broken'
		$Def = Join-Path $Copy 'Functions\DefineVariables.ps1'
		$Add = @'

$MyVars = [Ordered]@{
	N99FixtureVars = @{
		ZzFixtureBrokenVar = @{
			Value  = 1
			Scope  = 'Script'
			Option = 'NotAnOption'
		}
	}
}
Publish-Variable -Variables $MyVars
'@
		[System.IO.File]::AppendAllText($Def, $Add)
		$R = & $Script:ImportInChild (Join-Path $Copy 'NamedPipe.psd1')
		$R.ExitCode | Should -Be 3
		$R.Output | Should -Match 'FAILED Unable to initialise module: NamedPipe'
		$R.Output | Should -Match 'variable \[ZzFixtureBrokenVar\] could not be created'
		$R.Output | Should -Not -Match 'COUNTS'
	}
}

Describe 'Loader source' {
	BeforeAll {
		$Script:Ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Script:ModulePath 'InitialiseModule.psm1'), [ref]$null, [ref]$null)
		$Switch = $Script:Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.SwitchStatementAst] -and $n.Condition.Extent.Text -match 'OSVersion' }, $true)[0]
		$Script:OsFlags = @{}
		foreach ($Clause in $Switch.Clauses)
		{
			$Flags = $Clause.Item2.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] -and $n.VariablePath.UserPath -match '^F[A-Z]?InfoOn$' }, $true) |
				ForEach-Object { $_.VariablePath.UserPath } | Sort-Object -Unique
			$Script:OsFlags[$Clause.Item1.Extent.Text] = @($Flags)
		}
	}
	It 'has a clause for each of Windows, Linux and macOS' {
		$Script:OsFlags.Keys | Sort-Object | Should -Be @('2', '4', '6')
	}
	It 'tests only the Windows flag in the Windows loop' { $Script:OsFlags['2'] | Should -Be @('FWInfoOn') }
	It 'tests only the Linux flag in the Linux loop' { $Script:OsFlags['4'] | Should -Be @('FLInfoOn') }
	It 'tests only the macOS flag in the macOS loop' { $Script:OsFlags['6'] | Should -Be @('FMInfoOn') }
	It 'defines every flag the loops test' {
		$Def = Get-Content -LiteralPath (Join-Path $Script:ModulePath 'Functions\DefineVariables.ps1') -Raw
		foreach ($F in 'FInfoOn', 'FWInfoOn', 'FLInfoOn', 'FMInfoOn') { $Def | Should -Match "(?m)^\s*$F\s*=" }
	}
	It 'does not swallow a failed variable in Publish-Variable' {
		$Fn = $Script:Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Publish-Variable' }, $true)[0]
		$Catch = $Fn.FindAll({ param($n) $n -is [System.Management.Automation.Language.CatchClauseAst] }, $true)[0]
		$Throws = $Catch.FindAll({ param($n) $n -is [System.Management.Automation.Language.ThrowStatementAst] }, $true)
		@($Throws).Count | Should -BeGreaterThan 0
	}
}
