# NamedPipe Changelog

## Version 0.13 - 2026-08-13 (branched 2026-08-11)

### Fixes - server-side errors reaching the client

- **A scriptblock that FAILED on the elevated server could return to the caller looking like a
  success.** `Get-SBResult` invoked the caller's scriptblock with only its own local
  `$ErrorActionPreference` set to `Stop`. A module function resolves that preference from the
  **global** scope, never from its caller, so the local setting had no effect on code running inside
  the invoked block: anything that failed *non-terminatingly* wrote to the error stream and carried
  on, and the client received a partial or empty result with `$StrError` empty. The caller had no
  way to tell a completed operation from a failed one.
  `Get-SBResult` now sets **both** the local and the global preference to `Stop` before invoking, and
  restores the previous global value in a `Finally`.
- **`Save-ServerLog` set its "a log was written" flag unconditionally**, including on the path where
  no log was written. That flag suppresses later diagnostics, so the failure it should have reported
  was the exact case it silenced. The flag is now set only when a log is actually written.

### Verification

- Proven against all four consumers doing real work, not just the headless harness: VHDTools VHD
  builds, two unattended Macrium production backups, VaultTools, and the ConfigureDefender GUI.
- Module suite 159 passed / 0 failed / 1 skipped. Regression coverage for the specific defect lives
  outside this repo (it needs a consumer and a UAC prompt): `Test-PipeErrorPropagation.ps1` pins the
  symptom and `Test-PipeServerErrorCount.ps1` the cause - the server reporting `BEFORE=0 AFTER=0
  EAP=Stop` while an error had in fact occurred.

### Notes

- 0.12 is frozen; its history is contained in this line. Consumers pinning `RequiredVersion = '0.12'`
  keep working unchanged - repin to 0.13 to pick up the fix, since the whole point is that a failure
  which used to be invisible now surfaces.

## Version 0.12 - 2026-07-31 (branched 2026-07-21)

### Fixes - crash-log path redaction (security review 2026-07-31)
- The pipe server's crash handler redacted only `D:\...` paths from the stack trace / error detail written
  to the server log and Event Log - the author's development drive. On any other machine, and for every
  user of the public GitHub repo (who will be on `C:`), it redacted NOTHING, leaking full paths including
  `C:\Users\<username>\...` - so the control was ineffective anywhere but the development machine. Now
  matches any drive-qualified path
  plus UNC (`\\server\share\...`), which the module can genuinely emit given it supports loading modules
  from network drives. Same fix applied to 0.9 (committed to the public repo), 0.10 and 0.11.

### Changes - leak-proof PID hand-off (see PID-HANDOFF-DESIGN.md)
- Branched from 0.11 (which is the tested BACKSTOP: all transport hardening done + ConfigureDefender
  migrated). 0.12 is the sandbox for the VHDTools GUI->terminal hand-off over the nonce-gated pipe WITHOUT
  passing the nonce out-of-band. The authenticated client vouches for the terminal's PID (`HANDOFF X`); the
  terminal proves it is that PID (`HANDIN` + `GetNamedPipeClientProcessId`, kernel-set/unspoofable) and the
  server returns the nonce over that PID-verified channel. Nothing sensitive leaves the client process.
- **Server side DONE + TESTED + DEPLOYED 2026-07-21.** `HANDOFF` request (arms `$ExpectedHandinPid` with the
  PID in `$StrRequest`); `HANDIN` accept-gate (`GetNamedPipeClientProcessId` verifies the connecting PID, then
  returns the nonce); client hand-in mode (`$StrHandin` option). Method proven first by `C:\Temp\pid-handoff-test.ps1`
  (4/4); module regression `Tests\Test-PipeHandoff.ps1` 2/2 through a real spawned server (correct-PID child
  admitted, wrong-PID refused). Normal nonce/re-listen/connect-deadline/log paths all still green.
