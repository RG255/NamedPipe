# NamedPipe v0.9 Changes Summary

## Version: 0.9 (Released 2026-07-03)

### Security Fixes (CRITICAL)

**SECURITY ADVISORY**: v0.8 contains a critical code injection vulnerability that allows remote code execution on the server. All deployments must be upgraded to v0.9 immediately.

#### 1. Code Injection in Parameter Handling (CVE-equivalent)
- **File**: `Functions/ConvertTo-Parameters.ps1`
- **Issue**: String parameters were not properly escaped before embedding into scriptblocks
- **Attack Vector**: Malicious hashtable parameters could inject arbitrary PowerShell commands
- **Fix**: All string values now properly escaped with quote escaping
- **Status**: ✓ RESOLVED

#### 2. Syntax Validation Before Execution
- **File**: `Functions/Get-SBResult.ps1`
- **Issue**: No validation of command syntax before execution
- **Enhancement**: Added pre-execution syntax validation using PowerShell parser
- **Benefit**: Catches injection attempts that result in invalid syntax
- **Status**: ✓ ADDED

#### 3. Access Identifier Validation Hardened
- **File**: `FunctionsWindows/Test-UserOrGroupExists.ps1`
- **Issue**: Weak validation allowing malformed identifiers
- **Fix**: Strict validation of identifier format and whitespace checks
- **Status**: ✓ IMPROVED

### File Changes

```
Functions/ConvertTo-Parameters.ps1
- Added proper quote escaping for string values
- Added array handling with escaping
- Updated help text to document security measures

Functions/Get-SBResult.ps1
- Added syntax validation via Parser.ParseInput()
- Improved error messages for invalid commands
- Updated documentation to mention security validation

FunctionsWindows/Test-UserOrGroupExists.ps1
- Stricter part count validation (1-3 only)
- Added null/whitespace checks on identity
- Better error messages per validation type
- Use of -split operator instead of .split() method

NamedPipe.psd1
- Version bumped to 0.9
- Description updated to mention security fixes
```

### New Files

- `SECURITY_FIXES.md` - Detailed security advisory and remediation
- `CHANGES_v0.9.md` - This file
- `Tests/SecurityFixes-Test.ps1` - Security validation tests

### Backward Compatibility

✓ **Fully backward compatible** - All valid v0.8 code continues to work in v0.9.

Only malicious injection attempts are now blocked.

### Deployment

Deploy using the standard mechanism:
```powershell
powershell.exe -NoProfile -File "D:\PowerShellScripts\Modules\Deploy-Modules.ps1"
```

### Testing

Run the included security test:
```powershell
powershell.exe -NoProfile -File "D:\PowerShellScripts\Modules\NamedPipe\0.9\Tests\SecurityFixes-Test.ps1"
```

### Migration from v0.8

1. Deploy v0.9 module
2. Existing pipe sessions will reconnect to v0.9 automatically
3. No code changes required in consumer modules (VHDTools, etc.)
4. Optional: Review any custom parameter handling for edge cases

### Known Limitations

None - all critical issues addressed.

### Future Work

- [ ] Medium-priority fixes for information disclosure
- [ ] Error handling improvements for better diagnostics
- [ ] Extended audit logging for security monitoring

---

**Release Date**: 2026-07-03  
**Status**: Production Ready  
**Security Risk**: CRITICAL FIX - deploy immediately
