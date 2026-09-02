#requires -Version 7.0
#
# PS7 ONLY (the PARENT). [System.IO.Pipes.NamedPipeServerStreamAcl] is .NET Core only, so under
# Windows PowerShell 5.1 this failed with "Unable to find type" - which reads like a broken test
# rather than the wrong host. The #requires makes 5.1 skip it with a clear reason instead. The
# CHILD processes deliberately run under 5.1; see the note in Test-ChildAt.
#
# Regression test for 0.11 item 4.1b - the pipe mandatory integrity label (Set-PipeIntegrityLabel).
#
# Proves the SHIPPED module function labels a pipe such that a genuine LOW-integrity client is refused
# while a Medium client connects. Same user + same DACL for both children, so ONLY the integrity label
# can account for the difference.
#
# Runs ELEVATED or NOT (CreateProcessAsUser with a lowered duplicate of your OWN token needs no
# privilege). Reports via EXIT CODE (a Low-IL child cannot write to the Medium %TEMP%).
#   child exit = ilCode*100 + resultCode     il: 1=Low 2=Medium 3=High 0=?   result: 10=CONNECTED
#   20=ACCESS-DENIED 21=TIMEOUT 22=IO-ERROR 25=other  (20/21/22 all = "the label refused it")
#
# Manual script (spawns child processes), not Pester. Run from this folder.

$ErrorActionPreference = 'Stop'

# Test the REAL module function (internal -> dot-source it directly; it is self-contained).
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'FunctionsWindows\Set-PipeIntegrityLabel.ps1')

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class LowILLauncher {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    struct STARTUPINFO { public int cb; public string res0; public string desktop; public string title;
        public int x,y,xs,ys,xcc,ycc,fill,flags; public short show,res1; public IntPtr res2,stdin,stdout,stderr; }
    [StructLayout(LayoutKind.Sequential)] struct PROCESS_INFORMATION { public IntPtr hProcess,hThread; public int pid,tid; }
    [StructLayout(LayoutKind.Sequential)] struct SID_AND_ATTRIBUTES { public IntPtr Sid; public uint Attributes; }
    [StructLayout(LayoutKind.Sequential)] struct TOKEN_MANDATORY_LABEL { public SID_AND_ATTRIBUTES Label; }
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("advapi32.dll", SetLastError=true)] static extern bool OpenProcessToken(IntPtr h,uint a,out IntPtr t);
    [DllImport("advapi32.dll", SetLastError=true)] static extern bool DuplicateTokenEx(IntPtr t,uint a,IntPtr at,int imp,int type,out IntPtr nt);
    [DllImport("advapi32.dll", SetLastError=true)] static extern bool SetTokenInformation(IntPtr t,int cls,ref TOKEN_MANDATORY_LABEL i,int len);
    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool ConvertStringSidToSid(string s,out IntPtr sid);
    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    static extern bool CreateProcessAsUser(IntPtr t,string app,StringBuilder cmd,IntPtr pa,IntPtr ta,bool inh,uint fl,IntPtr env,string dir,ref STARTUPINFO si,out PROCESS_INFORMATION pi);
    [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h,uint ms);
    [DllImport("kernel32.dll")] static extern bool GetExitCodeProcess(IntPtr h,out uint code);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    public static int RunAtIntegrity(string appPath, string cmdLine, string ilSid) {
        IntPtr cur; if(!OpenProcessToken(GetCurrentProcess(),0xF01FF,out cur)) throw new Exception("OpenProcessToken "+Marshal.GetLastWin32Error());
        IntPtr dup; if(!DuplicateTokenEx(cur,0x02000000,IntPtr.Zero,2,1,out dup)) throw new Exception("DuplicateTokenEx "+Marshal.GetLastWin32Error());
        IntPtr sid; if(!ConvertStringSidToSid(ilSid,out sid)) throw new Exception("ConvertStringSidToSid "+Marshal.GetLastWin32Error());
        TOKEN_MANDATORY_LABEL tml; tml.Label.Sid=sid; tml.Label.Attributes=0x20;
        if(!SetTokenInformation(dup,25,ref tml,Marshal.SizeOf(typeof(TOKEN_MANDATORY_LABEL))+8)) throw new Exception("SetTokenInformation "+Marshal.GetLastWin32Error());
        STARTUPINFO si=new STARTUPINFO(); si.cb=Marshal.SizeOf(typeof(STARTUPINFO));
        StringBuilder cb=new StringBuilder(cmdLine); PROCESS_INFORMATION pi;
        if(!CreateProcessAsUser(dup,appPath,cb,IntPtr.Zero,IntPtr.Zero,false,0x08000000,IntPtr.Zero,null,ref si,out pi)) throw new Exception("CreateProcessAsUser "+Marshal.GetLastWin32Error());
        WaitForSingleObject(pi.hProcess,15000);
        uint code; GetExitCodeProcess(pi.hProcess,out code);
        CloseHandle(pi.hThread); CloseHandle(pi.hProcess); CloseHandle(dup); CloseHandle(cur);
        return (int)code;
    }
}
"@

