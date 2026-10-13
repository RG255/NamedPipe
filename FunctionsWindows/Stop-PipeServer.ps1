Function Stop-PipeServer
{
	<#
		.SYNOPSIS
		Terminates a pipe session's server process immediately. The session is lost.

		.DESCRIPTION
		0.16. Sends KILL on the session's health pipe; the server process ends at once without running its
		clean-up. Use it when a request is stuck somewhere Stop-PipeRequest cannot reach (for example native
		console input) or when the normal exit request cannot be delivered. Anything the request had half done
		stays half done - this is an emergency stop, not a rollback.

		Works for an elevated server from a non-elevated client, because the command is carried inside the
		server's own authenticated health pipe rather than by the operating system.

		.PARAMETER PipeInfo
		The session's PipeInfo ($ServerClientParams.$StrPipeInfo).

		.EXAMPLE
		Stop-PipeServer -PipeInfo $ServerClientParams.$StrPipeInfo

		.OUTPUTS
		System.String - 'KILL:ok', 'DENIED' or a bracketed failure description.
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Terminating the stuck server is the purpose of this command; an emergency stop must never prompt or be silently previewed away.')]
	Param(
		[Parameter(Mandatory)]
		[AllowNull()]
		[PSObject]$PipeInfo
	)
	If (1 -band ($env:MyFunctionTraceEnabled -as [Int])) { Write-MyFunctionTrace }

	Invoke-PipeHealthCommand -PipeInfo $PipeInfo -Command KILL
}
