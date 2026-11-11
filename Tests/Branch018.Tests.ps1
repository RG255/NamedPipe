#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
    .SYNOPSIS
    Pester tests for the 0.18 changes: frame direction, the nonce kept off the spawn command line, the client's server-PID
    check, the nonce from the OS generator, and RequestPolicy Audit mode.

    .DESCRIPTION
    Imports the SOURCE tree of this version. Write-MyCatchAudit and every Event Log writer are mocked, and the live tests give
    the spawned server a throwaway ProgramData and APPDATA, so nothing is written to the real catch-audit, spill, log or Event
    Log locations. The live tests start non-elevated servers (hidden window) that end through the pipe or by their own
    first-connect deadline; they are tagged Integration. No test starts an elevated server: the elevated spawn is covered only
    up to the command line it would use.

    Run with: Invoke-Pester -Path .\Branch018.Tests.ps1 -Output Detailed
#>

BeforeAll {
	$Script:ModulePath = Split-Path -Parent $PSScriptRoot
	$Script:Manifest = Join-Path -Path $Script:ModulePath -ChildPath 'NamedPipe.psd1'
	Remove-Module -Name NamedPipe -Force -ErrorAction SilentlyContinue
	Import-Module $Script:Manifest -Force
	Mock Write-MyCatchAudit { } -ModuleName NamedPipe
	$Script:Mtl = @{ Name = 'NamedPipe'; Version = '0.18'; Path = $Script:Manifest }
	# One throwaway root for everything a spawned server could write.
	$Script:Scratch = Join-Path ([System.IO.Path]::GetTempPath()) ('np18-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
	$null = New-Item -ItemType Directory -Path (Join-Path $Script:Scratch 'ProgramData') -Force
	$null = New-Item -ItemType Directory -Path (Join-Path $Script:Scratch 'AppData') -Force
	$Script:SavedEnv = @{ ProgramData = $env:ProgramData; APPDATA = $env:APPDATA }
	$Script:UseScratchEnv = { $env:ProgramData = Join-Path $Script:Scratch 'ProgramData'; $env:APPDATA = Join-Path $Script:Scratch 'AppData' }
	$Script:RestoreEnv = { $env:ProgramData = $Script:SavedEnv.ProgramData; $env:APPDATA = $Script:SavedEnv.APPDATA }
}

AfterAll {
	& $Script:RestoreEnv
	Remove-Module NamedPipe -Force -ErrorAction SilentlyContinue
	Remove-Item -LiteralPath $Script:Scratch -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Frame direction' {
	It 'marks a frame with its direction and verifies it only in that direction' {
		$R = InModuleScope NamedPipe {
			$Key = ('ab' * 32)
			$F = ConvertTo-PipeFrame -Payload 'hello|x' -Direction C -Id 5 -Key $Key
			$Ok = ConvertFrom-PipeFrame -Line $F -Direction C -Key $Key
			$Wrong = try { $null = ConvertFrom-PipeFrame -Line $F -Direction S -Key $Key; 'accepted' } catch { $_.Exception.Message }
			[pscustomobject]@{ Line = $F; Payload = $Ok.Payload; Wrong = $Wrong }
		}
		$R.Line | Should -Match '^NPF3\|C\|5\|'
		$R.Payload | Should -Be 'hello|x'
		$R.Wrong | Should -Match 'marked as direction'
	}
	It 'refuses a request frame relabelled as a response (the code covers the direction)' {
		$R = InModuleScope NamedPipe {
			$Key = ('ab' * 32)
			$F = ConvertTo-PipeFrame -Payload 'x' -Direction C -Id 5 -Key $Key
			$Relabelled = $F -replace '^NPF3\|C\|', 'NPF3|S|'
			try { $null = ConvertFrom-PipeFrame -Line $Relabelled -Direction S -Key $Key; 'accepted' } catch { $_.Exception.Message }
		}
		$R | Should -Match 'authentication code'
	}
	It 'also separates the directions when the session has no key' {
		$R = InModuleScope NamedPipe {
			$F = ConvertTo-PipeFrame -Payload 'x' -Direction C -Id 5 -Key $null
			$Relabelled = $F -replace '^NPF3\|C\|', 'NPF3|S|'
			try { $null = ConvertFrom-PipeFrame -Line $Relabelled -Direction S -Key $null; 'accepted' } catch { $_.Exception.Message }
		}
		$R | Should -Match 'authentication code'
	}
	It 'a client reading a server frame accepts it; a request frame is refused' {
		$R = InModuleScope NamedPipe {
			$Key = ('ab' * 32)
			$Payload = ConvertTo-Serial -Object ([pscustomobject]@{ A = 1 }) -ChunkSize 0
			$Srv = ConvertTo-PipeFrame -Payload $Payload -Direction S -Id 4 -Key $Key
			$Req = ConvertTo-PipeFrame -Payload $Payload -Direction C -Id 4 -Key $Key
			$Pi1 = [ordered]@{ Reader = [System.IO.StringReader]::new($Srv); InfoDisplay = 0; FrameId = 0; FrameKey = $Key; ExpectFrameId = 4 }
			$Pi2 = [ordered]@{ Reader = [System.IO.StringReader]::new($Req); InfoDisplay = 0; FrameId = 0; FrameKey = $Key; ExpectFrameId = 4 }
			$Good = Receive-Data -PipeInfo $Pi1
			$Bad = Receive-Data -PipeInfo $Pi2
			[pscustomobject]@{ GoodA = $Good.A; GoodError = $Good.Error; BadError = [string]$Bad.Error }
		}
		$R.GoodA | Should -Be 1
		$R.GoodError | Should -BeNullOrEmpty
		$R.BadError | Should -Match 'marked as direction ''C'' but this end expects ''S'''
	}
	It 'a server reading a client frame accepts it; a response frame is refused' {
		$R = InModuleScope NamedPipe {
			$Key = ('ab' * 32)
			$Payload = ConvertTo-Serial -Object ([pscustomobject]@{ A = 1 }) -ChunkSize 0
			$Req = ConvertTo-PipeFrame -Payload $Payload -Direction C -Id 4 -Key $Key
			$Srv = ConvertTo-PipeFrame -Payload $Payload -Direction S -Id 4 -Key $Key
			$Pi1 = [ordered]@{ Reader = [System.IO.StringReader]::new($Req); InfoDisplay = 0; FrameId = 0; FrameKey = $Key }
			$Pi2 = [ordered]@{ Reader = [System.IO.StringReader]::new($Srv); InfoDisplay = 0; FrameId = 0; FrameKey = $Key }
			$Good = Receive-Data -PipeInfo $Pi1
			$Bad = Receive-Data -PipeInfo $Pi2
			[pscustomobject]@{ GoodA = $Good.A; BadError = [string]$Bad.Error }
		}
		$R.GoodA | Should -Be 1
		$R.BadError | Should -Match 'marked as direction ''S'' but this end expects ''C'''
	}
	It 'Send-Data and Receive-Data pass a direction on every frame call' {
		$Calls = foreach ($F in 'Send-Data.ps1', 'Receive-Data.ps1')
		{
			$Ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Script:ModulePath "FunctionsWindows\$F"), [ref]$null, [ref]$null)
			$Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -in 'ConvertTo-PipeFrame', 'ConvertFrom-PipeFrame' }, $true)
		}
		@($Calls).Count | Should -BeGreaterThan 2
		foreach ($C in $Calls) { $C.Extent.Text | Should -Match '-Direction' }
	}
}

