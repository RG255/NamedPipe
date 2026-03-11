function Assert-Folder 
{
	<#
			.SYNOPSIS
			Tests, creates, or removes folders in a predictable, structured way.

			.DESCRIPTION
			Accepts folder paths via pipeline and performs one of the following operations:

			Test    - folder must exist
			Create  - create folder if missing
			Remove  - remove folder if it exists

			Returns a structured object describing success/failure.
	#>

	[CmdletBinding()]
	param(
		[Parameter(Mandatory, ValueFromPipeline)]
		[AllowEmptyString()]
		[string]$InputObject,

		[ValidateSet('Create','Remove','Test')]
		[string]$Option = 'Test'
	)

	begin {
		if ($Script:FTrace) 
		{Write-MyLog -PathToLogFile $Script:FTLogFilePath -CallStack (Get-PSCallStack)}
	}

	process {
		$Path = $InputObject

		# Handle null/empty input
		if ([string]::IsNullOrWhiteSpace($Path)) 
		{
			return [pscustomobject]@{
				Path      = $Path
				Operation = $Option
				Success   = $false
				Message   = 'Input path is null or empty.'
			}
		}

		# Pre-calc
		$FolderExists = Test-Path -Path $Path -PathType Container

		try 
		{
			switch ($Option) {

				'Test' 
				{
					if ($FolderExists) 
					{
						return [pscustomobject]@{
							Path      = $Path
							Operation = 'Test'
							Success   = $true
							Message   = ''
						}
					}
					return [pscustomobject]@{
						Path      = $Path
						Operation = 'Test'
						Success   = $false
						Message   = 'Folder does not exist.'
					}
				}

				'Create' 
				{
					if ($FolderExists) 
					{
						return [pscustomobject]@{
							Path      = $Path
							Operation = 'Create'
							Success   = $false
							Message   = 'Folder already exists.'
						}
					}

					$null = New-Item -Path $Path -ItemType Directory -Force -ErrorAction Stop
					return [pscustomobject]@{
						Path      = $Path
						Operation = 'Create'
						Success   = $true
						Message   = ''
					}
				}

				'Remove' 
				{
					if (-not $FolderExists) 
					{
						return [pscustomobject]@{
							Path      = $Path
							Operation = 'Remove'
							Success   = $false
							Message   = 'Folder does not exist.'
						}
					}

					Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
					return [pscustomobject]@{
						Path      = $Path
						Operation = 'Remove'
						Success   = $true
						Message   = ''
					}
				}
			}
		}
		catch 
		{
			$Err = Get-MyErrors -Return -Indent 2 -LinePad 0
			return [pscustomobject]@{
				Path      = $Path
				Operation = $Option
				Success   = $false
				Message   = "Operation failed: $($Err[6]) $($Err[8])"
			}
		}
	}
}
