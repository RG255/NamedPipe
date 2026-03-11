Function Publish-SetWindowCode
{
	<#
		.SYNOPSIS
		Compiles the [Window] class for Win32 API interop used by Set-Window.ps1

		.DESCRIPTION
		This function uses Add-Type to compile C# code that provides P/Invoke
		declarations for Win32 APIs. These APIs are required for window manipulation
		(positioning, sizing, state changes) which have no .NET equivalent.

		The [Window] class is only compiled once per PowerShell session.

		.NOTES
		Version: 1.21 2026-02-03
		- Removed unused P/Invoke declarations (GetClassName, GetWindowRect,
		  ShowWindowAsync, GetForegroundWindow, AttachConsole, FreeConsole, SetLastError,
		  GetConsoleFontSize, DWORD struct)
		- Restored FindWindow overloads for top-level window searches
		- Added documentation comments

		Required by: Set-Window.ps1

		Win32 APIs used:
		- user32.dll: Window manipulation (position, size, state, text)
		- kernel32.dll: Console font information
	#>
	Set-Variable -Name Publish-SetWindowCodeVersion -Value ('1.22 2026-02-07')
	If ($Script:FTrace)
	{Write-MyLog -PathToLogFile $Script:FTLogFilePath -CallStack (Get-PSCallStack)}
	try
	{
		Try
		{$Null = [Window]}
		Catch
		{
			if ($Global:Error.Count -eq [int]1)
			{$Global:Error.Clear()}
			Add-Type -TypeDefinition @'
        using System;
        using System.Runtime.InteropServices;
        using System.Text;

        /// <summary>
        /// Provides P/Invoke declarations for Win32 window manipulation APIs.
        /// Used by Set-Window.ps1 for positioning, sizing, and state management.
        /// </summary>
        public class Window
        {
          //=============================================================================
          // WINDOW SEARCH FUNCTIONS (used by helper functions)
          //=============================================================================

          /// <summary>Finds a top-level window by class name and/or window title</summary>
          [DllImport("user32.dll", SetLastError = true)]
          public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

          [DllImport("user32.dll", SetLastError = true)]
          public static extern IntPtr FindWindow(string lpClassName, IntPtr lpWindowName);

          [DllImport("user32.dll", SetLastError = true)]
          public static extern IntPtr FindWindow(IntPtr lpClassName, string lpWindowName);

          /// <summary>Finds a child window by class and/or title</summary>
          [DllImport("user32.dll", SetLastError = true)]
          public static extern IntPtr FindWindowEx(IntPtr hwndParent, IntPtr hwndChildAfter, IntPtr lpszClass, string lpszWindow);

          [DllImport("user32.dll", SetLastError = true)]
          public static extern IntPtr FindWindowEx(IntPtr hwndParent, IntPtr hwndChildAfter, string lpszClass, string lpszWindow);

          /// <summary>Gets the thread and process ID for a window handle</summary>
          [DllImport("user32.dll", SetLastError = true)]
          public static extern IntPtr GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

          //=============================================================================
          // WINDOW TEXT FUNCTIONS
          //=============================================================================

          /// <summary>Gets the window title/text into a StringBuilder</summary>
          [DllImport("user32.dll", SetLastError = true)]
          public static extern IntPtr GetWindowText(IntPtr hWnd, StringBuilder text, int count);

          /// <summary>Gets the length of window title/text</summary>
          [DllImport("user32.dll", CharSet=CharSet.Auto)]
          public static extern Int32 GetWindowTextLength(IntPtr hWnd);

          /// <summary>Sets the window title/text</summary>
          [DllImport("user32.dll", SetLastError = true)]
          [return: MarshalAs(UnmanagedType.Bool)]
          public static extern bool SetWindowText(IntPtr hWnd, String lpString);

          //=============================================================================
          // WINDOW POSITION AND SIZE FUNCTIONS
          //=============================================================================

          /// <summary>Moves and resizes a window</summary>
          [DllImport("User32.dll", SetLastError = true)]
          [return: MarshalAs(UnmanagedType.Bool)]
          public extern static bool MoveWindow(IntPtr hWnd, int x, int y, int width, int height, bool redraw);

          /// <summary>Gets detailed window information (size, borders, style)</summary>
          [DllImport("User32.dll", SetLastError = true)]
          [return: MarshalAs(UnmanagedType.Bool)]
          public extern static bool GetWindowInfo(IntPtr hWnd, ref WINDOWINFO pwi);

          /// <summary>Gets window placement (normal position, minimized/maximized state)</summary>
          [DllImport("user32.dll", SetLastError = true)]
          [return: MarshalAs(UnmanagedType.Bool)]
          public extern static bool GetWindowPlacement(IntPtr hWnd, ref Windowplacement lpwndpl);

          //=============================================================================
          // WINDOW STATE FUNCTIONS
          //=============================================================================

          /// <summary>Shows/hides window or changes its state (minimize, maximize, restore)</summary>
          [DllImport("user32.dll", SetLastError = true)]
          [return: MarshalAs(UnmanagedType.Bool)]
          public extern static bool ShowWindow(IntPtr hWnd, int nCmdShow);

          /// <summary>Brings window to foreground and activates it</summary>
          [DllImport("user32.dll", SetLastError = true)]
          [return: MarshalAs(UnmanagedType.Bool)]
          public extern static bool SetForegroundWindow(IntPtr hwnd);

          /// <summary>Enumerates all child windows of a parent window</summary>
          [DllImport("user32.dll", SetLastError = true)]
          [return: MarshalAs(UnmanagedType.Bool)]
          public static extern bool EnumChildWindows(IntPtr hwndParent, EnumWindowsProc lpEnumFunc, IntPtr lParam);
          public delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);

          //=============================================================================
          // CONSOLE FUNCTIONS (for character-based sizing)
          //=============================================================================

          /// <summary>Gets current console font information</summary>
          [DllImport("kernel32.dll", SetLastError = true)]
          [return: MarshalAs(UnmanagedType.Bool)]
          public static extern bool GetCurrentConsoleFont(IntPtr hWnd, bool bMaximumWindow, out CONSOLE_FONT_INFO lpConsoleCurrentFont);

          /// <summary>Gets a standard device handle (input/output/error)</summary>
          [DllImport("kernel32.dll", SetLastError = true)]
          public static extern IntPtr GetStdHandle(int nStdHandle);

          /// <summary>Gets the console window handle</summary>
          [DllImport("Kernel32.dll", SetLastError = true)]
          public extern static int GetConsoleWindow();

          //=============================================================================
          // ERROR HANDLING
          //=============================================================================

          /// <summary>Gets the last Win32 error code</summary>
          [DllImport("kernel32.dll")]
          public extern static int GetLastError();

          /// <summary>Gets a human-readable message for the last Win32 error</summary>
          public static string GetLastErrorMessage() {
            return (new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error())).Message;
          }
        }

        //=============================================================================
        // STRUCTURES
        //=============================================================================

        /// <summary>Window placement information (position, state)</summary>
        [StructLayout(LayoutKind.Sequential)]
        public struct Windowplacement
        {
          public uint length;
          public uint flags;
          public uint showCmd;      // Current show state (minimized, maximized, normal)
          public POINT ptMinPosition;
          public POINT ptMaxPosition;
          public RECT rcNormalPosition;
        }

        /// <summary>2D point coordinates</summary>
        [StructLayout(LayoutKind.Sequential)]
        public struct POINT
        {
          public int x;
          public int y;
        }

        /// <summary>ShowWindow command values</summary>
        public enum ShowWindowEnum
        {
          Hide = 0,
          ShowNormal = 1, ShowMinimized = 2, ShowMaximized = 3,
          Maximize = 3, ShowNormalNoActivate = 4, Show = 5,
          Minimize = 6, ShowMinNoActivate = 7, ShowNoActivate = 8,
          Restore = 9, ShowDefault = 10, ForceMinimized = 11
        }

        /// <summary>Rectangle coordinates (window bounds)</summary>
        public struct RECT
        {
          public int Left;    // x position of upper-left corner
          public int Top;     // y position of upper-left corner
          public int Right;   // x position of lower-right corner
          public int Bottom;  // y position of lower-right corner
        }

        /// <summary>Console font information</summary>
        [StructLayout(LayoutKind.Sequential)]
        public struct CONSOLE_FONT_INFO
        {
          public int Font;
          public COORD FontSize;
        }

        /// <summary>Console coordinate (short x, y)</summary>
        [StructLayout(LayoutKind.Sequential)]
        public struct COORD
        {
          public short x;
          public short y;
        }

        /// <summary>Detailed window information</summary>
        [StructLayout(LayoutKind.Sequential)]
        public struct WINDOWINFO
        {
          public uint cbSize;
          public RECT rcWindow;       // Window outer bounds
          public RECT rcClient;       // Client area bounds
          public uint dwStyle;
          public uint dwExStyle;
          public uint dwWindowStatus;
          public uint cxWindowBorders;  // Border width
          public uint cyWindowBorders;  // Border height
          public ushort atomWindowType;
          public ushort wCreatorVersion;

          // Constructor that auto-initializes cbSize
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
		Write-Output -InputObject 'Publish-SetWindowCode: Failed to compile'
		exit
	}
}

