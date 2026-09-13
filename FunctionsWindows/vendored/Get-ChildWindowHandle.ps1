# VENDORED from CommonScripts\0.2\FunctionsWindows\Get-ChildWindowHandle.ps1 by Sync-SharedUtilities [SHA256 ADB0B50E64A92A3547C76205FEE85E69509611ED39EC0E06AB6203F8CB29C5D8] - DO NOT EDIT (edit the master; Deploy-Modules re-syncs).
Function Get-ChildWindowHandle
{
	<#
		.SYNOPSIS
		Gets all child window handles for a parent window.

		.DESCRIPTION
		Enumerates child windows via EnumChildWindows. SELF-CONTAINED for the P/Invoke: carries its own minimal
		Win32 declaration (idempotent Add-Type, including the callback delegate) so it needs no [Window] type /
		Publish-SetWindowCode / this module for the native call. Each entry is "<handle>,<title>"; the title is
		resolved via Get-WindowName, so copy Get-WindowName alongside this function when using it standalone.
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $True)]
		[System.IntPtr]$ParentHandle
	)

	If (-not ('WindowHelper.EnumWindows' -as [type]))
	{
		Add-Type -Namespace 'WindowHelper' -Name 'EnumWindows' -MemberDefinition '
			public delegate bool EnumWindowsProc(System.IntPtr hwnd, System.IntPtr lParam);
			[System.Runtime.InteropServices.DllImport("user32.dll")]
			public static extern bool EnumChildWindows(System.IntPtr hwndParent, EnumWindowsProc lpEnumFunc, System.IntPtr lParam);
		'
	}

	# Use a regular (non-Private) variable so the scriptblock closure can access it
	$ChildWindows = New-Object -TypeName System.Collections.ArrayList
	$Callback = {
		Param (
			[System.IntPtr]$hwnd,
			[System.IntPtr]$lParam
		)
		$null = $lParam  # required by delegate signature; suppress unused-variable warning
		$ChildWindows.Add(('{0},{1}' -f $hwnd, ($hwnd | Get-WindowName)))
		return $True
	}
	$null = [WindowHelper.EnumWindows]::EnumChildWindows($ParentHandle, $Callback, [System.IntPtr]::Zero)
	$ChildWindows
}