Describe 'Nonce from the OS generator' {
	It 'is 32 lower-case hex characters and does not repeat' {
		$A = InModuleScope NamedPipe { New-PipeNonce }
		$B = InModuleScope NamedPipe { New-PipeNonce }
		$A | Should -Match '^[0-9a-f]{32}$'
		$A | Should -Not -Be $B
	}
	It 'is what a new session uses' {
		$S = InModuleScope NamedPipe { Set-ObjectParameterSet -Server -Dataset $StrServerClientParams -MyParameters ([pscustomobject]@{}) }
		$S.Nonce | Should -Match '^[0-9a-f]{32}$'
	}
	It 'no longer comes from a GUID' {
		$Ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Script:ModulePath 'Functions\Set-ObjectParameterSet.ps1'), [ref]$null, [ref]$null)
		$Hits = $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'NewGuid' -and $n.Extent.Text -match 'Guid' }, $true)
		@($Hits).Count | Should -Be 0
	}
}

Describe 'Get-PipePeerProcessId' {
	It 'reports this process at both ends of an in-process pipe, and 0 when not connected' {
		$Name = 'np18-peer-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
		$Server = [System.IO.Pipes.NamedPipeServerStream]::new($Name, [System.IO.Pipes.PipeDirection]::InOut, 1, [System.IO.Pipes.PipeTransmissionMode]::Byte, [System.IO.Pipes.PipeOptions]::None, 4096, 4096)
		$Wait = $Server.WaitForConnectionAsync()
		$Client = [System.IO.Pipes.NamedPipeClientStream]::new('.', $Name, [System.IO.Pipes.PipeDirection]::InOut)
		try
		{
			$Client.Connect(3000)
			$null = $Wait.Wait(3000)
			$R = InModuleScope NamedPipe -Parameters @{ S = $Server; C = $Client } {
				[pscustomobject]@{
					ClientSeenByServer = Get-PipePeerProcessId -Pipe $S -Peer Client
					ServerSeenByClient = Get-PipePeerProcessId -Pipe $C -Peer Server
				}
			}
			$R.ClientSeenByServer | Should -Be $PID
			$R.ServerSeenByClient | Should -Be $PID
		}
		finally { $Client.Dispose(); $Server.Dispose() }
		$Idle = [System.IO.Pipes.NamedPipeServerStream]::new(('np18-idle-' + [guid]::NewGuid().ToString('N').Substring(0, 8)), [System.IO.Pipes.PipeDirection]::InOut, 1)
		try { (InModuleScope NamedPipe -Parameters @{ S = $Idle } { Get-PipePeerProcessId -Pipe $S -Peer Client }) | Should -Be 0 }
		finally { $Idle.Dispose() }
	}
}

