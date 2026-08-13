Function Get-SBResult
{
	<#
		.SYNOPSIS
		Executes a scriptblock request on the server and returns the result.

		.DESCRIPTION
		Called by the server side of the pipe to execute commands received from the client.
		Takes a DataObject containing a request string (and optional parameters), creates a
		scriptblock from it, invokes it, and stores the result back in the DataObject.

		If the DataObject contains a Parameters property, these are appended to the
		scriptblock as arguments. Parameters can be a string or a hashtable (converted
		via ConvertTo-Parameters with injection-resistant escaping).

		Security: Validates scriptblock syntax before execution to detect malformed
		or suspicious commands. String parameters are escaped by ConvertTo-Parameters
		to prevent code injection.

		.PARAMETER DataObject
		The data structure containing the request to execute. Must have a Request property
		with the command string. Optionally includes Parameters and Data properties.

		.PARAMETER Command
		Alternative to DataObject - a direct command string to execute.

		.EXAMPLE
		$DataObject = Get-SBResult -DataObject $DataObject
		Executes the command in $DataObject.Request and stores output in $DataObject.Result.

		.EXAMPLE
		$Result = Get-SBResult -Command 'Get-Process | Select-Object -First 5'
		Executes the command string directly.

		.INPUTS
		DataObject - The pipe communication data structure, or a command string.

		.OUTPUTS
		The DataObject with the Result property populated, or Error property if execution failed.
	#>

	[CmdletBinding()]
	Param (
		[parameter(Mandatory,ParameterSetName = 'DataObject' ,HelpMessage = 'Pass the DataObject.')]
		$DataObject,
		[parameter(Mandatory,ParameterSetName = 'Command' ,HelpMessage = 'Pass the command line.')]
		[String]$Command
	)
	Try
	{
		$Private:ErrorActionPreferenceSave = $ErrorActionPreference
		Switch ($PsCmdlet.ParameterSetName)
		{	
			'Command'
			{$Private:Request = $Command}
			'DataObject'
			{$Private:Request = $DataObject.$StrRequest}
		}
		if ($DataObject.$StrParameters)
		{
			# Create the scriptblock with properly escaped parameters
			Switch ($DataObject.$StrParameters.gettype().Name)
			{
				'string'
				{$Private:MyArgs = '{0}' -f $DataObject.$StrParameters}
				'hashtable'
				{
					# ConvertTo-Parameters sanitizes values with proper quote escaping
					$Private:MyArgs = ConvertTo-Parameters -Hash $DataObject.$StrParameters
				}
			}
			$Private:SBText = '{0} {1}' -f $Private:Request, $Private:MyArgs
			$Private:errors = $null
			$null = [System.Management.Automation.Language.Parser]::ParseInput($Private:SBText, [ref]$null, [ref]$Private:errors)
			if ($Private:errors -and $Private:errors.Count -gt 0)
			{
				throw "Invalid scriptblock syntax: $($Private:errors[0].Message)"
			}
			$Private:SB = [ScriptBlock]::Create($Private:SBText)
		}
		Else
		{
			$Private:errors = $null
			$null = [System.Management.Automation.Language.Parser]::ParseInput($Private:Request, [ref]$null, [ref]$Private:errors)
			if ($Private:errors -and $Private:errors.Count -gt 0)
			{
				throw "Invalid scriptblock syntax: $($Private:errors[0].Message)"
			}
			$Private:SB = [ScriptBlock]::Create($Private:Request)
		}

		# --- request policy gate (0.10 injection hardening) ---
		# When the consumer supplied a RequestPolicy on the session, the request must pass the
		# default-deny AST allowlist BEFORE it runs. Validate $Private:SB.ToString() - the exact source
		# that InvokeReturnAsIs will execute (command + escaped params). No policy = unchanged behaviour.
		# See PIPE-INJECTION-HARDENING-PLAN.md and Test-RequestPolicy.
		$Private:ReqPolicy = $ServerClientParams.$StrRequestPolicy
		If ($Private:ReqPolicy)
		{
			$Private:PolicyResult = Test-RequestPolicy -Request ($Private:SB.ToString()) -Policy $Private:ReqPolicy
			If (-not $Private:PolicyResult.Allowed)
			{
				$DataObject.$StrError = ('Request blocked by pipe request policy: {0}' -f $Private:PolicyResult.Reason)
				$ErrorActionPreference = $Private:ErrorActionPreferenceSave
				Return $DataObject
			}
		}

		If ($ServerClientParams.$StrInfoDisplay -band $InfoDisplayBitVerbose)
		{Show-VerboseData -Object $Private:SB -Display -Title 'Full Scriptblock request'}
		# Echo the assembled scriptblock back to the client (bit 1 = server/client progress)
		If ($ServerClientParams.$StrInfoDisplay -band $InfoDisplayBitProgress)
		{
			$Private:DisplayStr = $Private:SB.ToString()
			$Private:RedactCfg  = $ServerClientParams.$StrRedactPattern
			If ($Private:RedactCfg -and $Private:RedactCfg.Option)
			{
				# Bit 1: built-in generic redaction -- 40+ char Base64/hex runs (quoted or bare)
				If ($Private:RedactCfg.Option -band $RedactBitBuiltIn)
				{ $Private:DisplayStr = $Private:DisplayStr -replace '[A-Za-z0-9+/=]{40,}', '<redacted>' }
				# Bit 2: consumer-supplied regex pattern
				If (($Private:RedactCfg.Option -band $RedactBitPattern) -and $Private:RedactCfg.Pattern)
				{ $Private:DisplayStr = $Private:DisplayStr -replace $Private:RedactCfg.Pattern, '<redacted>' }
				# Bit 4: consumer-supplied ScriptBlock -- receives display string, must return string
				If (($Private:RedactCfg.Option -band $RedactBitCommand) -and $Private:RedactCfg.Command)
				{ $Private:DisplayStr = & $Private:RedactCfg.Command $Private:DisplayStr }
			}
			Send-ProgressInfo -Type Console -String ('[Server] Executing: {0}' -f $Private:DisplayStr)
		}
		# NOTE 2026-08-08: two changes were tried here and REVERTED after they coincided with an elevated
		# server dying mid-request ("Pipe is broken" at the client, no server log written): an $Error.Clear()
		# before the invoke, and an "if ($Error.Count -gt 0) populate $DataObject.Error" after it. Neither is
		# needed for correctness - the non-terminating case they targeted does not reach $Error at all (see
		# memory todo_global.md, PARKED entry). Do NOT reintroduce them without isolating that crash first;
		# this file runs inside the elevated server for EVERY consumer.
		$ErrorActionPreference = 'Stop'
		$DataObject.$StrResult = $Private:SB.InvokeReturnAsIs()

		# Defensive: raw CIM/WMI objects do not round-trip through PSSerializer reliably
		# and can hang Send-Data indefinitely. Surface as a clear error instead of a hang
		# so the server function author sees what to fix (wrap return in [PSCustomObject]).
		If ($null -ne $DataObject.$StrResult)
		{
			$Private:Probe = If ($DataObject.$StrResult -is [System.Collections.IEnumerable] -and $DataObject.$StrResult -isnot [String])
			{ @($DataObject.$StrResult) | Select-Object -First 1 }
			Else { $DataObject.$StrResult }
			If ($null -ne $Private:Probe)
			{
				$Private:TypeName = $Private:Probe.GetType().FullName
				If ($Private:TypeName -like 'Microsoft.Management.Infrastructure.CimInstance*' -or
					$Private:TypeName -like 'System.Management.ManagementObject*' -or
					$Private:TypeName -like 'System.Management.ManagementBaseObject*' -or
					$Private:TypeName -like 'Microsoft.PowerShell.Cmdletization.GeneratedTypes.*')
				{
					$DataObject.$StrResult = $null
					$DataObject.$StrError = ('Server function returned a non-serializable type ({0}). Wrap it in [PSCustomObject] with typed primitive properties before returning, or PSSerializer will hang or truncate the result.' -f $Private:TypeName)
				}
			}
		}
	}
	Catch
	{
		$ErrorActionPreference = $Private:ErrorActionPreferenceSave
		$DataObject.$StrError = NamedPipe\Get-MyErrors -Return
	}
	$ErrorActionPreference = $Private:ErrorActionPreferenceSave
	$DataObject
}
