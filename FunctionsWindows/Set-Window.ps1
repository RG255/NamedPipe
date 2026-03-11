Function Set-Window
{
	<#
			To use this script as a function within your script uncomment:
			> the first two lines:
			#Function Set-Window
			#{
			> and the last line
			#}
			and copy the complete file as a function into your script.

			otherwise your script should contain these two lines:
			Set-Variable -Name ScriptPath -Value ([string]$MyInvocation.MyCommand.Definition) -Scope Script
			Set-Variable -Name SWFilePath -Value (Join-Path -Path (Split-Path -Parent -Path ('{0}' -f $Script:ScriptPath)) -ChildPath 'Set-Window.ps1')

			and to make use of the script call it like:
			$Result = &$SWFilePath -Passthru -ProcessId $ProcessId -Characters

			.SYNOPSIS
			Sets the window size (height,width) and coordinates (x,y) of
			a process window. It returns full details of the target window.

			.DESCRIPTION
			Sets the window size (height,width) and coordinates (x,y) of
			a process window. It returns full details of the target window.

			.PARAMETER ProcessName
			Name of the process to determine (and set) the window characteristics

			.PARAMETER WindowTitle
			Title of the window to determine (and set) the window characteristics

			.PARAMETER ProcessID
			Uses the PID passed to determine (and set) their window characteristics

			.PARAMETER Title
			Uses the target window's title to determine its window characteristics

			.PARAMETER XPosition
			Set the position of the window in pixels from the top.

			.PARAMETER YPosition
			Set the position of the window in pixels from the left.

			.PARAMETER Width
			Set the width of the window.

			.PARAMETER Height
			Set the height of the window.

			.PARAMETER Passthru
			Will return the details of the window in question.

			.PARAMETER Set
			Actually applies the settings passed otherwise function only returns information if -Passthru is set

			.PARAMETER Character
			Allows the Width and Height to be passed as characters and when returning information includes the current Width and Height in characters
			as separate details in returned information. This is true provided that the target window is a console window.

			.NOTES
			Based on:
			Name: Set-Window
			Original Author: Boe Prox
			Version History
			1.0//Boe Prox - 11/24/2015
			- Initial build

			Author: RayG
			Re-written to provide more returned information and a "read only" mode so calculations can be done by the caller
			before deciding how to resize/move the target window.

			Version 1.28 - 2026-02-01
			- Fixed character-based height calculation to include horizontal scrollbar
			- Fixed character count calculations to properly account for scrollbar space
			- Fixed position boundary checks to use new position values instead of old ones
			- Removed duplicate variable declarations and assignments
			- These fixes resolve the previous "off by one character" limitation

			.LIMITATIONS
			None currently known.

			.OUTPUT
			System.Automation.WindowInfo

			.EXAMPLE
			$Result Set-Window -XPosition 2040 -YPosition 142 -Passthru
			or
			$Result = &$SWFilePath -Passthru -ProcessId $ProcessId -Characters
			depending on your use.

			$result will look something like this:

			Display_1           : Screen[Bounds={X=0,Y=0,Width=1920,Height=1080}
			WorkingArea={X=0,Y=0,Width=1920,Height=999} Primary=True
			DeviceName=\\.\DISPLAY1
			PrimaryDisplay      : Display_1
			NumberOfDisplays    : 1
			LastErrorMessage    : The operation completed successfully
			LastErrorValue      : False
			CBordersX           : 8
			CBordersY           : 8
			CBottomRightX       : 811
			CBottomRightY       : 636
			CCaptionHeight      : 31
			CharactersHigh      : 28
			CharactersWide      : 101
			ClientWindowHeight  : 405
			ClientWindowWidth   : 713
			CHScrollBarHeight   : 0
			CVScrollBarWidth    : 25
			ConsoleFontCurrent  : CONSOLE_FONT_INFO
			ConsoleFontMax      : CONSOLE_FONT_INFO
			ConsoleHandle       : 84
			ConsoleWindowHandle : 656782
			CTopLeftX           : 98
			CTopLeftY           : 231
			CurrentTitle        : Size 746/444 Position 90/200
			FontSizeHeight      : 14
			FontSizeWidth       : 7
			IsConsole           : True
			MainWindowHandle    : 656782
			NumberOfProcesses   : 1
			ProcessID           : 9260
			ProcessInfo         : @{ProcessName=powershell; MainWindowHandle=656782;
			MainModule=System.Diagnostics.ProcessModule (powershell.exe);
			MainWindowTitle=Size 746/444 Position 90/200}
			ProcessName         : powershell
			ScreenWorkingHeight : 999
			ScreenWorkingWidth  : 1920
			ScreenOriginX       : 0
			ScreenOriginY       : 0
			WTopLeftX           : 90
			WTopLeftY           : 200
			WBottomRightX       : 836
			WBottomRightY       : 644
			WindowHeight        : 444
			WindowWidth         : 746
			WindowInfo          : WINDOWINFO
			WindowMinimised     : 0
			WindowState         : Normal

			The WindowState can be one of the values in the $WindowsState variable
			Items prefixed with a 'C' are client window values
			Items prefixed with a 'W' are windows window values

			https://gallery.technet.microsoft.com/scriptcenter/Set-the-position-and-size-54853527

			WindowState variable information:

			0 SW_HIDE            Hides the window and activates another window.
			1 SW_SHOWNORMAL      Activates and displays a window. If the window is minimized, maximized, or arranged,
			the system restores it to its original size and position.
			An application should specify this flag when displaying the window for the first time.
			1 SW_NORMAL
			2 SW_SHOWMINIMIZED   Activates the window and displays it as a minimized window.
			3 SW_SHOWMAXIMIZED   Activates the window and displays it as a maximized window.
			3 SW_MAXIMIZE
			4 SW_SHOWNOACTIVATE  Displays a window in its most recent size and position. This value is similar to SW_SHOWNORMAL, 
			except that the window is not activated.
			5 SW_SHOW            Activates the window and displays it in its current size and position.
			6 SW_MINIMIZE        Minimizes the specified window and activates the next top-level window in the Z order.
			7 SW_SHOWMINNOACTIVE Displays the window as a minimized window. This value is similar to SW_SHOWMINIMIZED, 
			except the window is not activated.
			8 SW_SHOWNA          Displays the window in its current size and position. This value is similar to SW_SHOW,
			except that the window is not activated.
			9 SW_RESTORE         Activates and displays the window. If the window is minimized, maximized, or arranged,
			the system restores it to its original size and position. 
			An application should specify this flag when restoring a minimized window.
			10 SW_SHOWDEFAULT     Sets the show state based on the SW_ value specified in the STARTUPINFO structure passed 
			to the CreateProcess function by the program that started the application.
			11 SW_FORCEMINIMIZE   Minimizes a window, even if the thread that owns the window is not responding. 
			This flag should only be used when minimizing windows from a different thread.

	#>
	[OutputType('System.Automation.WindowInfo')]
	[cmdletbinding()]
	Param (
		[Parameter(ValueFromPipelineByPropertyName = $True,ParameterSetName = 'ProcessId')]
		[ValidateRange(1,[int]::MaxValue)]
		[string[]]$ProcessId = $Null,
		[Parameter(ParameterSetName = 'ProcessName')]
		[string]$ProcessName = $Null,
		[Parameter(ParameterSetName = 'WindowTitle')]
		[string]$WindowTitle = $Null,
		[Parameter(ParameterSetName = 'ProcessId')]
		[Parameter(ParameterSetName = 'ProcessName')]
		[Parameter(ParameterSetName = 'WindowTitle')]
		[string]$Title = $Null,
		[Parameter(ParameterSetName = 'ProcessId')]
		[Parameter(ParameterSetName = 'ProcessName')]
		[Parameter(ParameterSetName = 'WindowTitle')]
		[int]$XPosition = [int]0,
		[Parameter(ParameterSetName = 'ProcessId')]
		[Parameter(ParameterSetName = 'ProcessName')]
		[Parameter(ParameterSetName = 'WindowTitle')]
		[int]$YPosition = [int]0,
		[ValidateRange(0,[int]::MaxValue)]
		[Parameter(ParameterSetName = 'ProcessId')]
		[Parameter(ParameterSetName = 'ProcessName')]
		[Parameter(ParameterSetName = 'WindowTitle')]
		[int]$Width = [int]0 ,
		[ValidateRange(0,[int]::MaxValue)]
		[Parameter(ParameterSetName = 'ProcessId')]
		[Parameter(ParameterSetName = 'ProcessName')]
		[Parameter(ParameterSetName = 'WindowTitle')]
		[int]$Height = [int]0,
		[Validateset('ForceMinimize', 'Hide', 'Maximize', 'Minimize', 'Restore', 
				'Show', 'ShowDefault', 'ShowMaximized', 'ShowMinimized', 
		'ShowMinNoactive', 'ShowNa', 'ShowNoActivate', 'ShowNormal')]
		[Parameter(ParameterSetName = 'ProcessId')]
		[Parameter(ParameterSetName = 'ProcessName')]
		[Parameter(ParameterSetName = 'WindowTitle')]
		[String]$State = $Null,
		[Parameter(ParameterSetName = 'ProcessId')]
		[Parameter(ParameterSetName = 'ProcessName')]
		[Parameter(ParameterSetName = 'WindowTitle')]
		[switch]$Passthru,
		[Parameter(ParameterSetName = 'ProcessId')]
		[Parameter(ParameterSetName = 'ProcessName')]
		[Parameter(ParameterSetName = 'WindowTitle')]
		[switch]$Set,
		[Parameter(ParameterSetName = 'ProcessId')]
		[Parameter(ParameterSetName = 'ProcessName')]
		[Parameter(ParameterSetName = 'WindowTitle')]
		[switch]$Characters,
		[switch]$ForeGround
	)
	Begin {
		#
		# Version number of this script 1.28 2026-02-01
		#
		function Get-ProcessID
		{
			param
			(
				[Object]
				[Parameter(Mandatory = $True, ValueFromPipeline = $True, HelpMessage = 'Data to filter')]
				$InputObject
			)
			process
			{
				if (($RegexWindowTitle.Match($InputObject.MainWindowTitle).Success))
				{$InputObject.ID}
			}
		}

		If ($Script:FTrace -and $Script:FTLogFilePath)
		{Write-MyLog -PathToLogFile $Script:FTLogFilePath -CallStack (Get-PSCallStack)}
		Try
		{$Null = [Window]}
		Catch
		{
			if ($Global:Error.Count -eq [int]1)
			{$Global:Error.Clear()}
			Publish-SetWindowCode
		}
		try
		{$Null = Get-Command -Name Set-Window -ErrorAction stop}
		catch
		{
			Set-Variable -Name SWScriptPath -Value ([string]$MyInvocation.MyCommand.Definition)
			Set-Variable -Name SWFilePath -Value (Join-Path -Path (Split-Path -Parent -Path ('{0}' -f $SWScriptPath)) -ChildPath 'Set-Window.ps1')
		}
		$RegexWindowTitle = [Regex]('{0}{1}$)' -f '(?i)(?<string>^', $WindowTitle)
		Set-Variable -Name StrCharacters -Value ('Characters')
		Set-Variable -Name StrHeight -Value ('Height')
		Set-Variable -Name StrWidth -Value ('Width')
		Set-Variable -Name StrPassThru -Value ('PassThru')
		Set-Variable -Name StrXPosition -Value ('XPosition')
		Set-Variable -Name StrYPosition -Value ('YPosition')
		Set-Variable -Name StrTitle -Value ('Title')
		Set-Variable -Name StrLastErrorValue -Value ('LastErrorValue')
		Set-Variable -Name StrLastErrorMessage -Value ('LastErrorMessage')
		Set-Variable -Name StrPS -Value ('PowerShell.exe')
		Set-Variable -Name StrPS6 -Value ('pwsh.exe')
		Set-Variable -Name StrPSISE -Value ('PowerShell_ISE.exe')
		Set-Variable -Name StrSet -Value ('Set')
		Set-Variable -Name StrState -Value ('State')
		Set-Variable -Name StrSysAutoWinInfo -Value ('System.Automation.WindowInfo')
		Set-Variable -Name WindowStates -Value ([Ordered]@{
				'HIDE'          = [int]0
				'SHOWNORMAL'    = [int]1
				'SHOWMINIMIZED' = [int]2
				'SHOWMAXIMIZED' = [int]3
				'MAXIMIZE'      = [int]3
				'SHOWNOACTIVATE' = [int]4
				'SHOW'          = [int]5
				'MINIMIZE'      = [int]6
				'SHOWMINNOACTIVE' = [int]7
				'SHOWNA'        = [int]8
				'RESTORE'       = [int]9
				'SHOWDEFAULT'   = [int]10
				'FORCEMINIMIZE' = [int]11
				'0'             = 'Hidden'
				'1'             = 'Normal'
				'2'             = 'Minimized'
				'3'             = 'Maximized'
				'4'             = 'ShowMinNoActivate'
				'5'             = 'show'
				'6'             = 'Minimize'
				'7'             = 'ShowMinNoActivate'
				'8'             = 'ShowNA'
				'9'             = 'Restore'
				'10'            = 'ShowDefault'
				'11'            = 'ForceMinimize'
		})
		Add-Type -AssemblyName System.Windows.Forms
		$StdInput = [int]-10
		$StdOutput = [int]-11
		$StdError = [int]-12
		$BoundParameters = $PSBoundParameters
		[String[]]$ProcessIdList = $Null
		Function Add-WindowObjectMembers
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
					ConsoleFontCurrent  = $Null
					ConsoleFontMax      = $Null
					ConsoleHandle       = $Null
					ConsoleWindowHandle = $Null
					CTopLeftX           = [Int]0
					CTopLeftY           = [Int]0
					CurrentTitle        = $Null
					FontSizeHeight      = [Int]0
					FontSizeWidth       = [Int]0
					IsConsole           = [Int]$False
					MainWindowHandle    = $Null
					NumberOfDisplays    = [Int]0
					NumberOfProcesses   = $ProcessCount
					ProcessID           = $Null
					ProcessInfo         = [PSObject]$Null
					ProcessName         = $Null
					PrimaryDisplay      = $Null
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
					WindowInfo          = [PSObject]$Null
					WindowMinimised     = [Int]$False
					WindowState         = 'Unknown'
					WindowPlacement     = [PSObject]$Null
			})
		}
		function Get-WindowDetail
		{
			<#
					.SYNOPSIS
					Short Description
					.DESCRIPTION
					Detailed Description
					.EXAMPLE
					Get-WindowDetail
					explains how to use the command
					can be multiple lines
					.EXAMPLE
					Get-WindowDetail
					another example
					can have as many examples as you like
			#>
			[CmdletBinding()]
			Param(
				[Parameter(Mandatory = $True,HelpMessage = "Please provide a valid list of process ID's")]
				[AllowEmptyString()]
				[String]$ProcessId
			)
			$ProcessInfo = Get-Process -Id $ProcessId -ErrorAction Ignore | Select-Object -Property ProcessName, MainWindowHandle, MainModule, MainWindowTitle
			$ThisProcessInfo = Get-Process -Id $Pid -ErrorAction Ignore | Select-Object -Property ProcessName, MainWindowHandle, MainModule, MainWindowTitle
			If (-not $Null -eq $ProcessInfo.MainWindowHandle)
			{
				Get-ScreenResolution
				$WindowInfo = New-Object -TypeName WindowInfo
				$ConsoleFont = New-Object -TypeName CONSOLE_FONT_INFO # Set up to get current font
				$Placement = New-Object -TypeName WindowPlacement
				$WindowObject.$StrLastErrorValue = [Int]$False
				$WindowObject.$StrLastErrorMessage = 'The operation completed successfully'
				$WindowObject.ProcessInfo = $ProcessInfo
				$WindowObject.ProcessID = $ProcessId
				$WindowObject.ProcessName = $WindowObject.ProcessInfo.ProcessName
				$WindowObject.MainWindowHandle = $WindowObject.ProcessInfo.MainWindowHandle # Get current window's handle
				$WindowObject.IsConsole = (($WindowObject.ProcessInfo.MainModule.ModuleName -imatch $StrPS -or $WindowObject.ProcessInfo.MainModule.ModuleName -imatch $StrPS6) -and $WindowObject.ProcessID -eq $Pid)
				If ($WindowObject.ProcessId -ne $Pid -and $BoundParameters.ContainsKey($StrCharacters) -and ($ProcessInfo.MainModule.ModuleName -imatch $StrPS -or $ProcessInfo.MainModule.ModuleName -imatch $StrPS6))
				{
					$WindowObject.LastErrorValue = [Int]$True # If error then get error number and message
					$WindowObject.LastErrorMessage = 'It is not possible to manipulate another console window using the: [-Character] option!'
				}
				if (-Not [Window]::GetWindowInfo($WindowObject.MainWindowHandle,[ref]$WindowInfo))
				{
					$WindowObject.LastErrorValue = [Window]::GetLastError() # If error then get error number and message
					$WindowObject.LastErrorMessage = [Window]::GetLastErrorMessage()
				}
				if (-Not [Window]::GetWindowPlaceMent($WindowObject.MainWindowHandle,[ref]$Placement))
				{
					$WindowObject.LastErrorValue = [Window]::GetLastError() # If error then get error number and message
					$WindowObject.LastErrorMessage = [Window]::GetLastErrorMessage()
				}
				Else
				{$WindowObject.WindowPlacement = $Placement}
				$WindowObject.WindowInfo = $WindowInfo
				$WindowObject.CBordersX = $WindowObject.WindowInfo.cxWindowBorders
				$WindowObject.CBordersY = $WindowObject.WindowInfo.cyWindowBorders
				$WindowObject.CBottomRightX = $WindowObject.WindowInfo.rcClient.Right
				$WindowObject.CBottomRightY = $WindowObject.WindowInfo.rcClient.Bottom
				$WindowObject.CCaptionHeight = ($WindowObject.WindowInfo.rcClient.top - $WindowObject.WindowInfo.rcWindow.top  )
				$WindowObject.CHScrollBarHeight = ($WindowObject.WindowInfo.rcWindow.Bottom - $WindowObject.WindowInfo.rcClient.Bottom)
				$WindowObject.ClientWindowHeight = ($WindowObject.WindowInfo.rcClient.Bottom - $WindowObject.WindowInfo.rcClient.Top)
				$WindowObject.ClientWindowWidth = ($WindowObject.WindowInfo.rcClient.Right - $WindowObject.WindowInfo.rcClient.Left)
				$WindowObject.CTopLeftX = $WindowObject.WindowInfo.rcClient.Left
				$WindowObject.CTopLeftY = $WindowObject.WindowInfo.rcClient.Top
				$WindowObject.CurrentTitle = $WindowObject.ProcessInfo.MainWindowTitle
				$WindowObject.CVScrollBarWidth = ($WindowObject.WindowInfo.rcWindow.Right - $WindowObject.WindowInfo.rcClient.Right)
				$WindowObject.ScreenWorkingHeight = $WindowObject.($WindowObject.PrimaryDisplay).WorkingArea.Size.Height
				$WindowObject.ScreenWorkingWidth = $WindowObject.($WindowObject.PrimaryDisplay).WorkingArea.Size.Width
				$WindowObject.ScreenOriginX = $WindowObject.($WindowObject.PrimaryDisplay).WorkingArea.Location.X
				$WindowObject.ScreenOriginY = $WindowObject.($WindowObject.PrimaryDisplay).WorkingArea.Location.Y
				$WindowObject.WBottomRightX = $WindowObject.WindowInfo.rcWindow.Right
				$WindowObject.WBottomRightY = $WindowObject.WindowInfo.rcWindow.Bottom
				$WindowObject.WindowHeight = ($WindowObject.WindowInfo.rcWindow.Bottom - $WindowObject.WindowInfo.rcWindow.Top)
				$WindowObject.WindowWidth = ($WindowObject.WindowInfo.rcWindow.Right - $WindowObject.WindowInfo.rcWindow.Left)
				$WindowObject.WTopLeftX = $WindowObject.WindowInfo.rcWindow.Left
				$WindowObject.WTopLeftY = $WindowObject.WindowInfo.rcWindow.Top
			
				if ($WindowObject.CVScrollBarWidth -eq $WindowObject.WindowInfo.cxWindowBorders)
				{$WindowObject.CVScrollBarWidth = 0}
				if ($WindowObject.CHScrollBarHeight -eq $WindowObject.WindowInfo.cyWindowBorders)
				{$WindowObject.CHScrollBarHeight = 0}
				If ($WindowObject.WindowInfo.rcWindow.Top -lt 0 -and $WindowObject.WindowInfo.rcWindow.Left -lt 0)
				{$WindowObject.WindowMinimised = [bool]$True}
				$WindowObject.WindowState = $WindowStates.[string]$Placement.showCmd
				If (-not $WindowObject.LastErrorValue -and $WindowObject.IsConsole)
				{
					$WindowObject.ConsoleWindowHandle = ([Window]::GetConsoleWindow())
					$WindowObject.ConsoleHandle = ([Window]::GetStdHandle($StdOutput)) # Get the current console's handle
					If (-not [Window]::GetCurrentConsoleFont($WindowObject.ConsoleHandle,$False,[ref]$ConsoleFont)) #Retrieve current font
					{
						$WindowObject.LastErrorValue = [Window]::GetLastError() # If error then get error number and message
						$WindowObject.LastErrorMessage = [Window]::GetLastErrorMessage()
					}
					else
					{$WindowObject.ConsoleFontCurrent = $ConsoleFont}
					If (-not [Window]::GetCurrentConsoleFont($WindowObject.ConsoleHandle,$True,[ref]$ConsoleFont)) #Retrieve current font
					{
						$WindowObject.LastErrorValue = [Window]::GetLastError() # If error then get error number and message
						$WindowObject.LastErrorMessage = [Window]::GetLastErrorMessage()
					}
					else
					{$WindowObject.ConsoleFontMax = $ConsoleFont}
					$WindowObject.FontSizeWidth = $WindowObject.ConsoleFontCurrent.FontSize.X
					$WindowObject.FontSizeHeight = $WindowObject.ConsoleFontCurrent.FontSize.Y
					If ($Characters -and $WindowObject.FontSizeHeight -gt [int]0 -and $WindowObject.FontSizeWidth -gt [int]0)
					{
						$WindowObject.CharactersHigh = [math]::truncate((($WindowObject.ClientWindowHeight - $WindowObject.CHScrollBarHeight) / $WindowObject.FontSizeHeight))
						$WindowObject.CharactersWide = [math]::truncate((($WindowObject.ClientWindowWidth - $WindowObject.CVScrollBarWidth) / $WindowObject.FontSizeWidth))
					}
				}
				if (-not $WindowObject.LastErrorValue -and $BoundParameters.ContainsKey($StrSet))
				{
					if ($WindowObject.NumberOfProcesses -eq [int]1)
					{Set-WindowParameters}
					else
					{
						$WindowObject.LastErrorValue = [int]1
						$WindowObject.LastErrorMessage = 'The number of windows found is: [{0}]' -F $WindowObject.NumberOfProcesses
					}
				}
			}
		}	

		function Set-WindowParameters
		{
			<#
					.SYNOPSIS
					Short Description
					.DESCRIPTION
					Detailed Description
					.EXAMPLE
					Set-WIndowParameters
					explains how to use the command
					can be multiple lines
					.EXAMPLE
					Set-WIndowParameters
					another example
					can have as many examples as you like
			#>
			# Setup to make changes to window
			If ($BoundParameters.ContainsKey($StrHeight))
			{
				If ($BoundParameters.ContainsKey($StrCharacters) -and $WindowObject.IsConsole)
				{$WHeight = (($WindowObject.FontSizeHeight)*$Height) + $WindowObject.CCaptionHeight + $WindowObject.CHScrollBarHeight + ($WindowObject.CBordersY * 2)} # Set height by characters
				Else
				{$WHeight = $Height}
				If ($WHeight -gt $WindowObject.ScreenWorkingHeight)
				{$WHeight = $WindowObject.ScreenWorkingHeight}
			}
			else
			{$WHeight = $WindowObject.WindowHeight} # Keep current height
			If ($BoundParameters.ContainsKey($StrWidth))
			{
				If ($BoundParameters.ContainsKey($StrCharacters) -and $WindowObject.IsConsole)
				{$WWidth = (($WindowObject.FontSizeWidth)*$Width) + $WindowObject.CVScrollBarWidth + ($WindowObject.CBordersX *2)} # Set width by characters
				else
				{$WWidth = $Width}
				If ($WWidth -gt $WindowObject.ScreenWorkingWidth)
				{$WWidth = $WindowObject.ScreenWorkingWidth}
			}
			else
			{$WWidth = $WindowObject.WindowWidth} # keep current width
	
			If (-not $BoundParameters.ContainsKey($StrXPosition))
			{$XPosition = $WindowObject.WTopLeftX} # Keep current X position
			If (-not $BoundParameters.ContainsKey($StrYPosition))
			{$YPosition = $WindowObject.WTopLeftY} # Keep current Y position
	
			if ($WindowObject.ProcessInfo.MainModule.ModuleName -inotmatch $StrPSISE)
			{
				If ($BoundParameters.ContainsKey($StrSet) -and
					($BoundParameters.ContainsKey($StrHeight) -or
						$BoundParameters.ContainsKey($StrWidth) -or
						$BoundParameters.ContainsKey($StrXPosition)-or
					$BoundParameters.ContainsKey($StrYPosition))
				)
				{
					If (($YPosition+$WHeight) -gt $WindowObject.ScreenWorkingHeight) # Adjust Y Position to accomodate window height
					{
						if ($BoundParameters.ContainsKey($StrYPosition))
						{$YPosition = $YPosition - (($YPosition+$WHeight) - $WindowObject.ScreenWorkingHeight)}
						Else
						{$YPosition = $WindowObject.WtopLeftY - (($YPosition+$WHeight) - $WindowObject.ScreenWorkingHeight)}
					}
					If ($YPosition -lt $WindowObject.ScreenOriginY) # Ensure window Y origin is on screen
					{$YPosition = $WindowObject.ScreenOriginY}
					If ($YPosition+$WHeight -gt $WindowObject.ScreenWorkingHeight)
					{$YPosition = $WindowObject.ScreenWorkingHeight - $WHeight}
					If (($XPosition+$WWidth) -gt $WindowObject.ScreenWorkingWidth) # Adjust X Position to accomodate window Width
					{
						if ($BoundParameters.ContainsKey($StrXPosition))
						{$XPosition = $XPosition - (($XPosition+$WWidth) - $WindowObject.ScreenWorkingWidth)}
						else
						{$XPosition = $WindowObject.WtopLeftX - (($XPosition+$WWidth) - $WindowObject.ScreenWorkingWidth)}
					}
					If ($XPosition -lt $WindowObject.ScreenOriginX) # Ensure window X origin is on screen
					{$XPosition = $WindowObject.ScreenOriginX}
					If ($XPosition+$WWidth -gt $WindowObject.ScreenWorkingWidth)
					{$XPosition = $WindowObject.ScreenWorkingWidth - $WWidth}
					If (-not [Window]::MoveWindow($WindowObject.MainWindowHandle, $XPosition, $YPosition, $WWidth, $WHeight, $True)) # Set window dimensions
					{
						$WindowObject.LastErrorValue = [Window]::GetLastError() # If error then get error number and message
						$WindowObject.LastErrorMessage = [Window]::GetLastErrorMessage()
					}
				}
				if ($BoundParameters.ContainsKey($StrSet) -and $BoundParameters.ContainsKey($StrTitle))
				{
					If (-not [Window]::SetWindowText($WindowObject.MainWindowHandle,$Title)) # Retrieve window dimensions
					{
						$WindowObject.LastErrorValue = [Window]::GetLastError() # If error then get error number and message
						$WindowObject.LastErrorMessage = [Window]::GetLastErrorMessage()
					}
				}
				If ($BoundParameters.ContainsKey($StrSet) -and $BoundParameters.ContainsKey($StrState))
				{
					If (-not [Window]::ShowWindow($WindowObject.MainWindowHandle,$WindowStates.$State)) # Set the window state Min,Max,Normal etc
					{
						$WindowObject.LastErrorValue = [Window]::GetLastError() # If error then get error number and message
						$WindowObject.LastErrorMessage = [Window]::GetLastErrorMessage()
					}
				}
				If ($BoundParameters.ContainsKey($StrSet) -and $ForeGround)
				{
					If (-not [Window]::SetForegroundWindow($WindowObject.MainWindowHandle)) # Make the window the foreground
					{
						$WindowObject.LastErrorValue = [Window]::GetLastError() # If error then get error number and message
						$WindowObject.LastErrorMessage = [Window]::GetLastErrorMessage()
					}
				}
			}
		}
		Function Get-ScreenResolution
		{
			$Screens = [windows.forms.screen]::AllScreens
			$DisplayNumber = [int]1
			foreach ($Screen in $Screens)
			{
				if (-not ($DevName = $Screen.DeviceName.Split('\',4)[3]))
				{[string]$DevName = 'Unknown'}
				$WindowObject | Add-Member -MemberType NoteProperty -Name $DevName -Value $Screen
				if ($Screen.primary)
				{$WindowObject.'PrimaryDisplay' = $Screen.DeviceName.Split('\',4)[3]}
				$DisplayNumber ++
			}
			$WindowObject.NumberOfDisplays = $DisplayNumber-1
		}
	}
	Process
	{
		switch ($PSCmdlet.ParameterSetName)
		{
			#$ProcessID = [window]::GetWindowThreadProcessId(([Window]::FindWindow([IntPtr]::Zero,$Title)),[ref]$ProcessId))
			'ProcessId'
			{$ProcessIds = $ProcessId}
			'WindowTitle'
			{
				$LastErrorMessage = 'Cannot find any Window with Title: [{0}]' -f $WindowTitle
				[string[]]$ProcessIds = Get-Process|Get-ProcessID
			}
			'ProcessName'
			{
				$LastErrorMessage = 'Cannot find a window for a process with a name of: [{0}]' -f $ProcessName
				$ProcessIds = (Get-Process -Name $ProcessName -ErrorAction Ignore).Id
			}
		}
		[int]$ProcessCount = $ProcessIds.count
		if ($ProcessIds)
		{
			foreach ($Id in $ProcessIds)
			{
				$LastErrorMessage = 'Cannot find any process with ID: [{0}]' -f $Id
				$WindowObject = Add-WindowObjectMembers
				Get-WindowDetail -ProcessId $Id
				#if ($BoundParameters.ContainsKey($StrPassthru))
				#{$WindowObject}
			}
		}
		else
		{
			$WindowObject = Add-WindowObjectMembers
			#if ($BoundParameters.ContainsKey($StrPassthru))
			#{$WindowObject}
		}
		if ($BoundParameters.ContainsKey($StrSet) -and $WindowObject.Numberofprocesses -eq [int]1)
		{
			try
			{
				$Null = Get-Command -Name Set-Window -ErrorAction Stop
				if ($BoundParameters.ContainsKey($StrCharacters))
				{$WindowObject = Set-Window -Passthru -ProcessId $ProcessIds -Characters}
				else
				{$WindowObject = Set-Window -Passthru -ProcessId $ProcessIds}
			}
			catch
			{
				if (Test-Path -Path $SWFilePath)
				{
					if ($BoundParameters.ContainsKey($StrCharacters))
					{$WindowObject = &$SWScriptPath -Passthru -ProcessId $ProcessIds -Characters}
					else
					{$WindowObject = &$SWScriptPath -Passthru -ProcessId $ProcessIds}
				}
			}
		}
		if ($BoundParameters.ContainsKey($StrPassthru))
		{$WindowObject}
	}
	End
	{
		If ($WindowObject.ProcessInfo.MainModule.ModuleName -like $StrPSISE)
		{
			$Script:IsConsole = $True
			$Script:WindowHeight = [Int]30
			$Script:WindowWidth = [Int]132
		}
		Else
		{
			$Script:IsConsole = $WindowObject.IsConsole
			$Script:WindowHeight = $WindowObject.CharactersHigh
			$Script:WindowWidth = $WindowObject.CharactersWide
		}
	}
}
