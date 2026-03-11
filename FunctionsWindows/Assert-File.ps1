function Assert-File 
{
	<#
			.SYNOPSIS
			Tests, creates, or removes files in a predictable, structured way.

			.DESCRIPTION
			Accepts file paths via pipeline and performs one of the following operations:

			Test       - file must exist as a leaf
			TestAny    - file or link must exist
			Create     - create file only if parent folder exists
			CreatePath - create parent folder (if needed) then create file
			Remove     - delete file if it exists

			Returns a structured object describing success/failure.
	#>

	[CmdletBinding()]
	param(
		[Parameter(Mandatory, ValueFromPipeline)]
		[AllowEmptyString()]
		[string]$InputObject,

		[ValidateSet('Create','CreatePath','Remove','Test','TestAny')]
		[string]$Option = 'Test'
	)

	begin {
		if ($Script:FTrace) 
		{Write-MyLog -PathToLogFile $Script:FTLogFilePath -CallStack (Get-PSCallStack)}
	}

	process {
		# Normalise
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
		$Parent = Split-Path -Path $Path -Parent
		$FileExists  = Test-Path -Path $Path   -PathType Leaf
		$AnyExists   = Test-Path -Path $Path   -PathType Any
		$FolderExists = Test-Path -Path $Parent -PathType Container

		try 
		{
			switch ($Option) {

				'Test' 
				{
					if ($FileExists) 
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
						Message   = 'File does not exist.'
					}
				}

				'TestAny' 
				{
					if ($AnyExists) 
					{
						return [pscustomobject]@{
							Path      = $Path
							Operation = 'TestAny'
							Success   = $true
							Message   = ''
						}
					}
					return [pscustomobject]@{
						Path      = $Path
						Operation = 'TestAny'
						Success   = $false
						Message   = 'File or link does not exist.'
					}
				}

				'Create' 
				{
					if (-not $FolderExists) 
					{
						return [pscustomobject]@{
							Path      = $Path
							Operation = 'Create'
							Success   = $false
							Message   = 'Parent folder does not exist.'
						}
					}
					if ($FileExists) 
					{
						return [pscustomobject]@{
							Path      = $Path
							Operation = 'Create'
							Success   = $false
							Message   = 'File already exists.'
						}
					}

					$null = New-Item -Path $Path -ItemType File -ErrorAction Stop
					return [pscustomobject]@{
						Path      = $Path
						Operation = 'Create'
						Success   = $true
						Message   = ''
					}
				}

				'CreatePath' 
				{
					if (-not $FolderExists) 
					{$null = New-Item -Path $Parent -ItemType Directory -Force -ErrorAction Stop}
					if (-not $FileExists) 
					{$null = New-Item -Path $Path -ItemType File -ErrorAction Stop}

					return [pscustomobject]@{
						Path      = $Path
						Operation = 'CreatePath'
						Success   = $true
						Message   = ''
					}
				}

				'Remove' 
				{
					if (-not $FileExists) 
					{
						return [pscustomobject]@{
							Path      = $Path
							Operation = 'Remove'
							Success   = $false
							Message   = 'File does not exist.'
						}
					}

					Remove-Item -Path $Path -ErrorAction Stop
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
