Function Format-MyTextLine
{
  <#
      .SYNOPSIS
      Formats a line of text given the supplied Parameters useful to format help type output
      to match the current screen width but can be used for anything.

      Requires a call to Set-Window with the -characters option to initialise the window size variables

      e.g. Set-Window -ProcessId $Pid -Characters
      as a minimum the window size, title and position can also be set in this call
      See Set-Window for more detail.

      .DESCRIPTION
      Will allow formatting like this:
      -help      : This is the text that will describe the help option
                   and may carry over to the next line if text is too
                   long
      -Opt       : Can describe an option that can be used with the
      -help

      .PARAMETER Parameter
      Describe Parameter -Parameter: is the "-help" in the description above.

      .PARAMETER Text
      Describe Parameter -Text: is the text to be formatted.

      .PARAMETER ParamLen
      Describe Parameter -ParamLen: is the amount of indent before the text.

      .PARAMETER IndentLen
      Describe Parameter -IndentLen: is the amount of indent before the -Parameter item.

      .PARAMETER ParamTrail
      Describe Parameter -ParamTrail: Is the character(s) that separate the Parameter
      from the text in the case above the ": ".

      .PARAMETER InitialLF
      Describe Parameter -InitialLF: Passes a CR, LF, or CRLF sequence which will preceed
      everything that is formatted.

      .PARAMETER NoWrap
      Describe Parameter -NoWrap: Will not process the textual part of the line but will honor
      the parameter, paramtrail, indent and initialLF parameters.

      .PARAMETER SetWindowWidth
      Describe Parameter -SetWindowWidth: This parameter determines the point in the assumbly of 
      the text line that the line will wrap. By default it is set to the width of the Interactive window
      returned from Set-Window -ProcessId $Pid -Characters. Set-Window sets this variable automatically.
      This can be overridden by setting the length here as required or using the -NoWrap option.

      .EXAMPLE
      $MyText=Format-MyTextLine -Parameter '-help' -ParamLen 10 -InitialLF "`r`n" -Text 'Will output this text.' -ParamTrail ": "

      Will return this text preceeded by a CRLF sequence to the variable $MyText:

      -help     : Will output this text.

      $MyText=Format-MyTextLine -Parameter "-help" -ParamLen 10 -InitialLF "`r`n" -Text 'Will output this text.' -ParamTrail ": " -IndentLen 4

      Will return this text preceeded by a CRLF sequence note the indent of 4 characters to the variable $MyText:

          -help : Will output this text.

      Successive calls can be used to build up one string variable by using the $MyText+=Format-MyTextLine... construct before using
      the string for whatever means.

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Format-MyTextLine

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      Returns a formatted string
  #>
  [CmdletBinding(PositionalBinding = $False)]
  Param (
    [Parameter(Mandatory = $True,HelpMessage = 'Please supply the string to Process')]
    [AllowEmptyString()]
    [String]$Text,
    [String]$Parameter = $Null,
    [String]$ParamTrail = $Null,
    [ValidatePattern('(?:[\n]+?|[\r]+?|[\r][\n]+?|^$)')]
    [AllowEmptyString()]
    [String]$InitialLF = $Null,
    [ValidateRange(0, [int]::MaxValue)]
    [int]$ParamLen = [int]0,
    [ValidateRange(0, [int]::MaxValue)]
    [int]$IndentLen = [int]0,
    [ValidateRange(0, [int]::MaxValue)]
    [int]$SetWindowWidth = [int]$Script:WindowWidth,
    [switch]$NoWrap
  )
  Function Split-MyLine
  {
    [CmdletBinding(PositionalBinding = $False)]
    Param (
      [Parameter(Mandatory = $True,HelpMessage = 'Please supply the string to Process',ValueFromPipeline = $True)]
      [String]$Text
    )

    # Return text length if already within limits
    if ($Text.Length -le $Maxlen)
    { return $Text.Length }

    # Handle zero-length strings
    if ($Text.Length -le [int]0)
    {
      $Text = 'A zero length string was passed'
      return $Text.Length
    }

    # Get substring to search within
    $SearchText = $Text.Substring(0, $Maxlen)

    # Find best break point - check in priority order: CRLF, CR, LF, space
    $BreakPoints = @(
      @{Char = $Script:StrCrlf; Pos = $SearchText.LastIndexOf($Script:StrCrlf); Method = 'IndexOf'}
      @{Char = $Script:StrCr;   Pos = $SearchText.LastIndexOf($Script:StrCr);   Method = 'LastIndexOf'}
      @{Char = $Script:StrLF;   Pos = $SearchText.LastIndexOf($Script:StrLF);   Method = 'LastIndexOf'}
      @{Char = ' ';             Pos = $SearchText.LastIndexOf(' ');             Method = 'LastIndexOf'}
    )

    foreach ($BreakPoint in $BreakPoints)
    {
      if ($BreakPoint.Pos -gt [int]0 -and $BreakPoint.Pos -le $Maxlen)
      {
        # Special case for CRLF - use IndexOf instead of LastIndexOf
        if ($BreakPoint.Char -eq $Script:StrCrlf)
        { return $SearchText.IndexOf($Script:StrCrlf) }
        else
        { return $BreakPoint.Pos }
      }
    }

    # No good break point found, break at maxlen
    return $Maxlen
  }
  If ($Script:FTrace)
  {Write-MyLog -PathToLogFile $Script:FTLogFilePath -CallStack (Get-PSCallStack)}
  if ($SetWindowWidth)
  {$MyWWidth = $SetWindowWidth}
  elseif ($Script:WindowWidth)
  {$MyWWidth = $Script:WindowWidth}
  elseIf ($Script:Interactive -and -not $NoWrap) # Check that window width is set otherwise things will fail
  {$MyWWidth = (Set-Window -ProcessId $pid -Characters -Passthru).characterswide}
  ElseIf(-Not $MyWWidth)
  {
    If ($Script:LogLevel -gt [int]4)
    {Write-MyLog -PathToLogFile $Script:LogFilePath -Message 'The variable $MyWWidth has not been set! Returning a line with no text wrapping.'}
    $NoWrap = $True
  }
  if(-not $ParamLen)
  {$ParamLen = $Parameter.length} # Set the length of the parameter
  $PadRight=$ParamLen-$IndentLen # Set the value to pad the parameter to the correct length
  If ($PadRight -lt [int]0) # If negative set to zero
  {$Padright=[int]0}
  $ParamTrailLen = $ParamTrail.Length # Get length of the ParamTrail passed
  $Maxlen = $MyWWidth-($ParamLen+$ParamTrailLen) # Set the value for the longest text length before wrap required
  If ($Parameter.Length -gt $ParamLen)
  {$Maxlen=$Maxlen -($Parameter.Length-$ParamLen)}
  $MinWindowWidth = $ParamLen+$ParamTrailLen+20 # What has to be left after the intial formatting to wrap the text
  $FirstLine = $True # This is the first line of this call
    
  if ($MinWindowWidth -gt $MyWWidth) # If NoWrap or space left to wrap text < 20 dont wrap
  {
    If ($Script:LogLevel -gt [int]4)
    {Write-MyLog -PathToLogFile $Script:LogFilePath -Message 'No line wrapping window not wide enough!'}
    $NoWrap=$True
  }
  
  [String]$TextOut = $Null # Set output string to no content
  $TextOut += ('{0}{1}{2}' -f ''.Padleft($IndentLen), $Parameter.PadRight($PadRight), $ParamTrail)
    
  if ($NoWrap)
  {$TextOut += ('{0}' -f $Text)}
  else # Proces the line
  {
    $Text = $Text.Trim() # Remove leading and trailing white space
    Write-Debug -Message ('Width:[{0}], Height:[{1}]' -f $MyWWidth, $Script:WindowHeight)
    Write-Verbose -Message ('{0}' -f $Text)
    if ($Text.Length -le $Maxlen) # if text less than max length
    {$TextOut += ('{0}' -f $Text)}
    else # Text line is greater than max length (available space)
    {
      while ($Text.Length -gt $Maxlen) # if the text line is longer that max width see where we can split it nicely
      {
        $Position = $Text|Split-MyLine
        If ($FirstLine)
        {
          $TextOut += ('{0}' -f $Text.Substring(0, $Position))
          $FirstLine = $False
        }
        else
        {$TextOut += ('{0}{1}{2}' -f $Script:StrCrlf, ''.PadLeft($ParamLen+$ParamTrailLen), $Text.Substring(0, $Position))}
        $Text = $Text.Substring($Position).trim() # remove start of the text we have already processed and remove white space
      }
      $TextOut += ('{0}{1}{2}' -f $Script:StrCrlf, ''.PadLeft($ParamLen+$ParamTrailLen), $Text)
    }
  }
  ('{0}{1}' -f $InitialLF, $TextOut) # return result
}