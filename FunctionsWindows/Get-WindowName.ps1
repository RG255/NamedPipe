# VENDORED from CommonScripts\0.2\FunctionsWindows\Get-WindowName.ps1 by Sync-SharedUtilities [SHA256 8066A357D4134F63C3053C51FC8CCBB80466FEDB7BE0B41641EFF163FB212DF8] - DO NOT EDIT (edit the master; Deploy-Modules re-syncs).
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
