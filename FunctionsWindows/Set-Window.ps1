# VENDORED from CommonScripts\0.2\FunctionsWindows\Set-Window.ps1 by Sync-SharedUtilities [SHA256 4097B406387862656BFED164550E2D0EF43616D410A9997ED7B0D307A5DB987D] - DO NOT EDIT (edit the master; Deploy-Modules re-syncs).
Function Set-Window
{
	<#
		.SYNOPSIS
		Sets the window size (height, width) and coordinates (x, y) of a process window.

		.DESCRIPTION
		Sets the window size and/or position of a process window identified by ProcessId,
		ProcessName, or WindowTitle. Use -Passthru to retrieve full window details.
		Use -Set to apply size/position changes. Use -Characters to specify dimensions
		in console character units rather than pixels.

		.PARAMETER ProcessId
		PID(s) of the target process.

		.PARAMETER ProcessName
		Name of the target process (without .exe extension).

		.PARAMETER WindowTitle
		Title of the target window.

		.PARAMETER Title
		New title to set on the window (requires -Set).

		.PARAMETER XPosition
		X position in pixels from the left edge of the screen.

		.PARAMETER YPosition
		Y position in pixels from the top edge of the screen.

		.PARAMETER Width
		Window width in pixels (or characters if -Characters is used).

		.PARAMETER Height
		Window height in pixels (or characters if -Characters is used).

		.PARAMETER State
		Window state to apply: Hide, Maximize, Minimize, Restore, Show, etc.

		.PARAMETER Passthru
		Return full window details as a System.Automation.WindowInfo object.

		.PARAMETER Set
		Apply the specified size/position/state changes.

		.PARAMETER Characters
		Treat Width and Height as character counts (console windows only).

		.PARAMETER ForeGround
		Bring the window to the foreground (requires -Set).

		.OUTPUTS
		System.Automation.WindowInfo - when -Passthru is specified.

		.EXAMPLE
		Set-Window -ProcessName powershell -Passthru

		.EXAMPLE
		Set-Window -ProcessId $PID -Width 120 -Height 40 -XPosition 0 -YPosition 0 -Set -Characters -Passthru

		.NOTES
		Version: 1.28 2026-02-01
		Based on original by Boe Prox (11/24/2015), re-written by RayG.
	#>

	[OutputType('System.Automation.WindowInfo')]
	[CmdletBinding()]
	Param (
		[Parameter(ValueFromPipelineByPropertyName = $True, ParameterSetName = 'ProcessId')]
		[ValidateRange(1, [int]::MaxValue)]
		[String[]]$ProcessId = $null,

		[Parameter(ParameterSetName = 'ProcessName')]
		[String]$ProcessName = $null,

		[Parameter(ParameterSetName = 'WindowTitle')]
		[String]$WindowTitle = $null,

		[Parameter(ParameterSetName = 'ProcessId')]
		[Parameter(ParameterSetName = 'ProcessName')]
		[Parameter(ParameterSetName = 'WindowTitle')]
		[String]$Title = $null,

		[Parameter(ParameterSetName = 'ProcessId')]
		[Parameter(ParameterSetName = 'ProcessName')]
		[Parameter(ParameterSetName = 'WindowTitle')]
		[Int]$XPosition = [int]0,

		[Parameter(ParameterSetName = 'ProcessId')]
		[Parameter(ParameterSetName = 'ProcessName')]
		[Parameter(ParameterSetName = 'WindowTitle')]
		[Int]$YPosition = [int]0,

		[ValidateRange(0, [int]::MaxValue)]
		[Parameter(ParameterSetName = 'ProcessId')]
		[Parameter(ParameterSetName = 'ProcessName')]
		[Parameter(ParameterSetName = 'WindowTitle')]
		[Int]$Width = [int]0,

		[ValidateRange(0, [int]::MaxValue)]
		[Parameter(ParameterSetName = 'ProcessId')]
		[Parameter(ParameterSetName = 'ProcessName')]
		[Parameter(ParameterSetName = 'WindowTitle')]
		[Int]$Height = [int]0,

		[ValidateSet('ForceMinimize', 'Hide', 'Maximize', 'Minimize', 'Restore',
			'Show', 'ShowDefault', 'ShowMaximized', 'ShowMinimized',
			'ShowMinNoactive', 'ShowNa', 'ShowNoActivate', 'ShowNormal')]
		[Parameter(ParameterSetName = 'ProcessId')]
		[Parameter(ParameterSetName = 'ProcessName')]
		[Parameter(ParameterSetName = 'WindowTitle')]
		[String]$State = $null,

		[Parameter(ParameterSetName = 'ProcessId')]
		[Parameter(ParameterSetName = 'ProcessName')]
		[Parameter(ParameterSetName = 'WindowTitle')]
		[Switch]$Passthru,

		[Parameter(ParameterSetName = 'ProcessId')]
		[Parameter(ParameterSetName = 'ProcessName')]
		[Parameter(ParameterSetName = 'WindowTitle')]
		[Switch]$Set,

		[Parameter(ParameterSetName = 'ProcessId')]
		[Parameter(ParameterSetName = 'ProcessName')]
		[Parameter(ParameterSetName = 'WindowTitle')]
		[Switch]$Characters,

		[Switch]$ForeGround
	)

	Begin
	{
		# Lazy-load the Window/WindowInfo/WindowPlacement/CONSOLE_FONT_INFO types on first use.
		# Publish-SetWindowCode compiles a fixed embedded C# string (no user input), so this
		# is safe; the types cannot be declared in the manifest because Add-Type is per-process.
		try
		{ $null = [Window] }
		catch
		{
			if ($Global:Error.Count -eq [int]1)
			{ $Global:Error.Clear() }
			Publish-SetWindowCode
		}

		$StrCharacters     = 'Characters'
		$StrHeight         = 'Height'
		$StrWidth          = 'Width'
		$StrPassThru       = 'PassThru'
		$StrXPosition      = 'XPosition'
		$StrYPosition      = 'YPosition'
		$StrTitle          = 'Title'
		$StrLastErrorValue  = 'LastErrorValue'
		$StrLastErrorMessage = 'LastErrorMessage'
		$StrPS             = 'PowerShell.exe'
		$StrPS6            = 'pwsh.exe'
		$StrPSISE          = 'PowerShell_ISE.exe'
		$StrSet            = 'Set'
		$StrState          = 'State'
		$WindowStates = [Ordered]@{
			'HIDE'            = [int]0
			'SHOWNORMAL'      = [int]1
			'SHOWMINIMIZED'   = [int]2
			'SHOWMAXIMIZED'   = [int]3
			'MAXIMIZE'        = [int]3
			'SHOWNOACTIVATE'  = [int]4
			'SHOW'            = [int]5
			'MINIMIZE'        = [int]6
			'SHOWMINNOACTIVE' = [int]7
			'SHOWNA'          = [int]8
			'RESTORE'         = [int]9
			'SHOWDEFAULT'     = [int]10
			'FORCEMINIMIZE'   = [int]11
			'0'               = 'Hidden'
			'1'               = 'Normal'
			'2'               = 'Minimized'
			'3'               = 'Maximized'
			'4'               = 'ShowMinNoActivate'
			'5'               = 'show'
			'6'               = 'Minimize'
			'7'               = 'ShowMinNoActivate'
			'8'               = 'ShowNA'
			'9'               = 'Restore'
			'10'              = 'ShowDefault'
			'11'              = 'ForceMinimize'
		}

		Add-Type -AssemblyName System.Windows.Forms
		$StdOutput       = [int]-11
		$BoundParameters = $PSBoundParameters

		Function Add-WindowObjectMember
		{
			New-Object -TypeName PSObject -Property ([Ordered]@{
				PSTypeName          = 'System.Automation.WindowInfo'
				LastErrorMessage    = $LastErrorMessage
				LastErrorValue      = [Int]$True
				CBordersX           = [Int]0
				CBordersY           = [Int]0
				CBottomRightX       = [Int]0
				CBottomRightY       = [Int]0
				CCaptionHeight      = [Int]0
				CharactersHigh      = [Int]0
				CharactersWide      = [Int]0
				ClientWindowHeight  = [Int]0
				ClientWindowWidth   = [Int]0
				CHScrollBarHeight   = [Int]0
				CVScrollBarWidth    = [Int]0
				ConsoleFontCurrent  = $null
				ConsoleFontMax      = $null
				ConsoleHandle       = $null
				ConsoleWindowHandle = $null
				CTopLeftX           = [Int]0
				CTopLeftY           = [Int]0
				CurrentTitle        = $null
				FontSizeHeight      = [Int]0
				FontSizeWidth       = [Int]0
				IsConsole           = [Int]$False
				MainWindowHandle    = $null
				NumberOfDisplays    = [Int]0
				NumberOfProcesses   = $ProcessCount
				ProcessID           = $null
				ProcessInfo         = [PSObject]$null
				ProcessName         = $null
				PrimaryDisplay      = $null
				ScreenWorkingHeight = [Int]0
				ScreenWorkingWidth  = [Int]0
				ScreenOriginX       = [Int]0
				ScreenOriginY       = [Int]0
				WTopLeftX           = [Int]0
				WTopLeftY           = [Int]0
				WBottomRightX       = [Int]0
				WBottomRightY       = [Int]0
				WindowHeight        = [Int]0
				WindowWidth         = [Int]0
				WindowInfo          = [PSObject]$null
				WindowMinimised     = [Int]$False
				WindowState         = 'Unknown'
				WindowPlacement     = [PSObject]$null
			})
		}

		Function Get-WindowDetail
		{
			[CmdletBinding()]
			Param (
				[Parameter(Mandatory = $True, HelpMessage = "Please provide a valid process ID")]
				[AllowEmptyString()]
				[String]$ProcessId,

				[Parameter()]
				[System.IntPtr]$WindowHandle = [System.IntPtr]::Zero
			)
			$ProcessInfo = Get-Process -Id $ProcessId -ErrorAction Ignore | Select-Object -Property ProcessName, MainWindowHandle, MainModule, MainWindowTitle

			# Determine the effective window handle to operate on:
			#  1. an explicit handle (from the -WindowTitle FindWindowEx lookup) always wins;
			#  2. otherwise the process MainWindowHandle;
			#  3. otherwise (still 0 - e.g. minimised to tray, or an Electron/UWP process whose
			#     visible window Windows does not report as its MainWindow) enumerate a top-level
			#     window owned by this PID (best-effort, first real-titled window).
			[System.IntPtr]$EffectiveHandle = $WindowHandle
			if ($EffectiveHandle -eq [System.IntPtr]::Zero -and $ProcessInfo)
			{ $EffectiveHandle = [System.IntPtr]$ProcessInfo.MainWindowHandle }
			if ($EffectiveHandle -eq [System.IntPtr]::Zero -and $ProcessInfo)
			{ $EffectiveHandle = Get-ProcessWindowHandle -ProcessId $ProcessId }

			if ($ProcessInfo -and $EffectiveHandle -ne [System.IntPtr]::Zero)
			{
				Get-ScreenResolution
				$WindowInfo  = New-Object -TypeName WindowInfo
				$ConsoleFont = New-Object -TypeName CONSOLE_FONT_INFO
				$Placement   = New-Object -TypeName WindowPlacement
				$WindowObject.$StrLastErrorValue   = [Int]$False
				$WindowObject.$StrLastErrorMessage = 'The operation completed successfully'
				$WindowObject.ProcessInfo          = $ProcessInfo
				$WindowObject.ProcessID            = $ProcessId
				$WindowObject.ProcessName          = $WindowObject.ProcessInfo.ProcessName
				$WindowObject.MainWindowHandle     = $EffectiveHandle
				$WindowObject.IsConsole = (($WindowObject.ProcessInfo.MainModule.ModuleName -imatch $StrPS -or $WindowObject.ProcessInfo.MainModule.ModuleName -imatch $StrPS6) -and $WindowObject.ProcessID -eq $PID)

				if ($WindowObject.ProcessId -ne $PID -and $BoundParameters.ContainsKey($StrCharacters) -and ($ProcessInfo.MainModule.ModuleName -imatch $StrPS -or $ProcessInfo.MainModule.ModuleName -imatch $StrPS6))
				{
					$WindowObject.LastErrorValue   = [Int]$True
					$WindowObject.LastErrorMessage = 'It is not possible to manipulate another console window using the: [-Character] option!'
				}

				if (-not [Window]::GetWindowInfo($WindowObject.MainWindowHandle, [ref]$WindowInfo))
				{
					$WindowObject.LastErrorValue   = [Window]::GetLastError()
					$WindowObject.LastErrorMessage = [Window]::GetLastErrorMessage()
				}

				if (-not [Window]::GetWindowPlaceMent($WindowObject.MainWindowHandle, [ref]$Placement))
				{
					$WindowObject.LastErrorValue   = [Window]::GetLastError()
					$WindowObject.LastErrorMessage = [Window]::GetLastErrorMessage()
				}
				else
				{ $WindowObject.WindowPlacement = $Placement }

				$WindowObject.WindowInfo          = $WindowInfo
				$WindowObject.CBordersX           = $WindowObject.WindowInfo.cxWindowBorders
				$WindowObject.CBordersY           = $WindowObject.WindowInfo.cyWindowBorders
				$WindowObject.CBottomRightX       = $WindowObject.WindowInfo.rcClient.Right
				$WindowObject.CBottomRightY       = $WindowObject.WindowInfo.rcClient.Bottom
				$WindowObject.CCaptionHeight      = ($WindowObject.WindowInfo.rcClient.Top - $WindowObject.WindowInfo.rcWindow.Top)
				$WindowObject.CHScrollBarHeight   = ($WindowObject.WindowInfo.rcWindow.Bottom - $WindowObject.WindowInfo.rcClient.Bottom)
				$WindowObject.ClientWindowHeight  = ($WindowObject.WindowInfo.rcClient.Bottom - $WindowObject.WindowInfo.rcClient.Top)
				$WindowObject.ClientWindowWidth   = ($WindowObject.WindowInfo.rcClient.Right - $WindowObject.WindowInfo.rcClient.Left)
				$WindowObject.CTopLeftX           = $WindowObject.WindowInfo.rcClient.Left
				$WindowObject.CTopLeftY           = $WindowObject.WindowInfo.rcClient.Top
				$WindowObject.CurrentTitle        = $WindowObject.ProcessInfo.MainWindowTitle
				$WindowObject.CVScrollBarWidth    = ($WindowObject.WindowInfo.rcWindow.Right - $WindowObject.WindowInfo.rcClient.Right)
				$WindowObject.ScreenWorkingHeight = $WindowObject.($WindowObject.PrimaryDisplay).WorkingArea.Size.Height
				$WindowObject.ScreenWorkingWidth  = $WindowObject.($WindowObject.PrimaryDisplay).WorkingArea.Size.Width
				$WindowObject.ScreenOriginX       = $WindowObject.($WindowObject.PrimaryDisplay).WorkingArea.Location.X
				$WindowObject.ScreenOriginY       = $WindowObject.($WindowObject.PrimaryDisplay).WorkingArea.Location.Y
				$WindowObject.WBottomRightX       = $WindowObject.WindowInfo.rcWindow.Right
				$WindowObject.WBottomRightY       = $WindowObject.WindowInfo.rcWindow.Bottom
				$WindowObject.WindowHeight        = ($WindowObject.WindowInfo.rcWindow.Bottom - $WindowObject.WindowInfo.rcWindow.Top)
				$WindowObject.WindowWidth         = ($WindowObject.WindowInfo.rcWindow.Right - $WindowObject.WindowInfo.rcWindow.Left)
				$WindowObject.WTopLeftX           = $WindowObject.WindowInfo.rcWindow.Left
				$WindowObject.WTopLeftY           = $WindowObject.WindowInfo.rcWindow.Top

				if ($WindowObject.CVScrollBarWidth -eq $WindowObject.WindowInfo.cxWindowBorders)
				{ $WindowObject.CVScrollBarWidth = 0 }
				if ($WindowObject.CHScrollBarHeight -eq $WindowObject.WindowInfo.cyWindowBorders)
				{ $WindowObject.CHScrollBarHeight = 0 }
				if ($WindowObject.WindowInfo.rcWindow.Top -lt 0 -and $WindowObject.WindowInfo.rcWindow.Left -lt 0)
				{ $WindowObject.WindowMinimised = [bool]$True }

				$WindowObject.WindowState = $WindowStates.[String]$Placement.showCmd

				if (-not $WindowObject.LastErrorValue -and $WindowObject.IsConsole)
				{
					$WindowObject.ConsoleWindowHandle = [Window]::GetConsoleWindow()
					$WindowObject.ConsoleHandle       = [Window]::GetStdHandle($StdOutput)

					if (-not [Window]::GetCurrentConsoleFont($WindowObject.ConsoleHandle, $False, [ref]$ConsoleFont))
					{
						$WindowObject.LastErrorValue   = [Window]::GetLastError()
						$WindowObject.LastErrorMessage = [Window]::GetLastErrorMessage()
					}
					else
					{ $WindowObject.ConsoleFontCurrent = $ConsoleFont }

					if (-not [Window]::GetCurrentConsoleFont($WindowObject.ConsoleHandle, $True, [ref]$ConsoleFont))
					{
						$WindowObject.LastErrorValue   = [Window]::GetLastError()
						$WindowObject.LastErrorMessage = [Window]::GetLastErrorMessage()
					}
					else
					{ $WindowObject.ConsoleFontMax = $ConsoleFont }

					$WindowObject.FontSizeWidth  = $WindowObject.ConsoleFontCurrent.FontSize.X
					$WindowObject.FontSizeHeight = $WindowObject.ConsoleFontCurrent.FontSize.Y

					if ($Characters -and $WindowObject.FontSizeHeight -gt [int]0 -and $WindowObject.FontSizeWidth -gt [int]0)
					{
						$WindowObject.CharactersHigh = [Math]::Truncate(($WindowObject.ClientWindowHeight - $WindowObject.CHScrollBarHeight) / $WindowObject.FontSizeHeight)
						$WindowObject.CharactersWide = [Math]::Truncate(($WindowObject.ClientWindowWidth - $WindowObject.CVScrollBarWidth) / $WindowObject.FontSizeWidth)
					}
				}

				if (-not $WindowObject.LastErrorValue -and $BoundParameters.ContainsKey($StrSet))
				{
					if ($WindowObject.NumberOfProcesses -eq [int]1)
					{ Set-WindowParameters }
					else
					{
						$WindowObject.LastErrorValue   = [int]1
						$WindowObject.LastErrorMessage = 'The number of windows found is: [{0}]' -f $WindowObject.NumberOfProcesses
					}
				}
			}
		}

		Function Set-WindowParameters
		{
			if ($BoundParameters.ContainsKey($StrHeight))
			{
				if ($BoundParameters.ContainsKey($StrCharacters) -and $WindowObject.IsConsole)
				{ $WHeight = ($WindowObject.FontSizeHeight * $Height) + $WindowObject.CCaptionHeight + $WindowObject.CHScrollBarHeight + ($WindowObject.CBordersY * 2) }
				else
				{ $WHeight = $Height }
				if ($WHeight -gt $WindowObject.ScreenWorkingHeight)
				{ $WHeight = $WindowObject.ScreenWorkingHeight }
			}
			else
			{ $WHeight = $WindowObject.WindowHeight }

			if ($BoundParameters.ContainsKey($StrWidth))
			{
				if ($BoundParameters.ContainsKey($StrCharacters) -and $WindowObject.IsConsole)
				{ $WWidth = ($WindowObject.FontSizeWidth * $Width) + $WindowObject.CVScrollBarWidth + ($WindowObject.CBordersX * 2) }
				else
				{ $WWidth = $Width }
				if ($WWidth -gt $WindowObject.ScreenWorkingWidth)
				{ $WWidth = $WindowObject.ScreenWorkingWidth }
			}
			else
			{ $WWidth = $WindowObject.WindowWidth }

			if (-not $BoundParameters.ContainsKey($StrXPosition))
			{ $XPosition = $WindowObject.WTopLeftX }
			if (-not $BoundParameters.ContainsKey($StrYPosition))
			{ $YPosition = $WindowObject.WTopLeftY }

			if ($WindowObject.ProcessInfo.MainModule.ModuleName -inotmatch $StrPSISE)
			{
				if ($BoundParameters.ContainsKey($StrSet) -and
					($BoundParameters.ContainsKey($StrHeight) -or
					$BoundParameters.ContainsKey($StrWidth) -or
					$BoundParameters.ContainsKey($StrXPosition) -or
					$BoundParameters.ContainsKey($StrYPosition)))
				{
					if (($YPosition + $WHeight) -gt $WindowObject.ScreenWorkingHeight)
					{
						if ($BoundParameters.ContainsKey($StrYPosition))
						{ $YPosition = $YPosition - (($YPosition + $WHeight) - $WindowObject.ScreenWorkingHeight) }
						else
						{ $YPosition = $WindowObject.WTopLeftY - (($YPosition + $WHeight) - $WindowObject.ScreenWorkingHeight) }
					}
					if ($YPosition -lt $WindowObject.ScreenOriginY)
					{ $YPosition = $WindowObject.ScreenOriginY }
					if ($YPosition + $WHeight -gt $WindowObject.ScreenWorkingHeight)
					{ $YPosition = $WindowObject.ScreenWorkingHeight - $WHeight }
					if (($XPosition + $WWidth) -gt $WindowObject.ScreenWorkingWidth)
					{
						if ($BoundParameters.ContainsKey($StrXPosition))
						{ $XPosition = $XPosition - (($XPosition + $WWidth) - $WindowObject.ScreenWorkingWidth) }
						else
						{ $XPosition = $WindowObject.WTopLeftX - (($XPosition + $WWidth) - $WindowObject.ScreenWorkingWidth) }
					}
					if ($XPosition -lt $WindowObject.ScreenOriginX)
					{ $XPosition = $WindowObject.ScreenOriginX }
					if ($XPosition + $WWidth -gt $WindowObject.ScreenWorkingWidth)
					{ $XPosition = $WindowObject.ScreenWorkingWidth - $WWidth }

					if (-not [Window]::MoveWindow($WindowObject.MainWindowHandle, $XPosition, $YPosition, $WWidth, $WHeight, $True))
					{
						$WindowObject.LastErrorValue   = [Window]::GetLastError()
						$WindowObject.LastErrorMessage = [Window]::GetLastErrorMessage()
					}
				}

				if ($BoundParameters.ContainsKey($StrSet) -and $BoundParameters.ContainsKey($StrTitle))
				{
					if (-not [Window]::SetWindowText($WindowObject.MainWindowHandle, $Title))
					{
						$WindowObject.LastErrorValue   = [Window]::GetLastError()
						$WindowObject.LastErrorMessage = [Window]::GetLastErrorMessage()
					}
				}

				if ($BoundParameters.ContainsKey($StrSet) -and $BoundParameters.ContainsKey($StrState))
				{
					if (-not [Window]::ShowWindow($WindowObject.MainWindowHandle, $WindowStates.$State))
					{
						$WindowObject.LastErrorValue   = [Window]::GetLastError()
						$WindowObject.LastErrorMessage = [Window]::GetLastErrorMessage()
					}
				}

				if ($BoundParameters.ContainsKey($StrSet) -and $ForeGround)
				{
					if (-not [Window]::SetForegroundWindow($WindowObject.MainWindowHandle))
					{
						$WindowObject.LastErrorValue   = [Window]::GetLastError()
						$WindowObject.LastErrorMessage = [Window]::GetLastErrorMessage()
					}
				}
			}
		}

		Function Get-ScreenResolution
		{
			$Screens        = [Windows.Forms.Screen]::AllScreens
			$DisplayNumber  = [int]1
			foreach ($Screen in $Screens)
			{
				if (-not ($DevName = $Screen.DeviceName.Split('\', 4)[3]))
				{ [String]$DevName = 'Unknown' }
				$WindowObject | Add-Member -MemberType NoteProperty -Name $DevName -Value $Screen
				if ($Screen.Primary)
				{ $WindowObject.PrimaryDisplay = $Screen.DeviceName.Split('\', 4)[3] }
				$DisplayNumber++
			}
			$WindowObject.NumberOfDisplays = $DisplayNumber - 1
		}

		Function Get-ProcessWindowHandle
		{
			# Best-effort fallback used ONLY when a process reports MainWindowHandle = 0. Enumerates
			# top-level windows (via the self-contained window helpers) and returns the first one owned
			# by $ProcessId that carries a real (non-empty, non-system) title. Returns IntPtr.Zero if none.
			Param (
				[String]$ProcessId
			)
			[System.IntPtr]$Found = [System.IntPtr]::Zero
			[uint32]$TargetPid = 0
			if (-not [uint32]::TryParse($ProcessId, [ref]$TargetPid))
			{ return $Found }

			foreach ($Entry in (Get-ChildWindowHandles -ParentHandle ([System.IntPtr]::Zero)))
			{
				$HandleText, $Title = $Entry -split ',', 2
				if ([String]::IsNullOrWhiteSpace($Title))
				{ continue }
				if ($Title -eq 'Default IME' -or $Title -eq 'MSCTFIME UI' -or $Title -like 'GDI+ Window*')
				{ continue }
				[System.IntPtr]$ThisHandle = [System.IntPtr][Int64]$HandleText
				if (($ThisHandle | Get-ProcessIdFromWindowHandle) -eq $TargetPid)
				{
					$Found = $ThisHandle
					break
				}
			}
			return $Found
		}
	}

	Process
	{
		[System.IntPtr]$ResolvedHandle = [System.IntPtr]::Zero

		switch ($PSCmdlet.ParameterSetName)
		{
			'ProcessId'
			{ $ProcessIds = $ProcessId }

			'WindowTitle'
			{
				$LastErrorMessage = 'Cannot find any Window with Title: [{0}]' -f $WindowTitle
				# Resolve by exact window title via FindWindowEx. Keep the ACTUAL window handle and pass
				# it through to Get-WindowDetail, so we operate on the real window even when the owning
				# process reports MainWindowHandle = 0 (minimised to tray, Electron/UWP helper, etc.).
				$ResolvedHandle = Get-WindowHandleByTitle -WindowTitle $WindowTitle
				if ($ResolvedHandle -and [System.IntPtr]$ResolvedHandle -ne [System.IntPtr]::Zero)
				{ [String[]]$ProcessIds = $ResolvedHandle | Get-ProcessIdFromWindowHandle }
				else
				{ [String[]]$ProcessIds = @() }
			}

			'ProcessName'
			{
				$LastErrorMessage = 'Cannot find a window for a process with a name of: [{0}]' -f $ProcessName
				$ProcessIds = (Get-Process -Name $ProcessName -ErrorAction Ignore).Id
			}
		}

		[int]$ProcessCount = $ProcessIds.Count

		$WindowResults = New-Object -TypeName System.Collections.Generic.List[System.Object]

		if ($ProcessIds)
		{
			foreach ($Id in $ProcessIds)
			{
				$LastErrorMessage = 'Cannot find any process with ID: [{0}]' -f $Id
				$WindowObject     = Add-WindowObjectMember
				if ($PSCmdlet.ParameterSetName -eq 'WindowTitle')
				{ Get-WindowDetail -ProcessId $Id -WindowHandle $ResolvedHandle }
				else
				{ Get-WindowDetail -ProcessId $Id }
				$WindowResults.Add($WindowObject)
			}
		}
		else
		{
			$WindowObject = Add-WindowObjectMember
			$WindowResults.Add($WindowObject)
		}

		if ($BoundParameters.ContainsKey($StrSet) -and $WindowObject.NumberOfProcesses -eq [int]1)
		{
			try
			{
				$null = Get-Command -Name Set-Window -ErrorAction Stop
				if ($BoundParameters.ContainsKey($StrCharacters))
				{ $WindowObject = Set-Window -Passthru -ProcessId $ProcessIds -Characters }
				else
				{ $WindowObject = Set-Window -Passthru -ProcessId $ProcessIds }
			}
			catch
			{
				if (Test-Path -Path $SWFilePath)
				{
					if ($BoundParameters.ContainsKey($StrCharacters))
					{ $WindowObject = & $SWScriptPath -Passthru -ProcessId $ProcessIds -Characters }
					else
					{ $WindowObject = & $SWScriptPath -Passthru -ProcessId $ProcessIds }
				}
			}
			# The set path re-reads a single window; make it the sole result.
			$WindowResults.Clear()
			$WindowResults.Add($WindowObject)
		}

		if ($BoundParameters.ContainsKey($StrPassthru))
		{
			# Return one object per PID that actually resolved a window; if none resolved, return the
			# last object so its LastErrorMessage is still visible to the caller.
			$Resolved = @($WindowResults | Where-Object { $null -ne $_.MainWindowHandle -and $_.MainWindowHandle -ne [System.IntPtr]::Zero })
			if ($Resolved.Count -gt 0)
			{ $Resolved }
			else
			{ $WindowObject }
		}
	}

	End {}
}
