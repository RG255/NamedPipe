# NamedPipe Module v0.13 - User Guide

<!-- CONTRIBUTOR NOTE: Do NOT use em-dashes in this file. Use a regular hyphen (-) only.
     Em-dashes cause PowerShell parser errors in string literals and may be silently
     corrupted by some editors. -->

## Overview

The NamedPipe module provides Inter-Process Communication (IPC) between PowerShell processes using Windows Named Pipes. It allows a client process to send commands to a server process running in a separate window, optionally with elevated (Administrator) privileges.

**Key features:**
- Execute PowerShell commands on a separate process (including elevated/admin)
- **Session management** - `Start-PipeSession`, `Test-PipeSession`, `Stop-PipeSession` replace boilerplate
- Automatic chunking for large data transfers (default 32KB chunks)
- Configurable serialization depth for complex objects
- SHA-256 checksum verification for chunked data integrity
- Built-in debug output at multiple verbosity levels
- **FunctionExportTable** - internal functions are no longer exported by default
- **Consumer module tracking** - spawned server automatically imports consumer modules
- Cross-version support (PowerShell 5.1 and PowerShell 7+)

**Self-contained:** All required functions (ConvertTo-Serial, ConvertFrom-Serial, Get-MyError, Show-VerboseData, Set-Window, etc.) are included within the NamedPipe module itself - no external dependencies.

### What's New in v0.4

| Feature | Description |
|---------|-------------|
| `Start-PipeSession` | Replaces ~20 lines of boilerplate setup with a single call |
| `Test-PipeSession` | Non-disruptive pipe health check (returns `$true`/`$false`) |
| `Stop-PipeSession` | Sends ExitPipe + disposes Writer/Reader in one call |
| `FunctionExportTable` | Internal functions (Send-Data, Receive-Data, etc.) are no longer exported |
| `ModuleToLoad` | Spawned server imports consumer module via Options (replaces `$ML`/`$ModuleLoaded`) |
| AccessList default | Defaults to current user only (no Unbound) |
| `InfoDisplayBit*` constants | Named constants for InfoDisplay bitmask bits: `$InfoDisplayBitProgress` (1), `$InfoDisplayBitVerbose` (2), `$InfoDisplayBitDebug` (4) |
| ConvertTo-ParameterSet fix | Empty string parameter values now serialise as `''` instead of nothing, preventing ParseException in dynamically created scriptblocks |

### What's New in v0.5

| Feature | Description |
|---------|-------------|
| `RedactPattern` | Session-level option that scrubs sensitive data from `[Server] Executing:` echo-back before it reaches the client. Bitmask `Option` field: bit 1=built-in (any 40+ char Base64 run), bit 2=consumer regex `Pattern`, bit 4=consumer `Command` ScriptBlock. Bits are applied in order; each step receives the result of the previous. |
| InfoDisplay bitmask | `Get-SBResult` echo-back now gated on bit 1 of InfoDisplay (was `>= 1`). All internal checks use `-band` not `-ge`. |
| `Send-Request` Last* rotation | After each request completes, `Request`/`Parameters`/`Data` are copied to `LastRequest`/`LastParameters`/`LastData` for diagnostics. |

### What's New in v0.6

| Feature | Description |
|---------|-------------|
| Multi-version safety | `Get-Module -Name NamedPipe \| Sort-Object Version -Descending \| Select-Object -First 1` used in spawned server, ensuring the highest loaded version is used when multiple NamedPipe versions are simultaneously in memory (e.g. profile auto-imports 0.4, consumer module imports 0.5). |

### What's New in v0.7

| Feature | Description |
|---------|-------------|
| Health pipe channel | A dedicated `.Health` background pipe is started automatically by `Start-PipeServerOrClient` in the server process. It listens on `PipeName.Health` using `MaxAllowedServerInstances` so concurrent health checks can connect without disrupting the main data pipe. |
| `Test-PipeSession` rewrite | Now performs a two-phase check. Phase 1 (passive): verifies PipeInfo, `Pipe.IsConnected`, Reader, Writer, and `Writer.BaseStream` are all valid. Phase 2 (active): connects to the `.Health` pipe, sends `PING:<nonce>`, and verifies `PONG:<nonce>` is echoed back. A per-call GUID nonce prevents replay attacks. Returns `$false` immediately if Phase 1 fails. |
| Nonce-based liveness | Phase 2 uses `[guid]::NewGuid().ToString('N')` as a per-call challenge. A squatting process cannot pass the check without relaying the exact nonce value, confirming the original server process is alive. |
| `ModuleToLoad.Path` | `ModuleToLoad` now accepts an optional `Path` field containing the full path to the consumer module's `.psd1` file. When present, the spawned server imports by path rather than by name+version. This is required when the module lives on a network or OneDrive drive (`L:\`, etc.) that is not in `$PSModulePath` in the elevated spawned process. |
| Spawn path fix | `Start-PipeServerOrClient` now uses `Get-Module -Name NamedPipe \| Sort-Object Version -Descending \| Select-Object -First 1` to locate its own script file when building the spawned server command line. This replaces the previous `$MyInvocation`-based approach and is robust when multiple NamedPipe versions are simultaneously loaded in the session. |

### What's New in v0.10 (injection hardening - BUILT, TESTED, DEPLOYED)

The mechanism below is complete and has shipped in every version since 0.10 (every version since is on
the hardened transport line). It remains fully **opt-in per
session**: as of 2026-08-14 no consumer has actually set `RequestPolicy`, so behaviour is IDENTICAL to
0.9 for everyone today unless you opt in to the option below yourself. (The planning doc's Section 9
records why adoption is not currently recommended for any consumer here - the request policy itself
works exactly as documented, but proving an `AllowedCommands` list is complete enough to trust is a much
higher bar than it first appears.)

| Feature | Description |
|---------|-------------|
| `RequestPolicy` option (request allowlist) | Session-level option that constrains what the elevated server will execute. When set, every request must pass a **default-deny AST allowlist** BEFORE it runs: only calls to commands in `AllowedCommands`, with literal/variable/array/hashtable arguments, are permitted; everything else (Add-Type, `&`/`.` invocation, Invoke-Expression, `.NET` method/type expressions, in-request function defs, computed/interpolated arguments, and - by default-deny - any construct not on the allow list, e.g. a `LanguageMode` assignment) is rejected. On rejection the server does NOT execute and returns `Error = 'Request blocked by pipe request policy: <reason>'`. **Not set = no enforcement (unchanged from 0.9).** |

**Usage:**

```powershell
$Session = Start-PipeSession -MyParameters $Private:MyBoundParameters -Options @{
    $StrAdminRequired = $True
    # Only these commands may run over the pipe; anything else is refused before execution.
    RequestPolicy     = @{
        AllowedCommands        = @('Invoke-VHDAction')   # bare command names, case-insensitive
        AllowComputedArguments = $false                  # $true relaxes interpolated-string args only
    }
}
```

Notes:
- Argument VALUES stay free (paths, sizes, ...); only the command surface and argument *shape* are
  constrained. Values are still escaped by `ConvertTo-ParameterSet`.
- The "ship helper functions inside the scriptblock" pattern is refused under a policy - move that logic
  into a named server function (the dispatch shape, e.g. `Invoke-VHDAction`, which is exactly what passes).
- Strict by default: computed arguments (`$( )`, `-f`, command substitution, interpolated strings) are
  rejected. Set `AllowComputedArguments = $true` to permit interpolated strings only.

### What's New in v0.11 (transport hardening)

v0.11 adds a second, automatic layer of protection to the pipe itself. Unlike the `RequestPolicy` option
above, it needs **no configuration** - it is always on - and it does not change how you use the module.

| Feature | Description |
|---------|-------------|
| Pipe integrity label | The data pipe is tagged with a Windows "Medium integrity" label the moment it is created, so a **low-integrity** process (see below) cannot connect to it at all - the operating system refuses the connection before any request is even sent. Normal apps are unaffected. Applied automatically; if it cannot be applied for any reason the pipe still works (the label is a bonus layer, never a blocker). |
| No "Interactive" access widening | The pipe is granted only to your exact user account, never to the broad "any interactive user" identity. |
| Capability nonce | Each session gets a one-time secret. The genuine client presents it the instant it connects; the server admits only a connection that shows the right secret and quietly drops any that does not. Automatic - you never see or handle it. |

