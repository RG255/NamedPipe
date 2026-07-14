# NamedPipe v0.9 - Security Release

## Quick Summary

NamedPipe v0.9 fixes **critical code injection vulnerabilities** discovered in v0.8 that could allow remote code execution on the server.

**Status**: ✓ Production Ready - Deploy Immediately

## What Changed

### Critical Fixes (3 issues resolved)

1. **Code Injection in Parameter Handling** ✓ FIXED
   - Parameter values now properly escaped before scriptblock embedding
   - Prevents attackers from breaking out of quoted strings
   - Example attack that now fails: `@{ Path = "C:\'; Remove-Item -Path C:\ #" }`

2. **Syntax Validation Added** ✓ ADDED
   - Commands validated before execution using PowerShell parser
   - Detects malformed or suspicious syntax early
   - Clear error messages for invalid commands

3. **Access Identifier Validation** ✓ HARDENED
   - Stricter validation of ACL identity strings
   - Rejects malformed inputs with clear error messages
   - Added null/whitespace checks

### Files Modified

- `Functions/ConvertTo-Parameters.ps1` - Core injection fix
- `Functions/Get-SBResult.ps1` - Syntax validation added
- `FunctionsWindows/Test-UserOrGroupExists.ps1` - Validation improved
- `NamedPipe.psd1` - Version bumped to 0.9

### New Documentation

- `SECURITY_FIXES.md` - Detailed vulnerability descriptions
- `CHANGES_v0.9.md` - Complete changelog
- `Tests/SecurityFixes-Test.ps1` - Security validation tests

## Backward Compatibility

✓ **100% Backward Compatible**

All valid v0.8 code continues to work. Only injection attacks are blocked.

## Installation

```powershell
# Deploy to Program Files
powershell.exe -NoProfile -File "D:\PowerShellScripts\Modules\Deploy-Modules.ps1"

# Or deploy only NamedPipe
powershell.exe -NoProfile -File "D:\PowerShellScripts\Modules\Deploy-Modules.ps1" -Module NamedPipe -Version 0.9
```

## Verification

Run the security test to verify fixes:
```powershell
powershell.exe -NoProfile -File "D:\PowerShellScripts\Modules\NamedPipe\0.9\Tests\SecurityFixes-Test.ps1"
```

## For v0.8 Users

**⚠️ URGENT**: v0.8 is **insecure** and must be replaced immediately.

**All existing deployments should upgrade to v0.9 without delay.**

No code changes required in consuming modules (VHDTools, ConfigureDefender, etc.) - they work with v0.9 as-is.

## Security Contact

These security fixes were identified through code review. If you discover additional security issues, please report them immediately.

---

**Version**: 0.9  
**Release Date**: 2026-07-03  
**Status**: Production Ready  
**Risk Level**: CRITICAL FIX
