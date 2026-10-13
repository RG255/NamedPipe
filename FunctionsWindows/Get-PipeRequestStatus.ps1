Function Get-PipeRequestStatus
{
	<#
		.SYNOPSIS
		Reports whether a pipe session's server is idle or busy, and for how long, without disturbing it.

		.DESCRIPTION
		0.16. Asks the server's health pipe (which runs in its own runspace, so it answers even while a request is
		wedged) for the state of the request currently running. Safe to call from another runspace or while a
		Send-Request is blocked in the same session.

		.PARAMETER PipeInfo
		The session's PipeInfo ($ServerClientParams.$StrPipeInfo).

		.EXAMPLE
		Get-PipeRequestStatus -PipeInfo $Session.$StrServerClientParams.$StrPipeInfo

		.OUTPUTS
		PSCustomObject with State ('Idle', 'Busy', 'Refused' or 'Unreachable'), RequestId, ElapsedMs and Reply.
	#>
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory)]
		[AllowNull()]
		[PSObject]$PipeInfo
	)
	If (1 -band ($env:MyFunctionTraceEnabled -as [Int])) { Write-MyFunctionTrace }

	$Private:Reply = Invoke-PipeHealthCommand -PipeInfo $PipeInfo -Command STATUS
	$Private:State = 'Unreachable'
	$Private:Id = 0
	$Private:Elapsed = [long]0
	If ($Private:Reply -eq 'STATUS:idle') { $Private:State = 'Idle' }
	ElseIf ($Private:Reply -match '^STATUS:busy;id=(\d+);elapsedMs=(\d+)$')
	{
		$Private:State = 'Busy'
		$Private:Id = [int]$Matches[1]
		$Private:Elapsed = [long]$Matches[2]
	}
	ElseIf ($Private:Reply -eq 'DENIED') { $Private:State = 'Refused' }
	[PSCustomObject]@{
		State     = $Private:State
		RequestId = $Private:Id
		ElapsedMs = $Private:Elapsed
		Reply     = $Private:Reply
	}
}