#### Understanding integrity levels (plain English)

Windows stamps **every running program with a trust tier**, called its *integrity level* (IL). Think of
it as a security clearance the program runs with:

| Integrity level | What runs there | Example |
|-----------------|-----------------|---------|
| **High** | Administrator / elevated programs (after a UAC prompt) | An elevated PowerShell window; an installer you approved |
| **Medium** | Normal programs you launch day to day | Your desktop apps, a normal PowerShell window, File Explorer |
| **Low** | Deliberately **sandboxed** code that is treated as untrusted, so that if it is hijacked the damage is contained | A web browser's page/tab process, a PDF viewer's "protected mode", Windows Store / AppContainer apps |

The important rule Windows enforces (called *Mandatory Integrity Control*): **a lower-integrity program
cannot tamper with something owned by a higher-integrity one - even when they are the same user account.**
That is exactly why a compromised web page (Low) cannot quietly reach into your documents or your normal
apps (Medium): the account is the same, but the integrity level is not.

#### Why the pipe needs this

The pipe already restricts access by **user account** (its access-control list). But "same user account"
is not the same as "trusted": a **Low-integrity** process running under your account - say, an exploited
browser tab - still carries your account, so the account check alone would let it connect. Because the
NamedPipe server can run privileged (elevated) work, we do not want any sandboxed/untrusted Low process
to reach it.

So the pipe is labelled **Medium**. Windows then refuses any process **below** Medium (i.e. Low) the
access that connecting requires, while Medium and above connect normally. In short:

- Your ordinary Medium programs (and elevated High ones) connect exactly as before - **no change**.
- A Low-integrity process (a sandbox/AppContainer app, a browser-renderer or PDF-sandbox escape) is
  **blocked by Windows itself**, before it can send a single request.

This is a defence-in-depth layer. It does **not** replace the `RequestPolicy` allowlist - that constrains
*what* a connected client may run; this constrains *who* (which trust tier) may connect at all. It also
does not stop another *Medium* program running as you (that is a separate concern addressed elsewhere in
the hardening plan). It specifically closes the "sandboxed/low-trust code escalating through the pipe"
door.

#### The capability nonce (plain English)

A pipe's **name is not a secret**: any program on the machine can list the open pipe names, so knowing the
name is not proof of being the right client. To close that gap, each session also mints a **nonce** - a
one-time random secret (like a cloakroom ticket). The server is told the nonce when it starts; the genuine
client is given the same nonce and **presents it as the very first thing it says** after connecting. The
server compares: right ticket -> you are in; wrong ticket, or no ticket at all -> you are shown the door
(disconnected) and the server keeps waiting for the real client.

Two things make this the right fit here:

- **It is not tied to which program you are.** The check is "do you hold the secret", not "are you a
  specific process". That matters because some legitimate workflows hand the session from one window to
  another - e.g. a GUI starts the elevated server, then opens a separate terminal window that continues
  the same session. That terminal is a *different* program, but it can be given the same nonce, so it is
  admitted. A rule based on "must be the exact program that started the server" would have wrongly locked
  that terminal out.
- **A stranger who only knows the pipe name is refused.** Without the secret, enumerating the name buys an
  attacker nothing - the first line they send is not the nonce, so they are dropped before any request is
  processed.

This is automatic and invisible: you do not generate, pass, or see the nonce in normal use. (It is also a
defence-in-depth layer, not a wall: if an attacker can read the genuine client's memory it can read the
nonce too - an operating-system-integrity problem no pipe check can solve.)

### What's New in v0.13 (leak-proof session hand-off)

v0.11 admits a *different* process that presents the session nonce - which is what lets a GUI hand its
elevated session to a separate terminal window. But *how* does that terminal get the nonce? Passing it in an
environment variable or on the command line would leak it, because any process running as the same user can
read those. v0.13 closes that gap: the nonce is **never** passed to the new process out-of-band. Instead the
two ends do a short **PID-verified handshake** and the server delivers the nonce over the pipe itself, to the
one process whose identity it has just confirmed.

| Feature | Description |
|---------|-------------|
| PID hand-off (`HANDOFF` / `HANDIN`) | The authenticated client tells the server "the next connection will be process X"; the reconnecting process proves it really is X (Windows reports the connecting PID to the server - the client cannot forge it); only then does the server hand it the nonce. Nothing secret ever crosses a channel a bystander can read - only the pipe **name**, which is already public. |

See **Session Hand-off** below for the full flow. Everything else is unchanged from v0.11, and consumers that
do not use the hand-off are entirely unaffected.

### What's New in v0.15 (RedactPotentialSecrets - what it actually is, and what it is not)

See **RedactPotentialSecrets** below (under Session Options) for the full explanation - this section
is the short version. Bit 1 of `RedactPattern` (built-in redaction) used to be an unconditional
regex that stripped any 40+ character run of base64/hex-alphabet characters. It has been replaced
with a real structural base64 check, gated behind a new option, `RedactPotentialSecrets` (default
`$true`). A matched value now shows as `<base64 encoded>` instead of `<redacted>`.

**Read the full section below before relying on this for anything security-relevant** - it explains
a real design mistake made and caught while building this (an earlier version fragmented text at
punctuation and flagged ordinary words like a 20-character parameter name), why the fix tests whole
quoted values instead of loose fragments, and - most importantly - why this can only ever detect "is
this shaped like base64," never "is this actually a secret."

## Architecture

The module uses a client-server architecture over Windows Named Pipes:

```
Your Script (Client)                    Server Process (Separate Window)
====================                    ================================

1. Start-PipeSession  ----------------> Spawns new PowerShell process
   (sets up everything)                 Imports NamedPipe module
                                        Imports module specified by ModuleToLoad
                                        Creates NamedPipeServerStream
                       <--------------> Connection established

2. Send-Request        ----------------> Receive-Data (receives request)
   (sends command via pipe)              Get-SBResult (executes command)
                        <--------------- Send-Data (sends result back)
   Result in DataObject.Result

3. Stop-PipeSession    ----------------> Server acknowledges and exits
   (ExitPipe + dispose)                  Resources cleaned up
```

### Data Flow

All configuration flows through data structures, not hardcoded parameters:

```
Script Parameters --> Start-PipeSession --> MyOptions --> ServerClientParams --> PipeInfo --> Send-Data/Receive-Data
```

The `$Str*` variables (e.g., `$StrInfoDisplay`, `$StrChunkSize`) are string constants defined in `DefineVariablesPipe.ps1` and used as dynamic property names throughout the module. This allows consistent property access like `$ServerClientParams.$StrInfoDisplay` instead of `$ServerClientParams.InfoDisplay`.

## Quick Start

### Minimal Working Example

```powershell
# Step 1: Import the module
Remove-Module -Name NamedPipe -Force -ErrorAction SilentlyContinue
Import-Module -Name NamedPipe -Force -RequiredVersion 0.8

# Step 2: Capture bound parameters and start session
$Private:MyBoundParameters = $PSCmdlet.MyInvocation.BoundParameters
$Session = Start-PipeSession -MyParameters $Private:MyBoundParameters
$ServerClientParams = $Session.$StrServerClientParams
$SendRequestParams  = $Session.$StrSendRequestParams

# Step 3: Send commands to the server
$SendRequestParams.$StrType = $StrScriptBlock
$SendRequestParams.$StrDataObject = 'Get-Process | Select-Object -First 5' | Send-Request @SendRequestParams

# The result is in:
$SendRequestParams.$StrDataObject.$StrResult

# Step 4: Clean up
Stop-PipeSession -SendRequestParams $SendRequestParams -PipeInfo $ServerClientParams.$StrPipeInfo
```

## Session Management (New in v0.4)

### Start-PipeSession