- **Client side DONE 2026-07-22.** VHDTools 0.4 `Connect-VHDExistingPipe` (HANDIN when `VHD_PIPE_NAME` is set,
  reclaim-by-nonce otherwise), `New-VHDPipeSession` reconnect block, and the `Show-VHDManager` sequenced-reclaim
  DispatcherTimer. Built on 0.12 primitives with no further NamedPipe change.
- **Consumer migration DONE.** VHDTools 0.4, Macrium 0.2 and VaultTools 0.3 all pin `RequiredVersion = '0.12'`.
- **PROVEN IN THE REAL WORLD 2026-07-31.** The full round trip - GUI hands its elevated session to a terminal
  and reclaims it afterwards - verified in a real WPF session, not just the headless harness. This was the last
  open gate: the PID hand-off is why 0.12 branched, and it now works in its actual usage mode.

## Version 0.11 - 2026-07-17 (complete - superseded by 0.12)

### Changes - transport hardening (Item 2 of the injection-hardening plan)

- Branched from 0.10 as a sandbox for the riskier transport work; 0.10 stays the tested backstop.
- **Pipe mandatory integrity label** (`Set-PipeIntegrityLabel`, internal): the data pipe is labelled
  Medium at creation via post-create `SetSecurityInfo(LABEL_SECURITY_INFORMATION)`, so a Low-integrity
  process cannot connect. Automatic, needs no privilege, and never blocks pipe creation (graceful on
  failure). See USERGUIDE "What's New in v0.11" for a plain-English explanation of integrity levels.
- Removed the broad "Interactive" (`S-1-5-4`) fallback on the health pipe; it now grants only the exact
  current-user SID.
- Regression tests: `Tests\Test-PipeIntegrityLabel.ps1` (Low-IL blocked / Medium allowed) and a label
  check in `Tests\Start-PipeTest.ps1`.
- **Capability-nonce client authentication (hardening 4.2):** the server holds a per-session nonce
  (auto-generated in `Set-ObjectParams`, carried in `ServerClientParams`, so both the spawned server and
  the inheriting client share it). On every connection the server reads the client's FIRST line and admits
  it only if it matches the nonce; a wrong or absent first line is disconnected and the server keeps
  listening. Admission is by the SECRET, not by PID - so the VHDTools GUI->terminal hand-off (a different
  process presenting the same nonce) still works, while a blind pipe-name enumerator is refused. Backward
  compatible: no nonce configured -> the check is skipped. The client-side `ServerClientParams.Nonce` is
  exposed so a consumer can forward it to a hand-off process. Regression test:
  `Tests\Test-PipeNonceAuth.ps1` (positive/hand-off, wrong-nonce refused, correct-nonce recovery - all
  pass against the deployed module).
- **Server diagnostics log (hardening 4.5, step 1a):** the spawned server buffers timestamped lifecycle
  milestones (pipe created, client connected/validated, connection rejected, outcome) in memory and, on
  exit, writes ONE per-session file `%APPDATA%\NamedPipe-Logs\server-<yyyyMMdd-HHmmss>-<pipename>.log` - but
  only on a FAILURE outcome (`crashed` / `timed-out-unclaimed` / `unknown-exit`, always), or on a CLEAN exit
  when new `InfoDisplay` bit 8 is set; a clean silent run discards the buffer (no file, no churn = identical
  to prior behaviour). This closes the previously-SILENT timeout/unclaimed path (which logged nothing) and
  unifies the old `server-error-<ts>.log` crash log onto the new name. Content is kept secrets-free: no
  nonce/arguments, and drive-letter paths are redacted. Internal helpers `Add-ServerLogEntry` /
  `Save-ServerLog` (idempotent, never throw). Tests: `Tests\Test-ServerLogE2E.ps1` (real server: discard at
  0, keep at bit 8) + unit `C:\Temp\test-serverlog.ps1` (flush rules / redaction / coalescing / filename).
