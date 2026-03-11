# NamedPipe Module Trimming Guide - Option 1 (Core Pipe Only)

## Overview
This guide shows exactly which files to remove to trim the module down to core named pipe functionality only.

## Summary of Changes
- **Format-MyTextLine.ps1**: ✅ Already refactored (simplified Split-MyLine logic)
- **DefineVariables.ps1**: Replace with DefineVariables-TRIMMED.ps1
- **Remove unused functions**: 21 files to delete
- **Keep core functions**: 20 files retained

---

## Step 1: Replace Variables File

### Action Required
```powershell
# Backup original
Copy-Item Functions\DefineVariables.ps1 Functions\DefineVariables.ps1.backup

# Replace with trimmed version
Copy-Item Functions\DefineVariables-TRIMMED.ps1 Functions\DefineVariables.ps1
```

### What Was Removed
- All Regex patterns except those actually used
- File extension constants (StrExt*) - mostly unused
- DayOfWeek and MonthOfYear hashtables
- Unused string constants (StrUTF8, StrAscii, StrTab, StrBackSlash, etc.)
- Unused variable option constants
- MyCulture variable

### What Was Kept
- StrCRLF, StrCr, StrLF (used by Format-MyTextLine)
- WindowWidth, WindowHeight (used by Set-Window)
- All logging variables (FTrace, LogLevel, LogFilePath, etc.)
- Interactive, IsConsole, Administrator
- ModuleVersion, MajorPSVersion
- Common parameter strings (StrVerbose, StrContinue, etc.)
- Variable definition helpers (VSScript, VOReadOnly, VONone)

---

## Step 2: Remove Unused Functions

### FunctionsWindows - DELETE These Files (11 files)

```powershell
# User/Group management - NOT needed for pipes
Remove-Item FunctionsWindows\Assert-UserGroup.ps1
Remove-Item FunctionsWindows\Test-UserOrGroupExists.ps1

# File/Folder operations - NOT needed for pipes
Remove-Item FunctionsWindows\Assert-File.ps1
Remove-Item FunctionsWindows\Assert-Folder.ps1
Remove-Item FunctionsWindows\Assert-Links.ps1

# Service management - NOT needed for pipes
Remove-Item FunctionsWindows\Assert-Service.ps1

# Debugging/Breakpoint tools - NOT needed for pipes
Remove-Item FunctionsWindows\Initialize-BPList.ps1
Remove-Item FunctionsWindows\Set-Breakpoints.ps1
Remove-Item FunctionsWindows\Remove-Breakpoints.ps1
Remove-Item FunctionsWindows\Publish-Code.ps1

# Also remove their .history.zip files
Remove-Item FunctionsWindows\Assert-*.history.zip
Remove-Item FunctionsWindows\Initialize-*.history.zip
Remove-Item FunctionsWindows\Set-Breakpoints.history.zip
Remove-Item FunctionsWindows\Remove-Breakpoints.history.zip
Remove-Item FunctionsWindows\Publish-Code.history.zip
Remove-Item FunctionsWindows\Test-*.history.zip
```

### Functions - DELETE These Files (10 files)

```powershell
# File/Byte conversion - NOT used by pipes
Remove-Item Functions\Convert-BytesToFile.ps1
Remove-Item Functions\Convert-FileToBytes.ps1

# Base64 conversion - NOT used by pipes (ConvertTo-Serial uses different encoding)
Remove-Item Functions\ConvertFrom-Base64.ps1
Remove-Item Functions\ConvertTo-Base64.ps1

# String expansion - NOT used by pipes
Remove-Item Functions\Expand-String.ps1
Remove-Item Functions\Expand-Variables.ps1

# Configuration file - NOT used by pipes
Remove-Item Functions\Get-ConfigurationFile.ps1

# Drive letter utility - NOT used by pipes
Remove-Item Functions\Get-FreeDriveLetter.ps1

# Scriptblock result - NOT used by pipes
Remove-Item Functions\Get-SBResult.ps1

# Parameter conversion - NOT used by pipes
Remove-Item Functions\ConvertTo-Parameters.ps1

# Also remove their .history.zip files
Remove-Item Functions\Convert-*.history.zip
Remove-Item Functions\Expand-*.history.zip
Remove-Item Functions\Get-ConfigurationFile.history.zip
Remove-Item Functions\Get-FreeDriveLetter.history.zip
Remove-Item Functions\Get-SBResult.history.zip
Remove-Item Functions\ConvertTo-Parameters.history.zip
```

---

## Step 3: Keep These Core Files

### FunctionsWindows - KEEP (10 files)