Replaces the ~20 lines of boilerplate that were previously required to set up a pipe session. It creates MyOptions, ServerClientParams, and SendRequestParams, starts the server process, connects the client, and returns both parameter objects ready for use.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `MyParameters` | IDictionary | Yes | Caller's `$PSCmdlet.MyInvocation.BoundParameters` |
| `Options` | Hashtable | No | Overrides to apply (e.g., `@{ $StrAdminRequired = $True }`) |
| `AccessList` | String[] | No | Pipe security identifiers. Defaults to current user only |

**Basic usage:**
```powershell
$Session = Start-PipeSession -MyParameters $Private:MyBoundParameters
$ServerClientParams = $Session.$StrServerClientParams
$SendRequestParams  = $Session.$StrSendRequestParams
```

**With options:**
```powershell
$Session = Start-PipeSession -MyParameters $Private:MyBoundParameters -Options @{
    $StrAdminRequired = $True
    $StrNoExitOnError = $True
    $StrWindowStyle   = $StrMinimized
}
```

**With custom access list:**
```powershell
$Session = Start-PipeSession -MyParameters $Private:MyBoundParameters -AccessList @(
    'DOMAIN\User:Allow:ReadWrite'
    'Administrators:Allow:ReadWrite'
)
```

### Test-PipeSession

Two-phase health check that confirms the pipe is connected and the server process is alive.

**Phase 1 (passive):** verifies PipeInfo object, `Pipe.IsConnected`, Reader, Writer, and
`Writer.BaseStream` are all valid. Returns `$false` immediately on any failure - no network I/O.

**Phase 2 (active):** connects to the dedicated `.Health` pipe started automatically by the server,
sends `PING:<nonce>`, and verifies `PONG:<nonce>` is echoed back. A per-call GUID nonce prevents
replay attacks. Default timeout is 2000 ms.

```powershell
if (Test-PipeSession -PipeInfo $ServerClientParams.$StrPipeInfo)
{
    # Pipe is healthy, safe to send commands
    $SendRequestParams.$StrDataObject = 'Get-Process' | Send-Request @SendRequestParams
}
else
{
    Write-Warning 'Pipe session is no longer connected'
}
```

### Stop-PipeSession

Sends an ExitPipe request (if the pipe is still connected) and disposes the Writer and Reader. The dispose is in a `finally` block so cleanup happens even if an error occurs.

```powershell
Stop-PipeSession -SendRequestParams $SendRequestParams -PipeInfo $ServerClientParams.$StrPipeInfo
```

## Sharing a Session Across Multiple Calls

By default, each function that calls `Start-PipeSession` opens its own server process, does its
work, and closes the session. This is correct and sufficient for most use cases - no setup needed.

When you want multiple calls to share one server process (one UAC prompt for the whole batch),
you pre-open a session before calling the functions. The functions detect it via a scope-walk
and reuse it automatically.

### How the Scope-Walk Works

Consumer modules that support shared sessions (such as VHDTools) implement `New-VHDPipeSession`
which walks the PowerShell call stack using `Get-Variable -Name 'Session' -Scope N` upward from
the immediate caller. If it finds a `$Session` variable containing a healthy pipe session at any
ancestor scope, it returns that session with `IsNew=$false` and the function does not open or
close the server. If no healthy session is found, a new server is opened with `IsNew=$true` and
the function closes it in its `Finally` block.

### The `$Script:Session` Requirement

For the scope-walk to find the pre-opened session reliably, the variable **must be declared at
script scope** using `$Script:Session`, not as a plain local variable `$Session`.

**Why:** `Get-Variable -Scope N` counts scopes numerically from the calling function upward.
When crossing the boundary from a module function (e.g. `New-VHDDisk` in VHDTools) back into
a calling `.ps1` script, scope numbering can skip or misalign depending on call depth. A plain
`$Session` at the script's top level may be in a local scope that the walk misses. `$Script:`
pins the variable to the script's persistent scope, which is always reachable regardless of
call depth.

```powershell
# CORRECT - scope-walk will find this from inside module functions
$Script:Session = New-VHDPipeSession

New-VHDDisk @Params1    # scope-walk finds $Script:Session - IsNew=$false, no UAC
New-VHDDisk @Params2    # same
New-VHDDisk @Params3    # same

Close-VHDPipeSession    # scope-walk finds $Script:Session, closes and nulls it


# ALSO CORRECT - no shared session, each call opens and closes its own server
New-VHDDisk @Params1    # opens server, IsNew=$true, closes when done (one UAC)
New-VHDDisk @Params2    # opens another server (another UAC)
```

### Rules

| Caller type | Variable to use | Reason |
|---|---|---|
| User `.ps1` script pre-opening a shared session | `$Script:Session` | Must be at script scope for cross-module scope-walk to find it |
| Module function (`New-VHDDisk`, etc.) | `$Session` (plain) | `$Script:` inside a module function refers to the module's own script scope - wrong place |
| Self-contained helper that opens and closes its own session | `$Session` (plain) | Never needs to be found by scope-walk |

**Note:** `PSUseDeclaredVarsMoreThanAssignments` will warn on `$Script:Session` in test scripts
because PSScriptAnalyzer cannot see the scope-walk usage. Suppress it with:

```powershell
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'Session',
    Justification = '$Session is set for scope-walk reuse by called functions')]
```

## Session Hand-off (transferring a live session to another process)

"Sharing a Session Across Multiple Calls" above keeps one server for many calls **inside a single process**.
A **hand-off** goes one step further: it transfers a live, already-elevated session to a **different
process** - most often a GUI that spawns a separate terminal window and wants that window to keep using the
same elevated server, with **no second UAC prompt** and **no secret leaking** between the two.

### The problem it solves

Three facts collide:

1. The server admits a connection only if it presents the session **nonce** (the capability secret, see
   "What's New in v0.11").
2. The data pipe is **single-instance** - exactly one client may be connected at a time (this is required by
   the Medium-integrity label). So the GUI and the terminal can never be connected at the same instant; one
   must release the pipe before the other connects.
3. The nonce **must not be handed to the new process out-of-band.** Environment variables and command-line
   arguments are readable by any process running as the same user, so putting the nonce there would leak it to
   exactly the same-user attacker the nonce exists to stop.

### The protocol (v0.13)

A short, PID-verified handshake. Only the pipe **name** (public - pipe names are enumerable) ever crosses
out-of-band; the nonce is delivered over the PID-verified pipe.

1. **The owner learns the new process's PID.** The GUI spawns the terminal with `-PassThru`, so it holds the
   child's process object (its PID **X**) and a live handle that keeps X from being reused while the child lives.
2. **The owner ARMS the server** - over its own authenticated connection it sends a `HANDOFF X` request. The
   server records "the next hand-in must be process X". Only an already-authenticated client can arm a hand-off.
3. **The owner releases the pipe** - it sends a `Disconnect` (the server re-listens) and disposes its client
   handle, freeing the single instance. It keeps its nonce.
4. **The new process claims the hand-off.** It connects and, as its very first line, sends the `HANDIN` marker
   (instead of a nonce it does not have).
5. **The server verifies identity and delivers the nonce.** It asks the kernel for the connecting client's PID
   (`GetNamedPipeClientProcessId` - set by Windows, not by the client, so it cannot be spoofed). If it equals
   the armed **X**, the server writes the **nonce** back over this now-verified channel; the new process stores
   it and behaves as a normal client from then on. Any other PID, or a `HANDIN` with nothing armed, is refused
   exactly like a wrong nonce.

The new process learns it is in hand-off mode from a non-secret signal the consumer chooses (VHDTools uses the
`$env:VHD_PIPE_NAME` environment variable, which carries only the public pipe name). It then does a `HANDIN`
instead of the normal nonce handshake.

### Reclaiming the session (hand-back)

Because the nonce is a durable, reusable credential, the **original owner still holds it** after step 3. Once
the borrowed process releases the pipe (its own `Disconnect`, e.g. when its work finishes), the owner simply
reconnects and presents the nonce again - admitted on the normal path, no UAC. That is how a GUI keeps
"owning" its elevated server across repeated hand-offs to short-lived terminal windows.

Single-instance still applies: only one of them is connected at any instant. Whoever needs the server
reconnects when it is free; the other waits (bounded by `ClientConnectTimeout`). A handy way to sequence this
without stealing the pipe is to *poll* the instance's free/busy state with `WaitNamedPipe` (which reports
availability **without** connecting) and only reconnect once it is free.