- **`InfoDisplay` bit 8 (step 1b):** new bit `8` = keep a CLEAN run's server log (failures are logged
  regardless). New named constant `$InfoDisplayBitKeepLog = 8`; every `InfoDisplay` `ValidateRange` widened
  `(0,7)`->`(0,15)`; bitmask docs/USERGUIDE updated (`15` = all).
- **Log retention + reader helpers (step 1c):** `LogRetentionDays` session option (default `14`; `0` = keep
  forever) prunes old `server-*.log` at server startup (`Remove-OldServerLog`, internal). New exported
  helpers `Get-PipeServerLog` / `Show-PipeServerLog` find and print logs so a non-admin consumer never needs
  the path. Unit-tested (retention + reader 8/8).
- **Event Log pointer (step 1d):** on a FAILURE outcome the server also writes a one-line **Application-log**
  entry (source `NamedPipe`, Error for `crashed` / Warning for the timeouts) that points at the full
  diagnostics file - the Event Log is the searchable index, the file is the detail. Uses the .NET
  `EventLog` API (PS7 has no `Write-EventLog`); wrapped so a missing source or lack of permission degrades
  silently to file-only. New exported `Register-PipeEventSource` (idempotent, needs admin) creates the
  source; `Deploy-Modules.ps1` runs it over its existing elevation whenever NamedPipe is deployed (both the
  RunAs and vault-session routes). Writing to the source afterwards needs no admin. Test: `C:\Temp\test-serverlog-1d.ps1`
  (Error event points at the file on crash; a clean discarded run writes no event).
  For a git-cloned copy that never runs Deploy, the **elevated server self-registers the source at startup**
  (`if ($Administrator) { Register-PipeEventSource }`), so it self-provisions on first elevated use.
- **Step 1 (server diagnostics log) is COMPLETE** (1a core / 1b bit 8 / 1c retention+readers / 1d Event Log).
- **Connect-deadline / kill-unclaimed (4.3):** an unclaimed elevated server now **self-terminates in
  ~`ClientConnectTimeout`** (a first-connect budget measured from pipe creation, as an overall stopwatch so a
  wrong-nonce squatter cannot keep it alive) instead of lingering the full 60s re-listen window; only the
  FIRST connect uses this short budget, re-listen after a validated session still uses `ServerWaitTimeout`, so
  live/reuse/hand-off sessions are unaffected. The **unconditional crash `Pause` is removed** - it now honours
  `-Wait` like the post-session Pause, so with no `-Wait` the server self-terminates on any exit (crash
  included, captured by the log) and `-Wait` becomes the single opt-in "hold the window so I can look" switch.
  `Register-EngineEvent PowerShell.Exiting` disposes the pipe as belt-and-braces. Test `Tests\Test-ConnectDeadline.ps1`
  (unclaimed server gone in 6.6s not 60s, with a `timed-out-unclaimed` log). (Idle timeout was DROPPED - plan
  §4.4. PID-auth was REPLACED by the capability nonce - plan §4.2.)
- Downstream follow-up (NOT in this module): when VHDTools migrates from 0.9 to 0.11, its hand-off client
  (`New-VHDPipeSession`, reading `$env:VHD_PIPE_NAME`) must also read the nonce from a second env var and
  present it, or the 0.11 server will refuse the terminal reconnect.

## Version 0.10 - 2026-07-17 (in progress)

### Changes - injection hardening (Item 1 of the plan)

- Branched from 0.9. **`RequestPolicy` option** (`Test-RequestPolicy`, gated in `Get-SBResult`): a
  default-deny AST allowlist that constrains what the elevated server will execute - only allowlisted
  command calls with literal/variable/array/hashtable arguments run; everything else (Add-Type, `&`/`.`,
  Invoke-Expression, `.NET` method/type expressions, computed arguments, and any non-allowed AST node such
  as a LanguageMode assignment) is refused before execution. Opt-in via `Start-PipeSession -Options`;
  no policy = unchanged behaviour. See USERGUIDE "What's New in v0.10".