Describe 'Spawn command line' {
	BeforeAll {
		Mock Start-Process { $global:NP18Args = [string]$Argumentlist; [pscustomobject]@{ Id = 4242 } } -ModuleName NamedPipe
		Mock Test-ServerCodePathTrusted { } -ModuleName NamedPipe
		$Script:SpawnCapture = {
			param($Parameters)
			$Scp = Set-ObjectParameterSet -Server -Dataset $StrServerClientParams -MyParameters ([pscustomobject]$Parameters)
			$global:NP18Args = $null
			$Pid2 = Start-PipeServerOrClient -SerialData (ConvertTo-Serial -Object $Scp)
			$Text = [string]$global:NP18Args
			$Decoded = $null
			if ($Text -match '-SerialData (\S+)\s*$') { $Decoded = ConvertFrom-Serial -Text $Matches[1] }
			[pscustomobject]@{ Nonce = $Scp.Nonce; Args = $Text; Decoded = $Decoded; SpawnedPid = $Pid2 }
		}
	}
	AfterAll { Remove-Variable -Name NP18Args -Scope Global -ErrorAction SilentlyContinue }

	It 'keeps the nonce on the command line for an ordinary (non-elevated) spawn' {
		$R = & (Get-Module NamedPipe) $Script:SpawnCapture @{}
		$R.SpawnedPid | Should -Be 4242
		$R.Decoded.Nonce | Should -Be $R.Nonce
		$R.Decoded.NonceViaPipe | Should -BeNullOrEmpty
	}
	It 'leaves the nonce off the command line when NonceViaPipe is forced' {
		$R = & (Get-Module NamedPipe) $Script:SpawnCapture @{ NonceViaPipe = $true }
		$R.Decoded | Should -Not -BeNullOrEmpty
		@($R.Decoded.Keys) -contains 'Nonce' | Should -BeFalse
		$R.Args | Should -Not -Match ([regex]::Escape($R.Nonce))
		$R.Decoded.NonceViaPipe | Should -BeTrue
		[uint32]$R.Decoded.ExpectedClientPid | Should -Be $PID
	}
	It 'does so automatically when the server is started elevated (RunAs)' {
		$Elevated = InModuleScope NamedPipe { [bool]$Administrator }
		if ($Elevated) { Set-ItResult -Skipped -Because 'this test process is already elevated, so no RunAs spawn is taken'; return }
		$R = & (Get-Module NamedPipe) $Script:SpawnCapture @{ AdminRequired = $true }
		@($R.Decoded.Keys) -contains 'Nonce' | Should -BeFalse
		$R.Args | Should -Not -Match ([regex]::Escape($R.Nonce))
		$R.Decoded.NonceViaPipe | Should -BeTrue
	}
	It 'keeps the nonce on the command line when NonceViaPipe is switched off, even for RunAs' {
		$Elevated = InModuleScope NamedPipe { [bool]$Administrator }
		if ($Elevated) { Set-ItResult -Skipped -Because 'this test process is already elevated, so no RunAs spawn is taken'; return }
		$R = & (Get-Module NamedPipe) $Script:SpawnCapture @{ AdminRequired = $true; NonceViaPipe = $false }
		$R.Decoded.Nonce | Should -Be $R.Nonce
	}
}

