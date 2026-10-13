Function Stop-PipeRequest
{
	<#
		.SYNOPSIS
		Asks the server to stop the request it is running, keeping the session open.

		.DESCRIPTION
		0.16. Sends CANCEL on the session's health pipe. If the running request can be interrupted (a busy loop,
		Start-Sleep, a native program) the server stops it and answers the blocked Send-Request with a normal
		response whose Cancelled is $true; the session stays usable. Code blocked in console input cannot be
		interrupted - the reply is then 'CANCEL:pending' and Stop-PipeServer is the remaining option.

		Usually called from another runspace while a Send-Request is blocked, or by Send-Request's own timeout
		handling (-TimeoutSeconds / -MaxRuntimeSeconds), which does this automatically.

		.PARAMETER PipeInfo
		The session's PipeInfo ($ServerClientParams.$StrPipeInfo).

		.PARAMETER RequestId
		Optional. Only cancel if this request id is the one running (from Get-PipeRequestStatus).

		.EXAMPLE
		Stop-PipeRequest -PipeInfo $ServerClientParams.$StrPipeInfo

		.OUTPUTS
		System.String - 'CANCEL:stopped', 'CANCEL:pending', 'CANCEL:none' (nothing running / id mismatch), 'DENIED'
		or a bracketed failure description.
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Stopping the running request is the purpose of this command; a -WhatIf preview of an emergency cancel has no value.')]
	Param(
		[Parameter(Mandatory)]
		[AllowNull()]
		[PSObject]$PipeInfo,
		[Int]$RequestId = 0
	)
	If (1 -band ($env:MyFunctionTraceEnabled -as [Int])) { Write-MyFunctionTrace }

	Invoke-PipeHealthCommand -PipeInfo $PipeInfo -Command CANCEL -RequestId $RequestId
}
