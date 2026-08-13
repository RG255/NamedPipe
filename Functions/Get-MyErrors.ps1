# VENDORED from CommonScripts\0.2\Functions\Get-MyErrors.ps1 by Sync-SharedUtilities [SHA256 AE483C09CC43C1D100EDA69C84C823044B03C6587343FF52001BBB6ED25CAEBA] - DO NOT EDIT (edit the master; Deploy-Modules re-syncs).
Function Get-MyErrors
{
	<#
		.SYNOPSIS
		Formats and optionally logs all errors from the global error collection.

		.DESCRIPTION
		Processes the $Global:Error collection and formats each error with detailed
		information: line number, offset, exception message, stack trace, and other
		diagnostic details. Errors are formatted using Format-MyTextLine for
		consistent, readable output.

		By default, clears $Global:Error after processing. Use -PreserveErrors to
		keep the error collection intact.

		.PARAMETER Indent
		Indentation level for error details. Default: 5.

		.PARAMETER Return
		When specified, returns the formatted error text as a string.
		Without this switch, errors are only logged (if PathToLogFile is set).

		.PARAMETER PreserveErrors
		When specified, does not clear $Global:Error after processing.

		.PARAMETER PathToLogFile
		Full path to the log file. If empty or null, logging is skipped.

		.PARAMETER LogLevel
		Minimum log level required to write errors to the log. Default: 0.

		.EXAMPLE
		Get-MyErrors -Return
		Returns all errors as a formatted string.

		.EXAMPLE
		Get-MyErrors -Return -PreserveErrors
		Returns errors as a formatted string without clearing the error collection.

		.NOTES
		Version: 1.27 2026-02-03

		.OUTPUTS
		System.String - When -Return is specified, returns formatted error text.
	#>

	[CmdletBinding(PositionalBinding = $False)]
	Param (
		[Int]$Indent = [int]5,
		[Switch]$Return,
		[Switch]$PreserveErrors,
		[String]$PathToLogFile = ''
	)

	$Private:ParamLen       = $Indent + 18
	$Private:NumberOfErrors = [int]$Global:Error.Count
	$Private:ErrorNumber    = $Private:NumberOfErrors - 1
	$Local:InternalError    = $True
	$Private:Err            = [System.Text.StringBuilder]''

	$Private:Params = @{
		IndentLen  = $Indent
		ParamLen   = $Private:ParamLen
		ParamTrail = ': '
	}

	# Property mapping table
	$Private:PropertyMap = @(
		@{ Name = 'Line No.';          Path = 'InvocationInfo.ScriptLineNumber' }
		@{ Name = 'Offset';            Path = 'InvocationInfo.OffsetInLine' }
		@{ Name = 'Line';              Path = 'InvocationInfo.Line' }
		@{ Name = 'Target Object';     Path = 'TargetObject' }
		@{ Name = 'Full Error ID';     Path = 'FullyQualifiedErrorId' }
		@{ Name = 'Message';           Path = 'Exception.Message'; Transform = { $_.Replace("`r`n", '') } }
		@{ Name = 'Command Path';      Path = 'InvocationInfo.PSCommandPath' }
		@{ Name = 'Exception Type';    Path = 'Exception'; Transform = { $_.GetType().FullName } }
		@{ Name = 'Full Error Reason'; Path = 'FullyQualifiedErrorId'; Transform = { ($_ -split ',')[0] } }
		@{ Name = 'Stack Trace';       Path = 'ScriptStackTrace' }
	)

	$Private:Number = [int]1

	While ([int]$Private:ErrorNumber -ge [int]0)
	{
		$Private:CurrentError = $Global:Error[$Private:ErrorNumber]

		# Error header
		$null = $Private:Err.AppendLine((Format-MyTextLine -IndentLen 0 -ParamLen 9 -Parameter ("`r`nError No") -Text ('{0}' -f $Private:Number)))

		# Process each property from the mapping table
		foreach ($Private:Prop in $Private:PropertyMap)
		{
			$Private:Value = $Private:CurrentError
			foreach ($Private:Part in $Private:Prop.Path -split '\.')
			{
				if ($null -ne $Private:Value)
				{ $Private:Value = $Private:Value.$Private:Part }
			}

			if ($Private:Value)
			{
				if ($Private:Prop.Transform)
				{ $Private:Value = $Private:Value | ForEach-Object $Private:Prop.Transform }

				$null = $Private:Err.AppendLine((
					Format-MyTextLine -ErrorAction SilentlyContinue @Private:Params `
						-Parameter $Private:Prop.Name `
						-Text ('{0}' -f $Private:Value)
				))
			}
		}

		# Handle internal errors during processing
		if ([int]$Global:Error.Count -gt $Private:NumberOfErrors -and $Local:InternalError)
		{
			$Private:NumberOfErrors = [int]$Global:Error.Count
			$Private:ErrorNumber    = [int]$Global:Error.Count - 2
			$Local:InternalError    = $False
			Write-MyLog -PathToLogFile $PathToLogFile -Message 'An error occurred processing the error collection'
		}
		else
		{ $Private:ErrorNumber-- }

		$Private:Number++

		# Add separator between errors
		if ([int]$Private:ErrorNumber -ge [int]0)
		{
			$Private:Params.ParamTrail = ''
			$Private:Params.IndentLen  = [int]0
			$null = $Private:Err.AppendLine((
				Format-MyTextLine @Private:Params `
					-InitialLF "`r`n" `
					-Parameter ('{0}' -f $(''.PadRight($Private:ParamLen).Replace(' ', '_'))) `
					-Text ''
			))
			$Private:Params.ParamTrail = ': '
			$Private:Params.IndentLen  = $Indent
		}
	}

	# Log errors if a log path is configured and errors exist
	if ($Private:NumberOfErrors -gt 0 -and -not [String]::IsNullOrWhiteSpace($PathToLogFile))
	{ Write-MyLog -PathToLogFile $PathToLogFile -Message $Private:Err.ToString() }

	if (-not $PreserveErrors)
	{ $Global:Error.Clear() }

	if ($Return)
	{ $Private:Err.ToString() }
}
