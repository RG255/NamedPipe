# VENDORED from CommonScripts\0.2\FunctionsWindows\Get-ProcessIdFromWindowHandle.ps1 by Sync-SharedUtilities [SHA256 D618C81A24C5F41C2F33C4EAB41DD28F5F6DE2DA388F00AB5698BF75C310BAC5] - DO NOT EDIT (edit the master; Deploy-Modules re-syncs).
Function Get-ProcessIdFromWindowHandle
{
	<#
		.SYNOPSIS
		Gets the process ID that owns a window.

		.DESCRIPTION
		Wraps GetWindowThreadProcessId. SELF-CONTAINED: carries its own minimal Win32 P/Invoke (idempotent
		Add-Type) so it works independently of the [Window] type / Publish-SetWindowCode / this module - copy
		the function into any script and it stands alone. Returns $null when the handle owns no process.
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $True, ValueFromPipeline = $True)]
		[IntPtr]$WindowHandle
	)
	Process
	{
		If (-not ('WindowHelper.WindowPid' -as [type]))
		{
			Add-Type -Namespace 'WindowHelper' -Name 'WindowPid' -MemberDefinition '
				[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
				public static extern uint GetWindowThreadProcessId(System.IntPtr hWnd, out uint processId);
			'
		}
		$Private:ProcessId = [uint32]::Zero
		$null = [WindowHelper.WindowPid]::GetWindowThreadProcessId($WindowHandle, [ref]$Private:ProcessId)
		if ($Private:ProcessId)
		{ $Private:ProcessId }
		else
		{ $null }
	}
}
