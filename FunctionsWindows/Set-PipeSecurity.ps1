Function Set-PipeSecurity
{
	<#
			.SYNOPSIS
			Creates a PipeSecurity object with access rules for the named pipe.

			.DESCRIPTION
			Builds a System.IO.Pipes.PipeSecurity object from an array of access identifier
			strings. Each string specifies a user or group and their access permissions.

			The access identifier format is: 'Identity:AllowOrDeny:AccessRight'
			- 1 part:  'Username'           - defaults to Allow:ReadWrite
			- 2 parts: 'Username:Allow'      - defaults to ReadWrite
			- 3 parts: 'Username:Allow:ReadWrite' - fully specified

			Supports both PowerShell 5.1 (using ::new()) and PowerShell 7+ (using New-Object)
			for cross-version compatibility.

			.PARAMETER AccessIdentifier
			An array of access identifier strings in the format 'Identity:AllowOrDeny:AccessRight'.
			Each string specifies a local user or group and their pipe access permissions.
			Accepts pipeline input.

			.EXAMPLE
			Set-PipeSecurity -AccessIdentifier 'DOMAIN\User:Allow:ReadWrite'
			Creates a PipeSecurity object granting ReadWrite access to the specified user.

			.EXAMPLE
			Set-PipeSecurity -AccessIdentifier @('Ray:Allow:ReadWrite', 'Administrators:Allow:ReadWrite')
			Creates a PipeSecurity object with multiple access rules.

			.INPUTS
			System.String[] - Array of access identifier strings.

			.OUTPUTS
			System.IO.Pipes.PipeSecurity - The configured pipe security object.
	#>


	[CmdletBinding(PositionalBinding = $False)]
	Param (
		[Parameter(Mandatory,ValueFromPipeline,HelpMessage = 'Please supply the Username to be given access')]
		[String[]]$AccessIdentifier
	)
	<#
			To add new access restrictions:
			$ar  += [IO.Pipes.PipeAccessRule]::New("<UserName | Group>", 'ReadWrite', 'Allow')
			Everyone
			$ar  += [IO.Pipes.PipeAccessRule]::new([Security.Principal.SecurityIdentifier]::new(([Security.Principal.WellKnownSidType]::WorldSid),$Null), 'ReadWrite', 'Allow')
			A specific User
			$ar  += [IO.Pipes.PipeAccessRule]::new("ray", 'ReadWrite', 'Allow')
			A specific group
			$ar  += [IO.Pipes.PipeAccessRule]::new("Users", 'ReadWrite', 'Allow')
			Well know SID's e.g. Authenticated users
			$ar += [IO.Pipes.PipeAccessRule]::new(([System.Security.Principal.SecurityIdentifier]'S-1-5-11'),'ReadWrite', 'Allow')
	#>
	Try
	{
		if ($PSVersionTable.PSVersion.Major -gt 5) 
		{$PipeSecurity = New-Object -TypeName System.IO.Pipes.PipeSecurity}
		Else
		{$PipeSecurity  = [IO.Pipes.PipeSecurity]::new()}
		for ($x = 0; $x -lt $AccessIdentifier.count ; $x ++) 
		{
			$Item = $AccessIdentifier[$x]
			$IDAccess = $Item.split(':')
			if ($PSVersionTable.PSVersion.Major -gt 5) 
			{
				Switch ($IDAccess.count)
				{
					'1'
					{$AccessRule = New-Object -TypeName System.IO.Pipes.PipeAccessRule -ArgumentList ($IDAccess[0], 'ReadWrite', 'Allow')}
					'2'
					{$AccessRule = New-Object -TypeName System.IO.Pipes.PipeAccessRule -ArgumentList ($IDAccess[0], 'ReadWrite', $IDAccess[1])}
					'3'
					{$AccessRule = New-Object -TypeName System.IO.Pipes.PipeAccessRule -ArgumentList ($IDAccess[0], $IDAccess[2], $IDAccess[1])}
				}
				$PipeSecurity.AddAccessRule($AccessRule)
			}
			else
			{				
				Switch ($IDAccess.count)
				{
					'1'
					{$PipeSecurity.AddAccessRule([IO.Pipes.PipeAccessRule]::new($IDAccess[0],'ReadWrite', 'Allow'))}
					'2'
					{$PipeSecurity.AddAccessRule([IO.Pipes.PipeAccessRule]::new($IDAccess[0],'ReadWrite', $IDAccess[1]))}
					'3'
					{$PipeSecurity.AddAccessRule([IO.Pipes.PipeAccessRule]::new($IDAccess[0],$IDAccess[2], $IDAccess[1]))}
				}
			}
		}	
	}	
	Catch
	{
		# Error creating pipe security - throw to caller for handling
		throw
	}
	$PipeSecurity
}
