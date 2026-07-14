function Exit-Pipe
{
	<#
			.SYNOPSIS
			"Exit-Pipe" enables both the client and server ends of the pipe to 
			close gracefully

			.DESCRIPTION
			The "$DataObject.Type" is set to "$StrExitPipe" and when this is sent to 
			the server it causes the server to acknowledge the request and then to close 
			the server end of the pipe. It will also process any error conditions
			that happened prior to it being called. The server process itself will also exit.

			.PARAMETER DataObject
			-DataObject should be passed the "$DataObject" structure that allows communucation 
			between the client an server to take place in an organised manner.

			.PARAMETER PipeInfo
			-PipeInfo is the "$PipeInfo" data structure that was wet up when the pipe was establishe 
			it hold the neccessary pointers to enable communucation to take place.

			.EXAMPLE
			Exit-Pipe -DataObject Value -PipeInfo Value
			Causes the server to acknowledge that the pipe should be shutdown and the server 
			process to exit after closing its writer end of the pipe.

			.NOTES
			Place additional notes here.

			.LINK
			URLs to related sites
			The first link is opened by Get-Help -Online Exit-Pipe

			.INPUTS
			The $DataObject and the $PipeInfo structures.

			.OUTPUTS
			Any error information that may exist.
	#>


	[CmdletBinding(PositionalBinding = $False)]
	param
	(
		[Parameter(Mandatory, Position = 0, HelpMessage = 'Please supply the $DataObject object!')]
		[PSObject]$DataObject,
		[Parameter(Mandatory, Position = 0, HelpMessage = 'Please supply the $PipeInfo object!')]
		[PSObject]$PipeInfo
	)
	if ($DataObject.Error)
	{
		'An error was returned from the server process:' | Write-Output
		$DataObject.Error | Write-Error
	}

	$Private:IsCriticalError = $false
	if ($DataObject.Error)
	{
		$Private:ErrorStr = $DataObject.Error
		if ($Private:ErrorStr -match 'IOException|pipe.*closed|broken pipe' -or
			$Private:ErrorStr -match 'PSSerializer.*error' -or
			$Private:ErrorStr -match 'could not be deserialized')
		{
			$Private:IsCriticalError = $true
		}
	}

	if (-not $Private:IsCriticalError)
	{
		try
		{
			$DataObject.Type = $StrExitPipe
			$DataObject = Send-Data -DataObject $DataObject -PipeInfo $PipeInfo
			if ($DataObject.Error)
			{
				'An error was returned from the server Pipe exit request:' | Write-Output
				$DataObject.Error | Write-Error
			}
			$DataObject.Result | Write-Output
		}
		catch
		{
			Write-Warning "Error during pipe exit: $($_.Exception.Message)"
		}
	}

	try { $PipeInfo.Writer.Close() } catch { $null = $_ }
	Exit
}
