# VENDORED from CommonScripts\0.2\FunctionsWindows\Get-WindowHandleByTitle.ps1 by Sync-SharedUtilities [SHA256 D4AE596BBF7215DBA8DEEDC4A0239A91C13D96AEB8898D3EBAD07DC6718C926B] - DO NOT EDIT (edit the master; Deploy-Modules re-syncs).
Function Get-WindowHandleByTitle
{
	<#
		.SYNOPSIS
		Finds a window handle by its exact title.

		.DESCRIPTION
		Wraps FindWindowEx. SELF-CONTAINED: carries its own minimal Win32 P/Invoke (idempotent Add-Type) so it
		works independently of the [Window] type / Publish-SetWindowCode / this module - copy the function into
		any script and it stands alone. Match is case-insensitive but EXACT on the full window title.
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $True, ValueFromPipeline = $True)]
		[String]$WindowTitle
	)
	Process
	{
		If (-not ('WindowHelper.FindWindow' -as [type]))
		{
			Add-Type -Namespace 'WindowHelper' -Name 'FindWindow' -MemberDefinition '
				[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
				public static extern System.IntPtr FindWindowEx(System.IntPtr parent, System.IntPtr childAfter, System.IntPtr className, string windowTitle);
			'
		}
		[WindowHelper.FindWindow]::FindWindowEx([System.IntPtr]::Zero, [System.IntPtr]::Zero, [System.IntPtr]::Zero, $WindowTitle)
	}
}
