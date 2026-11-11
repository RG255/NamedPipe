Function Get-PipeFrameMac
{
	<#
		.SYNOPSIS
		Computes the authentication code of one pipe frame: over the frame id, the payload length and the payload.

		.DESCRIPTION
		0.17, direction added in 0.18. Shared by ConvertTo-PipeFrame (sender) and ConvertFrom-PipeFrame (receiver) so both compute it identically.
		The input is the UTF-8 text '<direction>|<id>|<length>|<payload>', so the direction, id and length are covered as well as the payload:
		altering any of them changes the result, and a frame written for one direction never verifies as the other. With a key (Get-PipeFrameKey) it is HMAC-SHA256, which only a holder of the session nonce can produce; with no key it
		is plain SHA-256, which detects accidental damage only.

		.PARAMETER Direction
		C for a frame sent by the client (a request), S for a frame sent by the server (a response or progress message).

		.PARAMETER Id
		The frame id.

		.PARAMETER Length
		The payload length in characters.

		.PARAMETER Payload
		The serialized line.

		.PARAMETER Key
		The frame key as 64 hex characters (PipeInfo.FrameKey), or empty for the unkeyed form.

		.OUTPUTS
		System.String - 64 upper-case hex characters.
	#>
	[CmdletBinding(PositionalBinding = $False)]
	Param (
		[Parameter(Mandatory, HelpMessage = 'The frame direction: C (client to server) or S (server to client)')]
		[ValidateSet('C', 'S')]
		[String]$Direction,

		[Parameter(Mandatory, HelpMessage = 'The frame id')]
		[Int]$Id,

		[Parameter(Mandatory, HelpMessage = 'The payload length')]
		[Int]$Length,

		[Parameter(Mandatory, HelpMessage = 'The payload')]
		[AllowEmptyString()]
		[String]$Payload,

		[Parameter(HelpMessage = 'The frame key (hex) or empty')]
		[AllowEmptyString()]
		[AllowNull()]
		[String]$Key
	)
	If (1 -band ($env:MyFunctionTraceEnabled -as [Int])) { Write-MyFunctionTrace }

	$Private:Hasher = $null
	Try
	{
		$Private:Data = [System.Text.Encoding]::UTF8.GetBytes(('{0}|{1}|{2}|{3}' -f $Direction, $Id, $Length, $Payload))
		If ([String]::IsNullOrEmpty($Key))
		{ $Private:Hasher = [System.Security.Cryptography.SHA256]::Create() }
		Else
		{
			$Private:KeyBytes = [byte[]]::new($Key.Length / 2)
			For ($Private:i = 0; $Private:i -lt $Private:KeyBytes.Length; $Private:i++)
			{ $Private:KeyBytes[$Private:i] = [Convert]::ToByte($Key.Substring(2 * $Private:i, 2), 16) }
			$Private:Hasher = [System.Security.Cryptography.HMACSHA256]::new($Private:KeyBytes)
		}
		[BitConverter]::ToString($Private:Hasher.ComputeHash($Private:Data)).Replace('-', '')
	}
	Catch
	{
		Write-MyCatchAudit -Source 'Get-PipeFrameMac: computing a frame authentication code failed - re-thrown, the frame is not sent or accepted' -ErrorRecord $_
		throw
	}
	Finally
	{
		If ($Private:Hasher) { $Private:Hasher.Dispose() }
	}
}
