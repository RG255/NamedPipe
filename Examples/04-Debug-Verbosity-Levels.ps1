<#
	.SYNOPSIS
	NamedPipe example 4: what each -InfoDisplay bitmask level actually prints, side by side.

	.DESCRIPTION
	-InfoDisplay is a bitmask (0=silent, 1=server/client progress, 2=Show-VerboseData dump, 4=debug
	output - see Start-PipeTest.ps1's own -InfoDisplay help text). This script runs the SAME one
	request four times, once per level, with a fresh session each time, so the difference is directly
	comparable instead of inferred from documentation.

	.EXAMPLE
	powershell.exe -NoProfile -File .\04-Debug-Verbosity-Levels.ps1
#>

Remove-Module -Name NamedPipe -Force -ErrorAction SilentlyContinue
Import-Module -Name NamedPipe -Force -RequiredVersion 0.15 -ErrorAction Stop

$Private:Levels = @(
	@{ Value = 0; Label = '0 = silent' }
	@{ Value = 1; Label = '1 = server/client progress echo' }
	@{ Value = 2; Label = '2 = Show-VerboseData dump' }
	@{ Value = 4; Label = '4 = debug output' }
)

ForEach ($Private:Level in $Private:Levels)
{
	Write-Host ''
	Write-Host ('===== -InfoDisplay {0} =====' -f $Private:Level.Label) -ForegroundColor Cyan

	$Session = Start-PipeSession -MyParameters @{} -Options @{ $StrInfoDisplay = $Private:Level.Value }
	$ServerClientParams = $Session.$StrServerClientParams
	$SendRequestParams  = $Session.$StrSendRequestParams
	$SendRequestParams.$StrType = $StrScriptBlock

	try
	{
		$SendRequestParams.$StrDataObject = 'Get-Date' | Send-Request @SendRequestParams
		Start-Sleep -Milliseconds 300
		Write-Host ('(This script''s own view of the result: {0})' -f $SendRequestParams.$StrDataObject.$StrResult) -ForegroundColor DarkGray
	}
	finally
	{ Stop-PipeSession -SendRequestParams $SendRequestParams -PipeInfo $ServerClientParams.$StrPipeInfo }
}

Write-Host ''
Write-Host 'Compare the four server console windows above - each ran the identical request.' -ForegroundColor Cyan
