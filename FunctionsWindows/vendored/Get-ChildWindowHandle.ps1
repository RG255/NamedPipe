# VENDORED from CommonScripts\0.2\FunctionsWindows\Get-ChildWindowHandle.ps1 by Sync-SharedUtilities [SHA256 47E665B35A45AA4A58CA57ABB916BF5EF705DCA84730033588C6F312A68CC199] - DO NOT EDIT (edit the master; Deploy-Modules re-syncs).
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

	# -and (Get-Command...) guard: see ConvertFrom-Serial.ps1's own comment (2026-09-15) - this file
	# is vendored into modules that never vendor Write-MyFunctionTrace itself, and the process-scoped
	# $env:MyFunctionTraceEnabled can be '1' there regardless.
	If ((1 -band ($env:MyFunctionTraceEnabled -as [Int])) -and (Get-Command -Name Write-MyFunctionTrace -ErrorAction SilentlyContinue)) { Write-MyFunctionTrace }

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
