#!/usr/bin/env powershell
#requires -Version 5.0
Function Start-PipeTest
{
	[CmdletBinding()]
	Param (
		[Parameter(DontShow = $True)]
		[String]$PipeName = $Null,
		[Parameter(Dontshow = $True)]
		[String[]]$AccessIdentifier = @(),
		[Parameter(DontShow = $True)]
		[Switch]$AdminRequired,
		[Parameter(DontShow = $True)]
		[Switch]$Wait,
		[Parameter(HelpMessage = 'Bitmask: 0=silent, 1=server/client progress, 2=Show-VerboseData, 4=debug (7=all)')]
		[ValidateRange(0, 7)]
		[int]$InfoDisplay = 0,
		[Parameter(DontShow = $True)]
		[Switch]$NoExitOnError,
		[Parameter(HelpMessage = 'Serialization depth. Default 2. Increase for deeply nested objects (avoid high values for ACL objects)')]
		[ValidateRange(1, 100)]
		[int]$Depth = 2,
		[ValidateRange(1024, 65535)]
		[int]$ChunkSize = 32768,
		[ValidateRange(1, [Int32]::MaxValue)]
		$ServerWaitTimeout = 60,
		[ValidateRange(1, [Int32]::MaxValue)]
		$ClientConnectTimeout=10000

	)

	Remove-Module -name NamedPipe -force -ErrorAction SilentlyContinue
	Import-Module -Name NamedPipe -Force -RequiredVersion 0.7
	function Invoke-RequiredActions
	{
		<#
				.SYNOPSIS
				Describe purpose of "Invoke-RequiredActions" in 1-2 sentences.

				.DESCRIPTION
				Add a more complete description of what the function does.

				.PARAMETER DataObject
				Describe parameter -DataObject.

				.PARAMETER PipeInfo
				Describe parameter -PipeInfo.

				.EXAMPLE
				Invoke-RequiredActions -DataObject Value -PipeInfo Value
				Describe what this call does

				.NOTES
				Place additional notes here.

				.LINK
				URLs to related sites
				The first link is opened by Get-Help -Online Invoke-RequiredActions

				.INPUTS
				List of input types that are accepted by this function.

				.OUTPUTS
				List of output types produced by this function.
		#>

		# Get the current secirity setting on the pipe
		$SendRequestParams.$StrType = $StrSecurity
		$SendRequestParams.$StrDataObject = '' | 
		Send-Request @SendRequestParams

		If ($ServerClientParams.$StrInfoDisplay -band 2)
		{
			# Display the security setting on the pipe
			'{0}' -f $SendRequestParams.$StrDataObject.$StrResult
			'Client user is: [{0}]' -f $SendRequestParams.$StrDataObject.$StrClientUser
			'Server user is: [{0}]' -f $SendRequestParams.$StrDataObject.$StrServerUser
			$count = $SendRequestParams.$StrDataObject.Result.count-1
			'   Security is:'
			if ($PSVersionTable.PSVersion.Major -gt 5) 
			{$SendRequestParams.$StrDataObject.Result.accesstostring}
			else
			{$SendRequestParams.$StrDataObject.Result[0..$count]}
			Show-VerboseData -Object $SendRequestParams.$StrDataObject -Display -Title 'Data Object After Security call'
		}
	
		$SendRequestParams.$StrType = $StrScriptBlock
	
		#Remove-Breakpoints -All
		#$BPList = Initialize-BPList -AddModules
	
		#$BPList.'Start-PipeServerorClient'.lines.line = 140
		#$BPList.'Start-PipeServerorClient'.lines.Script = $BPList.'Start-PipeServerorClient'.Fullname
		#$BPList.'Receive-Data'.lines.line = 22
		#$BPList.'Receive-Data'.lines.Script = $BPList.'Receive-Data'.Fullname
		#$BPList.'Get-SBResult'.lines.line=30
		#$BPList.'Get-SBResult'.lines.Script=$BPList.'Get-SBResult'.Fullname

		# Set any defined breakpoints
		#$SendRequestParams.$StrDataObject.$StrData = $BPList
		#$SendRequestParams.$StrDataObject = 'Set-Breakpoints -BPObject $DataObject.data' | 
		#Send-Request @SendRequestParams
		#$BPList = $SendRequestParams.$StrDataObject.$StrResult
	
		#$BPList = Initialize-BPList -AddModules
		#$BPList.'Get-SBResult'.lines.line=12
		#$BPList.'Get-SBResult'.lines.Script=$BPList.'Get-SBResult'.Fullname
		#$BPList.'Show-VerboseData'.lines.line = 106
		#$BPList.'Show-VerboseData'.lines.Script = $BPList.'Show-VerboseData'.Fullname
			
		#$SendRequestParams.$StrDataObject.$StrData = $BPList
		#$SendRequestParams.$StrDataObject = 'Set-Breakpoints -BPObject $DataObject.data' |
		#Send-Request @SendRequestParams
		#$BPList = $SendRequestParams.$StrDataObject.$StrResult
	
		#$SendRequestParams.$StrDataObject.$Strdata = $BPList
		#$SendRequestParams.$StrDataObject = 'Set-Breakpoints -BPObject $DataObject.data' | 
		#Send-Request @SendRequestParams
	
		$SWParam =@{
			Passthru =$true
			Set = $True
		}
	
		$SendRequestParams.$StrDataObject.$StrParameters = $SWParam
		$SendRequestParams.$StrDataObject = 'Set-Window -ProcessId {0} -State {1}' -f $SendRequestParams.$StrDataObject.$StrServerPID, $StrRestore|
		Send-Request @SendRequestParams
	
		if ($SendRequestParams.$StrDataObject.$StrError)
		{write-information -MessageData $SendRequestParams.$StrDataObject.$StrError -InformationAction Continue}
	
		$SendRequestParams.$StrDataObject = 'Write-Host -Object "{0}" -Foreground Green' -f 'Hello World' |
		Send-Request @SendRequestParams
		$SendRequestParams.$StrDataObject = 'Set-Window -ProcessId {0} -State {1} -Set -Passthru' -f $SendRequestParams.$StrDataObject.$StrServerPID, $StrMinimize|
		Send-Request @SendRequestParams
		$WindowInfo = $SendRequestParams.$StrDataObject.$StrResult
	
		$SendRequestParams.$StrDataObject = 'Write-Host -Object "{0}" -Foreground red' -f 'Hello World'|
		Send-Request @SendRequestParams

		# ===== HEALTH PIPE CHECK =====

		Write-Host ("`n[Health1] Testing health pipe for [{0}]..." -f $ServerClientParams.$StrPipeInfo.$StrName) -ForegroundColor Cyan
		$HealthResult1 = Test-PipeSession -PipeInfo $ServerClientParams.$StrPipeInfo

		If ($HealthResult1)
		{ Write-Host "[Health1] PING/PONG OK - server process confirmed alive." -ForegroundColor Green }
		Else
		{ Write-Host "[Health1] PING/PONG FAILED - server may not be responding." -ForegroundColor Red }
	
		Get-PSCallStack
	
		$SendRequestParams.$StrDataObject = 'Set-Window -ProcessId ${0} -Passthru' -f 'pid'|
		Send-Request @SendRequestParams
		If ($ServerClientParams.$StrInfoDisplay -band 2)
		{Show-VerboseData -Object $SendRequestParams.DataObject -Display -Title 'Data Object Set-Window call'}
	
		$SendRequestParams.$StrDataObject = 'Set-Window -ProcessId {0} -State {1} -Set -Passthru -characters' -f $SendRequestParams.$StrDataObject.$StrServerPID, $StrRestore|
		Send-Request @SendRequestParams
		#start-sleep -Seconds 5
		#$SendRequestParams.DataObject = 'Get-MyDiskInfo -disknumber 0 '| Send-Request @SendRequestParams
		#D:\PowerShellScripts\DisplayMyDisks\Display-MyDisks.ps1 -DiskInfo $SendRequestParams.DataObject.Result -sdisk
	
		#Start-Sleep -Seconds 5
	
		# Remove any defined breakpoints
		#$SendRequestParams.$StrDataObject.data = $BPList
		#$SendRequestParams.$StrDataObject = 'Remove-Breakpoints -BPObject $DataObject.data' |
		#Send-Request @SendRequestParams
	
	}

	#############################
	# End of Functions
	#############################
	$Private:MyBoundParameters = $PSCmdlet.MyInvocation.BoundParameters
	$Global:Error.Clear()

	('Module version is {0}' -f $ModuleVersion) | Write-Host 

	#$BPList.'Get-SBResult'.lines.Script=$BPList.'Get-SBResult'.Fullname
	#$BPList.'Set-Breakpoints'.lines.line=17
	#$BPList.'Set-Breakpoints'.lines.Script=$BPList.'Set-Breakpoints'.Fullname
	#Set-PSBreakpoint -Line 12 -Script $BPlist.'Get-SBResult'.Fullname
	#$BPList = Initialize-BPList -AddModules

	#$BPList.'Start-PipeTest'.lines.Line=145
	#$BPList.'Start-PipeTest'.lines.Script=$BPList.'Start-PipeTest'.Fullname

	#$BPList.'Send-Request'.lines.Line=32
	#$BPList.'Send-Request'.lines.Script=$BPList.'Send-Request'.Fullname

	#$BPList.'Set-Breakpoints'.lines.line=17
	#$BPList.'Set-Breakpoints'.lines.Script=$BPList.'Set-Breakpoints'.Fullname

	#$BPList = Set-Breakpoints -BPObject $BPList
	#$BPList = Remove-Breakpoints -BPObject $BPList
	#Set-psbreakpoint -line 70 -script 'L:\OneDrive\Documents\WindowsPowerShell\Modules\NamedPipe\0.2\FunctionsWindows\Send-data.ps1'
	$Private:MyOptions = Set-ObjectParams -Dataset $StrMyOptions -MyParameters $Private:MyBoundParameters
	# These options can be set to enable various options but can also be part of a script's parameters at startup
	#$MyOptions.$StrInfoDisplay = $InfoDisplay # Bitmask: 0=silent, 1=server/client progress, 2=Show-VerboseData, 4=debug output (combine: 3=1+2, 7=all)
	#$MyOptions.$StrNoExitOnError = $NoExitOnError # The powershell window will not close when an error has occured
	#$MyOptions.$StrAdminRequired = $AdminRequired # Set to true in the server process needs to run as administrator
	#$MyOptions.$StrVerbose = $False # Will pass the -verbose option if required when true
	#$MyOptions.$StrWait = $Wait # Will cause the server window to remain open when the pipe is exited
	#$MyOptions.$StrWindowStyle = $StrMinimized
	$Private:MyOptions.$StrWindowStyle = $StrNormal
	#$MyOptions.$StrChunkSize = $ChunkSize # Chunk size for large data transfers (32KB default, 0 = no chunking)
	#$MyOptions.$StrDepth = $Depth # Serialization depth (default 2, avoid >10 for ACL objects)
	#$MyOptions.$StrServerWaitTimeout = $ServerWaitTimeout 
	#$MyOptions.$StrClientConnectTimeout=$ClientConnectTimeout

	# The serverClientParams dataset is populated with MyOptions as this dataset already contains any script supplied parameters

	$Session = Start-PipeSession -MyParameters $Private:MyOptions
	$ServerClientParams = $Session.$StrServerClientParams
	$SendRequestParams  = $Session.$StrSendRequestParams


	# ===== HEALTH PIPE CHECK =====

	Write-Host ("`n[Health] Testing health pipe for [{0}]..." -f $ServerClientParams.$StrPipeInfo.$StrName) -ForegroundColor Cyan
	$HealthResult = Test-PipeSession -PipeInfo $ServerClientParams.$StrPipeInfo

	If ($HealthResult)
	{ Write-Host "[Health] PING/PONG OK - server process confirmed alive." -ForegroundColor Green }
	Else
	{ Write-Host "[Health] PING/PONG FAILED - server may not be responding." -ForegroundColor Red }

	Get-PSCallStack
	
	Invoke-RequiredActions

	# ===== POST-ACTION HEALTH CHECK =====

	Write-Host "`n[Health2] Post-action health check..." -ForegroundColor Cyan
	$HealthResult2 = Test-PipeSession -PipeInfo $ServerClientParams.$StrPipeInfo

	If ($HealthResult2)
	{ Write-Host "[Health2] Server still alive after actions completed." -ForegroundColor Green }
	Else
	{ Write-Host "[Health2] Post-action health check FAILED." -ForegroundColor Red }

	Stop-PipeSession -SendRequestParams $SendRequestParams -PipeInfo $ServerClientParams.$StrPipeInfo

}
Get-PSBreakpoint
# Remove-Breakpoints -All
Start-PipeTest