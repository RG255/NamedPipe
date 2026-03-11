[CmdletBinding(PositionalBinding = $False,DefaultParameterSetName = 'Default')]
Param (
	[Parameter(ParameterSetName = 'Spawned',DontShow = $True)]
	[Switch]$Spawned,
	[Parameter(Mandatory,HelpMessage = 'Provide the Serial Data to use',ParameterSetName = 'Spawned',DontShow = $True)]
	[Parameter(DontShow = $True)]
	[String]$SerialData
)
If ($Spawned)
{
	#Set-PSBreakpoint -line 15 -Script L:\OneDrive\Documents\WindowsPowerShell\Modules\NamedPipe\0.6\FunctionsWindows\Start-PipeServerOrClient.ps1
	$Private:MyBoundParameters = $PSCmdlet.MyInvocation.BoundParameters
	# Bootstrap: $PSScriptRoot resolves to this script's installed FunctionsWindows\ directory.
	# Import the owning NamedPipe manifest so ConvertFrom-Serial is available before we
	# deserialise ServerClientParams. Works independently of profile or PSModulePath state.
	Import-Module -Name (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'NamedPipe.psd1') -ErrorAction Stop
	$ServerClientParams = ConvertFrom-Serial -Text $SerialData
	# Import the consumer module (e.g. VHD). NamedPipe is already loaded above; importing
	# VHD (which RequiredModules NamedPipe) or NamedPipe again are both no-ops for NamedPipe.
	Import-Module -Name $ServerClientParams.ModuleToLoad.Name -RequiredVersion $ServerClientParams.ModuleToLoad.Version
	# InfoDisplay bitmask: 1=server/client progress, 2=Show-VerboseData, 4=debug output
	if ($ServerClientParams.$StrInfoDisplay -band 4)
	{
		Write-Host -Object ('DEBUG SPAWN: Server process started, PS version = {0}' -f $PSVersionTable.PSVersion) -ForegroundColor Yellow
		Write-Host -Object ('DEBUG SPAWN: Imported {0} v{1}' -f $ServerClientParams.ModuleToLoad.Name, $ServerClientParams.ModuleToLoad.version) -ForegroundColor Green
	}
	if ($ServerClientParams.$StrInfoDisplay -band 2)
	{
		Show-VerboseData -Object $ServerClientParams -Display -Title 'ServerClientParams'
		Show-VerboseData -Object $ServerClientParams.$StrModuleToLoad -Display -Title 'Module to load in Spawned process'
	}
	
	$ServerClientParams.$StrSpawned = $True
	# Call via NamedPipe module scope because Start-PipeServerOrClient is internal (not exported)
	# Always use 'NamedPipe' here regardless of $ModuleName - the function lives in NamedPipe's scope
	# Match by path: find the NamedPipe module whose ModuleBase contains this script file.
	# This correctly identifies the owning version even when a newer NamedPipe version is
	# simultaneously loaded (e.g. user profile loads v0.7, consumer dependency loads v0.6).
	$Private:module = Get-Module -Name NamedPipe | Where-Object { $PSScriptRoot -like "$($_.ModuleBase)\*" } | Select-Object -First 1
	if (-not $Private:module)
	{
		# Fallback: highest loaded version (shouldn't be reached in normal operation)
		$Private:module = Get-Module -Name NamedPipe | Sort-Object -Property Version -Descending | Select-Object -First 1
	}
	$Private:module.Invoke({
			param($data)
			Start-PipeServerOrClient -SerialData $data
	}, (ConvertTo-Serial -Object $ServerClientParams))
}
Function Start-PipeServerOrClient
{
	<#
			.SYNOPSIS
			Establishes and manages both the server and client ends of a named pipe connection.

			.DESCRIPTION
			This script/function has a dual role:

			1. As a FUNCTION (Start-PipeServerOrClient): Called from the user's script to set up
			either the server or client side of the pipe, based on the ServerClientParams
			data structure passed via serialized data.

			2. As a SCRIPT (.ps1 file): When spawning the server, this file is executed in a
			separate PowerShell process. The -Spawned parameter indicates the script is
			running as a detached server process. It imports the NamedPipe module,
			deserializes the configuration, and calls itself as a function.

			Server behaviour:
			- First call (not spawned): Launches a new PowerShell process running this script
			with the -Spawned flag. Returns the server process ID.
			- Second call (spawned): Creates the NamedPipeServerStream, waits for the client
			to connect, then enters a request/response loop processing ScriptBlock,
			Security, and ExitPipe requests.

			Client behaviour:
			- Creates a NamedPipeClientStream, connects to the server, sets up StreamReader
			and StreamWriter, and returns the PipeInfo object for use with Send-Request.

			Configuration (ChunkSize, Depth, InfoDisplay, timeouts) flows from
			ServerClientParams into PipeInfo so that Send-Data/Receive-Data can access it.

			.PARAMETER SerialData
			A serialized (Base64) string containing the ServerClientParams data structure.
			Created by: ConvertTo-Serial -Object $ServerClientParams

			.EXAMPLE
			# Start the server (returns server PID)
			$ServerPID = Start-PipeServerOrClient -SerialData (ConvertTo-Serial -Object $ServerClientParams)

			.EXAMPLE
			# Start the client (returns PipeInfo with connection)
			$PipeInfo = Start-PipeServerOrClient -SerialData (ConvertTo-Serial -Object $ServerClientParams)

			.INPUTS
			System.String - Serialized ServerClientParams data structure.

			.OUTPUTS
			Server (first call): Process ID of the spawned server process.
			Server (spawned): No output (runs request loop until ExitPipe received).
			Client: PipeInfo object containing Pipe, Reader, Writer, and connection metadata.
	#>


	[CmdletBinding(PositionalBinding = $False)]
	Param (
		[Parameter(Mandatory,HelpMessage = 'Provide the Serial Data to use',DontShow = $True)]
		[String]$SerialData
	)

	$Private:MyBoundParameters = $PSCmdlet.MyInvocation.BoundParameters
	$ServerClientParams = ConvertFrom-Serial -Text $SerialData
	$DataObject = Set-ObjectParams -Dataset 'DataObject' -MyParameters $Private:MyBoundParameters

	If ($ServerClientParams.$StrInfoDisplay -band 2)
	{
		Show-VerboseData -Object $ServerClientParams -Display -Title ('ServerClientParams on Entry Server:[{0}] Client: [{1}] Spawned: [{2}]' -f $ServerClientParams.Server, $ServerClientParams.Client, $ServerClientParams.Spawned)
		Show-VerboseData -Object $ServerClientParams.$StrPipeInfo -Display -Title ('PipeInfo on Entry Server:[{0}] Client: [{1}] Spawned: [{2}]' -f $ServerClientParams.Server, $ServerClientParams.Client, $ServerClientParams.Spawned)
		Show-VerboseData -Object $ServerClientParams.$StrPipeParams -Display -Title ('PipeParams on Entry Server:[{0}] Client: [{1}] Spawned: [{2}]' -f $ServerClientParams.Server, $ServerClientParams.Client, $ServerClientParams.Spawned)
	}
	
	if($ServerClientParams.Server)
	{
		If (-Not $ServerClientParams.Spawned)
		{	
			If ($PSVersionTable.PSVersion.Major -gt [int]5)
			{$Executable = Join-Path -Path ('{0}' -f $PSHome) -ChildPath 'pwsh.exe'}
			else
			{$Executable = Join-Path -Path ('{0}' -f $PSHome) -ChildPath 'Powershell.exe'}
			$ProcessVerb = 'Open'
			If (-not $Administrator -and $ServerClientParams.AdminRequired)
			{$ProcessVerb = 'RunAs'}
			$ServerClientParams.$StrAdminRequired = $False
			$SB = [scriptblock]::Create(('{0} -spawned -SerialData {1}' -f ((Get-Command -Name $MyInvocation.InvocationName).ScriptBlock.File), (ConvertTo-Serial -Object $ServerClientParams)))
			$ProcessInfo = @{
				FilePath     = $Executable
				Passthru     = $True
				WindowStyle  = $ServerClientParams.$StrWindowStyle
				wait         = $False
				Verb         = $ProcessVerb
				Argumentlist = ('-Executionpolicy bypass -Command &{{{0}}}' -f $SB)
			}
			If ($ServerClientParams.$Strverbose)
			{Show-VerboseData -Object $ProcessInfo -Display -Title 'ProcessInfo Starting the Server'}	
			# Start the Server
			Try
			{
				(Start-Process @ProcessInfo).Id
			}
			Catch
			{
				throw ('Failed to start server process: {0}' -f $_.Exception.Message)
			}
		}
		Else
		{
			Try
			{
				#Server:
				if ($PSVersionTable.PSVersion.Major -gt 5)
				{
					$ServerClientParams.$StrPipeInfo.$StrPipe  = [IO.Pipes.NamedPipeServerStreamacl]::Create(
						$ServerClientParams.$StrPipeInfo.Name,
						$ServerClientParams.$StrPipeParams.Direction,
						$ServerClientParams.$StrPipeParams.Instances,
						$ServerClientParams.$StrPipeParams.Mode,
						$ServerClientParams.$StrPipeParams.Options,
						$ServerClientParams.$StrPipeParams.PipeBufferSizeR,
						$ServerClientParams.$StrPipeParams.PipeBufferSizeS,
						(Set-PipeSecurity -AccessIdentifier $ServerClientParams.$StrAccessIdentifier)
					)
				}
				Else
				{
					$ServerClientParams.$StrPipeInfo.$StrPipe  = [IO.Pipes.NamedPipeServerStream]::new(
						$ServerClientParams.$StrPipeInfo.Name,
						$ServerClientParams.$StrPipeParams.Direction,
						$ServerClientParams.$StrPipeParams.Instances,
						$ServerClientParams.$StrPipeParams.Mode,
						$ServerClientParams.$StrPipeParams.Options,
						$ServerClientParams.$StrPipeParams.PipeBufferSizeR,
						$ServerClientParams.$StrPipeParams.PipeBufferSizeS,
						(Set-PipeSecurity -AccessIdentifier $ServerClientParams.AccessIdentifier)
					)
				}
				$timeout = [timespan]::FromSeconds($ServerClientParams.$StrServerWaitTimeout)
				$source = [Threading.CancellationTokenSource]::new($timeout)
				$conn = $ServerClientParams.$StrPipeInfo.$StrPipe.WaitForConnectionAsync($source.token)
				do
				{
					# some other stuff here while waiting for connection
					Start-Sleep -Milliseconds 500
				}
				until ($conn.IsCompleted)
				$ServerClientParams.$StrPipeInfo.$StrReader = [IO.StreamReader]::new($ServerClientParams.$StrPipeInfo.$StrPipe)
				$ServerClientParams.$StrPipeInfo.$StrWriter = [IO.StreamWriter]::new($ServerClientParams.$StrPipeInfo.$StrPipe)
				$ServerClientParams.$StrPipeInfo.$StrWriter.AutoFlush = $True
				# Copy InfoDisplay, ChunkSize, Depth to PipeInfo so Send-Data/Receive-Data can access them
				$ServerClientParams.$StrPipeInfo.$StrInfoDisplay = $ServerClientParams.$StrInfoDisplay
				$ServerClientParams.$StrPipeInfo.$StrChunkSize = $ServerClientParams.$StrChunkSize
				$ServerClientParams.$StrPipeInfo.$StrDepth = $ServerClientParams.$StrDepth
				If ($ServerClientParams.$StrInfoDisplay -band 4)
				{
					Write-Host 'DEBUG SERVER: StreamReader and StreamWriter created' -ForegroundColor Magenta
					Write-Host "DEBUG SERVER: Pipe IsConnected = $($ServerClientParams.$StrPipeInfo.$StrPipe.IsConnected)" -ForegroundColor Magenta
				}
				If ($ServerClientParams.$StrInfoDisplay -band 2)
				{Show-VerboseData -Object $ServerClientParams.$StrPipeInfo -Display -Title 'PipeInfo after connection made'}
				Do
				{
					try
					{
						If ($ServerClientParams.$StrInfoDisplay -band 4)
						{Write-Host 'DEBUG SERVER: Entering main loop, calling Receive-Data...' -ForegroundColor Magenta}
						$DataObject = Receive-Data -PipeInfo $ServerClientParams.$StrPipeInfo -ErrorAction Stop
						If ($ServerClientParams.$StrInfoDisplay -band 4)
						{Write-Host "DEBUG SERVER: Receive-Data returned, Type = $($DataObject.$StrType)" -ForegroundColor Green}
						Switch ($DataObject.$StrType)
						{
							$StrScriptBlock
							{
								If ($ServerClientParams.$StrInfoDisplay -band 4)
								{Write-Host 'DEBUG SERVER: Processing ScriptBlock request' -ForegroundColor Magenta}
								If ($ServerClientParams.$StrInfoDisplay -band 2)
								{
									Show-VerboseData -Object $DataObject -Display -Title ('DataObject.{0}' -f $StrRequest)
									If ($DataObject.$StrParameters)
									{Show-VerboseData -Object $DataObject.$StrParameters -Display -Title ('DataObject.{0}' -f $StrParameters)}
									If ($DataObject.$StrData)
									{Show-VerboseData -Object $DataObject.$StrData -Display -Title ('DataObject.{0}' -f $StrData)}
								}
								$DataObject = Get-SBResult -DataObject $DataObject
								If ($ServerClientParams.$StrInfoDisplay -band 2)
								{
									Show-VerboseData -Object ('Scriptblock Error: {0}' -f $DataObject.$StrError) -Display -Title 'ScriptBlock Error State'
									Show-VerboseData -Object $DataObject.$StrResult -Display -Title ('DataObject.{0} {1}' -f $StrRequest, $StrResult)
								}
								If ($ServerClientParams.$StrInfoDisplay -band 4)
								{Write-Host 'DEBUG SERVER: ScriptBlock processing done' -ForegroundColor Green}
							}
							$StrSecurity
							{
								If ($ServerClientParams.$StrInfoDisplay -band 4)
								{Write-Host 'DEBUG SERVER: Processing Security request' -ForegroundColor Magenta}
								Try
								{
									$DataObject.$StrRequest = $DataObject.$StrType
									if ($PSVersionTable.PSVersion.Major -gt 5)
									{$DataObject.$StrResult =	[IO.Pipes.PipesAclExtensions]::GetAccessControl($ServerClientParams.$StrPipeInfo.$StrPipe)}
									Else
									{$DataObject.$StrResult = $ServerClientParams.$StrPipeInfo.$StrPipe.GetAccessControl().access}
									If ($ServerClientParams.$StrInfoDisplay -band 4)
									{Write-Host 'DEBUG SERVER: Security GetAccessControl done' -ForegroundColor Green}
								}
								catch
								{
									Write-Host "DEBUG SERVER: Security request FAILED: $_" -ForegroundColor Red
									$DataObject.$StrResult = 'An error Occured getting the Pipe Security information'
									$DataObject.$StrError = NamedPipe\Get-MyErrors -Return
								}
							}
							$StrExitPipe
							{
								If ($ServerClientParams.$StrInfoDisplay -band 4)
								{Write-Host 'DEBUG SERVER: Processing ExitPipe request' -ForegroundColor Magenta}
								try
								{
									$DataObject.$StrRequest = $DataObject.$StrType
									$DataObject.$StrResult = ('Server is Exiting')
									If ($ServerClientParams.$StrInfoDisplay -band 4)
									{Write-Host 'DEBUG SERVER: ExitPipe processing done' -ForegroundColor Green}
								}
								catch
								{$DataObject.$StrError = NamedPipe\Get-MyErrors -Return}
							}
						}
					}
					catch
					{
						Write-Host "DEBUG SERVER: Exception in main loop: $_" -ForegroundColor Red
						$DataObject.$StrError = NamedPipe\Get-MyErrors -Return
					}
					If ($ServerClientParams.$StrInfoDisplay -band 4)
					{Write-Host 'DEBUG SERVER: About to Send-Data response back to client' -ForegroundColor Magenta}
					Send-Data -DataObject $DataObject -PipeInfo $ServerClientParams.$StrPipeInfo -ErrorAction Stop
					If ($ServerClientParams.$StrInfoDisplay -band 4)
					{Write-Host 'DEBUG SERVER: Send-Data completed, looping back' -ForegroundColor Green}
				}
				while ($ServerClientParams.$StrPipeInfo.$StrPipe.IsConnected -and $DataObject.$StrType -inotmatch $StrExitPipe)

				If ($ServerClientParams.Wait)
				{
					Set-Window -ProcessId $DataObject.$StrServerPID -State Restore -Set
					Pause
				}
			}
			Catch
			{
				Set-Window -ProcessId $DataObject.$StrServerPID -State Restore -Set
				NamedPipe\Get-MyErrors -Return
				Pause
			}
			Finally
			{
				# Ensure proper cleanup of resources
				if ($ServerClientParams.$StrPipeInfo.$StrReader)
				{
					try 
					{$ServerClientParams.$StrPipeInfo.$StrReader.Dispose()}
					catch 
					{}
				}
				if ($ServerClientParams.$StrPipeInfo.$StrWriter)
				{
					try 
					{$ServerClientParams.$StrPipeInfo.$StrWriter.Dispose()}
					catch 
					{}
				}
				if ($ServerClientParams.$StrPipeInfo.$StrPipe)
				{
					try 
					{$ServerClientParams.$StrPipeInfo.$StrPipe.Dispose()}
					catch 
					{}
				}
			}
		}
	}
	Elseif($ServerClientParams.$StrClient)
	{
		try
		{
			$ServerClientParams.$StrPipeInfo.$StrPipe = [IO.Pipes.NamedPipeClientStream]::new(
				$ServerClientParams.$StrPipeParams.PipeServer,
				$ServerClientParams.$StrPipeName,$ServerClientParams.$StrPipeParams.Direction
			)
			$DataObject.$StrClientPID = $Pid
			$DataObject.$StrClientUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name

			If ($ServerClientParams.$StrInfoDisplay -band 4)
			{Write-Host 'DEBUG CLIENT: About to connect to pipe...' -ForegroundColor Cyan}
			$ServerClientParams.$StrPipeInfo.$StrPipe.Connect($ServerClientParams.$StrClientConnectTimeout)
			if ($ServerClientParams.$StrPipeInfo.$StrPipe.IsConnected)
			{
				If ($ServerClientParams.$StrInfoDisplay -band 4)
				{Write-Host 'DEBUG CLIENT: Connected, creating StreamReader/Writer' -ForegroundColor Cyan}
				$ServerClientParams.$StrPipeInfo.$StrReader = [IO.StreamReader]::new($ServerClientParams.$StrPipeInfo.$StrPipe)
				$ServerClientParams.$StrPipeInfo.$StrWriter = [IO.StreamWriter]::new($ServerClientParams.$StrPipeInfo.$StrPipe)
				$ServerClientParams.$StrPipeInfo.$StrWriter.AutoFlush = $True
				# Copy InfoDisplay, ChunkSize, Depth to PipeInfo so Send-Data/Receive-Data can access them
				$ServerClientParams.$StrPipeInfo.$StrInfoDisplay = $ServerClientParams.$StrInfoDisplay
				$ServerClientParams.$StrPipeInfo.$StrChunkSize = $ServerClientParams.$StrChunkSize
				$ServerClientParams.$StrPipeInfo.$StrDepth = $ServerClientParams.$StrDepth
				If ($ServerClientParams.$StrInfoDisplay -band 4)
				{Write-Host 'DEBUG CLIENT: StreamReader/Writer created successfully' -ForegroundColor Green}
			}
			else
			{Write-Host 'DEBUG CLIENT: IsConnected = False!' -ForegroundColor Red}
		}
		catch
		{
			Write-Host "DEBUG CLIENT: Exception during connection: $_" -ForegroundColor Red
			$ServerClientParams.$StrPipeInfo.$StrError = $True
			NamedPipe\Get-MyErrors -Return
		}
		$ServerClientParams.$StrPipeInfo
	}
}
