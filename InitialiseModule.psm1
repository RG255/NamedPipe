#!/usr/bin/env powershell
#requires -Version 5.0
#
<#
		.SYNOPSIS
		This is a script to simplify the use and management of a powershell module
		.DESCRIPTION
		This psm1 file will define variables, custom XML and functions as found in the directories:

		- Functions
		- FunctionsWindows
		- FunctionsLinux
		- FunctionsMacOS

		This initialise script will create any missing directories for completeness

		the psm1 will process the following files first if defined in the above directories

		Define-Variables.ps1
		Define-CustomXML.ps1

		See the contents of these files for an explanation of how to define the items within.
    
		any number of:

		xxx-xxx.ps1 

		files, where xxx-xxx is the name of the root function in the file, nothing else is required

		.EXAMPLE

		Typically a ps1 script wishing to make use of this module would define this line at the start
		of the ps1 file, this would cause all the appropriate items to be defined for the ps1 script
		to use while it is running.

		Remove-Module NamedPipe -Force -ErrorAction SilentlyContinue
		Import-Module NamedPipe -RequiredVersion 0.1

		Where -RequiredVersion 0.1 is the version of the module to use, there can be multiple
		versions of the same module as its functionality is improved or expanded.
#> 
try
{
	Function Publish-CustomXML
	{
		<#
				.SYNOPSIS
				Takes an XML definition that updates formatting data and applies is acording to the 
				definitions within.

				.DESCRIPTION
				As above

				.EXAMPLE
				Calling Publish-CustomXML
				Will look for any .ps1xml in the Function* folders and process the contents
		#>
		ForEach ($Item in ($MyCustomXML.GetEnumerator() | Sort-Object -Property key).Name)
		{
			$XMLItem = (Join-Path -Path $ModuleScriptRoot -ChildPath ('Functions{0}\{1}' -f $Option, $MyCustomXML[$Item].file))
			If (Test-Path -Path $XMLItem)
			{
				Switch ($MyCustomXML[$Item].Action)
				{
					'Update-FormatData'
					{
						Switch ($MyCustomXML[$Item].Option)
						{
							'Prependpath'
							{Update-FormatData -PrependPath $XMLItem -ErrorAction Stop}
							'Appendpath'
							{Update-FormatData -AppendPath $XMLItem -ErrorAction Stop}
						}
					}
					Default
					{'Unknown item in {0}MyCustomXML: [{1}] Option: [{2}]' -f $StrDollar, $Item, $MyCustomXML[$Item].Option | Write-Warning}
				}
			}
		} # End of Custom XML processing
	}
	
	Function Initialize-Folders
	{
		[CmdletBinding()]
		Param (
			[Parameter(Mandatory, HelpMessage = 'A List of folders to create')]
			[Array] $Folders
		)
	
		foreach ($Item in $Folders)
		{
			$Path = Join-Path -Path $ModuleScriptRoot -ChildPath $Item
			If (-not (Test-Path -Path $Path))
			{New-Item -Path $Path -ItemType Directory}
		}
	}
	Function Publish-Variables
	{
		<#
				.SYNOPSIS
				Takes the definitions in $Variables and processes them into the variables defined.
        
				.DESCRIPTION
				As Above
        
				.EXAMPLE
				Publish-Variables is called from the file Define-Variables.ps1 which is executed as part
				of this psm1 file when the module is initialised.
        
				.EXAMPLE
				Publish-Variables
		#>
		Param ([hashtable]$Variables)
		Try
		{
			ForEach ($VarSet in ($Variables.GetEnumerator() | Sort-Object -Property key).Name)
			{
				ForEach ($Item in ($Variables[$VarSet].GetEnumerator() | Sort-Object -Property key).Name)
				{
					$Params = @{
						Name   = $Null
						Value  = $Null
						Option = $Null
						Scope  = $Null
					}
					If (Test-Path -Path ('Variable:{0}:{1}' -f $Variables[$VarSet][$Item].Scope, $Item))
					{
						$Params = @{
							Name  = $Item
							Scope = $Variables[$VarSet][$Item].Scope
						}
						If ($Params.Scope -inotmatch $VOConstant)
						{Remove-Variable @Params -Force}
					}
					$Params = @{
						Name   = $Item
						Value  = $Variables[$VarSet][$Item].Value
						Option = $Variables[$VarSet][$Item].Option
						Scope  = $Variables[$VarSet][$Item].Scope
					}
					New-Variable @Params -ErrorAction Stop
					Export-ModuleMember -Variable $Item -ErrorAction Stop
					If ($VInfoOn)
					{
						$Msg = 'Variable:[{0}] created Value: [{1}]' -f $Item, $Params.Value
						Write-Information -MessageData $Msg -InformationAction Continue
					}
				}
			}
		}
		Catch
		{
			$Msg = 'Variable:[{0}] Failed to create Value: [{1}]' -f $Item, $Params.Value
			Write-Information -MessageData $Msg -InformationAction Continue
		}
	}
	Function Get-Psd1Data
	{
		<#
				.SYNOPSIS
				Returns the data in the psd1 file as a hashtable

				.DESCRIPTION
				Returns the data in the psd1 file as a hashtable

				.PARAMETER PathToPsd1file
				Gives the path to the psd1 file for this module.

				.EXAMPLE
				Get-Psd1Data -PathToPsd1file <path> e.g. c:\MyModule\Module.psd1
				Returns the data in the psd1 file as a hashtable

				.INPUTS
				-PathToPsd1file as above.

				.OUTPUTS
				A hashtable of the psd1 file's contents e.g:

				Name                           Value                                                                                                                                      
				----                           -----                                                                                                                                      
				ProcessorArchitecture                                                                                                                                                     
				PrivateData                                                                                                                                                               
				Description                    Rays set of useful functions                                                                                                               
				CLRVersion                                                                                                                                                                
				CmdletsToExport                *                                                                                                                                          
				Copyright                      (c) 2022 RayG. All rights reserved.                                                                                                        
				CompanyName                    RayG                                                                                                                                       
				Author                         RayG                                                                                                                                       
				FileList                       {}                                                                                                                                         
				PowerShellHostName                                                                                                                                                        
				PowerShellVersion              3.0                                                                                                                                        
				RequiredModules                {}                                                                                                                                         
				NestedModules                  {}                                                                                                                                         
				GUID                           388bc9ce-ab02-4459-861a-704d025c2b35                                                                                                       
				RootModule                     InitialiseModule.psm1                                                                                                                      
				VariablesToExport              *                                                                                                                                          
				AliasesToExport                *                                                                                                                                          
				FormatsToProcess               {}                                                                                                                                         
				RequiredAssemblies             {}                                                                                                                                         
				ModuleVersion                  0.6                                                                                                                                        
				ModuleList                     {}                                                                                                                                         
				ScriptsToProcess               {}                                                                                                                                         
				PowerShellHostVersion                                                                                                                                                     
				DotNetFrameworkVersion         4.0                                                                                                                                        
				FunctionsToExport              *                                                                                                                                          
				TypesToProcess                 {} 
		#>
		[CmdletBinding()]
		Param (
			[Parameter(Mandatory, HelpMessage = 'Path to psd1 file for this module required.')]
			[Microsoft.PowerShell.DesiredStateConfiguration.ArgumentToConfigurationDataTransformation()]
			[HashTable] $PathToPsd1file
		)
		$PathToPsd1file
	}
	Function Publish-MyEnvironment
	{
		<#
				.SYNOPSIS
				Looks for the files Define-Variables.ps1 & Define-CustomXML.ps1 in the Function* 
				folders in the same location as the psm1 file is located when it is executed.
        
				.DESCRIPTION
				As Above
        
				If either if the files is located they will be dot sourced and their contents processed

				.PARAMETER
				-Option

				This parameter will take three alternatives: Windows, Linux & MacOS
				This allows for operating system specific definitions to be created.
				Things that work in Windows will not necessarily work in Linux or MacOS

				The folder Funtions is for items that can be used on any Operating System and as
				such -Option can be omitted on the command line.

				.EXAMPLE
				Publish-Variables
				or 
				Publish-Variables -Option [Windows|Linux|MacOS]
		#>
		[CmdletBinding()]
		Param (
			[ValidateSet('Windows','Linux','MacOS')]
			[String]$Option = ''
		)
		foreach ($Item in ($PSD1Data.PrivateData.ModuleVars[$Option].keys | Sort-Object))
		{
			$FilePath = Join-Path -Path $ModuleScriptRoot -ChildPath ('Functions{0}\{1}' -f $Option, $PSD1Data.PrivateData.ModuleVars[$Option][$Item]) -ErrorAction Stop
			If (Test-Path -Path $FilePath)
			{
				# Dot-source the DefineVariables file to load its variables
				. $FilePath
			}
		}
	}
	Function Invoke-InitFunctions
	{
		<#
				.SYNOPSIS
				Calls initialization functions defined in PSD1 PrivateData.InitFunctions

				.DESCRIPTION
				Processes the InitFunctions hashtable from PSD1 and calls each function.
				Currently supports Set-Window for Windows initialization.

				.PARAMETER Option
				The OS option (Windows, Linux, MacOS) or empty string for common functions.

				.EXAMPLE
				Invoke-InitFunctions
				Invoke-InitFunctions -Option 'Windows'
		#>
		[CmdletBinding()]
		Param (
			[ValidateSet('Windows','Linux','MacOS')]
			[String]$Option = ''
		)
		if ($PSD1Data.PrivateData.InitFunctions -and $PSD1Data.PrivateData.InitFunctions[$Option])
		{
			foreach ($Key in ($PSD1Data.PrivateData.InitFunctions[$Option].keys | Sort-Object))
			{
				$InitFunc = $PSD1Data.PrivateData.InitFunctions[$Option][$Key]
				if ($InitFunc.Function -and (Get-Command $InitFunc.Function -ErrorAction SilentlyContinue))
				{
					# No init functions are currently wired - PrivateData.InitFunctions is empty on every OS.
					# The only handler used to be a Set-Window -Characters warm-up, removed with Set-Window in
					# 0.12 (NamedPipe now only hides/restores via Set-MyWindowState). If a future init function
					# needs invoking at load, add its handling in this block.
					Write-Verbose -Message ('Invoke-InitFunctions: no handler for [{0}] - skipped.' -f $InitFunc.Function)
				}
			}
		}
	}
	$Global:Error.clear() # Clear existing errors
	$ModuleScriptRoot = $PSScriptRoot # Save PSScriptRoot
	$ModuleName = (Split-Path -Path (Split-Path -Path $ModuleScriptRoot -Parent) -Leaf) # Get the Module name
	$PSD1Path = (Join-Path -Path $ModuleScriptRoot -ChildPath ('{0}.{1}' -f $ModuleName, 'psd1')) # Get modules psd1 file name
	# Get the data from the modules psd1 file
	$PSD1Data = Get-Psd1Data -PathToPsd1file ('{0}' -f $PSD1Path)
} # End of the initial module initialisation process
catch
{
	# if any error occurs output salient information
	$NumberOfErrors = [int]$Global:Error.count
	$ErrorNumber = $NumberOfErrors - 1
	'{1}{1}An error occurred while processing: [{0}]{1}{1}Message      : [{2}]{1}Command Path : [{3}]{1}Line No.     : [{4}]{1}Failing Line :Command Path: [{5}]{1}{1}' -f (Join-Path -Path $ModuleScriptRoot -ChildPath $PSD1Data.RootModule), "`r`n", 
	($Global:Error[$ErrorNumber].Exception.Message).Replace(('{0}' -f "`r`n"), ''), 
	$Global:Error[$ErrorNumber].InvocationInfo.PSCommandPath, 
	$Global:Error[$ErrorNumber].InvocationInfo.ScriptLineNumber, 
	($Global:Error[$ErrorNumber].InvocationInfo.Line).Trim() | Write-Warning
	throw 'Unable to retrieve required data from: [{0}]' -f $PSD1Path
}
try
{
	# Create any Missing folders
	Initialize-Folders -Folders 'Functions', 'FunctionsLinux', 'FunctionsWindows', 'FunctionsMacOS'
	# Define common variables and custom XML
	Publish-MyEnvironment
	# Check if we should export all functions (for testing)
	$ExportAll = ($env:NAMEDPIPE_EXPORT_ALL -eq '1')

	# Variables and Custom XML are defined in the 'Function(*)' Folders
	# exclude them from being processed as functions.
	$VarDefFiles = @($PSD1Data.PrivateData.ModuleVars[''].Values)
	$Exclude = @('Define-CustomXML|DefineVariables|{0}$' -f $StrExtZip)
	# Process all common functions
	$MyPath = (Join-Path -Path $ModuleScriptRoot -ChildPath ('Functions\*{0}' -f $StrExtPS1) -ErrorAction Stop)
	# Get a list of *.ps1 files that should contain a function of the same name
	$MyFunctions = (Get-ChildItem -Path $MyPath -ErrorAction stop | Where-Object {$_.Name -inotmatch $Exclude -and $_.Name -notin $VarDefFiles} )
	# Define and execute common functions  
	ForEach ($Item in $MyFunctions)
	{
		If ($FInfoOn)
		{
			$Msg = 'Processing Function:[{0}]' -f $Item.FullName
			Write-Information -MessageData $Msg -InformationAction Continue
		}
		. $Item.Fullname
		if (-not (Get-Command $Item.BaseName -CommandType Function,Filter -ErrorAction SilentlyContinue))
		{Write-Host "Function [$($Item.BaseName)] was NOT created by file [$($Item.Name)]"}
		else
		{
			$funcName = $Item.BaseName
			# Export all if env var set, otherwise check export table
			$shouldExport = $true  # Default to export if not in table
			if (-not $ExportAll -and $script:FunctionExportTable -and $script:FunctionExportTable.ContainsKey($funcName)) 
			{$shouldExport = $script:FunctionExportTable[$funcName]}
			if ($shouldExport) 
			{
				Export-ModuleMember -Function $funcName -ErrorAction Stop		
				If ($FInfoOn)
				{
					$Msg = ' Function exported:[{0}]' -f $Item.FullName
					Write-Information -MessageData $Msg -InformationAction Continue
				}
			}
		}
	}
	# OS-specific functions 2=Windows 4=Linux 6=MacOS
	switch ([System.Environment]::OSVersion.Platform.value__) {
		2
		{
			# Define Windows specific variables and custom XML
			Publish-MyEnvironment -Option 'Windows'
			# Variables and Custom XML are defined in the 'Function(*)' Folders
			# exclude them from being processed as functions - use PSD1 ModuleVars as source of truth
			$VarDefFiles = @($PSD1Data.PrivateData.ModuleVars['Windows'].Values)
			$Exclude = @('Define-CustomXML|{0}$' -f $StrExtZip)
			# Process all Windows specific functions
			$MyPath = (Join-Path -Path $ModuleScriptRoot -ChildPath ('FunctionsWindows\*{0}' -f $StrExtPS1) -ErrorAction Stop)
			$MyFunctions = (Get-ChildItem -Path $MyPath -ErrorAction stop | Where-Object {$_.Name -inotmatch $Exclude -and $_.Name -notin $VarDefFiles} )
			ForEach ($Item in $MyFunctions)
			{
				$Base = $Item.Basename
				#$base | Write-Host
				If ($FWInfoOn)
				{
					$Msg = 'Exporting W-Function:[{0}]' -f $Item.FullName
					Write-Information -MessageData $Msg -InformationAction Continue
				}
				. $Item.Fullname
				if (-not (Get-Command $Item.BaseName -CommandType Function,Filter -ErrorAction SilentlyContinue))
				{Write-Host "Function [$($Item.BaseName)] was NOT created by file [$($Item.Name)]"}
				else
				{
					$funcName = $Item.BaseName
					# Export all if env var set, otherwise check export table
					$shouldExport = $true  # Default to export if not in table
					if (-not $ExportAll -and $script:FunctionExportTable -and $script:FunctionExportTable.ContainsKey($funcName)) 
					{$shouldExport = $script:FunctionExportTable[$funcName]}
					if ($shouldExport)
					{
						Export-ModuleMember -Function $funcName -ErrorAction Stop
						If ($FWInfoOn)
						{
							$Msg = ' W-Function exported:[{0}]' -f $Item.FullName
							Write-Information -MessageData $Msg -InformationAction Continue
						}
					}
				}
			}
			# Call initialization functions defined in PSD1
			Invoke-InitFunctions -Option 'Windows'
		}
		4
		{
			# Define Linux specific variables and custom XML
			Publish-MyEnvironment -Option 'Linux'
			# Variables and Custom XML are defined in the 'Function(*)' Folders
			# exclude them from being processed as functions - use PSD1 ModuleVars as source of truth
			$VarDefFiles = @($PSD1Data.PrivateData.ModuleVars['Linux'].Values)
			$Exclude = @('Define-CustomXML|{0}$' -f $StrExtZip)
			# Process all Linux specific functions
			$MyPath = (Join-Path -Path $ModuleScriptRoot -ChildPath ('FunctionsLinux\*{0}' -f $StrExtPS1) -ErrorAction Stop)
			$MyFunctions = (Get-ChildItem -Path $MyPath -ErrorAction stop | Where-Object {$_.Name -inotmatch $Exclude -and $_.Name -notin $VarDefFiles} )
			ForEach ($Item in $MyFunctions)
			{
				$Base = $Item.Basename
				If ($FLInfoOn)
				{
					$Msg = 'Exporting L-Function:[{0}]' -f $Item.FullName
					Write-Information -MessageData $Msg -InformationAction Continue
				}
				. $Item.Fullname
				if (-not (Get-Command $Item.BaseName -CommandType Function,Filter -ErrorAction SilentlyContinue))
				{Write-Host "Function [$($Item.BaseName)] was NOT created by file [$($Item.Name)]"}
				else
				{
					$funcName = $Item.BaseName
					# Export all if env var set, otherwise check export table
					$shouldExport = $true  # Default to export if not in table
					if (-not $ExportAll -and $script:FunctionExportTable -and $script:FunctionExportTable.ContainsKey($funcName)) 
					{$shouldExport = $script:FunctionExportTable[$funcName]}
					if ($shouldExport)
					{
						Export-ModuleMember -Function $funcName -ErrorAction Stop
						If ($FWInfoOn)
						{
							$Msg = ' W-Function exported:[{0}]' -f $Item.FullName
							Write-Information -MessageData $Msg -InformationAction Continue
						}
					}
				}
			}
		}
		6
		{
			# Define MacOS specific variables and custom XML
			Publish-MyEnvironment -Option 'MacOS'
			# Variables and Custom XML are defined in the 'Function(*)' Folders
			# exclude them from being processed as functions - use PSD1 ModuleVars as source of truth
			$VarDefFiles = @($PSD1Data.PrivateData.ModuleVars['MacOS'].Values)
			$Exclude = @('Define-CustomXML|{0}$' -f $StrExtZip)
			# Process all MacOS specific functions
			$MyPath = (Join-Path -Path $ModuleScriptRoot -ChildPath ('FunctionsMacOS\*{0}' -f $StrExtPS1) -ErrorAction Stop)
			$MyFunctions = (Get-ChildItem -Path $MyPath -ErrorAction stop | Where-Object {$_.Name -inotmatch $Exclude -and $_.Name -notin $VarDefFiles} )
			ForEach ($Item in $MyFunctions)
			{
				$Base = $Item.Basename
				If ($FMInfoOn)
				{
					$Msg = 'Exporting M-Function:[{0}]' -f $Item.FullName
					Write-Information -MessageData $Msg -InformationAction Continue
				}
				. $Item.Fullname
				if (-not (Get-Command $Item.BaseName -CommandType Function,Filter -ErrorAction SilentlyContinue))
				{Write-Host "Function [$($Item.BaseName)] was NOT created by file [$($Item.Name)]"}
				else
				{
					$funcName = $Item.BaseName
					# Export all if env var set, otherwise check export table
					$shouldExport = $true  # Default to export if not in table
					if (-not $ExportAll -and $script:FunctionExportTable -and $script:FunctionExportTable.ContainsKey($funcName)) 
					{$shouldExport = $script:FunctionExportTable[$funcName]}
					if ($shouldExport)
					{
						Export-ModuleMember -Function $funcName -ErrorAction Stop
						If ($FWInfoOn)
						{
							$Msg = ' W-Function exported:[{0}]' -f $Item.FullName
							Write-Information -MessageData $Msg -InformationAction Continue
						}
					}
				}
			}
		}
		Default
		{throw 'Operating System Unknown'}
	}
	# Return information about who initiated the load of this module
	$MyInitialCallStack = Get-PSCallStack
	$MyInitialCallingScript = $MyInitialCallStack.InvocationInfo.MyCommand[1].ScriptBlock
}
Catch
{
	# if any error occurs output salient information
	$NumberOfErrors = [int]$Global:Error.count
	$ErrorNumber = $NumberOfErrors - 1
	'{1}{1}An error occurred while processing: [{0}]{1}{1}Message      : [{2}]{1}Command Path : [{3}]{1}Line No.     : [{4}]{1}Failing Line :Command Path: [{5}]{1}{1}' -f (Join-Path -Path $ModuleScriptRoot -ChildPath $PSD1Data.RootModule), "`r`n", 
	($Global:Error[$ErrorNumber].Exception.Message).Replace(('{0}' -f "`r`n"), ''), 
	$Global:Error[$ErrorNumber].InvocationInfo.PSCommandPath, 
	$Global:Error[$ErrorNumber].InvocationInfo.ScriptLineNumber, 
	($Global:Error[$ErrorNumber].InvocationInfo.Line).Trim() | Write-Warning
	throw 'Unable to initialise module: {0}' -f $ModuleName
}
