# VENDORED from CommonScripts\0.2\Functions\Format-MyTextLine.ps1 by Sync-SharedUtilities [SHA256 1A0D38D4A2850E806CDEBF1876B6C4A6F745D77DD8A16D401F15AFC6696A6CF8] - DO NOT EDIT (edit the master; Deploy-Modules re-syncs).
Function Format-MyTextLine
{
	<#
		.SYNOPSIS
		Formats a line of text with optional parameter label and automatic word-wrapping.

		.DESCRIPTION
		Produces console-friendly output lines with aligned parameter labels and text.
		Automatically wraps long text to fit the window width, breaking at spaces or
		line-ending characters. Useful for building -Help output and status messages.

		.PARAMETER Text
		The text body to format and (optionally) wrap.

		.PARAMETER Parameter
		Optional label placed to the left of the text, padded to ParamLen characters.

		.PARAMETER ParamTrail
		Character(s) between the label and the text. Defaults to nothing.

		.PARAMETER InitialLF
		A CR, LF, or CRLF sequence prepended to the output. Must be one of those
		whitespace sequences or empty.

		.PARAMETER ParamLen
		Width reserved for the label column. Defaults to the label's own length.

		.PARAMETER IndentLen
		Number of spaces to indent the label. Defaults to 0.

		.PARAMETER SetWindowWidth
		Override the auto-detected window width. Set to 0 (default) to auto-detect.

		.PARAMETER NoWrap
		Suppress word-wrapping. The text is appended as-is after the label.

		.EXAMPLE
		Format-MyTextLine -Parameter '-help' -ParamLen 10 -InitialLF "`r`n" `
		                  -Text 'Will output this text.' -ParamTrail ': '

		Returns (preceded by CRLF):
		-help     : Will output this text.

		.OUTPUTS
		System.String - The formatted line.
	#>

	[CmdletBinding(PositionalBinding = $False)]
	Param (
		[Parameter(Mandatory = $True, HelpMessage = 'Please supply the string to process')]
		[AllowEmptyString()]
		[String]$Text,
		[String]$Parameter    = '',
		[String]$ParamTrail   = '',
		[ValidatePattern('(?:[\n]+?|[\r]+?|[\r][\n]+?|^$)')]
		[AllowEmptyString()]
		[String]$InitialLF    = '',
		[ValidateRange(0, [int]::MaxValue)]
		[int]$ParamLen        = [int]0,
		[ValidateRange(0, [int]::MaxValue)]
		[int]$IndentLen       = [int]0,
		[ValidateRange(0, [int]::MaxValue)]
		[int]$SetWindowWidth  = [int]0,
		[switch]$NoWrap
	)

	# ── Inner helper: find a safe line-break position ─────────────────────────
	Function Split-MyLine
	{
		[CmdletBinding(PositionalBinding = $False)]
		Param (
			[Parameter(Mandatory = $True, ValueFromPipeline = $True)]
			[String]$Text
		)

		Process
		{
		# Already fits - return full length
		if ($Text.Length -le $Maxlen)
		{ return $Text.Length }

		# Degenerate case (should not occur in practice)
		if ($Text.Length -le 0)
		{ return 1 }

		$SearchText = $Text.Substring(0, $Maxlen)

		# Check break candidates in priority order: CRLF > CR > LF > space
		$BreakPoints = @(
			@{ Char = "`r`n"; Pos = $SearchText.IndexOf("`r`n")    }
			@{ Char = "`r";   Pos = $SearchText.LastIndexOf("`r")   }
			@{ Char = "`n";   Pos = $SearchText.LastIndexOf("`n")   }
			@{ Char = ' ';    Pos = $SearchText.LastIndexOf(' ')    }
		)

		foreach ($BP in $BreakPoints)
		{
			if ($BP.Pos -gt 0 -and $BP.Pos -le $Maxlen)
			{
				# For CRLF use the IndexOf position (first occurrence)
				return $BP.Pos
			}
		}

		# No good break point - hard-break at max
		return $Maxlen
		} # end Process
	}

	# ── Determine effective window width ──────────────────────────────────────
	$Private:MyWWidth = [int]0

	if ($SetWindowWidth -gt 0)
	{ $Private:MyWWidth = $SetWindowWidth }
	else
	{
		# Try reading from the host's raw UI; fall back to no-wrap if unavailable
		try
		{ $Private:MyWWidth = (Get-Host).UI.RawUI.WindowSize.Width }
		catch
		{ $Private:MyWWidth = 0 }
	}

	if ($Private:MyWWidth -le 0)
	{ $NoWrap = $True }

	# ── Column geometry ───────────────────────────────────────────────────────
	if (-not $ParamLen)
	{ $ParamLen = $Parameter.Length }

	$PadRight       = [Math]::Max($ParamLen - $IndentLen, 0)
	$ParamTrailLen  = $ParamTrail.Length
	$Maxlen         = $Private:MyWWidth - ($ParamLen + $ParamTrailLen)

	# If the label overflows its column, shrink the available text width
	if ($Parameter.Length -gt $ParamLen)
	{ $Maxlen -= ($Parameter.Length - $ParamLen) }

	# Require at least 20 characters for wrapped text to be meaningful
	$MinWindowWidth = $ParamLen + $ParamTrailLen + 20
	if ($MinWindowWidth -gt $Private:MyWWidth)
	{ $NoWrap = $True }

	# ── Build output string ───────────────────────────────────────────────────
	[String]$TextOut = ''
	$TextOut += ('{0}{1}{2}' -f ''.PadLeft($IndentLen), $Parameter.PadRight($PadRight), $ParamTrail)

	if ($NoWrap)
	{
		$TextOut += $Text
	}
	else
	{
		$Text = $Text.Trim()

		if ($Text.Length -le $Maxlen)
		{
			$TextOut += $Text
		}
		else
		{
			$Private:FirstLine = $True
			$Private:Pad       = ''.PadLeft($ParamLen + $ParamTrailLen)

			while ($Text.Length -gt $Maxlen)
			{
				$Position = $Text | Split-MyLine
				if ($Private:FirstLine)
				{
					$TextOut += $Text.Substring(0, $Position)
					$Private:FirstLine = $False
				}
				else
				{ $TextOut += ("`r`n{0}{1}" -f $Private:Pad, $Text.Substring(0, $Position)) }
				$Text = $Text.Substring($Position).TrimStart()
			}
			$TextOut += ("`r`n{0}{1}" -f $Private:Pad, $Text)
		}
	}

	# Prepend any requested line-ending and return
	('{0}{1}' -f $InitialLF, $TextOut)
}