Describe 'Client checks the server process before sending the nonce' {
	BeforeAll {
		$Script:ConnectClient = {
			param($Name, $WantPid)
			$Scp = Set-ObjectParameterSet -Server -Dataset $StrServerClientParams -MyParameters ([pscustomobject]@{ PipeName = $Name; ClientConnectTimeout = 3000 })
			$Scp.ExpectedServerPid = [uint32]$WantPid
			$Cl = Set-ObjectParameterSet -Client -Dataset $StrServerClientParams -MyParameters $Scp
			$Pi = Start-PipeServerOrClient -SerialData (ConvertTo-Serial -Object $Cl)
			[pscustomobject]@{ Nonce = $Scp.Nonce; Error = [bool]$Pi.Error; Verified = $Pi.VerifiedServerPid }
		}
	}
	It 'refuses a pipe served by another process and sends nothing' {
		$Name = 'np18-s1a-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
		$Server = [System.IO.Pipes.NamedPipeServerStream]::new($Name, [System.IO.Pipes.PipeDirection]::InOut, 1, [System.IO.Pipes.PipeTransmissionMode]::Byte, [System.IO.Pipes.PipeOptions]::None, 4096, 4096)
		$null = $Server.WaitForConnectionAsync()
		try
		{
			$R = & (Get-Module NamedPipe) $Script:ConnectClient $Name 4242 6>$null
			$R.Error | Should -BeTrue
			$R.Verified | Should -BeNullOrEmpty
			$Reader = [System.IO.StreamReader]::new($Server)
			$Task = $Reader.ReadLineAsync()
			$Got = $Task.Wait(1500)
			if ($Got) { $Task.Result | Should -BeNullOrEmpty } else { $Got | Should -BeFalse }
		}
		finally { $Server.Dispose() }
	}
	It 'sends the nonce to the expected server process and records its PID' {
		$Name = 'np18-s1b-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
		$Server = [System.IO.Pipes.NamedPipeServerStream]::new($Name, [System.IO.Pipes.PipeDirection]::InOut, 1, [System.IO.Pipes.PipeTransmissionMode]::Byte, [System.IO.Pipes.PipeOptions]::None, 4096, 4096)
		$null = $Server.WaitForConnectionAsync()
		try
		{
			$R = & (Get-Module NamedPipe) $Script:ConnectClient $Name $PID
			$R.Error | Should -BeFalse
			$R.Verified | Should -Be $PID
			$Reader = [System.IO.StreamReader]::new($Server)
			$Task = $Reader.ReadLineAsync()
			$Task.Wait(3000) | Should -BeTrue
			$Task.Result | Should -Be $R.Nonce
		}
		finally { $Server.Dispose() }
	}
	It 'is switched off by VerifyServerPid = false (diagnostics only)' {
		$Name = 'np18-s1c-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
		$Server = [System.IO.Pipes.NamedPipeServerStream]::new($Name, [System.IO.Pipes.PipeDirection]::InOut, 1, [System.IO.Pipes.PipeTransmissionMode]::Byte, [System.IO.Pipes.PipeOptions]::None, 4096, 4096)
		$null = $Server.WaitForConnectionAsync()
		try
		{
			$R = InModuleScope NamedPipe -Parameters @{ N = $Name } {
				$Scp = Set-ObjectParameterSet -Server -Dataset $StrServerClientParams -MyParameters ([pscustomobject]@{ PipeName = $N; ClientConnectTimeout = 3000; VerifyServerPid = $false })
				$Scp.ExpectedServerPid = [uint32]4242
				$Cl = Set-ObjectParameterSet -Client -Dataset $StrServerClientParams -MyParameters $Scp
				$Pi = Start-PipeServerOrClient -SerialData (ConvertTo-Serial -Object $Cl)
				[bool]$Pi.Error
			}
			$R | Should -BeFalse
		}
		finally { $Server.Dispose() }
	}
	It 'the client connects with Identification-level impersonation' {
		$Ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Script:ModulePath 'FunctionsWindows\Start-PipeServerOrClient.ps1'), [ref]$null, [ref]$null)
		$Hits = $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'new' -and $n.Extent.Text -match 'NamedPipeClientStream' -and $n.Extent.Text -match 'Identification' }, $true)
		@($Hits).Count | Should -Be 1
	}
}

