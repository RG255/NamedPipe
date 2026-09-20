Function Send-ProgressInfo
{
	<#
		.SYNOPSIS
		Sends a progress message from the server to the client through the pipe.

		.DESCRIPTION
		Used on the server side to send status or progress information back to the
		client during long-running operations. The client receives this as a
		ProgressInfo field in the DataObject and displays it via Write-Information.

		The Type parameter controls how the client handles the message:
		- 'Console': Displays the message and continues waiting
		- 'ConsoleStop': Displays the message and stops execution

		.PARAMETER String
		The progress message text to send to the client.

		.PARAMETER Type
		How the client should handle the message: 'Console' (continue) or 'ConsoleStop' (stop).

		.EXAMPLE
		Send-ProgressInfo -String 'Processing item 5 of 10...' -Type 'Console'
		Sends a progress update to the client.

		.OUTPUTS
		None. Data is sent through the pipe to the client.
	#>

	[cmdletbinding()]
	Param(
		[Parameter(Mandatory,HelpMessage = 'Please pass the required String.')]
		[String]$String,
		[Parameter(Mandatory,HelpMessage = 'Please pass the Type Parameter.')]
		[validateset('Console', 'ConsoleStop')]
		[validatescript({
				$_ -imatch $StrConsole -or
				$_ -imatch $StrConsoleStop
			})]
		[string]$Type
	)
	If (1 -band ($env:MyFunctionTraceEnabled -as [Int])) { Write-MyFunctionTrace }

	$Private:dataObject = Set-ObjectParameterSet -MyParameters $PSCmdlet.MyInvocation.BoundParameters -Dataset DataObject
	# Must tag this as a server-originated DataObject. Send-Data uses ServerPID -eq $PID
	# to decide whether to wait for a response after writing. Without this, Send-Data
	# treats the progress message as a client send and calls Receive-Data, deadlocking
	# the server against the client (client is also blocked reading for the real result).
	$Private:dataObject.$StrServerPID  = $PID
	$Private:dataObject.$StrProgressInfo = $String
	$Private:dataObject.$StrType = $Type
	# 2026-09-15: -ErrorAction Stop here was a no-op - Send-Data never throws, it catches its own
	# failures internally and returns a DataObject with .Error set instead. That result was previously
	# discarded (this function's own .OUTPUTS says "None"), so a failed progress send vanished
	# silently. Now checked and audited - a lost progress ping is low-stakes, but per the user's own
	# stated principle, an error must always be caught SOMEWHERE, even if only to make it trackable.
	$Private:dataObject = Send-Data -DataObject $Private:dataObject -PipeInfo $ServerClientParams.$StrPipeInfo -ErrorAction Stop
	If ($Private:dataObject.$StrError)
	{
		Write-MyCatchAudit -Source 'Send-ProgressInfo: Send-Data reported an error sending a progress message - the progress update was not delivered' -ErrorRecord (
			New-Object System.Management.Automation.ErrorRecord (
				(New-Object System.Exception($Private:dataObject.$StrError)),
				'SendProgressInfoFailed',
				[System.Management.Automation.ErrorCategory]::WriteError,
				$Private:dataObject
			)
		)
	}
}