## Version 0.8 - 2026-04-14

### Changes

- Branched from 0.7 as stable baseline before server re-listen implementation.
- New GUID assigned (0.8 is a separate installable module version).
- Pending: server re-listen support (outer loop in Start-PipeServerOrClient.ps1 so server
  waits for a new client after the current client disconnects, rather than exiting).
  Required for VHDTools pipe session hand-off between GUI and terminal windows.

## Version 0.9 - 2026-02-01

### Bug Fixes

#### 1. Fixed Set-PipeSecurity.ps1 Error Handling
- **File**: `FunctionsWindows\Set-PipeSecurity.ps1`
- **Lines**: 86-90
- **Issue**: Catch block referenced undefined `$DataObject` variable causing secondary errors
- **Fix**: Replaced with proper error handling that throws to caller
- **Impact**: Error handling now works correctly without causing additional errors

#### 2. Fixed Receive-Data.ps1 Uninitialized Variable
- **File**: `FunctionsWindows\Receive-Data.ps1`
- **Lines**: 51-66
- **Issue**: If deserialization failed on line 45, catch block tried to access uninitialized `$DataObject`
- **Fix**: Added null check and creates minimal error object when `$DataObject` doesn't exist
- **Impact**: Graceful error handling even when deserialization completely fails

### Enhancements

#### 3. Configurable Timeout Parameters
- **File**: `FunctionsWindows\Start-PipeServerOrClient.ps1`
- **Lines**: 56-59, 119, 231
- **Added**: Two new configurable properties in `ServerClientParams` object:
  - `ServerWaitTimeout`: Server wait timeout in seconds (default: 60)
  - `ClientConnectTimeout`: Client connection timeout in milliseconds (default: 10000)
- **Usage**: Set these properties in `ServerClientParams` before calling the function to override defaults
- **Impact**: Users can now customize timeouts based on their network/system requirements
- **Backward Compatible**: Yes - uses same defaults as hard-coded values in v0.8

#### 4. Resource Cleanup with Try-Finally Blocks
- **File**: `FunctionsWindows\Start-PipeServerOrClient.ps1`
- **Lines**: 202-217 (server), 222-242 (client restructured)
- **Added**: Finally blocks to ensure proper disposal of:
  - StreamReader (`$StrReader`)
  - StreamWriter (`$StrWriter`)
  - Named Pipe (`$StrPipe`)
- **Impact**: Prevents resource leaks even when errors occur
- **Note**: Disposal is wrapped in try-catch to prevent disposal errors from masking original errors

#### 5. Improved ConvertTo-Serial.ps1 Readability
- **File**: `Functions\ConvertTo-Serial.ps1`
- **Lines**: 48-65
- **Changed**: Broke down complex one-liner into clear, commented steps:
  1. Serialize PowerShell object to XML
  2. Remove CR/LF/TAB characters
  3. Remove unnecessary spaces between XML tags
  4. Convert to JSON and compress
  5. Encode as Unicode bytes
  6. Convert to Base64 string
- **Impact**: Much easier to understand, debug, and maintain
- **Backward Compatible**: Yes - produces identical output

#### 6. Refactored Format-MyTextLine.ps1
- **File**: `Functions\Format-MyTextLine.ps1`
- **Lines**: 99-143
- **Changed**: Simplified Split-MyLine function logic
  - Removed Test-Value filter (unnecessary complexity)
  - Clearer break point detection using array iteration
  - Added inline comments explaining logic
  - Same functionality, more maintainable code
- **Impact**: Easier to understand, debug, and maintain

#### 7. Module Trimming - Removed Non-Pipe Functions
- **Initially Removed**: 21 function files (4 later restored as required dependencies)
- **FunctionsWindows** (9 files permanently removed):
  - Assert-File.ps1, Assert-Folder.ps1, Assert-Links.ps1
  - Assert-Service.ps1, Assert-UserGroup.ps1
  - Initialize-BPList.ps1, Set-Breakpoints.ps1, Remove-Breakpoints.ps1
  - ~~Publish-Code.ps1~~ (restored - required by Set-Window)
  - ~~Test-UserOrGroupExists.ps1~~ (restored - required by Set-ObjectParams)