Describe 'Health command only goes to the verified server process' {
	It 'does not send the token to a health pipe served by another process' {
		$Name = 'np18-hc-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
		$Server = [System.IO.Pipes.NamedPipeServerStream]::new(($Name + '.Health'), [System.IO.Pipes.PipeDirection]::InOut, 1, [System.IO.Pipes.PipeTransmissionMode]::Byte, [System.IO.Pipes.PipeOptions]::Asynchronous)
		$null = $Server.WaitForConnectionAsync()
		try
		{
			$Pi = [ordered]@{ Name = $Name; CommandToken = 'TOKEN-0451'; VerifiedServerPid = 4242 }
			$R = InModuleScope NamedPipe -Parameters @{ Pi = $Pi } { Invoke-PipeHealthCommand -PipeInfo $Pi -Command STATUS -TimeoutMs 1500 }
			$R | Should -Match '^<refused'
			$Reader = [System.IO.StreamReader]::new($Server)
			$Task = $Reader.ReadLineAsync()
			if ($Task.Wait(800)) { [string]$Task.Result | Should -Not -Match 'TOKEN-0451' } else { $true | Should -BeTrue }
		}
		finally { $Server.Dispose() }
	}
	It 'sends it when the health pipe is served by the verified process' {
		$Name = 'np18-hd-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
		$Server = [System.IO.Pipes.NamedPipeServerStream]::new(($Name + '.Health'), [System.IO.Pipes.PipeDirection]::InOut, 1, [System.IO.Pipes.PipeTransmissionMode]::Byte, [System.IO.Pipes.PipeOptions]::Asynchronous)
		$Accept = $Server.WaitForConnectionAsync()
		try
		{
			$Pi = [ordered]@{ Name = $Name; CommandToken = 'TOKEN-0451'; VerifiedServerPid = $PID }
			$Ps = [powershell]::Create()
			$null = $Ps.AddScript({ param($m, $p) Import-Module $m -Force; & (Get-Module NamedPipe) { param($pi) Invoke-PipeHealthCommand -PipeInfo $pi -Command STATUS -TimeoutMs 4000 } $p }).AddArgument($Script:Manifest).AddArgument($Pi)
			$Ar = $Ps.BeginInvoke()
			$Accept.Wait(4000) | Should -BeTrue
			$Reader = [System.IO.StreamReader]::new($Server)
			$Task = $Reader.ReadLineAsync()
			$Task.Wait(3000) | Should -BeTrue
			$Task.Result | Should -Be 'STATUS:TOKEN-0451'
			$Writer = [System.IO.StreamWriter]::new($Server); $Writer.AutoFlush = $true
			$Writer.WriteLine('STATUS:idle')
			$null = $Ar.AsyncWaitHandle.WaitOne(5000)
			$Ps.Dispose()
		}
		finally { $Server.Dispose() }
	}
}

