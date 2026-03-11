# Debug script to check variable creation
Remove-Module NamedPipe -Force -ErrorAction SilentlyContinue

# Check variables before module load
Write-Host "=== Before Module Load ===" -ForegroundColor Yellow
Write-Host "StrSecurity exists: $(Test-Path Variable:StrSecurity)"
Write-Host "StrScriptBlock exists: $(Test-Path Variable:StrScriptBlock)"
Write-Host "StrType exists: $(Test-Path Variable:StrType)"

# Load the module
Import-Module NamedPipe -RequiredVersion 0.1

# Check variables after module load
Write-Host "`n=== After Module Load ===" -ForegroundColor Yellow
Write-Host "StrSecurity: '$StrSecurity'"
Write-Host "StrScriptBlock: '$StrScriptBlock'"
Write-Host "StrType: '$StrType'"
Write-Host "StrExitPipe: '$StrExitPipe'"
Write-Host "StrServer: '$StrServer'"
Write-Host "StrResult: '$StrResult'"

# List all Str* variables
Write-Host "`n=== All Str* Variables ===" -ForegroundColor Yellow
Get-Variable -Name Str* | Where-Object { $_.Value } | Format-Table Name, Value -AutoSize
