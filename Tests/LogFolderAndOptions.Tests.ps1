#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
    .SYNOPSIS
    Pester tests for two 0.18 changes: Set-ObjectParameterSet takes its options only through -MyOptions, and the server log folder is
    written and pruned through a handle that refuses links (Open-SafeLogFolder).

    .DESCRIPTION
    Imports the SOURCE tree of this version. Write-MyCatchAudit is mocked and APPDATA points at a throwaway folder, so nothing is
    written to the real catch-audit, spill or log locations. The junction tests need no elevation; the file symbolic-link test skips
    itself when the account may not create one. No test starts a server.

    Run with: Invoke-Pester -Path .\LogFolderAndOptions.Tests.ps1 -Output Detailed
#>

BeforeAll {
	$Script:ModulePath = Split-Path -Parent $PSScriptRoot
	$Script:Manifest = Join-Path -Path $Script:ModulePath -ChildPath 'NamedPipe.psd1'
	Remove-Module -Name NamedPipe -Force -ErrorAction SilentlyContinue
	Import-Module $Script:Manifest -Force
	Mock Write-MyCatchAudit { } -ModuleName NamedPipe
	$Script:Scratch = Join-Path ([System.IO.Path]::GetTempPath()) ('np18lf-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
	$null = New-Item -ItemType Directory -Path $Script:Scratch -Force
	$Script:SavedAppData = $env:APPDATA
	# A fresh APPDATA (with an optional victim folder a link would point at) per test.
	$Script:NewCase = {
		$Case = Join-Path $Script:Scratch ([guid]::NewGuid().ToString('N').Substring(0, 8))
		$null = New-Item -ItemType Directory -Path (Join-Path $Case 'appdata') -Force
		$null = New-Item -ItemType Directory -Path (Join-Path $Case 'victim') -Force
		[pscustomobject]@{ AppData = (Join-Path $Case 'appdata'); Victim = (Join-Path $Case 'victim'); Logs = (Join-Path (Join-Path $Case 'appdata') 'NamedPipe-Logs') }
	}
	$Script:Save = {
		InModuleScope NamedPipe {
			$Script:ServerLogSaved = $false
			$Script:ServerLogBuffer = [System.Collections.Generic.List[string]]::new()
			Save-ServerLog -Outcome 'exit-pipe' -InfoDisplay 8 -PipeName 'np-test'
		}
	}
}

AfterAll {
	$env:APPDATA = $Script:SavedAppData
	Remove-Module NamedPipe -Force -ErrorAction SilentlyContinue
	Remove-Item -LiteralPath ('\\?\' + $Script:Scratch) -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Set-ObjectParameterSet options come only from -MyOptions' {
	AfterEach {
		$env:APPDATA = $Script:SavedAppData
		InModuleScope NamedPipe { $Script:SeamAction = $null }
	}
	It 'uses the options passed with -MyOptions' {
		$S = InModuleScope NamedPipe { Set-ObjectParameterSet -Server -Dataset $StrServerClientParams -MyParameters ([pscustomobject]@{}) -MyOptions ([pscustomobject]@{ ChunkSize = 4096 }) }
		$S.ChunkSize | Should -Be 4096
	}
	It 'ignores a MyOptions variable in the caller scope when -MyOptions is not passed' {
		$global:MyOptions = [pscustomobject]@{ ChunkSize = 111; Wait = $true }
		try { $S = Set-ObjectParameterSet -Server -Dataset ServerClientParams -MyParameters ([pscustomobject]@{}) }
		finally { Remove-Variable -Name MyOptions -Scope Global -ErrorAction SilentlyContinue }
		$S.ChunkSize | Should -Be 32768
		$S.Wait | Should -BeFalse
	}
	It 'prefers -MyOptions to a MyOptions variable in the caller scope' {
		$global:MyOptions = [pscustomobject]@{ ChunkSize = 111 }
		try { $S = Set-ObjectParameterSet -Client -Dataset ServerClientParams -MyParameters ([pscustomobject]@{}) -MyOptions ([pscustomobject]@{ ChunkSize = 222 }) }
		finally { Remove-Variable -Name MyOptions -Scope Global -ErrorAction SilentlyContinue }
		$S.ChunkSize | Should -Be 222
	}
	It 'reads no caller-scope MyOptions even when -MyOptions is passed as $null' {
		$global:MyOptions = [pscustomobject]@{ ChunkSize = 111 }
		try { $S = Set-ObjectParameterSet -Server -Dataset ServerClientParams -MyParameters ([pscustomobject]@{}) -MyOptions $null }
		finally { Remove-Variable -Name MyOptions -Scope Global -ErrorAction SilentlyContinue }
		$S.ChunkSize | Should -Be 32768
	}
	It 'leaves the values taken from -MyParameters in front of -MyOptions' {
		$S = InModuleScope NamedPipe { Set-ObjectParameterSet -Server -Dataset $StrServerClientParams -MyParameters ([pscustomobject]@{ ChunkSize = 7000 }) -MyOptions ([pscustomobject]@{ ChunkSize = 4096 }) }
		$S.ChunkSize | Should -Be 7000
	}
	It 'has no module-internal caller of the ServerClientParams dataset that leaves out -MyOptions' {
		$Calls = foreach ($Dir in 'Functions', 'FunctionsWindows')
		{
			foreach ($File in Get-ChildItem -LiteralPath (Join-Path $Script:ModulePath $Dir) -Filter *.ps1)
			{
				$Ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$null, [ref]$null)
				$Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Set-ObjectParameterSet' }, $true) |
					Where-Object { $_.Extent.Text -match '-Dataset\s+\S*ServerClientParams' } |
					ForEach-Object { [pscustomobject]@{ File = $File.Name; Text = $_.Extent.Text } }
			}
		}
		@($Calls).Count | Should -BeGreaterThan 1
		foreach ($C in $Calls) { $C.Text | Should -Match '-MyOptions\b' -Because "$($C.File): $($C.Text)" }
	}
	It 'does not look up a variable named MyOptions anywhere in the function' {
		$Ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Script:ModulePath 'Functions\Set-ObjectParameterSet.ps1'), [ref]$null, [ref]$null)
		$Hits = $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -in 'Get-Variable', 'Get-Item', 'Invoke-Expression' }, $true)
		@($Hits).Count | Should -Be 0
	}
}