function New-ModuleLabeledPipe {
	param([string]$Name)
	$mySid = [Security.Principal.WindowsIdentity]::GetCurrent().User
	$ps = [System.IO.Pipes.PipeSecurity]::new()
	$ps.AddAccessRule([System.IO.Pipes.PipeAccessRule]::new($mySid,'ReadWrite','Allow'))
	# module data-pipe config: Instances=1, Async+WriteThrough
	$opts = [System.IO.Pipes.PipeOptions]::Asynchronous -bor [int][System.IO.Pipes.PipeOptions]::WriteThrough
	$pipe = [System.IO.Pipes.NamedPipeServerStreamAcl]::Create($Name,[System.IO.Pipes.PipeDirection]::InOut,1,[System.IO.Pipes.PipeTransmissionMode]::Byte,$opts,0,0,$ps)
	# <<< the thing under test: the shipped module function >>>
	$applied = Set-PipeIntegrityLabel -Pipe $pipe
	if (-not $applied) { $pipe.Dispose(); throw 'Set-PipeIntegrityLabel returned $false (label not applied)' }
	$pipe
}

function Test-ChildAt {
	param([string]$IlSid, [string]$Label, [string]$ExpectIL, [string]$Expect)
	$name = 'lbl-' + [guid]::NewGuid().ToString('N')
	$srv  = New-ModuleLabeledPipe -Name $name
	$iar  = $srv.BeginWaitForConnection($null,$null)
	$child = @"
`$g = whoami /groups /fo csv | ConvertFrom-Csv
`$il = (`$g | Where-Object { `$_.'Group Name' -match 'Mandatory Level' }).'Group Name'
`$ilc = if (`$il -match 'Low') {1} elseif (`$il -match 'Medium') {2} elseif (`$il -match 'High') {3} else {0}
`$rc = 30
try { `$c = New-Object System.IO.Pipes.NamedPipeClientStream('.','$name','InOut'); `$c.Connect(3000); `$c.Dispose(); `$rc = 10 }
catch { `$e = `$_.Exception; while (`$e.InnerException) { `$e = `$e.InnerException }
        `$rc = if (`$e -is [System.UnauthorizedAccessException]) {20} elseif (`$e -is [System.TimeoutException]) {21} elseif (`$e -is [System.IO.IOException]) {22} else {25} }
exit (`$ilc*100 + `$rc)
"@
	$enc  = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($child))
	# Windows PowerShell 5.1 for the CHILD, deliberately - not $PSHOME\pwsh.exe.
	#
	# PowerShell 7 cannot START at Low integrity: it writes to per-user locations during startup that
	# a Low-IL token cannot reach, so the process died with 0xE0434352 (CLR unhandled exception)
	# before running a single line. The harness then read IL=[unknown] and connect=[raw=-532462766]
	# and reported FAIL - which looked like the module's integrity label misbehaving when in fact the
	# LOW case had never been exercised at all. Diagnosed 2026-08-13.
	#
	# The payload above is deliberately version-agnostic (whoami, NamedPipeClientStream, exit code),
	# so 5.1 runs it unchanged. BOTH children use the same host, so the "same user, same DACL, only
	# the integrity level differs" property this test rests on still holds.
	#
	# The PARENT still requires PS7 - see the #requires at the top - because
	# NamedPipeServerStreamAcl is .NET Core only.
	$ChildHost = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
	$code = -1
	try { $code = [LowILLauncher]::RunAtIntegrity($ChildHost, ('"{0}" -NoProfile -EncodedCommand {1}' -f $ChildHost, $enc), $IlSid) }
	catch { Write-Host ("  {0,-14} LAUNCH FAILED: {1}" -f $Label, $_.Exception.Message) -ForegroundColor Red }
	if ($iar.AsyncWaitHandle.WaitOne(300)) { try { $srv.EndWaitForConnection($iar) } catch {} }
	$srv.Dispose()
	$ilc = [Math]::Floor($code / 100); $rc = $code % 100
	$ilName = @{1='Low';2='Medium';3='High';0='unknown'}[[int]$ilc]
	$resName = @{10='CONNECTED';20='ACCESS-DENIED';21='TIMEOUT';22='IO-ERROR';25='other-error';30='no-result'}[[int]$rc]
	if (-not $resName) { $resName = "raw=$code" }
	$refused = @('ACCESS-DENIED','TIMEOUT','IO-ERROR')
	$resOk = if ($Expect -eq 'CONNECTED') { $resName -eq 'CONNECTED' } else { $refused -contains $resName }
	$ok = ($ilName -eq $ExpectIL) -and $resOk
	Write-Host ("  {0,-14} ran at IL=[{1}]  connect=[{2}]   [{3}]" -f $Label, $ilName, $resName,
		$(if($ok){'as expected'} elseif($ilName -ne $ExpectIL){"WRONG IL (wanted $ExpectIL)"} else {"UNEXPECTED (wanted $Expect)"})) -ForegroundColor $(if($ok){'Green'}else{'Red'})
	[PSCustomObject]@{ IL=$ilName; Result=$resName; Ok=$ok }
}

Write-Host '=== 4.1b regression: module Set-PipeIntegrityLabel must block LOW-IL, allow Medium ===' -ForegroundColor Magenta
$med = Test-ChildAt -IlSid 'S-1-16-8192' -Label 'MEDIUM child' -ExpectIL 'Medium' -Expect 'CONNECTED'
$low = Test-ChildAt -IlSid 'S-1-16-4096' -Label 'LOW child'    -ExpectIL 'Low'    -Expect 'ACCESS-DENIED'

Write-Host ''
if ($med.Ok -and $low.Ok) {
	Write-Host 'PASS: Set-PipeIntegrityLabel enforces the integrity boundary (Medium connects, Low refused).' -ForegroundColor Green
	exit 0
} else {
	Write-Host ('FAIL: medium IL=[{0}] result=[{1}] ; low IL=[{2}] result=[{3}]' -f $med.IL,$med.Result,$low.IL,$low.Result) -ForegroundColor Red
	exit 1
}
