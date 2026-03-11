Function Test-PipeSession
{
	<#
			.SYNOPSIS
			Tests whether a named pipe session is still connected and healthy.

			.DESCRIPTION
			Performs a non-disruptive health check on the pipe session without
			sending any commands. Verifies that the pipe, reader, and writer
			objects exist and the pipe is still connected.

			.PARAMETER PipeInfo
			The PipeInfo object from the session's ServerClientParams.

			.EXAMPLE
			if (Test-PipeSession -PipeInfo $ServerClientParams.$StrPipeInfo)
			{
			# Pipe is healthy, safe to send commands
			}

			.OUTPUTS
			System.Boolean - $true if the session is healthy, $false otherwise.
	#>

	[CmdletBinding()]
	Param(
		[Parameter(Mandatory)]
		[AllowNull()]
		[PSObject]$PipeInfo
	)
	If ($Script:FTrace)
	{Write-MyLog -PathToLogFile $Script:FTLogFilePath -CallStack (Get-PSCallStack)}

	try
	{
		if (-not $PipeInfo)
		{return $false}
		if (-not $PipeInfo.$StrPipe)
		{return $false}
		if (-not $PipeInfo.$StrPipe.IsConnected)
		{return $false}
		if (-not $PipeInfo.$StrReader)
		{return $false}
		if (-not $PipeInfo.$StrWriter)
		{return $false}
		# Check writer's base stream is accessible (not disposed)
		$null = $PipeInfo.$StrWriter.BaseStream
		$true
	}
	catch
	{$false}
}
