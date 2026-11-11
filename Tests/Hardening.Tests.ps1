#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
    .SYNOPSIS
    Pester tests for the 0.17 hardening and correctness fixes (health pipe, parameter handling, access identifiers,
    chunk buffer, redaction, trusted-path warning).

    .DESCRIPTION
    Imports the SOURCE tree of this version. Tests that drive a failure path mock Write-MyCatchAudit so nothing is
    written to the real catch-audit or spill folders. The 'live server' tests start ONE non-elevated server (minimised
    window) and end it through the pipe; they are tagged Integration.

    Run with: Invoke-Pester -Path .\Hardening.Tests.ps1 -Output Detailed
#>

BeforeAll {
	$Script:ModulePath = Split-Path -Parent $PSScriptRoot
	$Script:Manifest = Join-Path -Path $Script:ModulePath -ChildPath 'NamedPipe.psd1'
	Remove-Module -Name NamedPipe -Force -ErrorAction SilentlyContinue
	Import-Module $Script:Manifest -Force
	Mock Write-MyCatchAudit { } -ModuleName NamedPipe
}

AfterAll {
	Remove-Module NamedPipe -Force -ErrorAction SilentlyContinue
}

Describe 'Test-AccessIdentifier short forms' {
	It 'completes a 1-part identifier' {
		$R = & (Get-Module NamedPipe) { 'Administrators' | Test-AccessIdentifier }
		$R | Should -Be 'Administrators:Allow:ReadWrite'
	}
	It 'completes a 2-part identifier' {
		$R = & (Get-Module NamedPipe) { 'Administrators:Deny' | Test-AccessIdentifier }
		$R | Should -Be 'Administrators:Deny:ReadWrite'
	}
	It 'keeps a 3-part identifier unchanged' {
		$R = & (Get-Module NamedPipe) { 'Administrators:Allow:ReadWrite' | Test-AccessIdentifier }
		$R | Should -Be 'Administrators:Allow:ReadWrite'
	}
	It 'handles an array passed by parameter entry by entry' {
		$R = @(& (Get-Module NamedPipe) { Test-AccessIdentifier -IDList @('Administrators', 'Users:Allow') })
		$R.Count | Should -Be 2
		$R[1] | Should -Be 'Users:Allow:ReadWrite'
	}
	It 'still rejects a bad access right' {
		{ & (Get-Module NamedPipe) { 'Administrators:Allow:Full' | Test-AccessIdentifier } } | Should -Throw
	}
}

Describe 'Get-SBResult Parameters types and -Command' {
	BeforeAll {
		function global:Show-ItNP { param($Name) "Name=[$Name]" }
	}
	AfterAll {
		Remove-Item -Path Function:\Show-ItNP -ErrorAction SilentlyContinue
	}
	It 'passes an ordered dictionary through' {
		$R = InModuleScope NamedPipe {
			$D = Set-ObjectParameterSet -Dataset 'DataObject'
			$D.Request = 'Show-ItNP'
			$D.Parameters = [ordered]@{ Name = 'A' }
			Get-SBResult -DataObject $D
		}
		$R.Result | Should -Be 'Name=[A]'
		$R.Error | Should -BeNullOrEmpty
	}
	It 'passes a PSCustomObject through' {
		$R = InModuleScope NamedPipe {
			$D = Set-ObjectParameterSet -Dataset 'DataObject'
			$D.Request = 'Show-ItNP'
			$D.Parameters = [pscustomobject]@{ Name = 'B' }
			Get-SBResult -DataObject $D
		}
		$R.Result | Should -Be 'Name=[B]'
	}
	It 'still passes a hashtable and a string' {
		$R = InModuleScope NamedPipe {
			$D = Set-ObjectParameterSet -Dataset 'DataObject'
			$D.Request = 'Show-ItNP'
			$D.Parameters = @{ Name = 'C' }
			$H = Get-SBResult -DataObject $D
			$D2 = Set-ObjectParameterSet -Dataset 'DataObject'
			$D2.Request = 'Show-ItNP'
			$D2.Parameters = "-Name 'D'"
			$S = Get-SBResult -DataObject $D2
			@($H.Result, $S.Result)
		}
		$R[0] | Should -Be 'Name=[C]'
		$R[1] | Should -Be 'Name=[D]'
	}
	It 'reports an unsupported Parameters type instead of running with no arguments' {
		$R = InModuleScope NamedPipe {
			$D = Set-ObjectParameterSet -Dataset 'DataObject'
			$D.Request = 'Show-ItNP'
			$D.Parameters = [int[]](1, 2)
			Get-SBResult -DataObject $D
		}
		$R.Result | Should -BeNullOrEmpty
		[string]$R.Error | Should -Match 'Unsupported Parameters type'
	}
	It '-Command returns a DataObject carrying the result' {
		$R = InModuleScope NamedPipe { Get-SBResult -Command 'Write-Output hello' }
		$R.Result | Should -Be 'hello'
		$R.Error | Should -BeNullOrEmpty
	}
}

