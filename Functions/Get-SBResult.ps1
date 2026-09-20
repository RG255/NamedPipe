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
		via ConvertTo-ParameterSet with injection-resistant escaping).

		Security: Validates scriptblock syntax before execution to detect malformed
		or suspicious commands. String parameters are escaped by ConvertTo-ParameterSet
		to prevent code injection.

		.PARAMETER DataObject
		The data structure containing the request to execute. Must have a Request property
		with the command string. Optionally includes Parameters and Data properties.

		When DataObject.Data is populated, its value is closure-injected so it never appears anywhere
		in the built command's text (console echo, trace log, or a raw scriptblock dump). This is a
		generic out-of-band channel: Get-SBResult never inspects, decodes, or has any opinion about
		what Data holds - that is entirely the invoked command's own concern. Whether it is also
		appended as a literal '-Data:$Data' argument depends on the shape of Request:
		  - Parameters set, OR Request is a single line (no embedded newline): appended automatically,
		    so a named function (with or without other Parameters) can receive it as an ordinary bound
		    -Data parameter, including a Mandatory one.
		  - Request spans multiple lines (a genuine multi-statement script body): never appended -
		    appending would corrupt whatever the LAST line happens to be. The script body itself
		    references $Data/$Data.<Key> directly wherever it needs to; the closure alone makes that
		    resolvable without anything needing to pass it explicitly.
		Either way, a Request that does not actually use -Data/$Data when Data was populated, or that
		does not declare a -Data parameter it was just handed, fails with a normal parameter-binding
		or runtime error - Get-SBResult does not try to prevent or paper over that.

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
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'Data', Justification = '$Data is read only via GetNewClosure() capture, then via a bare $Data reference inside the dynamically-built scriptblock text invoked further down - PSScriptAnalyzer cannot see either as a use, only a textual reference within this function body.')]
	Param (
		[parameter(Mandatory,ParameterSetName = 'DataObject' ,HelpMessage = 'Pass the DataObject.')]
		$DataObject,
		[parameter(Mandatory,ParameterSetName = 'Command' ,HelpMessage = 'Pass the command line.')]
		[String]$Command
	)
	If (1 -band ($env:MyFunctionTraceEnabled -as [Int])) { Write-MyFunctionTrace }

	# Captured OUTSIDE the Try so the Finally can always restore it. The server process is
	# long-lived and this preference is GLOBAL - leaking 'Stop' into it would change the
	# behaviour of every later request, and of the server's own teardown code.
	$Private:GlobalEapSave = $global:ErrorActionPreference

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
					# ConvertTo-ParameterSet sanitizes values with proper quote escaping
					$Private:MyArgs = ConvertTo-ParameterSet -Hash $DataObject.$StrParameters
				}
			}
			$Private:SBText = '{0} {1}' -f $Private:Request, $Private:MyArgs
			# Out-of-band data channel: when the consumer populated DataObject.Data, append one
			# fixed, generic argument rather than embedding the value anywhere in this text. Get-SBResult
			# has no opinion about what .Data holds (a password, a whole config file, anything else) -
			# it only ever appears here as a bare variable reference, never a literal value, so there is
			# nothing for the console echo, the trace-log Detail: line, or a raw Show-VerboseData dump
			# (all of which show this exact text) to expose. See DataObject.Data in the NamedPipe docs.
			If ($DataObject.$StrData) { $Private:SBText += ' -Data:$Data' }
			$Private:errors = $null
			$null = [System.Management.Automation.Language.Parser]::ParseInput($Private:SBText, [ref]$null, [ref]$Private:errors)
			if ($Private:errors -and $Private:errors.Count -gt 0)
			{
				# Caught by this function's OWN outer Catch (bottom of the function) and converted to
				# $DataObject.$StrError - never escapes to crash the server or collapse the pipe. This
				# is just the idiomatic way to jump to that Catch from inside the Try.
				throw "Invalid scriptblock syntax: $($Private:errors[0].Message)"
			}
			$Private:SB = [ScriptBlock]::Create($Private:SBText)
			If ($DataObject.$StrData)
			{
				# $Data MUST be a plain local, NOT $Private: - GetNewClosure() only captures plain
				# locals; a $Private:-scoped variable silently resolves to $null inside the closure
				# with no error (confirmed empirically). Do not "tidy" this to $Private:Data to match
				# the rest of this file's convention - that would silently reintroduce the bug. There
				# is no runtime check that can catch this here: the failure only manifests inside the
				# INVOKED function's own view of $Data, after this function has already handed off
				# control - see Tools\Tests\Test-InvokeResultShape.ps1 for the regression coverage.
				$Data = $DataObject.$StrData   # AS-IS, no decoding - NamedPipe never inspects this
				$Private:SB = $Private:SB.GetNewClosure()
			}
		}
		Else
		{
			# 2026-09-17, settled: '-Data:$Data' is appended here unconditionally whenever .Data is
			# populated, exactly like the -Parameters branch above - no attempt to detect whether the
			# request is a single command or a genuine multi-statement body first (earlier revisions
			# of this file tried exactly that, first via a newline check, then via full AST
			# statement-counting - both removed). NamedPipe does not own the question of whether a
			# given Request can safely take a trailing -Data argument; that is entirely the
			# CONSUMER's responsibility to get right, the same way it already owns getting any other
			# aspect of its own Request text right. A consumer that wants a genuine multi-statement
			# script body must not populate .Data for that request at all if the body cannot accept
			# the appended argument - this repo's own consumers (VHDTools, VaultTools) instead keep
			# every elevated dispatch to the single-command-plus-parameters shape for exactly this
			# reason (see e.g. VHDTools' ChangePassword flow and VaultTools' BitLocker command
			# templates, both rewritten away from multi-statement bodies this same session). $Data
			# stays closure-resolvable inside the request body regardless of whether the append was
			# syntactically valid for it - a request that references $Data directly instead of
			# relying on -Data being bound still works.
			If ($DataObject.$StrData) { $Private:Request += ' -Data:$Data' }
			$Private:errors = $null
			$null = [System.Management.Automation.Language.Parser]::ParseInput($Private:Request, [ref]$null, [ref]$Private:errors)
			if ($Private:errors -and $Private:errors.Count -gt 0)
			{
				# Same as the -Parameters branch above: caught by this function's own outer Catch and
				# converted to $DataObject.$StrError - never escapes to crash the server or collapse
				# the pipe.
				throw "Invalid scriptblock syntax: $($Private:errors[0].Message)"
			}
			$Private:SB = [ScriptBlock]::Create($Private:Request)
			If ($DataObject.$StrData)
			{
				# See the matching comment in the Parameters branch above - same requirement applies.
				$Data = $DataObject.$StrData
				$Private:SB = $Private:SB.GetNewClosure()
			}
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

		# 2026-09-16: this block now serves TWO independent consumers of the same redacted request
		# string - the pre-existing console echo (bit 1 = server/client progress) AND the new
		# function-trace Detail: line (tracing bit 2). Merged into one shared trigger/computation
		# rather than two separate blocks, after finding live that reusing a variable assigned only
		# INSIDE the old InfoDisplay-gated block would silently go empty for the trace-log output
		# whenever a consumer has tracing on but InfoDisplay progress off - the common case, since most
		# consumers never touch console verbosity.
		If (($ServerClientParams.$StrInfoDisplay -band $InfoDisplayBitProgress) -or
			(2 -band ($env:MyFunctionTraceEnabled -as [Int])))
		{
			$Private:DisplayStr = $Private:SB.ToString()
			$Private:RedactCfg  = $ServerClientParams.$StrRedactPattern

			# Bit 1 (built-in generic redaction), 0.15: replaced the earlier blind "40+ char
			# base64/hex-shaped run" regex with a REAL structural base64 check - the old version could
			# not tell a real secret from a legitimate long value that merely looked base64-shaped (a
			# hash, a GUID chain, any coincidentally shaped non-secret blob), and it missed short
			# secrets entirely. Gated behind RedactPotentialSecrets (default $true - see
			# DefineVariablesPipe.ps1's StrRedactPotentialSecrets and USERGUIDE.md for the full
			# reasoning), NOT unconditional like the 0.14 version - a consumer can now turn it off
			# entirely to see full, undisguised output.
			#
			# 2026-09-19 CORRECTED DESIGN: the first version of this matched maximal RUNS of
			# base64-alphabet characters ANYWHERE in the text - this was wrong, found live via a real
			# Pester failure. A run-based match fragments at every non-base64 character (\, :, -, ., $),
			# so a whole, obviously-non-base64 quoted PATH like 'W:\vhd\PSimple\tvhd-p.psd1' got broken
			# into pieces ('tvhd', 'psd1', 'vhdx'...) and several of those short fragments happened to
			# decode without error on their own - a single realistic command line lost SIX separate
			# words to false positives this way, including the parameter name 'CheckGroupMembership'
			# (20 chars) and NamedPipe's own '-Data:$Data' marker, making the display far LESS readable,
			# the opposite of the goal. A real secret in this codebase's request text is always an
			# ENTIRE quoted string value (ConvertTo-ParameterSet quotes every string parameter) - so the
			# fix tests each QUOTED VALUE AS ONE ATOMIC UNIT instead of scanning for loose alphanumeric
			# fragments within it. A path/GUID/parameter name containing ANY character outside the
			# base64 alphabet fails immediately as a whole (correctly, since Test-Base64String's own
			# length-modulo-4 check on the FULL quoted content will almost always reject it, and a
			# non-base64 character inside would fail even that if it were fed straight to
			# [Convert]::FromBase64String) - nothing is fragmented, so nothing inside a genuinely mixed
			# string can accidentally validate on its own. Bare (unquoted) tokens - parameter names,
			# $True/$False, a bare $Data reference - are never candidates at all under this design,
			# since a real secret value in this codebase is never passed unquoted.
			If ($ServerClientParams.$StrRedactPotentialSecrets)
			{
				$Private:DisplayStr = [regex]::Replace($Private:DisplayStr, "'([^']*)'|""([^""]*)""", {
						Param ($Match)
						$Private:Inner = If ($Match.Groups[1].Success) { $Match.Groups[1].Value } Else { $Match.Groups[2].Value }
						$Private:Quote = $Match.Value.Substring(0, 1)
						If (Test-Base64String -Value $Private:Inner) { ('{0}<base64 encoded>{0}' -f $Private:Quote) } Else { $Match.Value }
					})
			}

			# Bit 2 (consumer pattern) / bit 4 (consumer command) still require actual consumer
			# configuration - there is no default pattern/command to force. NOTE: bit-1 only catches
			# LONG (40+ char) secrets - a short human-typed passphrase or PIN is NOT caught by anything
			# in this block unless the consumer supplies their own bit-2 pattern below. Any consumer
			# passing credential-shaped parameters (VaultTools is the concrete case) should configure
			# RedactPattern with a pattern matching its own parameter name, e.g.
			# Pattern = '(?i)-Passphrase\s+\S+' - this is not solved generically here.
			If ($Private:RedactCfg -and $Private:RedactCfg.Option)
			{
				# Bit 2: consumer-supplied regex pattern
				If (($Private:RedactCfg.Option -band $RedactBitPattern) -and $Private:RedactCfg.Pattern)
				{ $Private:DisplayStr = $Private:DisplayStr -replace $Private:RedactCfg.Pattern, '<redacted>' }
				# Bit 4: consumer-supplied ScriptBlock -- receives display string, must return string
				If (($Private:RedactCfg.Option -band $RedactBitCommand) -and $Private:RedactCfg.Command)
				{ $Private:DisplayStr = & $Private:RedactCfg.Command $Private:DisplayStr }
			}

			If ($ServerClientParams.$StrInfoDisplay -band $InfoDisplayBitProgress)
			{ Send-ProgressInfo -Type Console -String ('[Server] Executing: {0}' -f $Private:DisplayStr) }

			If (2 -band ($env:MyFunctionTraceEnabled -as [Int]))
			{ Write-MyFunctionTrace -Detail ('Request:[{0}]' -f $Private:DisplayStr) }
		}
		# NOTE 2026-08-08: two changes were tried here and REVERTED after they coincided with an elevated
		# server dying mid-request ("Pipe is broken" at the client, no server log written): an $Error.Clear()
		# before the invoke, and an "if ($Error.Count -gt 0) populate $DataObject.Error" after it.
		#
		# !! 2026-08-11 UPDATE - BOTH halves of that reasoning were re-examined and neither holds up:
		#
		# 1. "no server log written" was NOT evidence of a hard process kill. Save-ServerLog claimed the
		#    flush flag BEFORE deciding to discard a clean exit, so on the default InfoDisplay (bit 8 off)
		#    ANY crash following the normal 'exit-pipe' call logged nothing at all. Measured, and fixed in
		#    0.13 - see Tools\Tests\Test-ServerLogSuppression.ps1, which fails on 0.12 and passes here.
		#    So the server may well have crashed for an unrelated reason and simply not said so.
		#
		# 2. The "if ($Error.Count -gt 0)" check was WRONG anyway, for a reason unrelated to any crash:
		#    it fires on SUCCESS. -ErrorAction SilentlyContinue still records to $Error, so any server
		#    function that enumerates a filesystem (C:\PerfLogs, $Recycle.Bin\S-1-5-18 ...) leaves records
		#    behind. Measured: one suppressed enumeration = 1 record; a depth-2 walk of C:\ = 14. Each
		#    formats to ~660 chars via Get-MyError, which dumps the WHOLE $Error list with stack traces.
		#    A successful request would have come back with a populated Error and a payload growing with
		#    the size of the walk (~645 KB at 1000 records).
		#
		# The genuine fix for the propagation defect is to capture the invocation's ERROR STREAM, not
		# $Error - the non-terminating case never reaches $Error at all. Do NOT reintroduce the two
		# reverted lines; this file runs inside the elevated server for EVERY consumer.
		# 0.13 FIX - make a server-side failure REACH THE CLIENT.
		#
		# The line below used to be the whole story, and it does not work for the case that
		# matters. A module function resolves $ErrorActionPreference from ITS OWN scope, falling
		# back to GLOBAL - never to the caller. So setting it here leaves a Write-Error raised
		# inside a module function non-terminating, and (measured) it is not recorded in $Error
		# either, so it evades both the Catch and any $Error inspection. Since "report failure via
		# Write-Error" is the DOCUMENTED convention for server functions, every such failure was
		# presenting to the client as SUCCESS.
		#
		# Setting the GLOBAL preference reaches the module function's scope, so the error becomes
		# TERMINATING and the existing Catch below populates $DataObject.Error - no new plumbing.
		#
		# Why not capture the error stream instead (the originally-planned fix): InvokeReturnAsIs()
		# is a .NET method call whose error stream is NOT connected to the caller's redirect, so an
		# outer '2>&1' captures nothing; and replacing it with '& $SB 2>&1 | ...' UNROLLS results -
		# measured to turn a single-element array into a scalar and an empty array into $null,
		# which would silently break consumers indexing or .Count-ing a result.
		# This approach leaves the result path untouched: 9/9 shapes identical to 0.12.
		# See Tools\Tests\Test-InvokeResultShape.ps1.
		#
		# EXPECTED FALLOUT, and it is the mechanism rather than a side effect: a server function
		# that previously carried on after a non-terminating error will now abort the request and
		# report it. That is the point of the change.
		$ErrorActionPreference        = 'Stop'
		$global:ErrorActionPreference = 'Stop'
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
		$DataObject.$StrError = NamedPipe\Get-MyError -Return
	}
	Finally
	{
		# MUST run on every path. $global:ErrorActionPreference is process-wide and the server
		# is long-lived, so leaking 'Stop' would silently change every subsequent request AND
		# the server's own teardown. Restoring in the Catch alone is not enough - a throw from
		# the Return inside the request-policy gate, or any non-exception exit, would skip it.
		$global:ErrorActionPreference = $Private:GlobalEapSave
	}
	$ErrorActionPreference = $Private:ErrorActionPreferenceSave
	$DataObject
}
