Function ConvertTo-PipeFrame
{
	<#
		.SYNOPSIS
		Wraps one pipe line (already serialized) in an integrity frame: NPF2|<id>|<length>|<mac>|<payload>.

		.DESCRIPTION
		0.17. Used only by Send-Data. The frame carries the request id (so Receive-Data can reject a response that belongs to a different
		request), the payload length in characters and an authentication code (Get-PipeFrameMac) over id, length and payload. With the
		session's frame key the code is an HMAC that only a holder of the capability nonce can compute, so an altered id, length or payload
		is detected and a forged frame is refused. The payload itself is untouched, so the chunk and single-message formats inside it are
		unchanged.

		.PARAMETER Payload
		The serialized line: either the single-message text or one 'JCHUNK:' chunk line.

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
		$Private:Mac = Get-PipeFrameMac -Id $Id -Length $Payload.Length -Payload $Payload -Key $Key
		'NPF2|{0}|{1}|{2}|{3}' -f $Id, $Payload.Length, $Private:Mac, $Payload
	}
	Catch
	{
		Write-MyCatchAudit -Source 'ConvertTo-PipeFrame: framing a pipe line failed' -ErrorRecord $_
		throw
	}
}
