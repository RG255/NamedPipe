Function Test-UserOrGroupExists
{
	<#
		.SYNOPSIS
		Validates that an access identifier string references a valid local user or group.

		.DESCRIPTION
		Parses access identifier strings in the format 'Identity:AllowOrDeny:AccessRight'
		and validates each component:
		- Identity must be an existing local user or group (supports DOMAIN\User format)
		- Access mode must be 'Allow' or 'Deny'
		- Access right must be 'ReadWrite'

		If only 1 or 2 parts are provided, defaults are appended:
		- 1 part:  'Username' becomes 'Username:Allow:ReadWrite'
		- 2 parts: 'Username:Allow' becomes 'Username:Allow:ReadWrite'

		Used internally by Set-ObjectParams to validate AccessIdentifier entries
		before they are passed to Set-PipeSecurity.

		.PARAMETER IDList
		Access identifier strings to validate. Accepts pipeline input.
		Format: 'Identity:AllowOrDeny:AccessRight'

		.EXAMPLE
		'Ray:Allow:ReadWrite' | Test-UserOrGroupExists
		Validates and returns the access identifier if the user 'Ray' exists.

		.EXAMPLE
		@('DOMAIN\User:Allow:ReadWrite', 'Administrators:Allow:ReadWrite') | Test-UserOrGroupExists
		Validates multiple access identifiers via pipeline.

		.INPUTS
		System.String[] - Access identifier strings.

		.OUTPUTS
		System.String - The validated (and potentially completed) access identifier string.
		Throws an error if the user/group does not exist or parameters are invalid.
	#>

	[CmdletBinding(PositionalBinding = $False)]
	Param (
		[Parameter(Mandatory,ValueFromPipeline,Dontshow = $True)]
		[String[]]$IDList
	)
	Process
	{
		$ID = $IDList -split ':'
		If ($ID.count -lt 1 -or $ID.count -gt 3)
		{
			throw "Invalid access identifier format: must have 1-3 parts separated by colons, got $($ID.count)"
		}
		If ($ID.count -ne 3)
		{
			If ($ID.count -eq 1)
			{$IDList += ':Allow:ReadWrite'}
			If ($ID.count -eq 2)
			{$IDList += ':ReadWrite'}
			$ID = $IDList -split ':'
		}
		$IDList | Write-Verbose
		$ID | Write-Verbose
		if ($ID[0] -like '*\*')
		{$IDu = $ID[0] -split '\\' | Select-Object -Last 1}
		else
		{$IDu = $ID[0]}

		if ([string]::IsNullOrWhiteSpace($IDu))
		{
			throw "Identity cannot be empty or whitespace"
		}

		$ID[0] | Write-Verbose
		Try
		{$Null = Get-LocalUser -Name $IDu -ErrorAction Stop}
		Catch [Microsoft.PowerShell.Commands.UserNotFoundException]
		{
			If ($Global:error.count -gt 0)
			{$Global:Error.RemoveAt(0)}
			Try
			{$Null = Get-LocalGroup -Name $IDu -ErrorAction Stop}
			catch [Microsoft.PowerShell.Commands.GroupNotFoundException]
			{
				$Msg = 'Invalid user or group specified: [{0}]' -f $ID[0]
				Throw $Msg
			}
		}
		If ($ID[2] -inotmatch '^ReadWrite$')
		{
			$Msg = 'Invalid access right specified (must be ReadWrite): [{0}]' -f $ID[2]
			Throw $Msg
		}
		If ($ID[1] -inotmatch '^Allow$|^Deny$')
		{
			$Msg = 'Invalid control specified (must be Allow or Deny): [{0}]' -f $ID[1]
			Throw $Msg
		}
		$ID -join ':'
	}
	end
	{}
}
