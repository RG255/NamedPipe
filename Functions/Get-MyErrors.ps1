Function Get-MyErrors
{
	<#
		.SYNOPSIS
		Formats and optionally logs all errors from the global error collection.

		.DESCRIPTION
		Processes the $Global:Error collection and formats each error with detailed
		information including line number, offset, exception message, stack trace,
		and other diagnostic details. Errors are formatted using Format-MyTextLine
		for consistent, readable output.

		By default, clears $Global:Error after processing. Use -PreserveErrors to
		keep the error collection intact.

		.PARAMETER LinePad
		The padding width for formatting output lines. Default is 5.

		.PARAMETER Indent
		The indentation level for error details. Default is 5.

		.PARAMETER Return
		When specified, returns the formatted error text as a string.
		Without this switch, errors are only logged (if logging is enabled).

		.PARAMETER PreserveErrors
		When specified, does not clear $Global:Error after processing.
		By default, errors are cleared after being processed.

		.EXAMPLE
		Get-MyErrors -Return
		Returns all errors as a formatted string.

		.EXAMPLE
		Get-MyErrors -Return -PreserveErrors
		Returns all errors as a formatted string without clearing the error collection.

		.EXAMPLE
		Get-MyErrors -Indent 10
		Processes and logs errors with a 10-character indentation.

		.NOTES
		Version: 1.27 2026-02-03
		- Refactored repetitive property checks into a maintainable mapping table
		- Added -PreserveErrors parameter to optionally keep error collection
		- Fixed variable reference bug in internal error logging
		- Updated documentation

		.OUTPUTS
		System.String - When -Return is specified, returns formatted error text.
	#>

	[CmdletBinding(PositionalBinding = $False)]
	Param (
		[Int]$LinePad = [int]5,
		[Int]$Indent = [int]5,
		[switch]$Return = $False,
		[switch]$PreserveErrors = $False
	)

	Set-Variable -Name Get-MyErrorsVersion -Value ('1.27 2026-02-03')

	If ($Script:FTrace)
	{Write-MyLog -PathToLogFile $Script:FTLogFilePath -CallStack (Get-PSCallStack)}

	$Private:ParamLen = $Indent + 18
	$Private:NumberOfErrors = [int]$Global:Error.count
	$Private:ErrorNumber = $Private:NumberOfErrors - 1
	$Local:InternalError = $True
	$Private:Err = [System.Text.StringBuilder]''

	$Private:Params = @{
		IndentLen  = $Indent
		ParamLen   = $Private:ParamLen
		ParamTrail = ': '
	}

	# Property mapping table - makes it easy to add/remove/modify error properties
	# Each entry: @{ Name = 'Display Name'; Path = 'Property.Path'; Transform = {optional scriptblock} }
	$Private:PropertyMap = @(
		@{ Name = 'Line No.';         Path = 'InvocationInfo.ScriptLineNumber' }
		@{ Name = 'Offset';           Path = 'InvocationInfo.OffsetInLine' }
		@{ Name = 'Line';             Path = 'InvocationInfo.Line' }
		@{ Name = 'Target Object';    Path = 'TargetObject' }
		@{ Name = 'Full Error ID';    Path = 'FullyQualifiedErrorId' }
		@{ Name = 'Message';          Path = 'Exception.Message'; Transform = { $_.Replace($Script:StrCRLF, '') } }
		@{ Name = 'Command Path';     Path = 'InvocationInfo.PSCommandPath' }
		@{ Name = 'Exception Type';   Path = 'Exception'; Transform = { $_.GetType().FullName } }
		@{ Name = 'Full Error Reason'; Path = 'FullyQualifiedErrorId'; Transform = { ($_ -split ',')[0] } }
		@{ Name = 'Stack Trace';      Path = 'ScriptStackTrace' }
	)

	$Number = [int]1

	While ([int]$Private:ErrorNumber -ge [int]0)
	{
		$Private:CurrentError = $Global:Error[$Private:ErrorNumber]

		# Error header
		$Null = $Private:Err.AppendLine((Format-MyTextLine -IndentLen 0 -ParamLen 9 -Parameter ('{0}Error No' -f $StrCRLF) -Text ('{0}' -f $Number)))

		# Process each property from the mapping table
		foreach ($Private:Prop in $Private:PropertyMap)
		{
			# Navigate the property path
			$Private:Value = $Private:CurrentError
			foreach ($Private:Part in $Private:Prop.Path -split '\.')
			{
				if ($Null -ne $Private:Value)
				{$Private:Value = $Private:Value.$Private:Part}
			}

			# If value exists, format and append
			if ($Private:Value)
			{
				# Apply transform if specified
				if ($Private:Prop.Transform)
				{$Private:Value = $Private:Value | ForEach-Object $Private:Prop.Transform}

				$Null = $Private:Err.AppendLine((
					Format-MyTextLine -ErrorAction SilentlyContinue @Private:Params `
						-Parameter $Private:Prop.Name `
						-Text ('{0}' -f $Private:Value)
				))
			}
		}

		# Handle internal errors during processing
		If ([int]$Global:Error.count -gt $Private:NumberOfErrors -and $Local:InternalError)
		{
			$Private:NumberOfErrors = [int]$Global:Error.count
			$Private:ErrorNumber = [int]$Global:Error.count - 2
			$Local:InternalError = $False
			Write-MyLog -PathToLogFile $Script:LogFilePath -Message 'An error occurred processing error collection'
		}
		else
		{$Private:ErrorNumber--}

		$Number++

		# Add separator between errors
		if ([int]$Private:ErrorNumber -ge [int]0)
		{
			$Private:Params.ParamTrail = ''
			$Private:Params.IndentLen = [int]0
			$Null = $Private:Err.AppendLine((Format-MyTextLine @Private:Params -InitialLF ('{0}' -f $Script:StrCRLF) -Parameter ('{0}' -f $(''.PadRight($Private:ParamLen).Replace(' ','_'))) -Text ''))
			$Private:Params.ParamTrail = ':'
			$Private:Params.Indentlen = $Indent
		}
	}

	# Log errors if logging is enabled
	If ($Private:NumberOfErrors -gt 0 -and ($Script:LogLevel -gt [int]0 -or $Script:FTrace) -and -not (Assert-file -InputObject $Script:LogFilePath -Option Test))
	{
		$Script:FTraceInternalCall = $False
		Write-MyLog -PathToLogFile $Script:LogFilePath -Message $Private:Err.tostring()
	}

	# Clear errors unless PreserveErrors is specified
	if (-not $PreserveErrors)
	{$Global:Error.Clear()}

	# Return formatted text if requested
	if ($Return)
	{$Private:Err.tostring()}
}
