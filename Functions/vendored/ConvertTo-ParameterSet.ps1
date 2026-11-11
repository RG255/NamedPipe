# VENDORED from CommonScripts\0.2\Functions\ConvertTo-ParameterSet.ps1 by Sync-SharedUtilities [SHA256 3DAB811B25C383080FCD9DBCC87C0D7D12F26A64664496651C437FA5790A8382] - DO NOT EDIT (edit the master; Deploy-Modules re-syncs).
Function ConvertTo-ParameterSet
{
	<#
			.SYNOPSIS
			Converts a hashtable into a parameter string for use in scriptblocks.

			.DESCRIPTION
			Hashtable splatting (@Hash) cannot be used inside dynamically created
			scriptblocks. This function converts a hashtable into a conventional
			parameter string that can be embedded in a scriptblock with proper
			escaping to prevent code injection attacks.

			For example, a hashtable:
			  @{ Path = 'C:\Temp'; Recurse = $True }

			Is converted to a string:
			  -Path: 'C:\Temp' -Recurse:$True

			Only the "-Name:" tokens are ever emitted unquoted, and each must be a plain identifier token
			(anything else throws). String values, and every non-numeric scalar (Guid, DateTime, enum, object), are
			emitted as single-quoted literals via Format-EscapedLiteral; numbers are emitted bare in the invariant
			culture; real booleans and [switch] values become $True / $False (the strings 'true'/'false' stay quoted text).

			This is used by Get-SBResult on the server side when the client sends
			parameters as a hashtable alongside a command request.

			.PARAMETER Hash
			The hashtable containing parameter names and values to convert.

			.EXAMPLE
			$Args = ConvertTo-ParameterSet -Hash @{ ProcessId = 1234; State = 'Restore' }
			Returns: " -ProcessId: 1234 -State: 'Restore'"

			.EXAMPLE
			$SB = [ScriptBlock]::Create("Set-Window $Args")
			Uses the converted parameter string in a dynamically created scriptblock.

			.INPUTS
			System.Collections.Hashtable - A hashtable of parameter name/value pairs.

			.OUTPUTS
			System.String - A parameter string suitable for embedding in scriptblocks.
	#>


	[CmdletBinding()]
	Param (
		[Parameter(Mandatory,HelpMessage='You must provide a hash table to convert to parameters',ValueFromPipeline)]
		[HashTable]$Hash
	)
	# The Get-Command guard is needed because this file is vendored into modules that never vendor
	# Write-MyFunctionTrace while $env:MyFunctionTraceEnabled can still be '1' (it is process-scoped).
	If ((1 -band ($env:MyFunctionTraceEnabled -as [Int])) -and (Get-Command -Name Write-MyFunctionTrace -ErrorAction SilentlyContinue)) { Write-MyFunctionTrace }

	# Numbers are emitted bare (invariant culture); strings and every other scalar are quoted, because an unquoted
	# ToString() of a Guid/DateTime/object could carry code.
	$Private:ScalarText = {
		param($v)
		$Private:numeric = $v -is [ValueType] -and $v -isnot [Char] -and $v -isnot [Enum] -and $v -isnot [DateTime] -and $v -isnot [Guid] -and $v -isnot [TimeSpan] -and $v -isnot [Boolean]
		if ($Private:numeric) { return ([IFormattable]$v).ToString($null, [Globalization.CultureInfo]::InvariantCulture) }
		return (Format-EscapedLiteral -Value ([String]$v) -Quote)
	}

	# Wrapped so a failure is audited; re-thrown because a swallowed error here could mean unescaped output
	# reaching [ScriptBlock]::Create.
	Try
	{
		# The splat yields "-Name:" tokens and values alternately. A $null value arrives as its own element, so the
		# pairing holds (CHANGELOG-style history: _PlanningDocs\CommonScripts\0.2\2026-11-08_ConvertTo-ParameterSet-comment-history.md).
		$Private:y = $(&{$args}@Hash)
		for ($Private:x = 0; $Private:x -lt $Private:y.count; $Private:x ++)
		{
			# Only an EVEN element is a parameter name; it is the only thing ever emitted unquoted, so it must be a
			# plain "-Name:" token. A VALUE that merely looks like one (e.g. '-a; Remove-Item C:\x ;b:') is escaped
			# below like any other value.
			If ($Private:x % 2 -eq 0)
			{
				If ($Private:y[$Private:x] -isnot [String] -or $Private:y[$Private:x] -notmatch '^-[\w-]+:$')
				{ throw ('ConvertTo-ParameterSet: unexpected parameter-name token [{0}].' -f $Private:y[$Private:x]) }
				$Private:y[$Private:x] = ' {0}' -f $Private:y[$Private:x]
				continue
			}

			# Only a real [bool] / [switch] becomes $True / $False; the STRING 'true' / 'false' is quoted like any other.
			# The unary comma is REQUIRED: Switch enumerates a collection instead of matching it once, and an
			# array value would be escaped repeatedly (exponential growth, OutOfMemory).
			Switch (,$Private:y[$Private:x])
			{{$_ -is [Boolean] -or $_ -is [System.Management.Automation.SwitchParameter]}
				{$Private:y[$Private:x-1] = '{0}$' -f $Private:y[$Private:x-1]}
				Default
				{
					# A $null value is emitted as '' so the "-Name:" token always has an argument.
					If ($null -eq $Private:y[$Private:x] -or $Private:y[$Private:x] -eq '')
					{$Private:y[$Private:x] = "''"}
					Else
					{
						If ($Private:y[$Private:x] -is [array])
						{
							$Private:escaped = @()
							foreach ($item in $Private:y[$Private:x])
							{
								$Private:escaped += (& $Private:ScalarText $item)
							}
							$Private:y[$Private:x] = $Private:escaped -join ','
						}
						else
						{
							$Private:y[$Private:x] = (& $Private:ScalarText $Private:y[$Private:x])
						}
					}
				}
			}
		}
		$Private:y -join ''
	}
	Catch
	{
		Write-MyCatchAudit -Source 'ConvertTo-ParameterSet: failed to build an escaped parameter string' -ErrorRecord $_
		# Re-thrown by design: each caller wraps this in the Try/Catch that suits its own transport.
		throw
	}
}
