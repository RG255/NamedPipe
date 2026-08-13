# VENDORED from CommonScripts\0.2\FunctionsWindows\Publish-SetWindowCode.ps1 by Sync-SharedUtilities [SHA256 12CA72F9C0AEE1C353209E6DBCBDFB7AD0C62CF84C36BF65548CA3F9534E7F55] - DO NOT EDIT (edit the master; Deploy-Modules re-syncs).
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
		Get-ProcessIdFromWindowHandle, Get-WindowName and Get-ChildWindowHandles and are
		no longer declared here.
		Required by: Set-Window.ps1
	#>

	try
	{
		try
		{ $null = [Window] }
		catch
		{
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
		Write-Output -InputObject 'Publish-SetWindowCode: Failed to compile [Window] type'
		exit
	}
}
