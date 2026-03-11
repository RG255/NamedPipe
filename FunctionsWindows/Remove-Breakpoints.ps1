Function Remove-Breakpoints
{
	<#
		.SYNOPSIS
		Removes PowerShell breakpoints set by Set-Breakpoints.

		.DESCRIPTION
		Removes breakpoints either from a specific breakpoint list (BPObject)
		or all breakpoints in the current session. Used for cleanup after
		debugging server-side pipe operations.

		.PARAMETER BPObject
		The breakpoint information hashtable containing breakpoint IDs to remove.

		.PARAMETER All
		When specified, removes ALL breakpoints in the current PowerShell session
		regardless of how they were created.

		.EXAMPLE
		Remove-Breakpoints -BPObject $BPList
		Removes only the breakpoints tracked in the breakpoint list.

		.EXAMPLE
		Remove-Breakpoints -All
		Removes all breakpoints in the session.

		.OUTPUTS
		The updated BPObject with cleared ID lists (when -BPObject is used).
		No output when -All is used.
	#>

	[CmdletBinding()]
	Param(
		[Parameter(Mandatory,ParameterSetName = 'list')]
		[PSObject]$BPObject,
		[Parameter(ParameterSetName = 'all')]
		[Switch]$All
	)
	If ($Script:FTrace)
	{Write-MyLog -PathToLogFile $Script:FTLogFilePath -CallStack (Get-PSCallStack)}
	
	If ($All)
	{
		foreach ($Private:ID in (Get-PSBreakpoint).Id)
		{Remove-PSBreakpoint -Id $Private:ID}
	}
	Else
	{
		foreach ($Private:BPFunction in $BPObject.keys)
		{
			If ($BPObject.$Private:BPFunction.IDNoList.count -gt [int]0)
			{
				foreach ($IDNo in $BPObject.$Private:BPFunction.IDNoList.Id)
				{Remove-PSBreakpoint -Id $IDNo -ErrorAction SilentlyContinue}
				$BPObject.$Private:BPFunction.IDNoList = @{}
			}
		}
		$BPObject
	}
}
