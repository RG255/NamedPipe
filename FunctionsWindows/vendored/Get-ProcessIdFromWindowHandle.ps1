# VENDORED from CommonScripts\0.2\FunctionsWindows\Get-ProcessIdFromWindowHandle.ps1 by Sync-SharedUtilities [SHA256 CEEE38DB2FE00E6FDAA2FDEEA87C5C1787D0883265A8032EB3F9A2406CB821B1] - DO NOT EDIT (edit the master; Deploy-Modules re-syncs).
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
	Begin
	{
		# -and (Get-Command...) guard: see ConvertFrom-Serial.ps1's own comment (2026-09-15) - this file
	# is vendored into modules that never vendor Write-MyFunctionTrace itself, and the process-scoped
	# $env:MyFunctionTraceEnabled can be '1' there regardless.
	If ((1 -band ($env:MyFunctionTraceEnabled -as [Int])) -and (Get-Command -Name Write-MyFunctionTrace -ErrorAction SilentlyContinue)) { Write-MyFunctionTrace }
	}
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