Describe 'RequestPolicy Audit mode' {
	BeforeAll {
		Mock Write-PipePolicyAuditEvent { 'audited' } -ModuleName NamedPipe
		$Script:RunPolicy = {
			param($Policy, $Request)
			# Get-SBResult reads $ServerClientParams from its caller's scope (the server's own variable).
			Set-Variable -Name ServerClientParams -Scope Local -Value ([ordered]@{ RequestPolicy = $Policy; InfoDisplay = 0; PipeInfo = [ordered]@{ FrameId = 3 } })
			$D = Set-ObjectParameterSet -Dataset 'DataObject'
			$D.Request = $Request
			Get-SBResult -DataObject $D
		}
	}
	It 'is silent for a request the policy allows' {
		$R = & (Get-Module NamedPipe) $Script:RunPolicy @{ AllowedCommands = @('Write-Output'); Mode = 'Audit' } "Write-Output 'fine'"
		$R.Result | Should -Be 'fine'
		Should -Invoke Write-PipePolicyAuditEvent -ModuleName NamedPipe -Times 0 -Exactly
	}
	It 'records a request the policy would block, and still runs it' {
		$R = & (Get-Module NamedPipe) $Script:RunPolicy @{ AllowedCommands = @('Get-Date'); Mode = 'Audit' } "Write-Output 'audit-ran'"
		$R.Result | Should -Be 'audit-ran'
		$R.Error | Should -BeNullOrEmpty
		Should -Invoke Write-PipePolicyAuditEvent -ModuleName NamedPipe -Times 1 -Exactly -ParameterFilter { $Reason -match "command not allowed: 'Write-Output'" -and $RequestId -eq 3 }
	}
	It 'accepts the mode in any letter case' {
		$R = & (Get-Module NamedPipe) $Script:RunPolicy @{ AllowedCommands = @('Get-Date'); Mode = 'audit' } "Write-Output 'case'"
		$R.Result | Should -Be 'case'
	}
	It 'still blocks without a Mode (enforce is the default)' {
		$R = & (Get-Module NamedPipe) $Script:RunPolicy @{ AllowedCommands = @('Get-Date') } "Write-Output 'blocked'"
		$R.Result | Should -BeNullOrEmpty
		[string]$R.Error | Should -Match 'blocked by pipe request policy'
		Should -Invoke Write-PipePolicyAuditEvent -ModuleName NamedPipe -Times 0 -Exactly
	}
	It 'enforces for any Mode other than Audit' {
		$R = & (Get-Module NamedPipe) $Script:RunPolicy @{ AllowedCommands = @('Get-Date'); Mode = 'Enforce' } "Write-Output 'blocked'"
		[string]$R.Error | Should -Match 'blocked by pipe request policy'
		$R2 = & (Get-Module NamedPipe) $Script:RunPolicy @{ AllowedCommands = @('Get-Date'); Mode = 'Audit ' } "Write-Output 'blocked'"
		[string]$R2.Error | Should -Match 'blocked by pipe request policy'
	}
	It 'Test-RequestPolicy gives the same verdict whatever the Mode' {
		$A = InModuleScope NamedPipe { Test-RequestPolicy -Request "Write-Output 'x'" -Policy @{ AllowedCommands = @('Get-Date'); Mode = 'Audit' } }
		$B = InModuleScope NamedPipe { Test-RequestPolicy -Request "Write-Output 'x'" -Policy @{ AllowedCommands = @('Get-Date') } }
		$A.Allowed | Should -BeFalse
		$A.Reason | Should -Be $B.Reason
	}
}

