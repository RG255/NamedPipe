# VENDORED from CommonScripts\0.2\Functions\ConvertTo-ParameterSet.ps1 by Sync-SharedUtilities [SHA256 7770899A300964521CCCAA360EB40CCA669925AD98ABBBC7EC59160DB3B14AE4] - DO NOT EDIT (edit the master; Deploy-Modules re-syncs).
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
			  -Path: C:\Temp -Recurse:$True

			This is used by Get-SBResult on the server side when the client sends
			parameters as a hashtable alongside a command request.

			2026-09-15: promoted from NamedPipe\0.14\Functions\ConvertTo-ParameterSet.ps1 into
			CommonScripts - nothing in this function is NamedPipe-specific, and "safely escape a
			hashtable into a dynamic command's parameter string" is a generically useful capability
			already hardened against two real, hard-won bugs (see the inline comments below). Promoted
			ahead of a second consumer, same precedent as Expand-Variable (2026-09-12). Its internal
			single-quote escaping now goes through the shared Format-EscapedLiteral, extracted the same
			day after finding the identical `-replace "'", "''"` step hand-rolled independently in
			New-MyScheduledTask.ps1, Remove-MyScheduledTask.ps1 and VaultTools' VaultFileHelpers.ps1.

			.PARAMETER Hash
			The hashtable containing parameter names and values to convert.

			.EXAMPLE
			$Args = ConvertTo-ParameterSet -Hash @{ ProcessId = 1234; State = 'Restore' }
			Returns: ' -ProcessId: 1234 -State: Restore'

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
	# -and (Get-Command...) guard: see ConvertFrom-Serial.ps1's own comment (2026-09-15) - this file is
	# vendored into modules that never vendor Write-MyFunctionTrace itself, and the process-scoped
	# $env:MyFunctionTraceEnabled can be '1' there regardless (confirmed live: a VHDTools crash caused
	# by an unrelated NamedPipe test session in the same shell).
	If ((1 -band ($env:MyFunctionTraceEnabled -as [Int])) -and (Get-Command -Name Write-MyFunctionTrace -ErrorAction SilentlyContinue)) { Write-MyFunctionTrace }

	# Wrapped - this is the injection-escaping function every scriptblock request is built through, so
	# a silent failure here would be worse than a loud one (a swallowed error could mean unescaped/wrong
	# output reaching [ScriptBlock]::Create). Re-thrown so callers keep current behavior; the audit
	# trail is what was missing.
	Try
	{
		$Private:y = $(&{$args}@Hash)
		for ($Private:x = 0; $Private:x -lt $Private:y.count; $Private:x ++)
		{
			# The unary comma is REQUIRED here, not decorative: PowerShell's Switch statement
			# enumerates a COLLECTION value instead of matching it as one scalar. $Private:y[$Private:x]
			# is an array whenever the hashtable held an array-valued parameter (e.g. ConfigContent, a
			# config file's lines) - without the comma, Switch silently ran its body ONCE PER ARRAY
			# ELEMENT for that single outer loop iteration. The first of those extra runs correctly
			# converted the array to one escaped string (the Default branch below); every SUBSEQUENT
			# run then re-escaped that ALREADY-ESCAPED string as if it were still the original array
			# element, and each re-escape pass roughly DOUBLES the string's length (every existing ''
			# becomes ''''). That is exponential growth - confirmed live 2026-08-29: a completely
			# ordinary 113-line config array reliably took the elevated server to double-digit GB and
			# an eventual OutOfMemoryException within seconds, on totally unremarkable input, because
			# the array-branch's re-entrant escaping had nothing to do with the array's actual size.
			# ',(...)' wraps the value in a ONE-element array, so Switch enumerates exactly once,
			# with the full original array (or string) passed through as a single item every time.
			Switch -Regex (,$Private:y[$Private:x])
			{'(?i)^(true|false)$'
				{$Private:y[$Private:x-1] = '{0}$' -f $Private:y[$Private:x-1]}
				'(?i)^[-].*[:]$'
				{$Private:y[$Private:x] = ' {0}' -f $Private:y[$Private:x]}
				Default
				{
					# 2026-08-31 fix: a $null-valued hashtable entry DOES splat onto $args as two
					# separate elements (a "-Name:" token, then the $null value itself as its own
					# array element) - confirmed empirically via direct inspection of the raw splat
					# array. But "$null -eq ''" is FALSE in PowerShell, so the null element fell
					# through this check entirely, matched neither branch below either ($null -is
					# [array] and $null -is [string] are both false), and was left completely
					# untouched - joining an unquoted $null into the final string contributes
					# NOTHING, leaving a bare "-Name:" with no value at all. That is a genuine
					# PowerShell parse error the moment any parameter follows it ("Parameter -Name:
					# requires an argument"), and because the whole parameter string becomes ONE
					# scriptblock via [ScriptBlock]::Create(), that single malformed token takes down
					# the ENTIRE command, not just the one optional parameter. Found live 2026-08-31
					# via VHDTools' Protect-VHDVolumeSession (a BitLocker encrypt's optional
					# secondary-passphrase parameters, $null when no secondary passphrase was used) -
					# confirmed by direct reproduction: ConvertTo-ParameterSet -Hash
					# @{ Foo = $null; Bar = 'x' } produced " -Foo: -Bar:'x'" (invalid) instead of
					# " -Foo:'' -Bar:'x'" (valid, parses as an empty string - exactly what
					# Resolve-VHDTransportKey-shaped callers already treat as "not supplied"). Treat
					# $null the same as an explicit '' value.
					If ($null -eq $Private:y[$Private:x] -or $Private:y[$Private:x] -eq '')
					{$Private:y[$Private:x] = "''"}
					Else
					{
						If ($Private:y[$Private:x] -is [array])
						{
							$Private:escaped = @()
							foreach ($item in $Private:y[$Private:x])
							{
								if ($item -is [string])
								{
									$Private:escaped += Format-EscapedLiteral -Value $item -Quote
								}
								else
								{
									$Private:escaped += $item
								}
							}
							$Private:y[$Private:x] = $Private:escaped -join ','
						}
						else
						{
							if ($Private:y[$Private:x] -is [string])
							{
								$Private:y[$Private:x] = Format-EscapedLiteral -Value $Private:y[$Private:x] -Quote
							}
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
		# Re-thrown by design, not swallowed - it is the CALLER's responsibility to wrap this call in a
		# Try/Catch appropriate to their own context. This file is vendored into multiple modules with
		# different transport/error-handling conventions; it makes no assumption about any one of them.
		throw
	}
}