- **Functions** (7 files permanently removed):
  - Convert-BytesToFile.ps1, Convert-FileToBytes.ps1
  - ConvertFrom-Base64.ps1, ConvertTo-Base64.ps1
  - Expand-String.ps1, Expand-Variables.ps1
  - Get-ConfigurationFile.ps1, Get-FreeDriveLetter.ps1
  - ~~Get-SBResult.ps1~~ (restored - core pipe function)
  - ~~ConvertTo-Parameters.ps1~~ (restored - required by Get-SBResult)
- **Net Impact**: 16 files removed (41% reduction), focused solely on named pipe IPC

#### 8. Trimmed DefineVariables.ps1
- **File**: `Functions\DefineVariables.ps1`
- **Changed**: Removed unused variables not required by pipe functions
  - Removed: Most Regex patterns, file extensions (StrExt*), DayOfWeek/MonthOfYear hashtables
  - Removed: Unused Str* constants (StrUTF8, StrAscii, StrBackSlash, StrTab, etc.)
  - Removed: Unused variable option constants (VOAllScope, VOPrivate, VSGlobal, etc.)
  - Kept: All logging, window, and module variables needed by pipe functions
- **Impact**: ~50% reduction in variables (from 50+ to 25), faster module load

#### 9. Silent Module Import by Default
- **File**: `Functions\DefineVariables.ps1`
- **Lines**: 40-56
- **Changed**: Set VInfoOn, FInfoOn, FWInfoOn to $False
- **Impact**: Module imports silently without verbose output
- **Note**: Set these to $True for debugging/development

#### 10. Fixed Test Script
- **File**: `Tests\Start-PipeTest.ps1`
- **Lines**: 2-6, 76, 181, 233
- **Changed**:
  - Replaced `#requires -Modules` with `Import-Module -Force` for reliable reloading
  - Commented out calls to removed breakpoint functions
  - Set $StrInfoDisplay to $False for quiet testing
- **Impact**: Test script works with trimmed module, avoids module caching issues

#### 11. Fixed Module Initialization Bug
- **File**: `InitialiseModule.psm1`
- **Lines**: 246-253
- **Issue**: Variable existence check `(Get-Variable...).value` threw error when variable didn't exist
- **Fix**: Removed problematic check - DefineVariables*.ps1 files now always load at module init
- **Impact**: Module now loads correctly with all variables properly exported

#### 12. Restored Required Dependencies
After testing, discovered some removed files were actually needed:
- **Publish-Code.ps1** (FunctionsWindows): Required by Set-Window - compiles C# Window class for Win32 API calls
- **Get-SBResult.ps1** (Functions): Core pipe function - executes scriptblocks sent through pipe
- **ConvertTo-Parameters.ps1** (Functions): Required dependency for Get-SBResult
- **Test-UserOrGroupExists.ps1** (FunctionsWindows): Required dependency for Set-ObjectParams access control validation
- **Impact**: These functions are essential for core pipe functionality

### Version Update
- **File**: `NamedPipe.psd1`
- **Line**: 15
- **Remains**: ModuleVersion '0.9'

## Files Modified in v0.9 (Updated)
**Modified:**
1. `FunctionsWindows\Set-PipeSecurity.ps1` - Error handling fix
2. `FunctionsWindows\Receive-Data.ps1` - Uninitialized variable fix
3. `FunctionsWindows\Start-PipeServerOrClient.ps1` - Timeout params, resource cleanup
4. `Functions\ConvertTo-Serial.ps1` - Readability improvements
5. `Functions\Format-MyTextLine.ps1` - Refactored Split-MyLine logic
6. `Functions\DefineVariables.ps1` - Trimmed to 25 core variables
7. `Tests\Start-PipeTest.ps1` - Removed breakpoint function calls
8. `InitialiseModule.psm1` - Fixed variable existence check bug