Describe 'Write-PipePolicyAuditEvent record' {
	BeforeAll { Mock Write-PipeEventLogEntry { $global:NP18Event = @{ Id = $EventId; Type = $EntryType; Text = $Text } } -ModuleName NamedPipe }
	AfterAll { Remove-Variable -Name NP18Event -Scope Global -ErrorAction SilentlyContinue }
	It 'names the request id, first command and reasons but no argument value' {
		$null = InModuleScope NamedPipe {
			Write-PipePolicyAuditEvent -RequestId 9 -Request "Set-Thing -Password 'TOPSECRET-VALUE' -Name x" -Reason "command not allowed: 'Set-Thing'; computed (interpolated) string argument: ""a `$(TOPSECRET-VALUE)"""
		}
		$E = $global:NP18Event
		$E.Id | Should -Be 4514
		$E.Type | Should -Be 'Warning'
		$E.Text | Should -Match 'request 9'
		$E.Text | Should -Match 'First command: Set-Thing'
		$E.Text | Should -Match "command not allowed: 'Set-Thing'"
		$E.Text | Should -Match 'computed \(interpolated\) string argument'
		$E.Text | Should -Not -Match 'TOPSECRET'
	}
	It 'reduces a parse error to its category' {
		$null = InModuleScope NamedPipe { Write-PipePolicyAuditEvent -RequestId 1 -Request 'Foo (' -Reason 'parse error: Missing closing '')'' in expression. SECRET-TEXT' }
		$global:NP18Event.Text | Should -Match 'parse error'
		$global:NP18Event.Text | Should -Not -Match 'SECRET-TEXT'
	}
}

Describe 'Nonce kept off the command line (live, non-elevated)' -Tag 'Integration' {
	BeforeAll {
		$Script:Live = $false
		& $Script:UseScratchEnv
		try
		{
			$Session = Start-PipeSession -MyParameters ([ordered]@{}) -Options @{ WindowStyle = 'Hidden'; ModuleToLoad = $Script:Mtl; NonceViaPipe = $true }
			$Script:Srp = $Session.SendRequestParams
			$Script:Scp = $Session.ServerClientParams
			$Script:Live = $true
		}
		catch { Write-Warning ('live server not started: {0}' -f $_.Exception.Message) }
		finally { & $Script:RestoreEnv }
	}
	AfterAll {
		if ($Script:Live)
		{
			try { $Script:Srp.Type = 'ExitPipe'; $null = $null | Send-Request @Script:Srp }
			catch { Write-Warning ('live server exit request failed: {0}' -f $_.Exception.Message) }
		}
	}
	It 'starts a server whose command line carries no nonce' {
		if (-not $Script:Live) { Set-ItResult -Skipped -Because 'no live server'; return }
		$ServerPid = [int]$Script:Srp.DataObject.ServerPID
		$Cmd = [string](Get-CimInstance -ClassName Win32_Process -Filter ('ProcessId = {0}' -f $ServerPid)).CommandLine
		$Cmd | Should -Match '-Spawned -SerialData '
		$Serial = ($Cmd -split '-SerialData ', 2)[1].Trim()
		$Decoded = InModuleScope NamedPipe -Parameters @{ S = $Serial } { ConvertFrom-Serial -Text $S }
		@($Decoded.Keys) -contains 'Nonce' | Should -BeFalse
		$Decoded.NonceViaPipe | Should -BeTrue
		$Cmd | Should -Not -Match ([regex]::Escape([string]$Script:Scp.Nonce))
	}
	It 'still serves requests: the server adopted the nonce over the pipe' {
		if (-not $Script:Live) { Set-ItResult -Skipped -Because 'no live server'; return }
		$Script:Srp.Type = 'ScriptBlock'
		$Script:Srp.DataObject = 'Write-Output "over-the-pipe"' | Send-Request @Script:Srp
		[string]$Script:Srp.DataObject.Error | Should -BeNullOrEmpty
		[string]$Script:Srp.DataObject.Result | Should -Be 'over-the-pipe'
	}
	It 'the client recorded the verified server PID and the health channel works with the same nonce' {
		if (-not $Script:Live) { Set-ItResult -Skipped -Because 'no live server'; return }
		[int]$Script:Scp.PipeInfo.VerifiedServerPid | Should -Be ([int]$Script:Srp.DataObject.ServerPID)
		Test-PipeSession -PipeInfo $Script:Scp.PipeInfo | Should -BeTrue
		(InModuleScope NamedPipe -Parameters @{ Pi = $Script:Scp.PipeInfo } { Invoke-PipeHealthCommand -PipeInfo $Pi -Command STATUS }) | Should -Match '^STATUS:'
	}
}

