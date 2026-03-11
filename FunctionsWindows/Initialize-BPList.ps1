Function Initialize-BPList
{
	<#
		.SYNOPSIS
		Initialises a breakpoint list for debugging server-side pipe operations.

		.DESCRIPTION
		Creates a breakpoint information structure that can be used to set and manage
		PowerShell breakpoints on the server process. When -AddModules is specified,
		scans all loaded module function files and adds them to the breakpoint list.

		This is a development/debugging utility for setting breakpoints in the
		detached server process, which cannot be debugged interactively.

		.PARAMETER AddModules
		When specified, adds all function files from loaded modules to the
		breakpoint list so breakpoints can be set on module functions.

		.EXAMPLE
		$BPList = Initialize-BPList -AddModules
		Initialises a breakpoint list including all loaded module functions.

		.OUTPUTS
		Hashtable of breakpoint information keyed by function/script name.
	#>

	[CmdletBinding(DefaultParameterSetName = 'None')]
	Param (
		[Switch]$AddModules
	)
	Try
	{
		If ($Script:FTrace)
		{Write-MyLog -PathToLogFile $Script:FTLogFilePath -CallStack (Get-PSCallStack)}
		
		$BPObject=Set-ObjectParams -Dataset breakpoint
		
		If ($BPObject.BPInfo.count -eq [int]0)
		{$Private:FunctionBPinfo = @{}
			# Add calling script
			$Private:Functioninfo = Set-ObjectParams -Dataset breakpoint
			$Private:Functioninfo.Fullname = ((Get-PSCallStack)[-1].Scriptname)
			$Private:Functioninfo.Name = [System.IO.Path]::GetFileNameWithoutExtension($Private:Functioninfo.Fullname)
			$Private:FunctionBPinfo.add($Private:Functioninfo.Name,$Private:Functioninfo)
		}
		Else
		{$Private:FunctionBPinfo = $BPObject.BPInfo}
		
		#if (-not $Private:FunctionBPinfo[$BPObject.name].Name)
		#{$Private:FunctionBPinfo.add($BPObject.name,$BPObject)}
						
		if ($AddModules)
		{
			foreach ($Private:Mod in (Get-Module | Where-Object { $_.ModuleBase }))
			{
				foreach ($Private:Item in (Get-ChildItem -Path (Join-Path -Path $Private:Mod.ModuleBase -ChildPath '\f*') -Filter *.ps1 -Recurse -ErrorAction SilentlyContinue))
				{
					if (-not $Private:FunctionBPinfo[$Private:Item.basename].name)
					{
						$Private:Functioninfo = Set-ObjectParams -Dataset breakpoint
						$Private:Functioninfo.Fullname = $Private:Item.Fullname
						$Private:Functioninfo.Name = [System.IO.Path]::GetFileNameWithoutExtension($Private:Functioninfo.Fullname)
						$Private:FunctionBPinfo.add($Private:Functioninfo.Name,$Private:Functioninfo)
					}
				}
			}
		}
	}
	catch
	{$Private:FunctionBPinfo.Add('Error',(Get-MyErrors -Return))}
	$Private:FunctionBPinfo
}