Describe 'Exit-Pipe parameter positions' {
	It 'gives DataObject and PipeInfo different positions' {
		$Cmd = Get-Command Exit-Pipe
		$PosD = $Cmd.Parameters['DataObject'].Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Position
		$PosP = $Cmd.Parameters['PipeInfo'].Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Position
		$PosD | Should -Be 0
		$PosP | Should -Be 1
	}
}

Describe 'ChunkSize 0 (no chunking) is kept' {
	It 'MyOptions keeps 0' {
		$O = InModuleScope NamedPipe { Set-ObjectParameterSet -Dataset 'MyOptions' -MyParameters ([pscustomobject]@{ ChunkSize = 0 }) }
		$O.ChunkSize | Should -Be 0
	}
	It 'ServerClientParams (server and client) keep 0' {
		$S = InModuleScope NamedPipe { Set-ObjectParameterSet -Server -Dataset 'ServerClientParams' -MyParameters ([pscustomobject]@{ ChunkSize = 0 }) }
		$C = InModuleScope NamedPipe { Set-ObjectParameterSet -Client -Dataset 'ServerClientParams' -MyParameters ([pscustomobject]@{ ChunkSize = 0 }) }
		$S.ChunkSize | Should -Be 0
		$C.ChunkSize | Should -Be 0
	}
	It 'an unset ChunkSize still defaults to 32768' {
		$O = InModuleScope NamedPipe { Set-ObjectParameterSet -Dataset 'MyOptions' -MyParameters ([pscustomobject]@{}) }
		$O.ChunkSize | Should -Be 32768
	}
}

Describe 'Receive-Data failure handling' {
	It 'does not hand back or modify the caller''s DataObject when the first line is bad' {
		$Result = InModuleScope NamedPipe {
			$DataObject = [ordered]@{ Error = $null; Marker = 'CALLERS-OBJECT' }
			$Pi = [ordered]@{ Reader = [System.IO.StringReader]::new('not a frame'); InfoDisplay = 0; FrameId = 0 }
			$R = Receive-Data -PipeInfo $Pi
			[pscustomobject]@{ Same = [object]::ReferenceEquals($R, $DataObject); CallerError = $DataObject.Error; HasError = [bool]$R.Error }
		}
		$Result.Same | Should -BeFalse
		$Result.CallerError | Should -BeNullOrEmpty
		$Result.HasError | Should -BeTrue
	}
	It 'drops the partial chunk buffer when a chunked transfer is aborted' {
		$Left = InModuleScope NamedPipe {
			$null = ConvertFrom-Serial -ClearBuffer
			$Chunks = ConvertTo-Serial -Object ('Z' * 20000) -ChunkSize 1000
			$First = ConvertTo-PipeFrame -Payload ('JCHUNK:' + ($Chunks[0] | ConvertTo-Json -Compress)) -Id 1 -Key $null
			$Lines = $First + [Environment]::NewLine + 'garbage-not-a-frame' + [Environment]::NewLine
			$Pi = [ordered]@{ Reader = [System.IO.StringReader]::new($Lines); InfoDisplay = 0; FrameId = 0; ChunkReadTimeout = 5000 }
			$null = Receive-Data -PipeInfo $Pi
			@(Get-ChunkBufferStatus).Count
		}
		$Left | Should -Be 0
	}
}

Describe 'Secrets are not displayed' {
	It 'Show-VerboseData masks the nonce, frame key and command token' {
		$Out = Show-VerboseData -Object ([ordered]@{ Nonce = 'SECRET-NONCE-VALUE'; FrameKey = 'SECRET-FRAME'; CommandToken = 'SECRET-TOKEN'; Plain = 'visible' }) -Display 6>&1 | Out-String
		$Out | Should -Not -Match 'SECRET'
		$Out | Should -Match '<redacted>'
		$Out | Should -Match 'visible'
	}
	It 'Show-VerboseData masks the serialized session on a spawn command line' {
		$Out = Show-VerboseData -Object @{ FilePath = 'pwsh.exe'; Argumentlist = '-NoProfile -File "x.ps1" -Spawned -SerialData QUJDREVGR0hJSktM' } -Display 6>&1 | Out-String
		$Out | Should -Not -Match 'QUJDREVGR0hJSktM'
		$Out | Should -Match '-Spawned'
	}
}