### Owned vs borrowed sessions (a consumer responsibility)

The server does not care who "owns" it - it admits whoever holds the nonce or wins a PID hand-off. But a
**consumer** must decide, per session, whether *closing* it should **tear the server down** or merely
**disconnect**:

- The **owner** (the process that spawned the server) closes with `ExitPipe` when truly finished - the server
  process exits.
- A **borrowed** session (a process that received a hand-off) must close with `Disconnect`, never `ExitPipe` -
  otherwise it kills the server out from under the owner. `Disconnect` leaves it alive and re-listening.

A consumer typically tracks this with a "borrowed" flag on the session and routes teardown accordingly.

### API summary

| Step | Who | How |
|------|-----|-----|
| Arm the hand-off | authenticated owner | `Send-Request` with request type `Handoff` and the target PID as the payload |
| Signal hand-off mode to the child | owner | a non-secret carrier of the **pipe name** only (e.g. an environment variable) - never the nonce |
| Claim the hand-off | new (borrowed) process | connect with the client `Handin` option set - it sends the `HANDIN` marker and reads the nonce the server returns |
| Reclaim after hand-back | owner | reconnect presenting the retained nonce (normal client path) |

The markers `HANDOFF` (request type) and `HANDIN` (connect first-line) are shaped so they can never collide
with a real nonce (a nonce is 32 lowercase hex characters). The whole exchange is line-based and happens
before the normal request loop, so it never disturbs request framing. Nothing here changes how non-hand-off
consumers work - they never send `HANDOFF`/`HANDIN`, so their normal nonce path is untouched.

## Setting Up Your Script

### Script Parameters

Your script can accept parameters that flow into the pipe configuration. Here is a recommended parameter block:

```powershell
#!/usr/bin/env powershell
#requires -Version 5.0
[CmdletBinding()]
Param (
    [String]$PipeName = $Null,
    [String[]]$AccessIdentifier = @(),
    [Switch]$AdminRequired,
    [Switch]$Wait,
    [Parameter(HelpMessage = 'Bitmask: 0=silent, 1=server/client progress, 2=Show-VerboseData, 4=debug output, 8=keep clean-run log (combine: 3=1+2, 15=all)')]
    [ValidateRange(0, 15)]
    [int]$InfoDisplay = 0,
    [Switch]$NoExitOnError,
    [Parameter(HelpMessage = 'Serialization depth (default 2, avoid >10 for ACL objects)')]
    [ValidateRange(1, 100)]
    [int]$Depth = 2,
    [ValidateRange(1024, 65535)]
    [int]$ChunkSize = 32768,
    [ValidateRange(1, [Int32]::MaxValue)]
    $ServerWaitTimeout = 60,
    [ValidateRange(1, [Int32]::MaxValue)]
    $ClientConnectTimeout = 10000,
    [ValidateRange(1, [Int32]::MaxValue)]
    $ChunkReadTimeout = 30000
)
```

### Initialisation Sequence

```powershell
# 1. Import the module
Remove-Module -Name NamedPipe -Force -ErrorAction SilentlyContinue
Import-Module -Name NamedPipe -Force -RequiredVersion 0.8

# 2. Capture bound parameters
$Private:MyBoundParameters = $PSCmdlet.MyInvocation.BoundParameters

# 3. Start the session (replaces all boilerplate)
$Session = Start-PipeSession -MyParameters $Private:MyBoundParameters
$ServerClientParams = $Session.$StrServerClientParams
$SendRequestParams  = $Session.$StrSendRequestParams

# 4. Send commands...

# 5. Clean up
Stop-PipeSession -SendRequestParams $SendRequestParams -PipeInfo $ServerClientParams.$StrPipeInfo
```

### Setting Options via Script Parameters

When your script has matching parameter names, they flow through automatically:

```powershell
# Run your script with parameters
.\MyScript.ps1 -InfoDisplay 7 -Depth 5 -AdminRequired -Wait
```

### Setting Options via the Options Parameter

You can pass a hashtable of overrides to `Start-PipeSession`:

```powershell
$Session = Start-PipeSession -MyParameters $Private:MyBoundParameters -Options @{
    $StrInfoDisplay        = 7  # Bitmask: 1=progress, 2=verbose data, 4=debug, 8=keep clean-run log (15=all)
    $StrAdminRequired      = $True
    $StrWait               = $True
    $StrWindowStyle        = $StrMinimized
    $StrChunkSize          = 65536
    $StrDepth              = 5
    $StrServerWaitTimeout  = 120
    $StrClientConnectTimeout = 30000
}
```

## Sending Requests

All requests use `Send-Request` with splatted `$SendRequestParams`. The command is piped in.

### ScriptBlock Requests

Execute any PowerShell command on the server:

```powershell
$SendRequestParams.$StrType = $StrScriptBlock

# Simple command
$SendRequestParams.$StrDataObject = 'Get-Process | Select-Object -First 5' |
Send-Request @SendRequestParams

# Access the result
$SendRequestParams.$StrDataObject.$StrResult

# Command with string parameters
$SendRequestParams.$StrDataObject.$StrParameters = '-Passthru'
$SendRequestParams.$StrDataObject = 'Set-Window -ProcessId {0} -State {1} -Set' -f $SendRequestParams.$StrDataObject.$StrServerPID, $StrRestore |
Send-Request @SendRequestParams

# Write-Host executes on the server window
$SendRequestParams.$StrDataObject = 'Write-Host -Object "{0}" -ForegroundColor Green' -f 'Hello World' |
Send-Request @SendRequestParams
```

### Security Requests

Query the pipe's access control list:

```powershell
$SendRequestParams.$StrType = $StrSecurity
$SendRequestParams.$StrDataObject = '' | Send-Request @SendRequestParams

# Display security information
$SendRequestParams.$StrDataObject.$StrResult
```

### Using Test-PipeSession Before Requests

For long-running scripts with multiple Send-Request calls, verify the pipe is still alive:

```powershell
if (Test-PipeSession -PipeInfo $ServerClientParams.$StrPipeInfo)
{
    $SendRequestParams.$StrDataObject = 'Get-Service' | Send-Request @SendRequestParams
}
```

## Configuration Reference

### MyOptions Parameters

