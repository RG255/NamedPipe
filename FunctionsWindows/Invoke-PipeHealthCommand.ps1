Function Invoke-PipeHealthCommand
{
	<#
		.SYNOPSIS
		Sends one authenticated command (STATUS, CANCEL or KILL) to a session's health pipe and returns the reply line.

		.DESCRIPTION
		0.16 internal helper behind Get-PipeRequestStatus, Stop-PipeRequest, Stop-PipeServer, Stop-PipeSession -Force
		and the Send-Request timeout escalation. The health pipe runs in its own runspace inside the server, so it
		still answers while the main runspace is wedged inside a request. The command is authenticated with the
		session's command token (PipeInfo.CommandToken, derived from the capability nonce).

		Never throws: failures come back as a descriptive string in angle brackets ('<no reply>', '<error: ...>',
		'<no command token>') so the escalation logic can always carry on to its next step.

		.PARAMETER PipeInfo
		The session's PipeInfo (supplies the pipe name and the command token).

		.PARAMETER Command
		STATUS, CANCEL or KILL.

		.PARAMETER RequestId
		Optional. For CANCEL: only act if this request id is the one running (guards against cancelling the NEXT
		request after the intended one has already finished).

		.PARAMETER TimeoutMs
		Connect and reply timeout. Default 6000 (the server may spend up to 3 s waiting for a stop to complete).

		.EXAMPLE
		Invoke-PipeHealthCommand -PipeInfo $PipeInfo -Command STATUS

		.OUTPUTS
		System.String - the server's reply line, for example 'STATUS:idle', 'CANCEL:stopped', 'KILL:ok', 'DENIED'.
	#>
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory)]
		[AllowNull()]
		$PipeInfo,
		[Parameter(Mandatory)]
		[ValidateSet('STATUS', 'CANCEL', 'KILL')]
		[String]$Command,
		[Int]$RequestId = 0,
		[Int]$TimeoutMs = 6000
	)
	If (1 -band ($env:MyFunctionTraceEnabled -as [Int])) { Write-MyFunctionTrace }

	# 0.16: accept a ServerClientParams as well as a PipeInfo (see Resolve-PipeInfo).
	$PipeInfo = Resolve-PipeInfo -InputObject $PipeInfo

	If (-not $PipeInfo -or -not $PipeInfo.$StrName)
	{ return '<no pipe info>' }
	$Private:Token = [string]$PipeInfo.$StrCommandToken
	If (-not $Private:Token)
	{ return '<no command token>' }

	$Private:Line = '{0}:{1}' -f $Command, $Private:Token
	If ($RequestId -gt 0) { $Private:Line += (':{0}' -f $RequestId) }

	$Private:Client = $null
	Try
	{
		$Private:Client = [System.IO.Pipes.NamedPipeClientStream]::new('.', ($PipeInfo.$StrName + '.Health'), [System.IO.Pipes.PipeDirection]::InOut)
		$Private:Client.Connect($TimeoutMs)
		$Private:Writer = [System.IO.StreamWriter]::new($Private:Client)
		$Private:Writer.AutoFlush = $true
		$Private:Reader = [System.IO.StreamReader]::new($Private:Client)
		$Private:Writer.WriteLine($Private:Line)
		$Private:Task = $Private:Reader.ReadLineAsync()
		If ($Private:Task.Wait($TimeoutMs)) { [string]$Private:Task.Result } Else { '<no reply>' }
	}
	Catch
	{
		# A failed health command is an EXPECTED outcome here (server already gone, pipe busy) and is reported to
		# the caller as a string; the caller's escalation logic decides what it means.
		'<error: {0}>' -f $_.Exception.Message
	}
	Finally
	{
		If ($Private:Client) { Try { $Private:Client.Dispose() } Catch { $null = $_ } }
	}
}
