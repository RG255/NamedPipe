# VENDORED from CommonScripts\0.2\FunctionsWindows\Assert-Folder.ps1 by Sync-SharedUtilities [SHA256 E5604ADDC3FD30FF4FFAD788BE2883B74530D1C2C9D6BFE2625EC784C0B92C44] - DO NOT EDIT (edit the master; Deploy-Modules re-syncs).
Function Assert-Folder
{
	<#
		.SYNOPSIS
		Tests, creates, or removes a folder.

		.DESCRIPTION
		Accepts a folder path (via pipeline or parameter) and performs one of:

		  Test    - verify the folder exists
		  Create  - create the folder if it does not already exist
		  Remove  - remove the folder if it exists

		Always returns a structured object describing the outcome.

		.PARAMETER InputObject
		Path to the folder to operate on.

		.PARAMETER Option
		Operation to perform: Test | Create | Remove. Default: Test.

		.EXAMPLE
		'C:\Temp\Logs' | Assert-Folder -Option Create
		Returns: @{ Path='C:\Temp\Logs'; Operation='Create'; Success=$true; Message='' }

		.EXAMPLE
		'C:\Temp\Missing' | Assert-Folder
		Returns: @{ Path='C:\Temp\Missing'; Operation='Test'; Success=$false; Message='Folder does not exist.' }

		.OUTPUTS
		[pscustomobject] with properties: Path, Operation, Success, Message.
	#>

	[CmdletBinding(PositionalBinding = $False)]
	Param (
		[Parameter(Mandatory = $True, ValueFromPipeline = $True,
			HelpMessage = 'Path to the folder')]
		[AllowEmptyString()]
		[String]$InputObject,

		[ValidateSet('Create', 'Remove', 'Test')]
		[String]$Option = 'Test'
	)

	Begin
	{
		# -and (Get-Command...) guard: see ConvertFrom-Serial.ps1's own comment (2026-09-15) - this file
	# is vendored into modules that never vendor Write-MyFunctionTrace itself, and the process-scoped
	# $env:MyFunctionTraceEnabled can be '1' there regardless.
	If ((1 -band ($env:MyFunctionTraceEnabled -as [Int])) -and (Get-Command -Name Write-MyFunctionTrace -ErrorAction SilentlyContinue)) { Write-MyFunctionTrace }
	}

	Process
	{
		$Private:Path = $InputObject

		if ([String]::IsNullOrWhiteSpace($Private:Path))
		{
			return [pscustomobject]@{
				Path      = $Private:Path
				Operation = $Option
				Success   = $false
				Message   = 'Input path is null or empty.'
			}
		}

		$Private:FolderExists = Test-Path -Path $Private:Path -PathType Container

		try
		{
			switch ($Option)
			{
				'Test'
				{
					if ($Private:FolderExists)
					{
						return [pscustomobject]@{
							Path      = $Private:Path
							Operation = 'Test'
							Success   = $true
							Message   = ''
						}
					}
					return [pscustomobject]@{
						Path      = $Private:Path
						Operation = 'Test'
						Success   = $false
						Message   = 'Folder does not exist.'
					}
				}

				'Create'
				{
					if ($Private:FolderExists)
					{
						return [pscustomobject]@{
							Path      = $Private:Path
							Operation = 'Create'
							Success   = $false
							Message   = 'Folder already exists.'
						}
					}
					$null = New-Item -Path $Private:Path -ItemType Directory -Force -ErrorAction Stop
					return [pscustomobject]@{
						Path      = $Private:Path
						Operation = 'Create'
						Success   = $true
						Message   = ''
					}
				}

				'Remove'
				{
					if (-not $Private:FolderExists)
					{
						return [pscustomobject]@{
							Path      = $Private:Path
							Operation = 'Remove'
							Success   = $false
							Message   = 'Folder does not exist.'
						}
					}
					Remove-Item -Path $Private:Path -Recurse -Force -ErrorAction Stop
					return [pscustomobject]@{
						Path      = $Private:Path
						Operation = 'Remove'
						Success   = $true
						Message   = ''
					}
				}
			}
		}
		catch
		{
			return [pscustomobject]@{
				Path      = $Private:Path
				Operation = $Option
				Success   = $false
				Message   = ('Operation failed: {0}' -f $_.Exception.Message)
			}
		}
	}
}