Describe 'Server log folder: normal operation' {
	AfterEach {
		$env:APPDATA = $Script:SavedAppData
		InModuleScope NamedPipe { $Script:SeamAction = $null }
	}
	It 'writes a log into an ordinary folder it creates, UTF-8 without a BOM' {
		$C = & $Script:NewCase
		$env:APPDATA = $C.AppData
		$R = & $Script:Save
		$R | Should -Not -BeNullOrEmpty
		(Split-Path -Parent $R) | Should -Be $C.Logs
		$Bytes = [System.IO.File]::ReadAllBytes($R)
		$Bytes[0] | Should -Not -Be 0xEF
		[System.Text.Encoding]::UTF8.GetString($Bytes) | Should -Match 'NamedPipe server diagnostics log'
	}
	It 'prunes only expired server logs' {
		$C = & $Script:NewCase
		$env:APPDATA = $C.AppData
		$null = New-Item -ItemType Directory -Path $C.Logs
		$Old = Join-Path $C.Logs 'server-old.log'; $New = Join-Path $C.Logs 'server-new.log'; $Other = Join-Path $C.Logs 'notes-old.txt'
		foreach ($F in $Old, $New, $Other) { Set-Content -LiteralPath $F -Value 'x' }
		foreach ($F in $Old, $Other) { (Get-Item -LiteralPath $F).LastWriteTime = (Get-Date).AddDays(-40) }
		InModuleScope NamedPipe { Remove-OldServerLog -RetentionDays 14 }
		Test-Path -LiteralPath $Old | Should -BeFalse
		Test-Path -LiteralPath $New | Should -BeTrue
		Test-Path -LiteralPath $Other | Should -BeTrue
	}
	It 'keeps everything when the retention is 0' {
		$C = & $Script:NewCase
		$env:APPDATA = $C.AppData
		$null = New-Item -ItemType Directory -Path $C.Logs
		$Old = Join-Path $C.Logs 'server-old.log'
		Set-Content -LiteralPath $Old -Value 'x'
		(Get-Item -LiteralPath $Old).LastWriteTime = (Get-Date).AddDays(-400)
		InModuleScope NamedPipe { Remove-OldServerLog -RetentionDays 0 }
		Test-Path -LiteralPath $Old | Should -BeTrue
	}
	It 'works when the APPDATA path is longer than 260 characters' {
		$C = & $Script:NewCase
		$Deep = $C.AppData
		while ($Deep.Length -lt 300) { $Deep = Join-Path $Deep ('segment-of-a-long-path-' + $Deep.Length) }
		$null = [System.IO.Directory]::CreateDirectory('\\?\' + $Deep)
		$env:APPDATA = $Deep
		$R = & $Script:Save
		$R | Should -Not -BeNullOrEmpty
		$R.Length | Should -BeGreaterThan 260
		[System.IO.File]::Exists('\\?\' + $R) | Should -BeTrue
		$Old = '\\?\' + (Join-Path (Join-Path $Deep 'NamedPipe-Logs') 'server-old.log')
		[System.IO.File]::WriteAllText($Old, 'x')
		[System.IO.File]::SetLastWriteTime($Old, (Get-Date).AddDays(-40))
		InModuleScope NamedPipe { Remove-OldServerLog -RetentionDays 14 }
		[System.IO.File]::Exists($Old) | Should -BeFalse
		[System.IO.File]::Exists('\\?\' + $R) | Should -BeTrue
	}
}

Describe 'Server log folder: folder that does not exist' {
	AfterEach {
		$env:APPDATA = $Script:SavedAppData
		InModuleScope NamedPipe { $Script:SeamAction = $null }
	}
	It 'is created by the writer' {
		$C = & $Script:NewCase
		$env:APPDATA = $C.AppData
		Test-Path -LiteralPath $C.Logs | Should -BeFalse
		$R = & $Script:Save
		$R | Should -Not -BeNullOrEmpty
		Test-Path -LiteralPath $C.Logs | Should -BeTrue
	}
	It 'is neither created nor reported as a failure by the pruner' {
		$C = & $Script:NewCase
		$env:APPDATA = $C.AppData
		{ InModuleScope NamedPipe { Remove-OldServerLog -RetentionDays 14 } } | Should -Not -Throw
		Test-Path -LiteralPath $C.Logs | Should -BeFalse
		Should -Invoke Write-MyCatchAudit -ModuleName NamedPipe -Times 0 -Exactly
	}
	It 'is reported as not found by Open-SafeLogFolder without -Create' {
		$C = & $Script:NewCase
		$R = InModuleScope NamedPipe -Parameters @{ P = $C.Logs } { param($P) try { Open-SafeLogFolder -Path $P; 'opened' } catch { $E = $_.Exception; if ($E.InnerException) { $E = $E.InnerException }; $E.GetType().Name } }
		$R | Should -Be 'DirectoryNotFoundException'
	}
}

Describe 'Server log folder: links are never followed' {
	AfterEach {
		$env:APPDATA = $Script:SavedAppData
		InModuleScope NamedPipe { $Script:SeamAction = $null }
	}
	It 'refuses a junction that is already in place, writes and deletes nothing, and audits it' {
		$C = & $Script:NewCase
		$env:APPDATA = $C.AppData
		Set-Content -LiteralPath (Join-Path $C.Victim 'server-old.log') -Value 'victim'
		(Get-Item -LiteralPath (Join-Path $C.Victim 'server-old.log')).LastWriteTime = (Get-Date).AddDays(-40)
		$null = New-Item -ItemType Junction -Path $C.Logs -Target $C.Victim
		try
		{
			(& $Script:Save) | Should -BeNullOrEmpty
			InModuleScope NamedPipe { Remove-OldServerLog -RetentionDays 14 }
			@(Get-ChildItem -LiteralPath $C.Victim -Force).Name | Should -Be @('server-old.log')
			Should -Invoke Write-MyCatchAudit -ModuleName NamedPipe -Times 2 -Exactly -ParameterFilter { $Source -match 'Open-SafeLogFolder' } -Scope It
		}
		finally { [System.IO.Directory]::Delete($C.Logs) }
	}
	It 'refuses a junction swapped in AFTER the folder was prepared and BEFORE it was opened (writer)' {
		$C = & $Script:NewCase
		$env:APPDATA = $C.AppData
		$null = New-Item -ItemType Directory -Path $C.Logs
		$global:NpSeamLink = $C.Logs; $global:NpSeamTarget = $C.Victim
		Mock Invoke-SafeLogFolderSeam -ModuleName NamedPipe { Remove-Item -LiteralPath $global:NpSeamLink -Force; $null = New-Item -ItemType Junction -Path $global:NpSeamLink -Target $global:NpSeamTarget }
		try
		{
			(& $Script:Save) | Should -BeNullOrEmpty
			(Get-Item -LiteralPath $C.Logs -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint | Should -Not -Be 0
			@(Get-ChildItem -LiteralPath $C.Victim -Force).Count | Should -Be 0
		}
		finally { Remove-Variable NpSeamLink, NpSeamTarget -Scope Global -ErrorAction SilentlyContinue; if (Test-Path -LiteralPath $C.Logs) { [System.IO.Directory]::Delete($C.Logs) } }
	}
	It 'refuses a junction swapped in before the open and deletes nothing through it (pruner)' {
		$C = & $Script:NewCase
		$env:APPDATA = $C.AppData
		$null = New-Item -ItemType Directory -Path $C.Logs
		$VictimFile = Join-Path $C.Victim 'server-old.log'
		Set-Content -LiteralPath $VictimFile -Value 'victim'
		(Get-Item -LiteralPath $VictimFile).LastWriteTime = (Get-Date).AddDays(-40)
		$global:NpSeamLink = $C.Logs; $global:NpSeamTarget = $C.Victim
		Mock Invoke-SafeLogFolderSeam -ModuleName NamedPipe { Remove-Item -LiteralPath $global:NpSeamLink -Force; $null = New-Item -ItemType Junction -Path $global:NpSeamLink -Target $global:NpSeamTarget }
		try
		{
			InModuleScope NamedPipe { Remove-OldServerLog -RetentionDays 14 }
			Test-Path -LiteralPath $VictimFile | Should -BeTrue
		}
		finally { Remove-Variable NpSeamLink, NpSeamTarget -Scope Global -ErrorAction SilentlyContinue; if (Test-Path -LiteralPath $C.Logs) { [System.IO.Directory]::Delete($C.Logs) } }
	}
	It 'cannot have the folder swapped, renamed or removed while it is open' {
		$C = & $Script:NewCase
		$null = New-Item -ItemType Directory -Path $C.Logs
		$R = InModuleScope NamedPipe -Parameters @{ L = $C.Logs; V = $C.Victim } {
			param($L, $V)
			$F = Open-SafeLogFolder -Path $L
			try
			{
				$Out = [ordered]@{}
				$Out.Delete = try { [System.IO.Directory]::Delete($L); 'deleted' } catch { 'blocked' }
				$Out.Move = try { [System.IO.Directory]::Move($L, $L + '-moved'); 'moved' } catch { 'blocked' }
				$Out.MoveParent = try { [System.IO.Directory]::Move((Split-Path -Parent $L), (Split-Path -Parent $L) + '-moved'); 'moved' } catch { 'blocked' }
				[pscustomobject]$Out
			}
			finally { $F.Dispose() }
		}
		$R.Delete | Should -Be 'blocked'
		$R.Move | Should -Be 'blocked'
		$R.MoveParent | Should -Be 'blocked'
		Test-Path -LiteralPath $C.Logs | Should -BeTrue
	}
	It 'will not write over an existing name (a planted link is not followed)' {
		$C = & $Script:NewCase
		$null = New-Item -ItemType Directory -Path $C.Logs
		$Plant = Join-Path $C.Logs 'server-x.log'
		Set-Content -LiteralPath $Plant -Value 'original'
		$R = InModuleScope NamedPipe -Parameters @{ L = $C.Logs } {
			param($L)
			$F = Open-SafeLogFolder -Path $L
			try { $F.WriteNewFile('server-x.log', 'new'); 'written' } catch { 'refused' } finally { $F.Dispose() }
		}
		$R | Should -Be 'refused'
		(Get-Content -LiteralPath $Plant -Raw).Trim() | Should -Be 'original'
	}
	It 'will not take a file name with a path in it' {
		$C = & $Script:NewCase
		$null = New-Item -ItemType Directory -Path $C.Logs
		$R = InModuleScope NamedPipe -Parameters @{ L = $C.Logs } {
			param($L)
			$F = Open-SafeLogFolder -Path $L
			try { $F.WriteNewFile('..\escape.log', 'x'); 'written' } catch { 'refused' } finally { $F.Dispose() }
		}
		$R | Should -Be 'refused'
	}
	It 'leaves a symbolic link that has the name of an expired log alone' {
		$C = & $Script:NewCase
		$env:APPDATA = $C.AppData
		$null = New-Item -ItemType Directory -Path $C.Logs
		$VictimFile = Join-Path $C.Victim 'precious.txt'
		Set-Content -LiteralPath $VictimFile -Value 'victim'
		$Link = Join-Path $C.Logs 'server-old.log'
		try { $null = New-Item -ItemType SymbolicLink -Path $Link -Target $VictimFile -ErrorAction Stop }
		catch { Set-ItResult -Skipped -Because 'this account may not create symbolic links'; return }
		(Get-Item -LiteralPath $Link -Force).LastWriteTime = (Get-Date).AddDays(-40)
		(Get-Item -LiteralPath $VictimFile).LastWriteTime = (Get-Date).AddDays(-40)
		InModuleScope NamedPipe { Remove-OldServerLog -RetentionDays 14 }
		Test-Path -LiteralPath $VictimFile | Should -BeTrue
		Test-Path -LiteralPath $Link -PathType Leaf | Should -BeTrue
		Should -Invoke Write-MyCatchAudit -ModuleName NamedPipe -Times 1 -Exactly -ParameterFilter { $Source -match 'left a log entry alone' } -Scope It
	}
}

Describe 'Open-SafeLogFolder source' {
	AfterEach {
		$env:APPDATA = $Script:SavedAppData
		InModuleScope NamedPipe { $Script:SeamAction = $null }
	}
	It 'is the only place the log folder is opened by handle: Save-ServerLog and Remove-OldServerLog no longer check it by path' {
		foreach ($F in 'Save-ServerLog.ps1', 'Remove-OldServerLog.ps1')
		{
			$Ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Script:ModulePath "FunctionsWindows\$F"), [ref]$null, [ref]$null)
			$Names = $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() }
			$Names | Should -Contain 'Open-SafeLogFolder'
			$Names | Should -Not -Contain 'Remove-Item'
			$Names | Should -Not -Contain 'Get-ChildItem'
			$Text = $Ast.Extent.Text
			$Text | Should -Not -Match 'WriteAllText'
			$Text | Should -Not -Match 'ReparsePoint\]'
		}
	}
}
