# VENDORED from CommonScripts\0.2\FunctionsWindows\Get-WindowName.ps1 by Sync-SharedUtilities [SHA256 7838BA6176B6FCC02BA06DA29A0AF34FB6B09B93980C96556B389DF59681947B] - DO NOT EDIT (edit the master; Deploy-Modules re-syncs).
Function Get-WindowName
{
	<#
		.SYNOPSIS
		Gets the title/text of a window by its handle.

		.DESCRIPTION
		Wraps GetWindowText/GetWindowTextLength. SELF-CONTAINED: carries its own minimal Win32 P/Invoke
		(idempotent Add-Type) so it works independently of the [Window] type / Publish-SetWindowCode / this
		module - copy the function into any script and it stands alone.
	#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $True, ValueFromPipeline = $True)]
		[IntPtr]$hwnd
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
		If (-not ('WindowHelper.WindowText' -as [type]))
		{
			Add-Type -Namespace 'WindowHelper' -Name 'WindowText' -MemberDefinition '
				[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
				public static extern int GetWindowTextLength(System.IntPtr hWnd);
				[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
				public static extern int GetWindowText(System.IntPtr hWnd, System.Text.StringBuilder text, int count);
			'
		}
		$Private:Len = [WindowHelper.WindowText]::GetWindowTextLength($hwnd)
		if ($Private:Len -gt 0)
		{
			$Private:Sb = New-Object -TypeName Text.StringBuilder -ArgumentList ($Private:Len + 1)
			$null = [WindowHelper.WindowText]::GetWindowText($hwnd, $Private:Sb, $Private:Sb.Capacity)
			$Private:Sb.ToString()
		}
	}
}