These are set via script parameters or the `Options` hashtable in `Start-PipeSession`:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `InfoDisplay` | Int | 0 | Bitmask: 1=server/client progress, 2=Show-VerboseData, 4=debug output, 8=keep server diagnostics log on a clean run (combine values, e.g. 15=all) |
| `AdminRequired` | Bool | $False | Run server process with elevated (Administrator) privileges |
| `Wait` | Bool | $False | Keep server window open after the pipe closes |
| `WindowStyle` | String | Minimized | Server window style: Normal, Minimized, Maximized, Hidden |
| `ChunkSize` | Int | 32768 | Chunk size in characters for large data transfers |
| `Depth` | Int | 2 | Serialization depth for nested objects |
| `NoExitOnError` | Bool | $False | Keep server window open when errors occur |
| `Verbose` | Bool | $False | Enable verbose output |
| `ServerWaitTimeout` | Int | 60 | Seconds the server waits for a client connection |
| `ClientConnectTimeout` | Int | 10000 | Milliseconds the client waits to connect to the server |
| `ChunkReadTimeout` (v0.13+) | Int | 30000 | Milliseconds Receive-Data waits for the NEXT chunk of an already-started chunked transfer. Does NOT apply to the first read of a message (waiting for a server-side operation to complete, or for the server's next request, has no timeout - both are normal, not stalls) - only to a gap AFTER a transfer has already begun, which means the sender broke mid-stream. |
| `RedactPotentialSecrets` (v0.15+) | Bool | $True | Gates the built-in structural base64 check described below. See that section before changing this. |

### RedactPattern (v0.5+)

A session-level option that scrubs sensitive values from `[Server] Executing:` echo messages
before they reach the client. Set it in the Options hashtable as a nested hashtable:

```powershell
$PipeOptions['RedactPattern'] = @{ Option = 1 }   # built-in scrubbing only (recommended default)
```

| `Option` bit | Behaviour |
|---|---|
| 1 | Built-in: tests each QUOTED VALUE in the request text as a whole for structural base64 validity, gated by `RedactPotentialSecrets` - see the dedicated section below. Prior to v0.15 this was a blind regex ("any 40+ character run of `[A-Za-z0-9+/=]`"); that version is gone. |
| 2 | Consumer regex: redacts matches of `Pattern` (a regex string) |
| 4 | Consumer command: runs `Command` (a ScriptBlock) on each echo line |

Bits combine additively (e.g. `3` = built-in + regex). Each step receives the output of the
previous step. The VHD module defaults to `@{ Option = 1 }`.

### RedactPotentialSecrets (v0.15+) - what this actually does, and what it does not

**Read this whole section before relying on it for anything.** The name is deliberate:
`RedactPotentialSecrets` says *potential*, not *confirmed* - and that distinction is the single most
important thing to understand about this feature.

#### What problem this solves

Every request `Get-SBResult` executes gets built into literal PowerShell source text, and that text
can appear in three places: the console echo (`InfoDisplay` bit 1), the persistent function-trace log
(`Write-MyFunctionTrace -Detail`, tracing bit 2), and a raw `Show-VerboseData` dump (`InfoDisplay` bit
2). NamedPipe's `DataObject.Data` out-of-band channel (see above) is the STRUCTURAL fix for secrets a
consumer deliberately routes through it - those values are closure-injected and never become literal
text at all, so there is nothing in any of the three paths above for this feature to even need to
catch. `RedactPotentialSecrets` exists for everything else: a value that ends up in `-Parameters` (or
directly in the request text) instead of `.Data`, whether by design, by a consumer that hasn't
migrated yet, or by a future mistake in code that has.

#### What it actually checks

A request like:
```
Invoke-VHDAction -DestinationPath:'W:\vhd\PSimple\tvhd-p.psd1' -Data:'aGVsbG8gd29ybGQ='
```
gets scanned for every QUOTED STRING VALUE (`'...'` or `"..."`) and each one's content is tested, as
a WHOLE, for structural base64 validity (`Test-Base64String`: length must be a multiple of 4, then a
real `[Convert]::FromBase64String` decode). A value that passes gets replaced with
`<base64 encoded>`. Everything else - the path, parameter names, `$True`/`$False`, a bare `$Data`
reference - is left completely unchanged, because none of it is ever tested in isolation: only the
full content between a matching pair of quotes is a candidate at all.

#### A real mistake made building this, kept here deliberately as a warning

The first version of this feature did NOT test whole quoted values - it matched maximal RUNS of
base64-alphabet characters anywhere in the text, splitting automatically at any character outside
that alphabet. This looked reasonable but was wrong, and it was caught by a real Pester test failure,
not by review: a completely ordinary, non-secret path like `'W:\vhd\PSimple\tvhd-p.psd1'` contains no
base64-invalid characters within some of its own pieces once you fragment it at `\`, `:`, `-`, and
`.` - so `tvhd`, `psd1`, and `vhdx` each got tested ALONE, and each one happens to be 4 characters of
pure base64-alphabet content, which decodes without error every time (any 4-character string drawn
from the base64 alphabet decodes to 3 bytes - the decode step adds essentially no filtering beyond
the length/charset check for a candidate with no `=` padding). One realistic command line lost SIX
separate words to this, including a 20-character parameter name (`CheckGroupMembership`) and this
module's OWN `-Data:$Data` out-of-band marker text (`Data` is 4 letters). The fix - testing whole
quoted values instead of fragments - closes this because a real secret in this codebase's request
text is always an entire quoted string value (`ConvertTo-ParameterSet` quotes every string
parameter); nothing legitimate ever needs to be pulled apart to find something hidden inside it.

#### What it does NOT do, and never can

This is a **structural** test, nothing more. It answers exactly one question - "is this a valid
base64 string?" - and that question is not the same question as "is this actually sensitive?" Two
consequences follow directly, and neither is a bug:

- **It will mask non-secret data.** Any legitimately base64-encoded value that is quoted as a whole
  (a config blob, a hash, a certificate thumbprint stored as base64) gets masked exactly like a real
  password would. This is fine, and arguably a feature in its own right: a long base64 blob is
  visually noisy and unhelpful to read in a console echo or a persistent trace log whether or not it
  turns out to be sensitive, so masking it keeps the log readable either way. Do not read a
  `<base64 encoded>` marker as proof that something sensitive was found - it only proves something
  base64-shaped was found.
- **It will miss real secrets that are not base64-encoded.** A short, human-typed passphrase, PIN, or
  API key that is plain text (not base64) is invisible to this check entirely, no matter how
  sensitive it is. See `03-Redaction-CustomPattern.ps1` for the actual fix for that case: a
  consumer-supplied `RedactPattern.Pattern` matching your own parameter name (bit 2, above) - there is
  no generic way to catch this, since NamedPipe has no way to know which of a consumer's own
  parameter names carry secrets.

**The real, structural protection for a value you know is sensitive remains `DataObject.Data`** (see
above) - route it through there and it never becomes text in the first place, which is strictly
better than any amount of pattern-matching after the fact. `RedactPotentialSecrets` is a backstop and
a readability aid, not a substitute for using `.Data` correctly.

#### Turning it off

```powershell
$PipeOptions['RedactPotentialSecrets'] = $false
```

This is an explicit, deliberate choice to see full, undisguised request text - e.g. to copy a masked
value out and decode it elsewhere, or to confirm a masked value was never actually sensitive. **The
consequence is concrete and immediate**: if a real secret is currently living in `-Parameters` (or
directly in the request text) instead of being routed through `.Data`, turning this off means that
secret WILL appear in plaintext, in both the console echo and the persistent, on-disk function-trace
log, for as long as the option stays off. There is no partial or scoped version of turning it off -
it is all-or-nothing for every request this session sends while it is set. Turn it back on (or restart
the session) once you are done looking.

See `Examples\06-RedactPotentialSecrets-QuotedValues.ps1` for a runnable demonstration of everything
in this section: the false-positive bug and its fix, the "potential not confirmed" distinction in
practice, and turning the option off to see a real value.

### Access Control

By default, `Start-PipeSession` grants ReadWrite access to the current user only. To specify custom access:

```powershell
# Via -AccessList parameter
$Session = Start-PipeSession -MyParameters $Private:MyBoundParameters -AccessList @(
    'DOMAIN\User:Allow:ReadWrite'
    'Administrators:Allow:ReadWrite'
)

# Via script parameter
.\MyScript.ps1 -AccessIdentifier 'DOMAIN\User:Allow:ReadWrite','Administrators:Allow:ReadWrite'
```

**Access identifier formats:**
```powershell
'DOMAIN\User:Allow:ReadWrite'    # Full format
'Username'                        # Shorthand - becomes 'Username:Allow:ReadWrite'
'Username:Allow'                  # Shorthand - becomes 'Username:Allow:ReadWrite'
```

Access identifiers are validated by `Test-AccessIdentifier` which checks that the user or group exists locally before the pipe is created.

## Data Structures

The module uses several interconnected data structures:

### MyOptions
Created first by `Start-PipeSession`. Holds configuration values from your script parameters and any overrides from the Options hashtable.

### ServerClientParams
Created from MyOptions. Contains all server/client connection parameters including PipeInfo, PipeParams, access control, timeouts, and display settings. Created twice internally - once for server mode, once for client mode.

### SendRequestParams
Created from ServerClientParams. Contains the splatting parameters for `Send-Request`: Type, PipeInfo, DataObject, and NoExitOnError.

### DataObject
The communication payload. Contains:
- `Type` - Request type (ScriptBlock, Security, ExitPipe)
- `Request` - The command to execute
- `Parameters` - Optional parameters for the command
- `Data` - Optional out-of-band value(s) the request needs but that should never appear as a literal
  in `Request`/`Parameters`' own text - credentials/keys, or simply a large value (a whole config
  file) that would otherwise be dumped verbatim as one unreadable line in a console echo, the trace
  log's `Detail:` line, or a raw scriptblock dump. `Get-SBResult` closure-injects it, so it never
  inspects, decodes, or has any opinion about what `Data` holds, or about whether `Request` is a
  single command or a whole multi-statement script. How you reference it depends on which shape you
  use:
  - **With `Parameters` set** (a named command + parameter list): `Get-SBResult` appends
    `-Data:$Data` to the generated argument list automatically, so the invoked function just declares
    an ordinary `-Data` parameter and reads out whatever you put there.
  - **With `Parameters` NOT set** (raw `Request` text of any shape): nothing is appended - your own
    text can and should reference `$Data`/`$Data.<Key>` directly wherever it needs to, since the
    closure already makes it resolvable there. This is what makes a genuine multi-statement script
    body safe to use with `.Data` - appending text to the end of one would corrupt whatever line
    happens to be last. Neither shape is preferred by this module; a single-command dispatch and a
    multi-statement scriptblock are equally well supported.
- `Result` - The server's response
- `Error` - Any error information
- `ServerPID` / `ClientPID` - Process identifiers
- `ServerUser` / `ClientUser` - User identities

### PipeInfo
The pipe connection details:
- `Name` - The unique pipe name
- `Pipe` - The NamedPipeServerStream or NamedPipeClientStream object
- `Reader` - StreamReader for the pipe
- `Writer` - StreamWriter for the pipe
- `InfoDisplay` / `ChunkSize` / `Depth` / `ChunkReadTimeout` (v0.13+) - Copied from ServerClientParams

## InfoDisplay Bitmask

Control debug output with the InfoDisplay parameter using a bitmask (combine values by adding them):

| Bit | Value | Named Constant | Output |
|-----|-------|----------------|--------|
| - | 0 | - | **Silent** - no debug output (production use) |
| 1 | 1 | `$InfoDisplayBitProgress` | **Server/client progress** - `[Server] Executing:` messages via Send-ProgressInfo |
| 2 | 2 | `$InfoDisplayBitVerbose` | **Show-VerboseData** - displays data structure contents in formatted tables |
| 4 | 4 | `$InfoDisplayBitDebug` | **Debug output** - DEBUG Write-Host statements showing pipe operations, serialization, chunk transfers |
| 8 | 8 | `$InfoDisplayBitKeepLog` | **Keep server diagnostics log** - persist the per-session server log even on a CLEAN exit. Failures (crash / unclaimed timeout) are logged regardless of this bit; this only affects whether a *successful* run's log is kept. See "Server diagnostics log" below. |

Common combinations: `1` = progress only, `3` = progress + verbose data, `7` = all console output, `15` = everything including a kept log

```powershell
# Example: Enable server/client progress messages only
.\MyScript.ps1 -InfoDisplay 1
# Example: Enable all console debug output
.\MyScript.ps1 -InfoDisplay 7
# Example: silent, but keep the server diagnostics log for a successful run too
.\MyScript.ps1 -InfoDisplay 8
```

### InfoDisplay Named Constants

The module exports four named constants for use in code that checks InfoDisplay bits.
These are defined in `DefineVariablesPipe.ps1` and exported to global scope when the module
is imported:

```powershell
$InfoDisplayBitProgress = 1   # server/client progress messages
$InfoDisplayBitVerbose  = 2   # Show-VerboseData calls
$InfoDisplayBitDebug    = 4   # debug Write-Host output
$InfoDisplayBitKeepLog  = 8   # keep the server diagnostics log on a clean exit

# Use with -band instead of comparing literal numbers:
if ($ServerClientParams.$StrInfoDisplay -band $InfoDisplayBitProgress)
{
    Send-ProgressInfo -Type Console -String ('[Server] Executing: {0}' -f $command)
}
```

Using the named constants makes code easier to read and means a single change to the constant
definition updates all uses automatically.

## Function tracing (the shared trace log)

NamedPipe vendors a small, generic function-trace facility (`Enable-MyFunctionTrace`,
`Disable-MyFunctionTrace`, `Clear-MyFunctionTraceLog`, `Clear-MyFunctionTraceArchive`; the writer
`Write-MyFunctionTrace` stays internal). It writes to a log file, never to the console.

```powershell
Enable-MyFunctionTrace -Option 2      # -Option is mandatory, 1 to 3
# ... run the operation ...
Disable-MyFunctionTrace
```

`-Option` is a bitmask: **1** = ordinary per-function call tracing (every instrumented function, the full
noisy call flow); **2** = curated action detail (the meaningful steps only, none of the plumbing);
**3** = both. `Enable-MyFunctionTrace` prints one line saying what was enabled and which file it is
writing to. Call it BEFORE `Start-PipeSession`: the setting is carried to the elevated server, so a
client and its own server write to the same file.

**Bit 2 detail.** A caller that wants a step recorded passes a short `Detail:[...]` text to
`Write-MyFunctionTrace -Detail`, guarded by its own bit-2 check. NamedPipe's `Get-SBResult` does this for
every request it runs (the request text, already redacted), and a consumer module can do the same for its
own steps. `Write-MyFunctionTrace` does no redaction and no caller checking of its own - the caller owns
what it passes. (Earlier builds restricted `-Detail` to a hardcoded caller list; that was removed so the
shared function names no module.) A wrapper that only forwards a message can pass `-SkipFrames 1` so the
log line names the wrapper's caller rather than the wrapper.

**One file per window.** Enabling tracing creates a short session id (`$env:MyFunctionTraceSessionId`) and
the log file is `C:\ProgramData\FunctionTrace\FunctionTrace-Session-<Id>.log`, so two PowerShell windows
tracing at once do not interleave. `Enable-MyFunctionTrace -NewSession` starts a fresh file in the same
window. `Clear-MyFunctionTraceLog` archives the current window's file (the session id stays in the archive
name), and `Clear-MyFunctionTraceArchive` prunes old archives and session files by age.

**Security caveat - lock the trace folder down on a shared machine.** The module creates the folder with
whatever default permissions `C:\ProgramData` gives, and those let every local user READ every log in it.
Traced text can include paths, program names, timing and refusal reasons such as a required group name, so
on a machine used by more than one account, lock it down once from an elevated prompt:

```powershell
Protect-MyFunctionTraceFolder            # apply (elevated); add -WhatIf to preview
Protect-MyFunctionTraceFolder -Check     # report only - works without elevation
```

That gives SYSTEM and Administrators full control, lets ordinary users list the folder and add a file but
not read anyone else's, and lets each user keep writing to (and archiving) their own logs; existing logs are
reset so they inherit the new ACL. An elevated pipe server running as an administrator can still write to the
log its non-elevated client created, so the shared client/server log keeps working. Other users can still see
the log file NAMES (session ids and times), not their contents.

`Enable-MyFunctionTrace` prints one warning when it finds the folder is not locked down, naming this command;
it never blocks tracing. Set `$env:MyFunctionTraceNoAclWarning = '1'` to silence it (for example on a
single-user machine). Whatever the permissions, treat anything traced with the same sensitivity as console
output, not as a private record.

## Server diagnostics log

Because the elevated pipe server runs in its own (usually hidden) window, v0.11 captures what happens on the
server side to a file instead of relying on you watching that window.

**What is written, and when.** During a session the server records timestamped milestones (pipe created,
client connected, connection rejected, outcome). On exit it decides what to keep:

- **Failures are always kept** - a crash, or an unclaimed-connection timeout, writes a log regardless of
  `InfoDisplay`. This is the safety net.
- **A clean run is discarded by default** - a successful session writes nothing, so busy consumers do not
  accumulate throwaway files. To keep a successful run's log too, set `InfoDisplay` **bit 8** (see the
  InfoDisplay Bitmask section).

**Where.** One file per session at `%APPDATA%\NamedPipe-Logs\server-<yyyyMMdd-HHmmss>-<pipename>.log`. The
server elevates as **the same user**, so the log lands in your own profile - you can read it **without admin
rights**.

**It is deliberately secrets-free.** Because a program running as you can read your own `%APPDATA%`, the log
never contains the session nonce, request arguments, or full paths (drive-letter paths are redacted). Treat
it as a diagnostic breadcrumb, not a confidential audit trail.

**Reading it.** Two helper functions find and show logs so you never need the path:

```powershell
Show-PipeServerLog                                   # print the most recent server log
Get-PipeServerLog -Newest 1 | Get-Content            # same, as a file you can process
Get-PipeServerLog -PipeName $Session.ServerClientParams.PipeInfo.Name   # logs for one session
```

**Retention.** Old logs are pruned at server startup. The window is the `LogRetentionDays` option (default
`14`; `0` = keep forever), passed like any other option:

```powershell
$Session = Start-PipeSession -MyParameters $bp -Options @{ LogRetentionDays = 30 }
```

## Chunking

Large data transfers are automatically chunked to prevent pipe buffer overflow.

### How It Works

1. Data is serialized: Object -> PSSerializer XML -> compress -> JSON -> Base64
2. If the Base64 string exceeds ChunkSize, it is split into chunks
3. Each chunk includes: TransferId, ChunkIndex, TotalChunks, and data
4. The final chunk includes a SHA-256 checksum
5. The receiver accumulates chunks and verifies the checksum before reassembling

### Configuration

```powershell
# Via script parameter
.\MyScript.ps1 -ChunkSize 65536

# Via Options hashtable
$Session = Start-PipeSession -MyParameters $Private:MyBoundParameters -Options @{
    $StrChunkSize = 65536  # 64KB chunks
}
```

## Serialization Depth

### The Problem
When sending data through the pipe, objects are serialized using `PSSerializer`. Complex objects like ACLs (Access Control Lists) contain deeply nested structures that can cause:
- Massive memory consumption
- OutOfMemoryException
- Process hangs

### The Solution
The default serialization depth is 2, which is safe for most objects including ACLs.

### Adjusting Depth
If your data appears truncated, increase the depth:
```powershell
# Via script parameter
.\MyScript.ps1 -Depth 5

# Via Options hashtable
$Session = Start-PipeSession -MyParameters $Private:MyBoundParameters -Options @{
    $StrDepth = 5
}
```

**WARNING**: Never use Depth > 10 when working with objects containing ACLs (like Security request results). The ACL object graph is deeply recursive and will cause OutOfMemoryException.

### Truncation Warning
A warning is displayed if serialized data is suspiciously small:
```
WARNING: Send-Data: Serialized data is very small (50 chars). Consider increasing Depth if data appears truncated.
```

## Error Handling

Errors from server-side execution are returned in the DataObject:

```powershell
$SendRequestParams.$StrDataObject = 'Some-Command' | Send-Request @SendRequestParams

if ($SendRequestParams.$StrDataObject.$StrError)
{
    # An error occurred on the server
    Write-Error "Command failed: $($SendRequestParams.$StrDataObject.$StrError)"
}
else
{
    # Success - result is available
    $SendRequestParams.$StrDataObject.$StrResult
}
```

### NoExitOnError

By default, errors cause `Exit-Pipe` to close the connection. Use `-NoExitOnError` to continue:

```powershell
# Via Options hashtable
$Session = Start-PipeSession -MyParameters $Private:MyBoundParameters -Options @{
    $StrNoExitOnError = $True
}

# Or set the NoExitOnError script parameter
.\MyScript.ps1 -NoExitOnError
```

## Consumer Module Import

When your module depends on NamedPipe (via `RequiredModules` in your psd1), the spawned server process needs to load your module too. Version 0.4 uses the `ModuleToLoad` pattern for this.

### How It Works

1. `Start-PipeSession` stores a `ModuleToLoad` hashtable (Name + Version) into `$ServerClientParams.$StrModuleToLoad`
2. By default, `ModuleToLoad` is NamedPipe itself (from `$script:DefaultModuleToLoad`)
3. Consumer modules override this via the Options parameter
4. The spawned server imports the specified module - if it's a consumer (e.g. VHD), `RequiredModules` in VHD's psd1 auto-imports NamedPipe first

### Example: VHD module using NamedPipe

```powershell
# VHD.psd1
@{
    RequiredModules = @(
        @{ ModuleName = 'NamedPipe'; RequiredVersion = '0.15' }
    )
}
```

```powershell
# In VHD's Start-VHDSession.ps1 - use literal string keys (NOT $Str* variables).
# In PowerShell 7, NamedPipe exported variables like $StrModuleToLoad are NULL in
# consumer module scope - $PipeOptions[$null] silently sets a null-keyed entry.
# Always use the literal string 'ModuleToLoad' in consumer code.
$PipeOptions = Get-VHDPipeOptions -VHDConfig $ConfigLocation
$PipeOptions['ModuleToLoad'] = @{ Name = 'VHD'; Version = $ModuleVersion }
$Session = Start-PipeSession -MyParameters $MyBoundParameters -Options $PipeOptions
```

The spawned server imports VHD by name and version, which auto-imports NamedPipe via RequiredModules. All VHD functions are then available on the server side.

### ModuleToLoad.Path (v0.7+) - modules outside the server's PSModulePath

When the module lives somewhere the elevated spawned server process does not have on its
`$PSModulePath` - e.g. a mapped network drive, or a per-user synced folder (OneDrive / roaming
profile) - import by name silently fails and PowerShell may autoload an older version of the module
instead. (Modules deployed to the AllUsers Program Files paths are already on the default
`$PSModulePath`, so they do not hit this; it applies only when a consumer keeps its module on such
a drive.)

**Fix:** include the full `.psd1` path in `ModuleToLoad`. The spawned server prefers path-based
import when `Path` is present and the file exists, falling back to name+version only if not.

```powershell
# Resolve the loaded module's full .psd1 path on the client side (where the drive IS mapped)
# then pass it into ModuleToLoad so the elevated server can import by path.
$Private:mod = Get-Module -Name 'MyModule' | Where-Object { $_.Version -eq $ModuleVersion } | Select-Object -First 1
$Private:psd1 = if ($Private:mod) { Join-Path $Private:mod.ModuleBase ($Private:mod.Name + '.psd1') } else { $null }
$PipeOptions['ModuleToLoad'] = @{
    Name    = 'MyModule'
    Version = $ModuleVersion
    Path    = $Private:psd1      # full path - used by spawned server when PSModulePath lacks the drive
}
```

If `Path` is `$null` (module not currently loaded on the client), the server falls back to
name+version import - same behaviour as v0.6.

## Complete Example Script

```powershell
#!/usr/bin/env powershell
#requires -Version 5.0
[CmdletBinding()]
Param (
    [String]$PipeName = $Null,
    [String[]]$AccessIdentifier = @(),
    [Switch]$AdminRequired,
    [Switch]$Wait,
    [ValidateRange(0, 15)]
    [int]$InfoDisplay = 0,
    [Switch]$NoExitOnError,
    [ValidateRange(1, 100)]
    [int]$Depth = 2,
    [ValidateRange(1024, 65535)]
    [int]$ChunkSize = 32768,
    [ValidateRange(1, [Int32]::MaxValue)]
    $ServerWaitTimeout = 60,
    [ValidateRange(1, [Int32]::MaxValue)]
    $ClientConnectTimeout = 10000,
    [ValidateRange(1, [Int32]::MaxValue)]
    $ChunkReadTimeout = 30000
)

# Import the module
Remove-Module -Name NamedPipe -Force -ErrorAction SilentlyContinue
Import-Module -Name NamedPipe -Force -RequiredVersion 0.8

# Define your actions to execute on the server
function Invoke-MyActions
{
    # Query pipe security
    $SendRequestParams.$StrType = $StrSecurity
    $SendRequestParams.$StrDataObject = '' | Send-Request @SendRequestParams

    If ($ServerClientParams.$StrInfoDisplay)
    {
        'Client user is: [{0}]' -f $SendRequestParams.$StrDataObject.$StrClientUser
        'Server user is: [{0}]' -f $SendRequestParams.$StrDataObject.$StrServerUser
    }

    # Execute commands on the server
    $SendRequestParams.$StrType = $StrScriptBlock

    $SendRequestParams.$StrDataObject = 'Get-Process | Select-Object -First 5' |
    Send-Request @SendRequestParams
    'Top 5 processes:'
    $SendRequestParams.$StrDataObject.$StrResult | Format-Table

    $SendRequestParams.$StrDataObject = 'Get-Service | Where-Object Status -eq Running | Measure-Object' |
    Send-Request @SendRequestParams
    'Running services: {0}' -f $SendRequestParams.$StrDataObject.$StrResult.Count
}

#############################
# Main Script
#############################
$Private:MyBoundParameters = $PSCmdlet.MyInvocation.BoundParameters
$Global:Error.Clear()

# Start the session
$Session = Start-PipeSession -MyParameters $Private:MyBoundParameters
$ServerClientParams = $Session.$StrServerClientParams
$SendRequestParams  = $Session.$StrSendRequestParams

# Run actions
Invoke-MyActions

# Clean up
Stop-PipeSession -SendRequestParams $SendRequestParams -PipeInfo $ServerClientParams.$StrPipeInfo
```

Run with: `.\MyScript.ps1 -InfoDisplay 1 -Wait`

## Running as Administrator

To run the server process with elevated privileges:

```powershell
# Via script parameter
.\MyScript.ps1 -AdminRequired

# Via Options hashtable
$Session = Start-PipeSession -MyParameters $Private:MyBoundParameters -Options @{
    $StrAdminRequired = $True
}
```

This triggers a UAC elevation prompt when spawning the server process.

## FunctionExportTable

The `FunctionExportTable` in `DefineVariables.ps1` controls which functions are exported (public) and which are internal (private).

### Public Functions
These are exported and available to consumers:

| Function | Description |
|----------|-------------|
| `Start-PipeSession` | Sets up a complete pipe session in a single call |
| `Test-PipeSession` | Non-disruptive pipe health check |
| `Stop-PipeSession` | Clean shutdown with ExitPipe + dispose |
| `Send-Request` | Sends a request from client to server |
| `Set-ObjectParameterSet` | Creates and initialises data structures |
| `ConvertTo-Serial` | Serializes objects to Base64 with optional chunking |
| `ConvertFrom-Serial` | Deserializes Base64 data back to objects |
| `ConvertTo-ParameterSet` | Converts hashtables to parameter strings |
| `Format-MyTextLine` | Text formatting utility |
| `Show-VerboseData` | Displays formatted debug output |
| `Get-MyError` | Formats error information for diagnostics |
| `Write-MyLog` | Logging utility |
| `Set-Window` | Manipulates window position, size, and state |
| `Exit-Pipe` | Gracefully closes pipe on error conditions |
| `Assert-File` | File assertion utility |
| `Assert-Folder` | Folder assertion utility |
| `Send-ProgressInfo` | Sends progress messages from server to client |

### Internal Functions (Not Exported)
These are used internally by the module and are not available to consumers:

| Function | Description |
|----------|-------------|
| `Start-PipeServerOrClient` | Establishes server or client pipe (use `Start-PipeSession` instead) |
| `Send-Data` | Serializes and sends data through the pipe |
| `Receive-Data` | Receives and deserializes data from the pipe |
| `Get-SBResult` | Executes scriptblock requests on the server |
| `Set-PipeSecurity` | Creates pipe access control rules |
| `Test-AccessIdentifier` | Validates access identifier strings |
| `Get-NewPipeName` | Generates unique pipe names |
| `Publish-SetWindowCode` | Compiles Win32 P/Invoke code |

### Exporting All Functions for Testing

Set `$env:NAMEDPIPE_EXPORT_ALL = '1'` before importing the module to bypass the FunctionExportTable and export all functions:

```powershell
$env:NAMEDPIPE_EXPORT_ALL = '1'
Import-Module -Name NamedPipe -Force -RequiredVersion 0.15   # all functions now available
$env:NAMEDPIPE_EXPORT_ALL = $null                           # clear before importing normally
```

## Debugging the server side

The server runs as a separate, often elevated, process, which used to make it hard to inspect while
a request was in flight. An earlier version of this module carried a custom dynamic breakpoint-list
facility (`Initialize-BPList`/`Set-Breakpoint`/`Remove-Breakpoint`) built to work around that. It was
removed (nothing had called it in a long time) in favour of PowerShell's own built-in remote
debugging, which needs no code in this module at all:

```powershell
# From a session on the SAME machine as the server process:
Enter-PSHostProcess -Id $ServerPID     # $ServerPID is already on DataObject/ServerClientParams
Debug-Runspace -Id 1                   # lists to 1 if there's only one runspace; Get-Runspace to check

# Once attached, use normal debugging commands against the live server process:
Set-PSBreakpoint -Command Get-SBResult
# or plant `Wait-Debugger` at a specific point in a server-side function and it will break
# as soon as a debugger is attached via Enter-PSHostProcess/Debug-Runspace.

Exit-PSHostProcess   # when done
```

This supports full interactive debugging (step, inspect variables, call stack) against the actual
running server process, rather than a pre-planted, more limited breakpoint list - and requires
nothing to be added to a request to enable it.

## Troubleshooting

### Pipe hangs on Security request
**Cause**: High serialization depth on ACL objects.
**Solution**: Ensure Depth is 2 (default). Never use Depth > 10 with ACL objects.

### Data appears truncated
**Cause**: Serialization depth too low for the object being sent.
**Solution**: Increase depth with `-Depth` parameter. Watch for the truncation warning message.

### Server window closes immediately
**Cause**: Error during startup or connection.
**Solution**: Run with `-Wait` and `-NoExitOnError` to keep the server window open so you can see error messages.

### Connection timeout
**Cause**: Server not ready when client tries to connect, or pipe name mismatch.
**Solution**: Increase `ServerWaitTimeout` (seconds) and/or `ClientConnectTimeout` (milliseconds).

### "timed out ... waiting for the next chunk of transfer ..." (v0.13+)
**Cause**: A chunked transfer started (the first chunk arrived) but the sender stopped sending
before finishing it - a crash, a dropped connection, or a hung process on the sending side. This
is NOT the same as a slow server-side operation - the initial wait for a request/response has no
timeout at all, precisely so a genuinely long-running operation is never mistaken for a stall.
**Solution**: This is a real failure on the sending side, not a false positive to tune away in the
normal case. If a specific environment's link is unusually slow BETWEEN chunks of a single large
transfer (not the initial wait), increase `ChunkReadTimeout` (milliseconds, default 30000).

### "Module not found" in server process
**Cause**: Module not installed in the PSModulePath.
**Solution**: Ensure the module is deployed to a location in `$env:PSModulePath`. The server process loads the module by name and version.

### OutOfMemoryException
**Cause**: Serialization depth too high for complex/recursive objects.
**Solution**: Reduce Depth (default 2 is safe). This commonly occurs with ACL objects at Depth > 10.

### Debug output appearing when not expected
**Cause**: InfoDisplay bitmask has bits set that enable unwanted output.
**Solution**: Set InfoDisplay to 0 for silent operation. Use 1 for progress only, 2 for verbose data, 4 for debug, 8 to keep the server diagnostics log on a clean run, or combine (e.g. 15=all).

### "Function not found" errors
**Cause**: Attempting to call an internal function that is no longer exported in v0.4.
**Solution**: Use `Start-PipeSession` instead of calling `Start-PipeServerOrClient` directly. See the FunctionExportTable section for which functions are public.

### Multiple UAC prompts when a shared session is expected
**Cause**: The pre-opened `$Session` variable is not being found by the scope-walk, so each
function call opens a new server instead of reusing the existing one.
**Solution**: Change `$Session = New-VHDPipeSession` to `$Script:Session = New-VHDPipeSession`
in the calling script. See the "Sharing a Session Across Multiple Calls" section.

### "Module not found" or wrong module version in the elevated server
**Cause**: The consumer module is installed on a network or OneDrive drive (e.g. `L:\`) that
is not mapped in the elevated spawned process's `$PSModulePath`. Import by name silently fails
and PowerShell may autoload an older version of the same module.
**Solution**: Pass the full `.psd1` path in `ModuleToLoad.Path` (resolved on the client side
where the drive is mapped). See the "ModuleToLoad.Path" section under Consumer Module Import.

### Migrating from v0.2
**Problem**: Scripts written for v0.2 call `Start-PipeServerOrClient` directly.
**Solution**: Replace the boilerplate with `Start-PipeSession`/`Stop-PipeSession`. See the Quick Start section.
