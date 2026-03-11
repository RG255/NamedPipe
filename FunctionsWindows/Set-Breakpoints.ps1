Function Set-Breakpoints
{
	<#
		.SYNOPSIS
		Sets PowerShell breakpoints on the server process from a breakpoint list.

		.DESCRIPTION
		Iterates through a breakpoint information structure (from Initialize-BPList)
		and sets line or command breakpoints on the specified scripts/functions.
		Used for debugging the detached server process.

		.PARAMETER BPObject
		The breakpoint information hashtable from Initialize-BPList, with
		line/command breakpoint definitions populated.

		.EXAMPLE
		$BPList = Set-Breakpoints -BPObject $BPList
		Sets all defined breakpoints and returns the updated list with IDs.

		.OUTPUTS
		The updated BPObject with breakpoint ID information populated.
	#>

	[CmdletBinding()]
	Param(
		[Parameter(Mandatory)]
		$BPObject
	)
	If ($Script:FTrace)
	{Write-MyLog -PathToLogFile $Script:FTLogFilePath -CallStack (Get-PSCallStack)}
	
	foreach ($Private:Function in $BPObject.keys)
	{
		If ($BPObject.$Private:Function.Lines.count -ne [int]0)
		{
			If ($ServerClientParams.$StrInfoDisplay -band 2)
			{
				Show-VerboseData -Object $BPObject.$Private:Function.Fullname -Display -Title 'Set breakpoint for script'
				Show-VerboseData -Object $BPObject.$Private:Function.Lines -Display -Title 'Line breakpoint to set'
			}
			if ($BPObject.$Private:Function.IDNoList.line -inotmatch $BPObject.$Private:Function.Lines.line)
			{
				$Private:Params = $BPObject.$Private:Function.Lines
				$Private:BreakPointInfo = Set-PSBreakpoint @Private:Params
				$BPObject.$Private:Function.IdNoList += $Private:BreakPointInfo
				If ($ServerClientParams.$StrInfoDisplay -band 2)
				{Show-VerboseData -Object $Private:BreakPointInfo -Display -Title 'After setting breakpoint'}
			}
		}
		If ($BPObject.$Private:Function.Command.count -ne [int]0)
		{
			If ($ServerClientParams.$StrInfoDisplay -band 2)
			{
				Show-VerboseData -Object $BPObject.$Private:Function.Fullname -Display -Title 'Set breakpoint for script'
				Show-VerboseData -Object $BPObject.$Private:Function.Command -Display -Title 'Command breakpoint to set'
			}
			$Private:Params = $BPObject.$Private:Function.Command
			$Private:BreakPointInfo = Set-PSBreakpoint @Private:Params
			$BPObject.$Private:Function.IdNoList += $Private:BreakPointInfo
			If ($ServerClientParams.$StrInfoDisplay -band 2)
			{Show-VerboseData -Object $Private:BreakPointInfo -Display -Title 'After setting breakpoint'}
		}
	}
	$BPObject
}
