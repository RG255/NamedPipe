Function ConvertTo-Parameters
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

			.PARAMETER Hash
			The hashtable containing parameter names and values to convert.

			.EXAMPLE
			$Args = ConvertTo-Parameters -Hash @{ ProcessId = 1234; State = 'Restore' }
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
	$Private:y = $(&{$args}@Hash)
	for ($Private:x = 0; $Private:x -le $Private:y.count; $Private:x ++)
	{
		Switch -Regex ($Private:y[$Private:x])
		{'(?i)^(true|false)$'
			{$Private:y[$Private:x-1] = '{0}$' -f $Private:y[$Private:x-1]}
			'(?i)^[-].*[:]$'
			{$Private:y[$Private:x] = ' {0}' -f $Private:y[$Private:x]}
			Default
			{
				If ($Private:y[$Private:x] -eq '')
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
								$esc = $item -replace "'", "''"
								$Private:escaped += "'$esc'"
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
							$esc = $Private:y[$Private:x] -replace "'", "''"
							$Private:y[$Private:x] = "'$esc'"
						}
					}
				}
			}
					}
	}
	$Private:y -join ''
}