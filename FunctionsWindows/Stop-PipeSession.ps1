Function Stop-PipeSession
{
	<#
		.SYNOPSIS
		Cleanly shuts down a named pipe session.

		.DESCRIPTION
		Sends an ExitPipe request to the server (if the pipe is still connected),
		then disposes the Writer and Reader in a finally block to ensure cleanup
		even if an error occurs.

		.PARAMETER SendRequestParams
		The SendRequestParams object from Start-PipeSession.

		.PARAMETER PipeInfo
		The PipeInfo object from the session's ServerClientParams.

		.EXAMPLE
		Stop-PipeSession -SendRequestParams $SendRequestParams -PipeInfo $ServerClientParams.$StrPipeInfo

		.OUTPUTS
		None.
	#>

	[CmdletBinding()]
	Param(
		[Parameter(Mandatory)]
		[PSObject]$SendRequestParams,
		[Parameter(Mandatory)]
		[PSObject]$PipeInfo
	)
	If ($Script:FTrace)
	{Write-MyLog -PathToLogFile $Script:FTLogFilePath -CallStack (Get-PSCallStack)}

	try
	{
		if (Test-PipeSession -PipeInfo $PipeInfo)
		{
			$SendRequestParams.$StrType = $StrExitPipe
			$SendRequestParams.$StrDataObject = $Null | Send-Request @SendRequestParams
		}
	}
	finally
	{
		try {$PipeInfo.$StrWriter.Dispose()} catch {}
		try {$PipeInfo.$StrReader.Dispose()} catch {}
	}
}