<#
	.SYNOPSIS
	Helper functions that use the [Window] class for window enumeration and lookup
#>

function Get-ChildWindowHandles
{
	<#
		.SYNOPSIS
		Gets all child window handles for a parent window

		.PARAMETER ParentHandle
		The window handle of the parent window

		.OUTPUTS
		ArrayList of "handle,windowname" strings
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $True)]
		[System.IntPtr] $ParentHandle
	)

	$ChildWindows = New-Object -TypeName System.Collections.ArrayList
	$Callback = {
		param (
			[System.IntPtr] $hwnd,
			[System.IntPtr] $lParam
		)
		$ChildWindows.add(('{0},{1}' -f $hwnd, ($hwnd|Get-WindowName)))
		return $True
	}

	$Null = [Window]::EnumChildWindows($ParentHandle, $Callback, [System.IntPtr]::Zero)
	$ChildWindows
}

function Get-WindowName
{
	<#
		.SYNOPSIS
		Gets the title/text of a window by its handle

		.PARAMETER hwnd
		The window handle

		.OUTPUTS
		String containing the window title, or nothing if empty
	#>
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory,ValueFromPipeline)]
		[IntPtr]$hwnd
	)
	$len = [Window]::GetWindowTextLength($hwnd)
	if($len -gt 0)
	{
		$sb = New-Object -TypeName text.stringbuilder -ArgumentList ($len + 1)
		$rtnlen = [Window]::GetWindowText($hwnd,$sb,$sb.Capacity)
		$sb.tostring()
	}
}

