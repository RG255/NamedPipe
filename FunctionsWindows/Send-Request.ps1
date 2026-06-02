Function Send-Request
{
  <#
    .SYNOPSIS
    Assembles and sends a request from the client to the server through the named pipe.

    .DESCRIPTION
    Prepares a DataObject with the specified request and type, sends it to the server
    via Send-Data, and waits for the response. Handles error conditions and progress
    information from the server.

    This function is the primary client-side interface for communicating with the server.
    It supports three request types: ScriptBlock (execute commands), Security (query pipe ACLs),
    and ExitPipe (close the connection).

    Typically called using pipeline syntax:
      'Get-Process' | Send-Request @SendRequestParams

    .PARAMETER Request
    The command string or scriptblock text to send to the server for execution.
    Accepts pipeline input. For ExitPipe requests, pass $Null or an empty string.

    .PARAMETER Type
    The type of request: 'ScriptBlock' to execute commands, 'Security' to query
    pipe access control, or 'ExitPipe' to close the connection.

    .PARAMETER PipeInfo
    The pipe connection object containing Writer, Reader, and connection metadata.

    .PARAMETER DataObject
    The data structure used for client-server communication. Contains fields for
    request, result, error, parameters, and process identity information.

    .PARAMETER NoExitOnError
    When specified, displays errors but continues execution instead of calling
    Exit-Pipe to close the connection.

    .EXAMPLE
    $SendRequestParams.DataObject = 'Get-Process | Select-Object -First 5' |
    Send-Request @SendRequestParams
    Sends a ScriptBlock request to execute Get-Process on the server.

    .EXAMPLE
    $SendRequestParams.Type = 'Security'
    $SendRequestParams.DataObject = '' | Send-Request @SendRequestParams
    Queries the pipe's security/ACL information.

    .EXAMPLE
    $SendRequestParams.Type = 'ExitPipe'
    $SendRequestParams.DataObject = $Null | Send-Request @SendRequestParams
    Closes the pipe connection and exits the server.

    .INPUTS
    System.String - The request command via pipeline.

    .OUTPUTS
    The DataObject with the server's response in the Result property,
    or error information in the Error property.
  #>


	[CmdletBinding()]
	param
	(
		[Parameter(ValueFromPipeline ,Mandatory,HelpMessage = 'Please supply the request String')]
		[Allowemptystring()]
		[String]$Request,
		[Parameter(Mandatory,HelpMessage = 'Please supply the Type For this command')]
		[Validateset('Security', 'ScriptBlock', 'ExitPipe', 'Disconnect')]
		[Validatescript({
					$_ -imatch $StrSecurity -or
					$_ -imatch $StrScriptBlock -or
					$_ -imatch $StrExitPipe -or
					$_ -imatch $StrDisconnect
		})]
		[String]$Type,
		[Parameter(Mandatory,HelpMessage = 'Please supply the PipeInfo Object')]
		$PipeInfo,
		[Parameter(Mandatory,HelpMessage = 'Please supply the Data Object')]
		$DataObject,
		[Switch]$NoExitOnError
	)
	$Private:ProgressInfo = $False
	$DataObject.$StrType = $Type
	$DataObject.$StrRequest = $Request
	$DataObject = Send-Data -DataObject $DataObject -PipeInfo $PipeInfo
	do
	{
		If ($Private:ProgressInfo)
		{$DataObject = Receive-Data -PipeInfo $PipeInfo -ErrorAction Stop}
		$Private:ProgressInfo = $False
		if ($DataObject.$Strerror)
		{
			If ($NoExitOnError)
			{Write-Information -MessageData $DataObject.Error -InformationAction Continue}
			# Always return DataObject with error to caller - never auto-exit the pipe.
			# Callers check $DataObject.$StrError and decide what to do (rollback, Stop-PipeSession, etc.)
		}
		If ($DataObject.$StrProgressInfo)
		{
			$Private:ProgressInfo = $True
			Switch ($DataObject.$StrType)
			{
				$StrConsole
				{Write-Information -MessageData ('{0}' -f $DataObject.$StrProgressInfo) -InformationAction Continue}
				$StrConsoleStop
				{Write-Information -MessageData ('{0}' -f $DataObject.$StrProgressInfo) -InformationAction stop}
			}
		}
	}
	while ($Private:ProgressInfo)
	# Rotate completed request to Last* fields so stale data doesn't confuse debugging
	$DataObject.$StrLastRequest    = $DataObject.$StrRequest
	$DataObject.$StrLastParameters = $DataObject.$StrParameters
	$DataObject.$StrLastData       = $DataObject.$StrData
	$DataObject.$StrRequest        = $Null
	$DataObject.$StrParameters     = $Null
	$DataObject.$StrData           = $Null
	$DataObject
}
