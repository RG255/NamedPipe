# NamedPipe Changelog

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
