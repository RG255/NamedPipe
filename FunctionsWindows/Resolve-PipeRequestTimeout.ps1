Function Resolve-PipeRequestTimeout
{
	<#
		.SYNOPSIS
		Escalates a timed-out request: CANCEL first, then (unless told not to) KILL. Internal to Send-Request.

		.DESCRIPTION
		0.16. Called by Send-Request when its inactivity timeout or maximum runtime expires.

		1. CANCEL on the health pipe, then wait up to GraceSeconds for the server's normal response. If the
		   cancel was honoured the server answers the request with Cancelled = $true and the SESSION IS STILL
		   OPEN - that response is returned as-is and the caller decides what to do next.
		2. If nothing arrives (the request is blocked somewhere a stop cannot reach, for example native console
		   input), then with -NoKill the request object is returned with an explanatory Error and the server left
		   running (the caller can inspect it and call Stop-PipeServer); otherwise KILL ends the server process
		   and the session is dead.

		.PARAMETER PipeInfo
		The session's PipeInfo. Its pending read (kept by Receive-Data when the timeout fired) is what picks up the
		cancelled response.

		.PARAMETER RequestObject
		The request's own DataObject, returned (with Error set) when no server response can be had.

		.PARAMETER Reason
		'Inactivity' or 'MaxRuntime' (what Receive-Data recorded).

		.PARAMETER GraceSeconds
		How long to wait for the cancelled response. Default 5.

		.PARAMETER NoKill
		Do not escalate to KILL.

		.OUTPUTS
		A DataObject: the server's (cancelled) response, or RequestObject with Error and TimedOut set.
	#>
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory)]
		$PipeInfo,
		[Parameter(Mandatory)]
		$RequestObject,
		[String]$Reason = 'Inactivity',
		[Int]$GraceSeconds = 5,
		[Switch]$NoKill
	)
	If (1 -band ($env:MyFunctionTraceEnabled -as [Int])) { Write-MyFunctionTrace }

	$Private:Why = If ($Reason -eq 'MaxRuntime') { 'maximum runtime reached' } Else { 'no activity from the server' }

	$Private:CancelReply = Invoke-PipeHealthCommand -PipeInfo $PipeInfo -Command CANCEL

	# Wait for the response to the ORIGINAL request: the read that timed out is still pending on the reader and
	# Receive-Data picks it up, so nothing is read twice or lost.
	$PipeInfo.$StrReadTimeoutMs = [int]([Math]::Max(1, $GraceSeconds) * 1000)
	$PipeInfo.$StrDeadlineTicks = [long]0
	$PipeInfo.$StrTimedOut      = $null
	$Private:Response = Receive-Data -PipeInfo $PipeInfo
	If (-not $PipeInfo.$StrTimedOut)
	{
		# The server answered. Under a honoured cancel this is the Cancelled response and the session lives on.
		return $Private:Response
	}
	$PipeInfo.$StrTimedOut = $null

	If ($NoKill)
	{
		$RequestObject.$StrError = ('Request timed out ({0}) and CANCEL was not honoured (reply: {1}). The server is still running the request; the session is NOT safe to reuse. Stop-PipeServer ends it.' -f $Private:Why, $Private:CancelReply)
		$RequestObject.$StrTimedOut = 'CancelNotHonoured'
		return $RequestObject
	}

	$Private:KillReply = Invoke-PipeHealthCommand -PipeInfo $PipeInfo -Command KILL
	$RequestObject.$StrError = ('Request timed out ({0}); the server did not honour CANCEL and was terminated (KILL reply: {1}). Open a new session.' -f $Private:Why, $Private:KillReply)
	$RequestObject.$StrTimedOut = 'ServerKilled'
	$RequestObject
}
