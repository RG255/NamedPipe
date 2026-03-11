Function Write-MyLog
{
  <#
      .SYNOPSIS
      This function will write details passed to it into a predefined log file It is also
      Capable of writing function tracing information gained from the CallStack data passed

      .DESCRIPTION
      As above but: If any errors have been generated it will also output those to the log file

      .PARAMETER PathToLogFile
      -PathToLogFile.
      Is what it says, a fully qualified path to a file to which textual data can be written

      .PARAMETER Message
      -Message.
      Is the information you wish to have written to the log file

      .PARAMETER CallStack
      -CallStack.
      For full function call tracing this is the output from get-callstack at the
      time of calling write-mylog.
      The method of inplementing this is to include the following two lines at the start of
      every function you wish to trace:

      If ($Script:FTrace)
      {Write-MyLog -PathToLogFile $LogFilePath -CallStack (Get-PSCallStack)}

      you can either code the relevant details into your script by:
      Setting $Script:LogLevel=$Script:MaxLogLevel and $LogFilePath=<A full path and filename>

      Alternatively

      If the RayG-Module is loaded you can use the function:
    
      Trace-MyFunctionCalls

      This function takes four parameters:

      -Off - to turn off function call tracing
      -On  - to turn on function call tracing

      -On requires two further parameters:
      -LogfilePath - this requires a full path to the location of the file where tracing information will be written
      -LogFileOption - this takes 3 options Test, Create, CreatePath
      Test - just ensures the log file exists
      Create - Will create the log file so long as the path exists
      CreatePath - Will create the path and the log file if required
 
      .PARAMETER Encoding
      -Encoding.
      The Default for this is UTF8 which is the most suitable option however you can override it
      with your choice of encoding

      .PARAMETER Console
      -Console.
      If present will output the same information to the console provided it is interactive

      .EXAMPLE
      Write-MyLog -PathToLogFile Value -Message Value [-Encoding Value, -Console]
      Usually used in line with code to pop useful information into a log file
    
      .EXAMPLE
      Write-MyLog -PathToLogFile Value -CallStack Value [-Encoding Value, -Console]
      This is used at the start of a function as decribed above to do Function Call tracing
  #>
  [CmdletBinding(PositionalBinding = $False)]
  Param (
    [ValidateNotNullorEmpty()]
    [String]$PathToLogFile = $Script:LogFilePath, # Path To Log File
    [Parameter(ValueFromPipeline)]
    [String]$Message = $Null, # Message to output
    [Array]$CallStack = $Null, # Call stack to process
    [String]$Encoding = $Script:Encoding,
    [Switch]$Console = $Script:Console
  )
  # $FTraceInternalCall stops any functions within Write-MyLog from being recorded in the log file.
  # It assumes the user is only interested in what their script is doing rather than how Write-MyLog works
  If (-not $Script:FTraceInternalCall)
  {
    if (-not $CallStack)
    {$MyCallStack = Get-PSCallStack}
    if ([int]$MyCallStack.Count -eq [int]2)
    {
      $Private:MyErrorsCalled = $True
      If ($Script:Ftrace -and -not $Script:FTraceAllCalls)
      {$Script:FTraceInternalCall = $True}
    }
    else
    {$Private:MyErrorsCalled = $False}
    $Recurse = ((Get-PSCallStack).command -imatch 'Write-MyLog').count -ge [int]2
    # The following two lines can be uncommented for testing purposes.
    #for ($x = 0; $x -lt (Get-PSCallStack).count; $x += 1) 
    #{Write-Host -Object ('{0}: {1}' -f $x, (Get-PSCallStack).command[$x])}
    [String]$MyInfo = $Null
    [String]$CallInfo = $Null
    [String]$Private:LogFilePath = $PathToLogFile
    $MyDate = '{0} Stack Count:[{1}]' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $CallStack.Count
    # If Callstack is passed construct the required detail from the stack to output
    If ($CallStack)
    {$CallInfo = ('{0} Function:[{1}] in:[{3}] Called from:[{2}] Function:[{4}]' -f $MyDate, $CallStack.FunctionName[0], $CallStack.location[1], $CallStack.location[0].Split(':')[0], $CallStack.FunctionName[1])}
    # If Message is passed construct the required detail to output
    if ($Message)
    {$MyInfo = ('{0} {1}' -f $MyDate, $Message)} # Add current date/time to message
    If ($CallInfo)
    {Out-File -Encoding $Private:Encoding -FilePath ('{0}' -f $Private:LogFilePath) -Append -InputObject $CallInfo} # write log info to file
    If ($Message)
    {Out-File -Encoding $Private:Encoding -FilePath ('{0}' -f $Private:LogFilePath) -Append -InputObject $MyInfo} # write log info to file
    if ($Console.IsPresent -and $Script:IsConsole -and $Script:Interactive)
    {
      # Write log info to console if defined and session is interactive
      if ($CallInfo)
      {Write-Host -Object $CallInfo -ForegroundColor Cyan}
      if ($Message)
      {Write-Host -Object $MyInfo -ForegroundColor Magenta}
    }
    If (-not $Recurse -and $Script:FTrace)
    {
      if ($Script:FTraceInternalCall)
      {
        $Script:FTraceInternalCall = $False
        Write-MyLog -PathToLogFile $Script:FTLogFilePath -CallStack (Get-PSCallStack)
        $Script:FTraceInternalCall = $True
      }
      else
      {Write-MyLog -PathToLogFile $Script:FTLogFilePath -CallStack (Get-PSCallStack)}
    }
    # If errors have occured write them to the log file
    if (-not $Recurse -and $Global:Error.count -and $Private:MyErrorsCalled)
    {
      If ($Script:FTrace)
      {$Script:FTraceInternalCall = $False}
      else
      {$Script:FTraceInternalCall = $True}
      $Private:MyErrorsCalled = $False
      Out-File -Encoding $Private:Encoding -FilePath ('{0}' -f $Private:LogFilePath) -Append -InputObject (Get-MyErrors -Return)
      $Private:MyErrorsCalled = $True
    }
    # Reset internal call flag
    $Script:FTraceInternalCall = $False
  }
}
