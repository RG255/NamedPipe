Function ConvertTo-PipeFrame
{
	<#
		.SYNOPSIS
		Wraps one pipe line (already serialized) in an integrity frame: NPF3|<direction>|<id>|<length>|<mac>|<payload>.

		.DESCRIPTION
		0.17, direction added in 0.18 (marker NPF2 became NPF3). Used only by Send-Data. The frame carries the direction (C = client request,
		S = server response or progress), the request id (so Receive-Data can reject a response that belongs to a different request), the
		payload length in characters and an authentication code (Get-PipeFrameMac) over direction, id, length and payload. With the
		session's frame key the code is an HMAC that only a holder of the capability nonce can compute, so an altered field or payload
		is detected, a forged frame is refused, and a request frame can never be accepted as a response (or the reverse). The payload itself is untouched, so the chunk and single-message formats inside it are
		unchanged.

		.PARAMETER Payload
		The serialized line: either the single-message text or one 'JCHUNK:' chunk line.

		.PARAMETER Direction
		C when the client is sending (a request), S when the server is sending (a response or progress message).

		.PARAMETER Id
		Frame id: the client's per-session request counter; the server echoes the id of the request it is answering.

		.PARAMETER Key
		PipeInfo.FrameKey (hex), or empty for the unkeyed form (a session started without a nonce).

		.OUTPUTS
		The framed line (a string, no line terminator).
	#>

	[CmdletBinding(PositionalBinding = $False)]
	Param (
		[Parameter(Mandatory, HelpMessage = 'The serialized line to frame')]
		[AllowEmptyString()]
		[String]$Payload,

		[Parameter(Mandatory, HelpMessage = 'The frame direction: C (client to server) or S (server to client)')]
		[ValidateSet('C', 'S')]
		[String]$Direction,

		[Parameter(Mandatory, HelpMessage = 'The frame id')]
		[Int]$Id,

		[Parameter(HelpMessage = 'The frame key (hex) or empty')]
		[AllowEmptyString()]
		[AllowNull()]
		[String]$Key
	)

	If (1 -band ($env:MyFunctionTraceEnabled -as [Int])) { Write-MyFunctionTrace }

	Try
	{
		$Private:Mac = Get-PipeFrameMac -Direction $Direction -Id $Id -Length $Payload.Length -Payload $Payload -Key $Key
		'NPF3|{0}|{1}|{2}|{3}|{4}' -f $Direction, $Id, $Payload.Length, $Private:Mac, $Payload
	}
	Catch
	{
		Write-MyCatchAudit -Source 'ConvertTo-PipeFrame: framing a pipe line failed' -ErrorRecord $_
		throw
	}
}
