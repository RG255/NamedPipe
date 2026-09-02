Function Show-VerboseData
{
	<#
			.SYNOPSIS
			Displays the contents of a PowerShell object in a formatted, readable output.

			.DESCRIPTION
			A diagnostic display function used throughout the NamedPipe module when InfoDisplay
			is set to level 1 or above. Automatically detects the object type (hashtable,
			ordered dictionary, PSCustomObject, string, scriptblock, collection, or breakpoint)
			and formats the output accordingly.

			When -Display is specified, output is written via Write-Information with
			InformationAction Continue so it always appears. Without -Display, hashtable
			output uses Write-Verbose instead.

			.PARAMETER Object
			The object to display. Supports hashtables, ordered dictionaries, PSCustomObjects,
			strings, scriptblocks, collections, and breakpoint objects.

			.PARAMETER KeySize
			The padding width for hashtable key names. If 0 (default), automatically
			calculates from the longest key name.

			.PARAMETER Title
			An optional title string displayed above the object contents, surrounded
			by dashes for visibility.

			.PARAMETER Display
			When specified, forces output via Write-Information (always visible).
			Without this switch, hashtable output uses Write-Verbose instead.

			.EXAMPLE
			Show-VerboseData -Object $ServerClientParams -Display -Title 'Server Parameters'
			Displays the ServerClientParams hashtable with a title header.

			.EXAMPLE
			Show-VerboseData -Object $DataObject -Display -Title 'DataObject After Security call'
			Displays the DataObject contents for debugging.

			.INPUTS
			Any PowerShell object (hashtable, ordered dictionary, PSCustomObject, string, etc.)

			.OUTPUTS
			Formatted text output to the information or verbose stream.
	#>


	[CmdletBinding(PositionalBinding = $False)]
	Param (
		[Parameter(Mandatory,HelpMessage = 'Please supply the Object to be listed')]
		[AllowEmptyCollection()]
		[AllowNull()]
		$Object,
		[Int]$KeySize = 0,
		[String]$Title = $Null,
		[Switch]$Display
	)
	If ($Display)
	{
		$Private:Stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
		If ($Title)
		{$Private:Msg = '{1}{0}{3} {2}{0}{1}' -f $StrCrlf, ''.PadRight(40, '-'), $Title, $Private:Stamp}
		Else
		{$Private:Msg = '{1} {0}' -f ''.PadRight(40, '-'), $Private:Stamp}
		Write-Information -InformationAction Continue -MessageData $Private:Msg
	}
	if ($Object.count -ne [int]0)
	{
		Switch -regex ($Object.gettype().name)
		{
			'LineBreakPoint'
			{
				$Private:Msg = $Object |
					Select-Object -Property * |
					Out-String
				Write-Information -InformationAction Continue -MessageData $Private:Msg.trim("`r`n")
			}
			'String|ScriptBlock'
			{
				$Private:Msg = $Object
				Write-Information -InformationAction Continue -MessageData $Private:Msg
			}
			'PSCustomObject|OrderedDictionary'
			{Write-Information -InformationAction Continue -MessageData ($Object|Out-String).trim("`r`n")}
			'Collection*'
			{
				$Private:Msg = $Object | Out-String
				Write-Information -InformationAction Continue -MessageData $Private:Msg
			}
			'Hashtable'
			{
				if ($KeySize -eq 0)
				{
					foreach($Item in $Object.GetEnumerator())
					{
						If ($Item.Name.length -gt $KeySize)
						{$KeySize = $Item.Name.length}
					}
				}
				If ($Display)
				{
					foreach($Item in $Object.GetEnumerator() | Sort-Object -Property key)
					{
						$Private:Msg = '{0} = {1}' -f $Item.key.PadRight($KeySize), $Item.value
						Write-Information -InformationAction Continue -MessageData $Private:Msg
					}
				}
				Else
				{
					foreach($Item in $Object.GetEnumerator() | Sort-Object -Property key)
					{'{0} = {1}' -f $Item.key.PadRight($KeySize), $Item.value | Write-Verbose}
				}
			}
		}
	}
	Else
	{
		$Private:Msg = 'The item has no content'
		Write-Information -InformationAction Continue -MessageData $Private:Msg
	}
}
