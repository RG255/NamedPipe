Function Start-PipeSession
{
	<#
		.SYNOPSIS
		Sets up a complete named pipe session (server + client) in a single call.

		.DESCRIPTION
		Replaces the ~20 lines of boilerplate required to establish a named pipe
		session. Creates MyOptions, ServerClientParams, and SendRequestParams,
		starts the server process, connects the client, and returns both parameter
		objects ready for use with Send-Request.

		Stores ModuleToLoad info into ServerClientParams so the spawned server
		imports the correct module (e.g. VHD). Defaults to NamedPipe itself.
		Consumer modules override via Options: @{ $StrModuleToLoad = @{Name='VHD'; Version='0.1'} }

		.PARAMETER MyParameters
		The caller's bound parameters, typically $PSCmdlet.MyInvocation.BoundParameters.
		These flow through Set-ObjectParams to configure the pipe session.

		.PARAMETER Options
		Optional hashtable of overrides to apply to MyOptions after initial creation.
		Example: @{ $StrAdminRequired = $True; $StrWindowStyle = $StrMinimized }

		.PARAMETER AccessList
		Optional string array of pipe security identifiers.
		Format: 'DOMAIN\User:Allow:ReadWrite'
		If not provided, defaults to the current user only.

		.EXAMPLE
		$Session = Start-PipeSession -MyParameters $Private:MyBoundParameters
		$ServerClientParams = $Session.$StrServerClientParams
		$SendRequestParams  = $Session.$StrSendRequestParams

		.EXAMPLE
		$Session = Start-PipeSession -MyParameters $Private:MyBoundParameters -Options @{
			$StrAdminRequired = $True
			$StrWindowStyle   = $StrMinimized
		}

		.OUTPUTS
		Ordered hashtable with keys $StrServerClientParams and $StrSendRequestParams.
	#>

	[CmdletBinding()]
	Param(
		[Parameter(Mandatory)]
		[System.Collections.IDictionary]$MyParameters,
		[HashTable]$Options = @{},
		[String[]]$AccessList
	)
	If ($Script:FTrace)
	{Write-MyLog -PathToLogFile $Script:FTLogFilePath -CallStack (Get-PSCallStack)}

	# Step 1: Create MyOptions from caller's bound parameters
	$Private:MyOptions = Set-ObjectParams -Dataset $StrMyOptions -MyParameters $MyParameters

	# Step 2: Apply any overrides
	foreach ($Private:Key in $Options.Keys)
	{$Private:MyOptions.$Private:Key = $Options[$Private:Key]}

	# Step 3: Handle AccessList - pass through MyOptions so Set-ObjectParams Server picks it up
	if ($AccessList)
	{$Private:MyOptions.$StrAccessIdentifier = $AccessList}
	elseif (-not $MyParameters.$StrAccessIdentifier)
	{
		# Default to current user only
		$Private:MyOptions.$StrAccessIdentifier = @(
			'{0}:Allow:ReadWrite' -f [Security.Principal.WindowsIdentity]::GetCurrent().Name
		)
	}

	# Step 4: Create ServerClientParams (server side) and SendRequestParams
	$Private:ServerClientParams = Set-ObjectParams -Server -Dataset $StrServerClientParams -MyParameters $Private:MyOptions
	$Private:SendRequestParams = Set-ObjectParams -Dataset $StrSendRequestParams -MyParameters $Private:ServerClientParams

	# Debug output
	If ($Private:ServerClientParams.$StrInfoDisplay -band 2)
	{
		Show-VerboseData -Object $Private:ServerClientParams.$StrPipeParams -Display -Title 'Initial PipeParam'
		Show-VerboseData -Object $Private:ServerClientParams -Display -Title 'ServerClient Parameters'
		Show-VerboseData -Object $Private:ServerClientParams.$StrModuleToLoad -Display -Title 'Module to load in Spawned process'
		Show-VerboseData -Object $Private:SendRequestParams.$StrDataObject -Display -Title 'DataObject Before Server started'
	}

	# Step 6: Start the server
	$Private:SendRequestParams.$StrDataObject.$StrServerPID = Start-PipeServerOrClient -SerialData (ConvertTo-Serial -Object $Private:ServerClientParams)
	If ($Private:ServerClientParams.$StrInfoDisplay -band 2)
	{Show-VerboseData -Object $Private:SendRequestParams.$StrDataObject -Display -Title 'DataObject Before Client started'}

	# Step 7: Switch to client and connect
	$Private:ServerClientParams = Set-ObjectParams -Client -Dataset $StrServerClientParams -MyParameters $Private:ServerClientParams

	$Private:SendRequestParams.$StrDataObject.$StrClientPID = $Pid
	$Private:SendRequestParams.$StrDataObject.$StrClientUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name

	$Private:ServerClientParams.$StrPipeInfo = Start-PipeServerOrClient -SerialData (ConvertTo-Serial -Object $Private:ServerClientParams)
	$Private:SendRequestParams.$StrPipeInfo = $Private:ServerClientParams.$StrPipeInfo

	If ($Private:ServerClientParams.$StrInfoDisplay -band 2)
	{Show-VerboseData -Object $Private:ServerClientParams.$StrPipeInfo -Display -Title 'PipeInfo after Client Started'}

	# Step 8: Error check
	if ($Private:ServerClientParams.$StrPipeInfo.$StrError)
	{
		$Private:ServerClientParams.$StrPipeInfo[0] | Write-Host
		throw 'Start-PipeSession: A fatal error has occurred, cannot continue!'
	}

	# Step 9: Return both parameter objects
	[Ordered]@{
		$StrServerClientParams = $Private:ServerClientParams
		$StrSendRequestParams  = $Private:SendRequestParams
	}
}