**Core Pipe Functions:**
- ✅ Start-PipeServerOrClient.ps1 - Main pipe entry point
- ✅ Send-Data.ps1 - Send data through pipe
- ✅ Receive-Data.ps1 - Receive data from pipe
- ✅ Send-Request.ps1 - High-level request wrapper
- ✅ Send-ProgressInfo.ps1 - Progress reporting
- ✅ Get-NewPipeName.ps1 - Generate unique pipe names
- ✅ Set-PipeSecurity.ps1 - Configure pipe ACLs
- ✅ Exit-Pipe.ps1 - Close pipe connection
- ✅ Show-VerboseData.ps1 - Debug output helper
- ✅ Set-Window.ps1 - Console window management (needed for Format-MyTextLine)

**Variable Definitions:**
- ✅ DefineVariablesCommon.ps1 - Window styles (used by Start-PipeServerOrClient)
- ✅ DefineVariablesSetWindow.ps1 - Window states (used by Set-Window, Receive-Data)
- ✅ DefineVariablesPipe.ps1 - Pipe property names (ALL needed)

### Functions - KEEP (7 files)

**Serialization:**
- ✅ ConvertTo-Serial.ps1 - Serialize objects for pipe transport
- ✅ ConvertFrom-Serial.ps1 - Deserialize objects from pipe

**Utilities:**
- ✅ Set-ObjectParams.ps1 - Initialize pipe data structures
- ✅ Get-MyErrors.ps1 - Error handling
- ✅ Write-MyLog.ps1 - Logging
- ✅ Format-MyTextLine.ps1 - Text formatting (for errors/logs)

**Variable Definitions:**
- ✅ DefineVariables.ps1 - Common variables (REPLACE with trimmed version)

---

## Step 4: Verification

After removing files, verify the module loads correctly:

```powershell
# Remove module from session
Remove-Module NamedPipe -Force -ErrorAction SilentlyContinue

# Re-import
Import-Module d:\PowerShellScripts\NamedPipe\0.9\NamedPipe.psd1 -Force

# Test basic functionality
$pipeName = Get-NewPipeName -PipeName 'Test'
Write-Host "Generated pipe name: $pipeName"

# Check exported functions
Get-Command -Module NamedPipe | Format-Table Name
```

Expected functions after trimming:
- ConvertFrom-Serial
- ConvertTo-Serial
- Exit-Pipe
- Format-MyTextLine
- Get-MyErrors
- Get-NewPipeName
- Receive-Data
- Send-Data
- Send-ProgressInfo
- Send-Request
- Set-ObjectParams
- Set-PipeSecurity
- Set-Window
- Show-VerboseData
- Start-PipeServerOrClient
- Write-MyLog

---

## Before/After Stats

### Before Trimming
- **Functions folder**: 18 .ps1 files
- **FunctionsWindows folder**: 21 .ps1 files
- **DefineVariables.ps1**: 600+ lines, 50+ variables

### After Trimming
- **Functions folder**: 7 .ps1 files (removed 11)
- **FunctionsWindows folder**: 13 .ps1 files (removed 8)
- **DefineVariables.ps1**: ~300 lines, 25 variables

**Reduction**: ~45% fewer function files, ~50% fewer variables

---

## Rollback Procedure

If you need to restore removed files:

```powershell
# All files have .history.zip backups
# To restore a file:
Expand-Archive -Path "FunctionsWindows\Assert-File.history.zip" -DestinationPath "FunctionsWindows\" -Force

# Or restore from your version control system
git checkout Functions/DefineVariables.ps1
```

---

## Notes

1. **DefineVariablesCommon.ps1** and **DefineVariablesSetWindow.ps1** are KEPT because:
   - DefineVariablesCommon.ps1 provides window style strings used by Start-PipeServerOrClient
   - DefineVariablesSetWindow.ps1 provides window state strings used by Set-Window and Receive-Data

2. **DefineVariablesPipe.ps1** is KEPT with ALL variables because they're all property names for the DataObject and ServerClientParams structures

3. **Set-Window.ps1** is KEPT because:
   - It initializes WindowWidth/WindowHeight during module load
   - Format-MyTextLine depends on these values
   - Receive-Data calls it for error handling

4. **Format-MyTextLine.ps1** has been refactored with cleaner Split-MyLine logic (already done)

---

## Ready to Proceed?

1. ✅ Review this guide
2. ✅ Backup your module: `Copy-Item -Recurse 0.9 0.9.backup`
3. ✅ Run Step 1: Replace DefineVariables.ps1
4. ✅ Run Step 2: Remove unused functions
5. ✅ Run Step 4: Verification
6. ✅ Update ModuleVersion to 1.0 in NamedPipe.psd1
7. ✅ Update CHANGELOG.md with trimming details
