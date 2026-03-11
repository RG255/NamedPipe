# Test script to check what values are parsed from the DefineVariablesPipe hashtable

# First define the required variables that the file depends on
$VSScript = 'Script'
$VONone = 'None'
$VOReadOnly = 'ReadOnly'

# Function to capture MyVars
function Publish-Variables {
    Write-Host "Publish-Variables called. Checking MyVars:" -ForegroundColor Cyan
    foreach ($VarSet in $MyVars.Keys) {
        Write-Host "  VarSet: $VarSet" -ForegroundColor Yellow
        foreach ($Item in $MyVars[$VarSet].Keys | Sort-Object) {
            $value = $MyVars[$VarSet][$Item].Value
            $valueBytes = if ($value) { [System.Text.Encoding]::UTF8.GetBytes($value) -join ',' } else { 'NULL/EMPTY' }
            Write-Host "    $Item = '$value' (bytes: $valueBytes)"
        }
    }
}

# Dot-source the file
Write-Host "=== Dot-sourcing DefineVariablesPipe.ps1 ===" -ForegroundColor Green
. "$PSScriptRoot\..\FunctionsWindows\DefineVariablesPipe.ps1"