function Get-WindowHandleByTitle
{
	<#
		.SYNOPSIS
		Finds a window handle by its exact title

		.PARAMETER WindowTitle
		The exact window title to search for

		.OUTPUTS
		IntPtr window handle, or Zero if not found
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory,ValueFromPipeline)]
		[string]$WindowTitle
	)
	$nullPtr = [IntPtr]::Zero
	$windowHandle = [Window]::FindWindowEx($nullPtr, $nullPtr, $nullPtr, $WindowTitle)
	$windowHandle
}

function Get-ProcessIdFromWindowHandle
{
	<#
		.SYNOPSIS
		Gets the process ID that owns a window

		.PARAMETER windowHandle
		The window handle

		.OUTPUTS
		UInt32 process ID, or $null if not found
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory,ValueFromPipeline)]
		[IntPtr]$windowHandle
	)

	$Local:ProcessId = [uint32]::Zero
	$Null = [Window]::GetWindowThreadProcessId($windowHandle, [ref]$Local:ProcessId)
	If ($Local:ProcessId)
	{$Local:ProcessId}
	Else
	{$Null}
}

Export-ModuleMember -Function Get-ChildWindowHandles
Export-ModuleMember -Function Get-ProcessIdFromWindowHandle
Export-ModuleMember -Function Get-WindowHandleByTitle
Export-ModuleMember -Function Get-WindowName
