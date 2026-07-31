# VENDORED from CommonScripts\0.2\FunctionsWindows\Set-MyWindowState.ps1 by Sync-SharedUtilities - DO NOT EDIT (edit the master; Deploy-Modules re-syncs).
Function Set-MyWindowState
{
	<#
		.SYNOPSIS
		Hide, show, minimise, restore, or maximise a process's main window.

		.DESCRIPTION
		A lightweight replacement for the window-STATE part of Set-Window: a single ShowWindow P/Invoke, with
		no geometry and no [Window] C# type. Operates on a process's MainWindowHandle.

		Never throws. Returns $true if the state was applied, $false if the process has no top-level window
		(e.g. a console hosted by Windows Terminal / ConPTY, where MainWindowHandle is 0) or on any failure.

		Position/size were deliberately NOT carried over: Set-Window's sizing/positioning does not work under
		Windows Terminal (each session is a tab, not a window) - see memory reference_setwindow_win11. The full
		Set-Window remains archived in CommonScripts for the rare case a real classic window needs geometry.

		.PARAMETER ProcessId
		PID of the target process whose main window to act on.

		.PARAMETER State
		Hide | Show | Minimize | Restore | Maximize | Normal.

		.OUTPUTS
		[Bool] - $true if the state was applied, $false if there was no window to act on (or on error).

		.EXAMPLE
		Set-MyWindowState -ProcessId $PID -State Minimize

		.EXAMPLE
		$null = Set-MyWindowState -ProcessId $child.Id -State Restore
	#>
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Best-effort window-state toggle via ShowWindow; must never prompt or throw')]
	[CmdletBinding()]
	[OutputType([Bool])]
	Param (
		[Parameter(Mandatory, HelpMessage = 'Target process id')]
		[int]$ProcessId,
		[Parameter(Mandatory, HelpMessage = 'Window state to apply')]
		[ValidateSet('Hide', 'Show', 'Minimize', 'Restore', 'Maximize', 'Normal')]
		[String]$State
	)

	If (-not ([System.Management.Automation.PSTypeName]'CS.WinState').Type)
	{
		Add-Type -Namespace 'CS' -Name 'WinState' -MemberDefinition '
			[System.Runtime.InteropServices.DllImport("user32.dll")]
			public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
		' -ErrorAction SilentlyContinue
	}

	# ShowWindow nCmdShow codes.
	$Private:Codes = @{ Hide = 0; Normal = 1; Maximize = 3; Show = 5; Minimize = 6; Restore = 9 }

	Try
	{
		$Private:Hwnd = (Get-Process -Id $ProcessId -ErrorAction Stop).MainWindowHandle
		# No top-level window (0) - e.g. a console under Windows Terminal/ConPTY. Nothing to do; report it.
		If (-not $Private:Hwnd -or $Private:Hwnd -eq [IntPtr]::Zero) { return $false }
		return [CS.WinState]::ShowWindow($Private:Hwnd, [int]$Private:Codes[$State])
	}
	Catch { return $false }
}