Describe 'Test-ConstantTimeEqual' {
	It 'compares equal and different strings correctly' {
		& (Get-Module NamedPipe) { Test-ConstantTimeEqual -Left 'abc123' -Right 'abc123' } | Should -BeTrue
		& (Get-Module NamedPipe) { Test-ConstantTimeEqual -Left 'abc123' -Right 'abc124' } | Should -BeFalse
		& (Get-Module NamedPipe) { Test-ConstantTimeEqual -Left 'abc' -Right 'abcd' } | Should -BeFalse
		& (Get-Module NamedPipe) { Test-ConstantTimeEqual -Left 'ABC' -Right 'abc' } | Should -BeFalse
		& (Get-Module NamedPipe) { Test-ConstantTimeEqual -Left '' -Right '' } | Should -BeTrue
	}
	It 'the server nonce check uses it' {
		$Ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Script:ModulePath 'FunctionsWindows\Start-PipeServerOrClient.ps1'), [ref]$null, [ref]$null)
		$Hits = $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Test-ConstantTimeEqual' }, $true)
		@($Hits).Count | Should -BeGreaterThan 0
	}
}

Describe 'Test-ServerCodePathTrusted' {
	It 'reports nothing for an administrator-only location' {
		$R = @(& (Get-Module NamedPipe) { param($p) Test-ServerCodePathTrusted -Path $p } $PSHOME)
		$R.Count | Should -Be 0
	}
	It 'reports a folder a standard user owns' {
		$Dir = Join-Path ([System.IO.Path]::GetTempPath()) ('np-trust-' + [guid]::NewGuid().ToString('N'))
		$null = New-Item -ItemType Directory -Path $Dir
		try
		{
			$R = @(& (Get-Module NamedPipe) { param($p) Test-ServerCodePathTrusted -Path $p } $Dir)
			$R.Count | Should -BeGreaterThan 0
		}
		finally { Remove-Item -LiteralPath $Dir -Recurse -Force -ErrorAction SilentlyContinue }
	}
}

Describe 'Server log folder redirection' {
	It 'writes nothing through a junction in place of the log folder' {
		$Root = Join-Path ([System.IO.Path]::GetTempPath()) ('np-log-' + [guid]::NewGuid().ToString('N'))
		$Target = Join-Path $Root 'target'
		$null = New-Item -ItemType Directory -Path $Target -Force
		$Saved = $env:APPDATA
		try
		{
			$env:APPDATA = Join-Path $Root 'appdata'
			$null = New-Item -ItemType Directory -Path $env:APPDATA -Force
			$null = New-Item -ItemType Junction -Path (Join-Path $env:APPDATA 'NamedPipe-Logs') -Target $Target
			$R = InModuleScope NamedPipe {
				$Script:ServerLogSaved = $false
				$Script:ServerLogBuffer = [System.Collections.Generic.List[string]]::new()
				Save-ServerLog -Outcome 'exit-pipe' -InfoDisplay 8 -PipeName 'np-test'
			}
			$R | Should -BeNullOrEmpty
			@(Get-ChildItem -LiteralPath $Target -Force).Count | Should -Be 0
		}
		finally
		{
			$env:APPDATA = $Saved
			$Link = Join-Path (Join-Path $Root 'appdata') 'NamedPipe-Logs'
			if (Test-Path -LiteralPath $Link) { [System.IO.Directory]::Delete($Link) }
			Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
		}
	}
	It 'still writes a log into an ordinary log folder' {
		$Root = Join-Path ([System.IO.Path]::GetTempPath()) ('np-log-' + [guid]::NewGuid().ToString('N'))
		$Saved = $env:APPDATA
		try
		{
			$env:APPDATA = $Root
			$null = New-Item -ItemType Directory -Path $Root -Force
			$R = InModuleScope NamedPipe {
				$Script:ServerLogSaved = $false
				$Script:ServerLogBuffer = [System.Collections.Generic.List[string]]::new()
				Save-ServerLog -Outcome 'exit-pipe' -InfoDisplay 8 -PipeName 'np-test'
			}
			$R | Should -Not -BeNullOrEmpty
			Test-Path -LiteralPath $R | Should -BeTrue
		}
		finally
		{
			$env:APPDATA = $Saved
			Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
		}
	}
}

Describe 'Health pipe listener source' {
	BeforeAll {
		$Script:ServerAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Script:ModulePath 'FunctionsWindows\Start-PipeServerOrClient.ps1'), [ref]$null, [ref]$null)
	}
	It 'backs off in the listener catch block' {
		$Catches = $Script:ServerAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.CatchClauseAst] -and $n.Extent.Text -match 'Health pipe listener: WaitForConnection' }, $true)
		@($Catches).Count | Should -BeGreaterThan 0
		$Sleeps = $Catches[0].FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Start-Sleep' }, $true)
		@($Sleeps).Count | Should -BeGreaterThan 0
	}
	It 'bounds the listener read' {
		$Reads = $Script:ServerAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'ReadLine' -and $n.Extent.Text -match 'hReader' }, $true)
		@($Reads).Count | Should -Be 0
	}
}