**Removed (16 files):**
- FunctionsWindows: Assert-* (5 files), Initialize-BPList, Set/Remove-Breakpoints
- Functions: Convert-BytesToFile/FileToBytes, ConvertFrom/To-Base64, Expand-*, Get-ConfigurationFile, Get-FreeDriveLetter

**Restored (4 files - required dependencies):**
- FunctionsWindows: Publish-Code, Test-UserOrGroupExists
- Functions: Get-SBResult, ConvertTo-Parameters

**Final Count (25 files):**
- 16 FunctionsWindows: Core pipe functions + 3 DefineVariables*.ps1 + Publish-Code + Test-UserOrGroupExists
- 9 Functions: Core helpers (serialization, scriptblock execution, logging, error handling, text formatting)

## Backward Compatibility
All changes in version 0.9 are fully backward compatible with version 0.8 **for core pipe functionality**.

**Breaking Changes:**
- Removed non-pipe utility functions (Assert-*, Convert-Bytes*, Base64, Expand-*, etc.)
- If your scripts depend on these removed functions, they will break
- Core pipe functions (Start-PipeServerOrClient, Send/Receive-Data, etc.) remain unchanged

**Migration Path:**
- Scripts using only named pipe functions: No changes required
- Scripts using removed utilities: Extract those functions to a separate utility module

## Known Issues Not Addressed
The following were identified during code review but not changed in v0.9 (working as designed):
- Line 116 in Start-PipeServerOrClient.ps1 uses literal property name vs `$Str*` variable (style inconsistency only)
- Exit-Pipe.ps1 uses `Exit` command which terminates entire PowerShell session (by design)
- Empty wait loop comment on lines 122-127 (placeholder for future enhancements)

## Module Statistics (v0.9)

### Before Trimming
- **Functions folder**: 18 .ps1 files
- **FunctionsWindows folder**: 21 .ps1 files
- **Total**: 39 function files
- **DefineVariables.ps1**: 600+ lines, 50+ variables
- **Exported functions**: ~26 functions

### After Trimming (Final)
- **Functions folder**: 9 .ps1 files (removed 7, restored 2)
  - Removed: Convert-Bytes*, Base64, Expand-*, Get-ConfigurationFile, Get-FreeDriveLetter
  - Restored: Get-SBResult, ConvertTo-Parameters
- **FunctionsWindows folder**: 16 .ps1 files (removed 9, restored 2)
  - Removed: Assert-* (5), Initialize-BPList, Set/Remove-Breakpoints
  - Restored: Publish-Code, Test-UserOrGroupExists
- **Total**: 25 function files (9 Functions, 16 FunctionsWindows)
- **DefineVariables.ps1**: ~300 lines, 25 variables
- **Exported functions**: 24 functions (20 core pipe + 4 window helper functions)

### Improvements
- ✅ 41% reduction in function files (39 → 25)
- ✅ 50% reduction in variables (50+ → 25)
- ✅ Silent module import by default
- ✅ Fixed module initialization bug
- ✅ Cleaner, more maintainable code
- ✅ Focused solely on named pipe IPC functionality

## Notes for Implementation in Other Scripts
- Named pipe server must be started before client connects
- Use `ServerWaitTimeout` and `ClientConnectTimeout` properties to customize timeouts
- Objects are serialized via PSSerializer → XML → JSON → Base64 for transport
- Security ACLs can be configured via `AccessIdentifier` parameter in format:
  - Single value: `"username"` (grants ReadWrite/Allow)
  - Two values: `"username:Deny"` (grants ReadWrite with specified access)
  - Three values: `"username:Allow:FullControl"` (grants specified rights and access)
- Module imports silently - set VInfoOn/FInfoOn/FWInfoOn to $True in DefineVariables.ps1 for verbose output
