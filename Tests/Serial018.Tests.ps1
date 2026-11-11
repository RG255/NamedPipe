#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
	.SYNOPSIS
	Pester tests for the UTF-8 serial format of 0.18: round trips of non-ASCII and whitespace-only values, reading of the
	older UTF-16 format, and that every sender in this module asks for UTF-8.

	.DESCRIPTION
	Imports the SOURCE tree of this version. Nothing is written outside memory.

	Run with: Invoke-Pester -Path .\Serial018.Tests.ps1 -Output Detailed
#>

BeforeAll {
	$Script:ModulePath = Split-Path -Parent $PSScriptRoot
	Remove-Module -Name NamedPipe -Force -ErrorAction SilentlyContinue
	Import-Module (Join-Path $Script:ModulePath 'NamedPipe.psd1') -Force
	Mock Write-MyCatchAudit { } -ModuleName NamedPipe
	$Script:Emoji = [char]::ConvertFromUtf32(0x1F600)
}

AfterAll {
	Remove-Module NamedPipe -Force -ErrorAction SilentlyContinue
}

Describe 'UTF-8 serial format' {
	It 'round trips <Name> exactly (top level, nested, array)' -ForEach @(
		@{ Name = 'accented text'; Value = "caf$([char]0xE9) $([char]0xDC)n$([char]0xEF)c$([char]0xF6)d$([char]0xE9)" }
		@{ Name = 'a non-BMP emoji'; Value = "a$([char]::ConvertFromUtf32(0x1F600))b" }
		@{ Name = 'CJK text'; Value = "$([char]0x65E5)$([char]0x672C)$([char]0x8A9E)" }
		@{ Name = 'one space'; Value = ' ' }
		@{ Name = 'spaces only'; Value = '   ' }
		@{ Name = 'tabs and newlines'; Value = "a`t b`r`n  c" }
		@{ Name = 'an empty string'; Value = '' }
	) {
		$Ser = ConvertTo-Serial -Object @{ v = $Value; n = @{ inner = $Value }; a = @($Value, 'x') } -ChunkSize 0 -Encoding Utf8
		$Back = ConvertFrom-Serial -Text $Ser
		$Back.v | Should -BeExactly $Value
		$Back.n.inner | Should -BeExactly $Value
		$Back.a[0] | Should -BeExactly $Value
	}

	It 'is plain UTF-8 JSON (no NUL second byte) and shorter than the UTF-16 form' {
		$Obj = @{ Command = 'Get-Process'; Args = @{ Name = 'x'; Path = 'C:\Temp\a b' } }
		$U8 = ConvertTo-Serial -Object $Obj -ChunkSize 0 -Encoding Utf8
		$U16 = ConvertTo-Serial -Object $Obj -ChunkSize 0
		[Convert]::FromBase64String($U8)[1] | Should -Not -Be 0
		[Convert]::FromBase64String($U16)[1] | Should -Be 0
		$U8.Length | Should -BeLessThan ($U16.Length * 0.7)
	}

	It 'still reads data written in the older UTF-16 format' {
		$Old = ConvertTo-Serial -Object @{ v = "caf$([char]0xE9) $Script:Emoji"; s = '   ' } -ChunkSize 0
		$Back = ConvertFrom-Serial -Text $Old
		$Back.v | Should -BeExactly "caf$([char]0xE9) $Script:Emoji"
		$Back.s | Should -BeExactly '   '
	}

	It 'round trips a large non-ASCII value through the chunked path' {
		$Big = (("caf$([char]0xE9) $Script:Emoji " * 4000))
		$Chunks = @(ConvertTo-Serial -Object @{ big = $Big } -ChunkSize 1000 -Encoding Utf8)
		$Chunks.Count | Should -BeGreaterThan 1
		$Result = $null
		ForEach ($C in $Chunks) { $Result = ConvertFrom-Serial -Chunk $C }
		$Result.big | Should -BeExactly $Big
	}

	It 'is requested by every sender in the module (Send-Data and the spawn / session helpers)' {
		$Files = Get-ChildItem -Path (Join-Path $Script:ModulePath 'FunctionsWindows') -Filter '*.ps1'
		$Calls = @()
		ForEach ($F in $Files) {
			$Ast = [System.Management.Automation.Language.Parser]::ParseFile($F.FullName, [ref]$null, [ref]$null)
			$Calls += $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'ConvertTo-Serial' }, $true) | ForEach-Object {
				[pscustomobject]@{ File = $F.Name; Utf8 = ($_.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'Encoding' }).Count -eq 1 }
			}
		}
		$Calls.Count | Should -BeGreaterThan 3
		@($Calls | Where-Object { -not $_.Utf8 }).Count | Should -Be 0
	}
}
