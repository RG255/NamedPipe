# VENDORED from CommonScripts\0.2\FunctionsWindows\Assert-File.ps1 by Sync-SharedUtilities [SHA256 191C296E35EFF28BE0F28D4179850B2A60EA275FB1620BED157AB80D57F6531E] - DO NOT EDIT (edit the master; Deploy-Modules re-syncs).
Function Assert-File
{
	<#
		.SYNOPSIS
		Tests, creates, or removes files.

		.DESCRIPTION
		Accepts file paths via pipeline and performs one of:

		  Test       - verify the file exists as a Leaf (file, not container)
		  TestAny    - verify the path exists as any type (file, link, etc.)
		  Create     - create the file if the parent folder exists and the file does not
		  CreatePath - create the parent folder if needed, then create the file
		  Remove     - delete the file if it exists

		Returns nothing on success; returns an error string on failure.

		.PARAMETER InputObject
		One or more file paths to operate on.

		.PARAMETER Option
		Operation: Test | TestAny | Create | CreatePath | Remove. Default: Test.

		.EXAMPLE
		'C:\Temp\myfile.txt' | Assert-File -Option Create

		.EXAMPLE
		If ($Msg = 'C:\Temp\myfile.txt' | Assert-File)
		{ Write-Warning $Msg }

		.OUTPUTS
		Nothing on success. An error string on failure.
	#>

	[CmdletBinding(PositionalBinding = $False)]
	Param (
		[Parameter(Mandatory = $True, ValueFromPipeline = $True,
			HelpMessage = 'Path to the file')]
		[AllowEmptyString()]
		[String]$InputObject,

		[ValidateSet('Create', 'CreatePath', 'Remove', 'Test', 'TestAny')]
		[String]$Option = 'Test'
	)

	Process
	{
		if (-not $InputObject)
		{
			'The requested file [{0}] is a null or empty string!' -f [String]$InputObject
			return
		}

		try
		{
			$Private:AnyExists    = Test-Path -Path $InputObject -PathType Any  -ErrorAction Stop
			$Private:FileExists   = Test-Path -Path $InputObject -PathType Leaf -ErrorAction Stop
			$Private:FolderResult = Split-Path -Path $InputObject -Parent | Assert-Folder -Option Test

			switch ($Option)
			{
				'Test'
				{
					if (-not $Private:FileExists)
					{ 'The [{0}] file does not exist!' -f [String]$InputObject }
				}

				'TestAny'
				{
					if (-not $Private:AnyExists)
					{ 'The [{0}] path does not exist!' -f [String]$InputObject }
				}

				'Create'
				{
					if ($Private:FolderResult.Success -and -not $Private:FileExists)
					{
						$null = New-Item -Path $InputObject -ItemType File -ErrorAction Stop
					}
					elseif (-not $Private:FolderResult.Success)
					{
						'The [{0}] file could not be created: parent folder does not exist.' -f [String]$InputObject
					}
					else
					{
						'The [{0}] file already exists!' -f [String]$InputObject
					}
				}

				'CreatePath'
				{
					# Ensure the parent folder exists, creating it if necessary
					if (-not $Private:FolderResult.Success)
					{
						$Private:CreateResult = Split-Path -Path $InputObject -Parent | Assert-Folder -Option Create
						if (-not $Private:CreateResult.Success)
						{
							'The [{0}] file could not be created: {1}' -f [String]$InputObject, $Private:CreateResult.Message
							return
						}
					}
					if (-not $Private:FileExists)
					{ $null = New-Item -Path $InputObject -ItemType File -ErrorAction Stop }
				}

				'Remove'
				{
					if ($Private:FileExists)
					{ $null = Remove-Item -Path $InputObject -ErrorAction Stop }
				}
			}
		}
		catch
		{
			'The Option: [{0}] on file: [{1}] did not succeed!{2}{3}' -f $Option, [String]$InputObject, "`r`n", $_.Exception.Message
		}
	}
}
