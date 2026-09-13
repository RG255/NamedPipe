# VENDORED from CommonScripts\0.2\FunctionsWindows\Publish-SetWindowCode.ps1 by Sync-SharedUtilities [SHA256 E61FD13B31BA70887972AE82BB95B7BE867C93167DD49D8F8CD43418FD97346D] - DO NOT EDIT (edit the master; Deploy-Modules re-syncs).
Function Publish-SetWindowCode
{
	<#
		.SYNOPSIS
		Compiles the [Window] class for Win32 API interop used by Set-Window.

		.DESCRIPTION
		Uses Add-Type to compile C# code that provides P/Invoke declarations for
		Win32 APIs required for window manipulation (positioning, sizing, state
		changes). The [Window] class is only compiled once per PowerShell session.

		.NOTES
		Version: 1.23 2026-07-25
		Scope is limited to what Set-Window consumes. The window-lookup P/Invokes
		(FindWindow/FindWindowEx/GetWindowThreadProcessId/GetWindowText/GetWindowTextLength/
		EnumChildWindows) now live self-contained in Get-WindowHandleByTitle,
		Get-ProcessIdFromWindowHandle, Get-WindowName and Get-ChildWindowHandle and are
		no longer declared here.
		Required by: Set-Window.ps1
	#>

	try
	{
		try
		{ $null = [Window] }
		catch
		{
			# 2026-09-11: only audit an UNEXPECTED exception type here - a RuntimeException ("Unable to
			# find type [Window]") is the routine, expected outcome EVERY time this function runs (it is
			# only ever called when Set-Window's own probe already found the type missing), so auditing
			# it every time was pure log noise, not a signal of anything worth reviewing. Everything below
			# still runs unconditionally either way - only the audit call is gated.
			if ($_.Exception -isnot [System.Management.Automation.RuntimeException])
			{ Write-MyCatchAudit -Source 'Publish-SetWindowCode: [Window] type probe failed with an unexpected exception - not the routine "not yet defined" case' -ErrorRecord $_ }
			if ($Global:Error.Count -eq [int]1)
			{ $Global:Error.Clear() }

			Add-Type -TypeDefinition @'
        using System;
        using System.Runtime.InteropServices;

        public class Window
        {
          [DllImport("user32.dll", SetLastError = true)]
          [return: MarshalAs(UnmanagedType.Bool)]
          public static extern bool SetWindowText(IntPtr hWnd, String lpString);

          [DllImport("User32.dll", SetLastError = true)]
          [return: MarshalAs(UnmanagedType.Bool)]
          public extern static bool MoveWindow(IntPtr hWnd, int x, int y, int width, int height, bool redraw);

          [DllImport("User32.dll", SetLastError = true)]
          [return: MarshalAs(UnmanagedType.Bool)]
          public extern static bool GetWindowInfo(IntPtr hWnd, ref WINDOWINFO pwi);

          [DllImport("user32.dll", SetLastError = true)]
          [return: MarshalAs(UnmanagedType.Bool)]
          public extern static bool GetWindowPlacement(IntPtr hWnd, ref Windowplacement lpwndpl);

          [DllImport("user32.dll", SetLastError = true)]
          [return: MarshalAs(UnmanagedType.Bool)]
          public extern static bool ShowWindow(IntPtr hWnd, int nCmdShow);

          [DllImport("user32.dll", SetLastError = true)]
          [return: MarshalAs(UnmanagedType.Bool)]
          public extern static bool SetForegroundWindow(IntPtr hwnd);

          [DllImport("kernel32.dll", SetLastError = true)]
          [return: MarshalAs(UnmanagedType.Bool)]
          public static extern bool GetCurrentConsoleFont(IntPtr hWnd, bool bMaximumWindow, out CONSOLE_FONT_INFO lpConsoleCurrentFont);

          [DllImport("kernel32.dll", SetLastError = true)]
          public static extern IntPtr GetStdHandle(int nStdHandle);

          [DllImport("Kernel32.dll", SetLastError = true)]
          public extern static int GetConsoleWindow();

          [DllImport("kernel32.dll")]
          public extern static int GetLastError();

          public static string GetLastErrorMessage() {
            return (new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error())).Message;
          }
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct Windowplacement
        {
          public uint length;
          public uint flags;
          public uint showCmd;
          public POINT ptMinPosition;
          public POINT ptMaxPosition;
          public RECT rcNormalPosition;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct POINT
        {
          public int x;
          public int y;
        }

        public enum ShowWindowEnum
        {
          Hide = 0,
          ShowNormal = 1, ShowMinimized = 2, ShowMaximized = 3,
          Maximize = 3, ShowNormalNoActivate = 4, Show = 5,
          Minimize = 6, ShowMinNoActivate = 7, ShowNoActivate = 8,
          Restore = 9, ShowDefault = 10, ForceMinimized = 11
        }

        public struct RECT
        {
          public int Left;
          public int Top;
          public int Right;
          public int Bottom;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct CONSOLE_FONT_INFO
        {
          public int Font;
          public COORD FontSize;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct COORD
        {
          public short x;
          public short y;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct WINDOWINFO
        {
          public uint cbSize;
          public RECT rcWindow;
          public RECT rcClient;
          public uint dwStyle;
          public uint dwExStyle;
          public uint dwWindowStatus;
          public uint cxWindowBorders;
          public uint cyWindowBorders;
          public ushort atomWindowType;
          public ushort wCreatorVersion;

          public WINDOWINFO(Boolean ? filler) : this()
          {
            cbSize = (UInt32)(Marshal.SizeOf(typeof(WINDOWINFO)));
          }
        }
'@
		}
	}
	catch
	{
		# 2026-09-11: a genuine Add-Type compile failure here is a real, worth-investigating defect (the
		# embedded C# is a fixed, hardcoded string - "no user input" per this function's own .DESCRIPTION
		# - so failure here means something is deeply wrong with the .NET/PowerShell environment itself),
		# unlike the routine "not yet defined" case above. The Write-Output line below is not a reliable
		# way for a human to ever see this: Set-Window (this function's only caller) can be invoked from
		# a GUI async runspace whose output stream is never displayed, or from a server-side elevated
		# dispatch context where `exit` below would terminate that process before anyone reads its
		# output. Write-MyCatchAudit gives this a durable, persisted record regardless of who is or isn't
		# watching the console at that exact moment.
		Write-MyCatchAudit -Source 'Publish-SetWindowCode: Add-Type failed to compile the [Window] type - the embedded C# is a fixed, hardcoded string, so this indicates a genuinely broken .NET/PowerShell environment, not routine first-use behavior' -ErrorRecord $_
		Write-Output -InputObject 'Publish-SetWindowCode: Failed to compile [Window] type'
		exit
	}
}
