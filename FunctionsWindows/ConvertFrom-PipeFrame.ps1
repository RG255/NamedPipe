Function ConvertFrom-PipeFrame
{
	<#
		.SYNOPSIS
		Checks and unwraps a line framed by ConvertTo-PipeFrame; throws if it is not a valid frame.

		.DESCRIPTION
		0.17. Used only by Receive-Data. Verifies the 'NPF2|' marker, that the payload is exactly the declared length, and that the
		authentication code over id, length and payload matches (compared in constant time). Any failure throws a message saying which
		check failed; Receive-Data's own Catch turns that into the returned DataObject's Error and audits it. There is deliberately no
		fallback to unframed lines: both ends of a pipe always run the same module version.

		.PARAMETER Line
		One line as read from the pipe.

		.PARAMETER Key
		PipeInfo.FrameKey (hex), or empty for the unkeyed form. Sender and receiver must agree; a keyed frame never verifies unkeyed.

		.OUTPUTS
		[pscustomobject] with Id (int) and Payload (string).
	#>

	[CmdletBinding(PositionalBinding = $False)]
	Param (
		[Parameter(Mandatory, HelpMessage = 'The line read from the pipe')]
		[AllowEmptyString()]
		[String]$Line,

		[Parameter(HelpMessage = 'The frame key (hex) or empty')]
		[AllowEmptyString()]
		[AllowNull()]
		[String]$Key
	)

	If (1 -band ($env:MyFunctionTraceEnabled -as [Int])) { Write-MyFunctionTrace }

	# Split into at most 5 parts so a '|' inside the payload (JSON chunk lines contain them) stays in the payload.
	$Private:Parts = $Line.Split([char[]]'|', 5)
	If ($Private:Parts.Count -ne 5 -or $Private:Parts[0] -cne 'NPF2')
	{ throw 'Pipe frame rejected: the line is not an NPF2 frame. The other end is most likely running a different build of the NamedPipe module - typically a PowerShell window that loaded NamedPipe before it was last updated. Close and reopen that PowerShell session (and any server window it started), then try again. If it happens again from fresh sessions, the stream is being corrupted.' }

	$Private:Id = 0
	$Private:Len = 0
	If (-not [int]::TryParse($Private:Parts[1], [ref]$Private:Id) -or -not [int]::TryParse($Private:Parts[2], [ref]$Private:Len))
	{ throw 'Pipe frame rejected: the frame header is malformed.' }

	$Private:Payload = $Private:Parts[4]
	If ($Private:Payload.Length -ne $Private:Len)
	{ throw ('Pipe frame rejected: payload is {0} characters, the frame declares {1} (truncated or altered).' -f $Private:Payload.Length, $Private:Len) }

	$Private:Expected = Get-PipeFrameMac -Id $Private:Id -Length $Private:Len -Payload $Private:Payload -Key $Key
	$Private:Presented = [string]$Private:Parts[3]
	# Constant-time comparison: no early exit on the first differing character.
	$Private:Diff = $Private:Expected.Length -bxor $Private:Presented.Length
	$Private:Max = [Math]::Min($Private:Expected.Length, $Private:Presented.Length)
	For ($Private:i = 0; $Private:i -lt $Private:Max; $Private:i++)
	{ $Private:Diff = $Private:Diff -bor ([int]$Private:Expected[$Private:i] -bxor [int]$Private:Presented[$Private:i]) }
	If ($Private:Diff -ne 0)
	{ throw 'Pipe frame rejected: the authentication code does not match (id, length or payload altered, or forged without the session key).' }

	[pscustomobject]@{ Id = $Private:Id; Payload = $Private:Payload }
}