Describe 'Test-PipeSession against a silent health peer' {
	It 'returns instead of hanging' {
		$Name = 'np-silent-' + [guid]::NewGuid().ToString('N')
		$Fake = [System.IO.Pipes.NamedPipeServerStream]::new(($Name + '.Health'), [System.IO.Pipes.PipeDirection]::InOut, 1)
		$null = $Fake.WaitForConnectionAsync()
		$Pi = [ordered]@{ Name = $Name; Pipe = [pscustomobject]@{ IsConnected = $true }; Reader = [pscustomobject]@{}; Writer = [pscustomobject]@{ BaseStream = 1 } }
		$Ps = [powershell]::Create()
		try
		{
			$null = $Ps.AddScript({ param($m, $p) Import-Module $m -Force; Test-PipeSession -PipeInfo $p -TimeoutMs 1000 }).AddArgument($Script:Manifest).AddArgument($Pi)
			$Ar = $Ps.BeginInvoke()
			$Done = $Ar.AsyncWaitHandle.WaitOne(12000)
			$Done | Should -BeTrue
		}
		finally
		{
			# Releasing the fake peer lets even a blocked read return, so nothing is left running.
			$Fake.Dispose()
			$null = $Ar.AsyncWaitHandle.WaitOne(5000)
			$Ps.Dispose()
		}
	}
}

Describe 'Health pipe on a live server' -Tag 'Integration' {
	BeforeAll {
		$Script:Live = $false
		try
		{
			$Mtl = @{ Name = 'NamedPipe'; Version = '0.17'; Path = $Script:Manifest }
			$Session = Start-PipeSession -MyParameters ([ordered]@{}) -Options @{ WindowStyle = 'Minimized'; ModuleToLoad = $Mtl }
			$Script:Srp = $Session.SendRequestParams
			$Script:Pi = $Session.ServerClientParams.PipeInfo
			$Script:PipeName = $Script:Pi.Name
			$Script:Live = $true
		}
		catch { Write-Warning ('live server not started: {0}' -f $_.Exception.Message) }
		$Script:SendHealthLine = {
			param([string]$Line, [int]$ConnectMs = 8000, [int]$ReplyMs = 8000)
			$C = [System.IO.Pipes.NamedPipeClientStream]::new('.', ($Script:PipeName + '.Health'), [System.IO.Pipes.PipeDirection]::InOut, [System.IO.Pipes.PipeOptions]::Asynchronous)
			try
			{
				$C.Connect($ConnectMs)
				$W = [System.IO.StreamWriter]::new($C); $W.AutoFlush = $true
				$R = [System.IO.StreamReader]::new($C)
				$W.WriteLine($Line)
				$T = $R.ReadLineAsync()
				if ($T.Wait($ReplyMs)) { $T.Result } else { '<no reply>' }
			}
			catch { '<error: {0}>' -f $_.Exception.Message }
			finally { $C.Dispose() }
		}
	}
	AfterAll {
		if ($Script:Live)
		{
			try
			{
				$Script:Srp.Type = 'ExitPipe'
				$null = $null | Send-Request @Script:Srp
			}
			catch { Write-Warning ('live server exit request failed: {0}' -f $_.Exception.Message) }
		}
	}
	It 'answers PING while a silent client is connected' {
		if (-not $Script:Live) { Set-ItResult -Skipped -Because 'no live server'; return }
		$Silent = [System.IO.Pipes.NamedPipeClientStream]::new('.', ($Script:PipeName + '.Health'), [System.IO.Pipes.PipeDirection]::InOut)
		try
		{
			$Silent.Connect(3000)
			& $Script:SendHealthLine -Line 'PING:abc' | Should -Be 'PONG:abc'
		}
		finally { $Silent.Dispose() }
	}
	It 'refuses a STOP without the command token and keeps the command channel working' {
		if (-not $Script:Live) { Set-ItResult -Skipped -Because 'no live server'; return }
		& $Script:SendHealthLine -Line 'STOP' | Should -Be 'DENIED'
		& $Script:SendHealthLine -Line 'STOP:0000' | Should -Be 'DENIED'
		& $Script:SendHealthLine -Line ('STATUS:' + $Script:Pi.CommandToken) | Should -Be 'STATUS:idle'
	}
	It 'honours a STOP that carries the command token' {
		if (-not $Script:Live) { Set-ItResult -Skipped -Because 'no live server'; return }
		$null = & $Script:SendHealthLine -Line ('STOP:' + $Script:Pi.CommandToken) -ReplyMs 1500
		Start-Sleep -Milliseconds 800
		& $Script:SendHealthLine -Line 'PING:abc' -ConnectMs 1500 -ReplyMs 1500 | Should -Not -Be 'PONG:abc'
	}
}