Describe 'A server started without a nonce admits only the PID that started it (live, non-elevated)' -Tag 'Integration' {
	It 'rejects a client from another process, closes the connection and ends by its own deadline' {
		$Spawn = InModuleScope NamedPipe -Parameters @{ Mtl = $Script:Mtl } {
			$S = Set-ObjectParameterSet -Server -Dataset $StrServerClientParams -MyParameters ([pscustomobject]@{ ClientConnectTimeout = 2000; ModuleToLoad = $Mtl })
			$Copy = [ordered]@{}
			foreach ($K in $S.Keys) { if ([string]$K -cne 'Nonce') { $Copy[$K] = $S[$K] } }
			$Copy.NonceViaPipe = $true
			# PID 4 (System) is never the process connecting here.
			$Copy.ExpectedClientPid = [uint32]4
			$Copy.Spawned = $true
			[pscustomobject]@{ Serial = (ConvertTo-Serial -Object $Copy); Name = [string]$S.PipeInfo.Name }
		}
		$Script = Join-Path $Script:ModulePath 'FunctionsWindows\Start-PipeServerOrClient.ps1'
		$Exe = Join-Path $PSHOME $(if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' })
		& $Script:UseScratchEnv
		try { $Proc = Start-Process -FilePath $Exe -ArgumentList ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Spawned -SerialData {1}' -f $Script, $Spawn.Serial) -WindowStyle Hidden -PassThru }
		finally { & $Script:RestoreEnv }
		$Client = [System.IO.Pipes.NamedPipeClientStream]::new('.', $Spawn.Name, [System.IO.Pipes.PipeDirection]::InOut)
		try
		{
			$Client.Connect(15000)
			$Writer = [System.IO.StreamWriter]::new($Client); $Writer.AutoFlush = $true
			$Reader = [System.IO.StreamReader]::new($Client)
			$Writer.WriteLine((InModuleScope NamedPipe { New-PipeNonce }))
			$Task = $Reader.ReadLineAsync()
			# A rejected connection is closed by the server: the read ends with no data.
			$Closed = $false
			try { if ($Task.Wait(8000)) { $Closed = [string]::IsNullOrEmpty($Task.Result) } } catch { $Closed = $true }
			$Closed | Should -BeTrue
		}
		finally { $Client.Dispose() }
		# The unclaimed server ends itself (first-connect deadline); nothing is killed here.
		$Proc.WaitForExit(30000) | Should -BeTrue
	}
}

Describe 'Test scripts do not launch encoded commands' {
	It 'has no -EncodedCommand (or -enc / -ec short form) under Tests\ (Defender flags such launches)' {
		# The pattern is assembled so this file does not match itself.
		$Pattern = '-(?:' + 'Encoded' + 'Command|enc|ec)\b'
		$Hits = Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -File -Include *.ps1, *.psm1 |
			Where-Object { $_.FullName -ne $PSCommandPath } |
			Select-String -Pattern $Pattern -CaseSensitive:$false
		@($Hits).Count | Should -Be 0
	}
}