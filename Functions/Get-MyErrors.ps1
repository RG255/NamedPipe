# VENDORED from CommonScripts\0.2\Functions\Get-MyErrors.ps1 by Sync-SharedUtilities [SHA256 7AC45CE9830B9DD9320AA33F40339ED7941409BDF20B533D0D9A58325E79BDF0] - DO NOT EDIT (edit the master; Deploy-Modules re-syncs).
Function Get-MyErrors
{
	<#
		.SYNOPSIS
		Formats and optionally logs errors from the global error collection.

		.DESCRIPTION
		Processes the $Global:Error collection and formats each error with detailed
		information: line number, offset, exception message, stack trace, and other
		diagnostic details. Errors are formatted using Format-MyTextLine for
		consistent, readable output.

		By default, clears $Global:Error after processing. Use -PreserveErrors to
		keep the error collection intact.

		Bounded by default (2026-08-29, after a live incident: a long-lived elevated
		NamedPipe server's $Global:Error accumulated several benign, locally-caught
		errors across a multi-step operation; the next unrelated failure's report
		dumped the WHOLE collection with full stack traces, and that ballooning text
		fed into a downstream parameter-escaping call that hit OutOfMemoryException,
		taking the server process to 25GB+ before it was killed. See memory
		project_namedpipe_oom_error_cascade_2026_08_29 for the full incident). Only
		the MOST RECENT errors are formatted, each error's stack trace is capped, and
		a hard overall-length backstop applies regardless of the other two caps - so
		no caller can ever receive an unbounded report no matter how many errors, or
		how deep a single stack trace, feeds this. Existing callers get this for free
		with no changes; nothing relying on -Return output was relying on UNBOUNDED
		historical detail, only on what actually failed.

		.PARAMETER Indent
		Indentation level for error details. Default: 5.

		.PARAMETER Return
		When specified, returns the formatted error text as a string.
		Without this switch, errors are only logged (if PathToLogFile is set).

		.PARAMETER PreserveErrors
		When specified, does not clear $Global:Error after processing.

		.PARAMETER PathToLogFile
		Full path to the log file. If empty or null, logging is skipped.

		.PARAMETER MaxErrors
		Maximum number of MOST RECENT errors to format. Default: 10. The rest of
		$Global:Error is still cleared as normal (unless -PreserveErrors) - this only
		bounds how much gets FORMATTED/returned/logged in one call.

		.PARAMETER MaxStackTraceLength
		Maximum characters kept from each error's ScriptStackTrace. Default: 2000
		(normally 10-15 stack frames - enough to identify where something failed).
		Longer traces are truncated with a marker noting how much was cut.

		.PARAMETER MaxTotalLength
		Hard cap, in characters, on the total formatted output regardless of the two
		caps above. Default: 32768 (32KB). A backstop, not the primary control - the
		MaxErrors/MaxStackTraceLength defaults should normally stay well under this.

		.EXAMPLE
		Get-MyErrors -Return
		Returns the most recent errors (bounded) as a formatted string.

		.EXAMPLE
		Get-MyErrors -Return -PreserveErrors
		Returns errors as a formatted string without clearing the error collection.

		.EXAMPLE
		Get-MyErrors -Return -MaxErrors 25 -MaxStackTraceLength 5000
		Widens the caps for a deeper one-off diagnostic dump.

		.NOTES
		Version: 1.28 2026-08-29

		.OUTPUTS
		System.String - When -Return is specified, returns formatted error text.
	#>

	[CmdletBinding(PositionalBinding = $False)]
	Param (
		[Int]$Indent = [int]5,
		[Switch]$Return,
		[Switch]$PreserveErrors,
		[String]$PathToLogFile = '',
		[Int]$MaxErrors = 10,
		[Int]$MaxStackTraceLength = 2000,
		[Int]$MaxTotalLength = 32768
	)

	$Private:ParamLen       = $Indent + 18
	$Private:NumberOfErrors = [int]$Global:Error.Count
	$Private:ErrorsToShow   = [Math]::Min($Private:NumberOfErrors, [Math]::Max($MaxErrors, 0))
	$Private:ErrorNumber    = $Private:NumberOfErrors - 1
	$Local:InternalError    = $True
	$Private:Err            = [System.Text.StringBuilder]''
	$Private:Shown          = [int]0
	$Private:LengthCapped   = $False

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

	While (([int]$Private:ErrorNumber -ge [int]0) -and ($Private:Shown -lt $Private:ErrorsToShow) -and (-not $Private:LengthCapped))
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

				$Private:Text = '{0}' -f $Private:Value
				# Cap each error's own stack trace independently - the single most likely field
				# to be unexpectedly huge (deep nested elevated-pipe call chains).
				if ($Private:Prop.Name -eq 'Stack Trace' -and $Private:Text.Length -gt $MaxStackTraceLength)
				{
					$Private:OmittedChars = $Private:Text.Length - $MaxStackTraceLength
					$Private:Text = '{0} ...(truncated, {1} more char(s))' -f $Private:Text.Substring(0, $MaxStackTraceLength), $Private:OmittedChars
				}

				$null = $Private:Err.AppendLine((
					Format-MyTextLine -ErrorAction SilentlyContinue @Private:Params `
						-Parameter $Private:Prop.Name `
						-Text $Private:Text
				))
			}
		}

		# Handle internal errors during processing
		if ([int]$Global:Error.Count -gt $Private:NumberOfErrors -and $Local:InternalError)
		{
			$Private:NumberOfErrors = [int]$Global:Error.Count
			$Private:ErrorsToShow   = [Math]::Min($Private:NumberOfErrors, [Math]::Max($MaxErrors, 0))
			$Private:ErrorNumber    = [int]$Global:Error.Count - 2
			$Local:InternalError    = $False
			Write-MyLog -PathToLogFile $PathToLogFile -Message 'An error occurred processing the error collection'
		}
		else
		{ $Private:ErrorNumber-- }

		$Private:Number++
		$Private:Shown++

		# Hard backstop - stop regardless of MaxErrors/MaxStackTraceLength if the total is
		# already large. Checked AFTER appending the current entry so an in-progress entry is
		# never cut mid-property; the next iteration's loop condition then exits cleanly.
		if ($Private:Err.Length -ge $MaxTotalLength)
		{ $Private:LengthCapped = $True }

		# Add separator between errors
		if (([int]$Private:ErrorNumber -ge [int]0) -and ($Private:Shown -lt $Private:ErrorsToShow) -and (-not $Private:LengthCapped))
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

	# Note when the report is not the full picture - either more errors existed than MaxErrors
	# allowed, or the hard length backstop cut the run short.
	if (($Private:NumberOfErrors -gt $Private:Shown) -or $Private:LengthCapped)
	{
		$null = $Private:Err.AppendLine((
			Format-MyTextLine -IndentLen 0 -ParamLen 9 -InitialLF "`r`n" -Parameter 'Note' `
				-Text ('Showing the {0} most recent of {1} error(s); older ones omitted{2}.' -f
					$Private:Shown, $Private:NumberOfErrors,
					$(If ($Private:LengthCapped) { ' (report length cap reached)' } Else { '' }))
		))
	}

	# Log errors if a log path is configured and errors exist
	if ($Private:NumberOfErrors -gt 0 -and -not [String]::IsNullOrWhiteSpace($PathToLogFile))
	{ Write-MyLog -PathToLogFile $PathToLogFile -Message $Private:Err.ToString() }

	if (-not $PreserveErrors)
	{ $Global:Error.Clear() }

	if ($Return)
	{ $Private:Err.ToString() }
}
