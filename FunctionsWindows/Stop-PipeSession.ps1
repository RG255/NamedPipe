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

		.PARAMETER Force
			0.16. Terminate the server process through the health pipe instead of sending a normal ExitPipe request.
			Use when a request is stuck and the normal exit cannot be delivered. Any in-flight work is abandoned.

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
		[PSObject]$PipeInfo,
		[Switch]$Force
	)
	If (1 -band ($env:MyFunctionTraceEnabled -as [Int])) { Write-MyFunctionTrace }

	# 0.16: tolerate the whole ServerClientParams being passed (otherwise Test-PipeSession said "dead", no
	# ExitPipe was sent, and the server was leaked).
	$PipeInfo = Resolve-PipeInfo -InputObject $PipeInfo

	try
	{
		if ($Force)
		{
			# 0.16: the ExitPipe request is queued behind whatever the server is doing, so it never arrives while a
			# request is wedged. -Force goes straight to KILL on the authenticated health pipe instead. Best effort:
			# an unreachable server is already gone, and the streams are still disposed below.
			$null = Invoke-PipeHealthCommand -PipeInfo $PipeInfo -Command KILL
		}
		elseif (Test-PipeSession -PipeInfo $PipeInfo)
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
