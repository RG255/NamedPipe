# In the following tables defining variables:
#
# Option can be one of the following: AllScope, Private, Constant, ReadOnly, None
# Scope  can be one of the following: Global, Local, Script , Using, Workflow
# See Microsoft documentation for full descriptions.
#
# To use the regular expressions below:
#
# Does the item your testing match the expresion:
#
# if (($RegexComment.Match($Item).Success)){'It is a comment'}else{'It is not a comment'}
#
# To get the item itself use the name defined in the expression:
#
# $Result = $RegexFile.Match($Item)
# $Length = $Result.Groups['file'].length - will return the length of the 'file' group
# $Entry = $Result.Groups['file'].value - will return the value of the 'file' group
#
# Alternativly you can use:
#
# If ($Item -match $RegexFile)
# {$matches['file']} # to display the item if a match is found
#
# Both ways return different attributes it depends how you want to use the results
#
# NOTE: To get the captured group information the name is case sensitive.
#'file' is OK but 'File' is not!
#
# Add variables that you can use later in the 'MyConstantVars' hash table
#
# Variables defined in the 'MyOtherVars' hashtable can make use of the variables defined above
# in the 'MyConstantVars' or 'MyReadOnlyVars' hashtable
#
# NOTE: If any variables are defined in 'MyConstantVars' you will not be able to force a
# reload of the module, you will have to start a new PowerShell session.
#
# The option on the constant Variables is read only to make testing easier
#
#$MyVars = [Ordered]@{
#}
#Publish-Variables -Variables $MyVars
#$MyVars = @{
#}
#Publish-Variables -Variables $MyVars
$MyVars = [Ordered]@{
	N03OtherVars = @{
		StrError              = @{
			Value  = 'Error'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module'
		}
		StrResult             = @{
			Value  = 'Result'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module'
		}
		StrType               = @{
			Value  = 'Type'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module'
		}
		StrRequest            = @{
			Value  = 'Request'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module'
		}
		StrLastRequest        = @{
			Value  = 'LastRequest'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module'
		}
		StrScriptBlock        = @{
			Value  = 'ScriptBlock'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module'
		}
		StrSecurity           = @{
			Value  = 'Security'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module'
		}
		StrExitPipe           = @{
			Value  = 'ExitPipe'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module'
		}
		StrServer             = @{
			Value  = 'Server'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module'
		}
		StrServerUser         = @{
			Value  = 'ServerUser'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module'
		}
		StrServerPID          = @{
			Value  = 'ServerPID'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module'
		}
		StrClient             = @{
			Value  = 'Client'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module'
		}
		StrClientUser         = @{
			Value  = 'ClientUser'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module'
		}
		StrClientPID          = @{
			Value  = 'ClientPID'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module'
		}
		StrFromServerOrClient = @{
			Value  = 'FromServerOrClient'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module'
		}
		StrWait               = @{
			Value  = 'Wait'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module'
		}
		StrParameters         = @{
			Value  = 'Parameters'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module'
		}
		StrLastParameters     = @{
			Value  = 'LastParameters'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module'
		}
		StrData               = @{
			Value  = 'Data'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module'
		}
		StrLastData           = @{
			Value  = 'LastData'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module'
		}
		StrAction             = @{
			Value  = 'Action'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module'
		}
		StrBreakpoint         = @{
			Value  = 'BreakPoint'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module'
		}
		StrBreakPointID       = @{
			Value  = 'BreakPointId'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module'
		}
		StrInfoDisplay        = @{
			Value  = 'InfoDisplay'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module'
		}
		InfoDisplayBitProgress = @{
			Value  = [Int]1
			Scope  = $VSScript
			Option = $VOReadOnly
			Use    = 'InfoDisplay bitmask bit 1: [Server] Executing echo in Get-SBResult'
		}
		InfoDisplayBitVerbose  = @{
			Value  = [Int]2
			Scope  = $VSScript
			Option = $VOReadOnly
			Use    = 'InfoDisplay bitmask bit 2: Show-VerboseData dumps'
		}
		InfoDisplayBitDebug    = @{
			Value  = [Int]4
			Scope  = $VSScript
			Option = $VOReadOnly
			Use    = 'InfoDisplay bitmask bit 4: Debug Write-Host in Send-Data/Receive-Data'
		}
		StrAdminRequired      = @{
			Value  = 'AdminRequired'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module'
		}
		StrNoExitOnError      = @{
			Value  = 'NoExitOnError'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module'
		}
		StrAccessIdentifier   = @{
			Value  = 'AccessIdentifier'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module'
		}
		StrWindowStyle        = @{
			Value  = 'WindowStyle'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module'
		}
		StrSpawned            = @{
			Value  = 'Spawned'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module'
		}
		StrMyOptions          = @{
			Value  = 'MyOptions'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module'
		}
		StrPipeParams         = @{
			Value  = 'PipeParams'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in Set-objectParams'
		}
		StrPipeName           = @{
			Value  = 'PipeName'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in Set-objectParams'
		}
		StrPipeInfo           = @{
			Value  = 'PipeInfo'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in Set-objectParams'
		}
		StrPipe               = @{
			Value  = 'Pipe'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in Set-objectParams'
		}
		StrName               = @{
			Value  = 'Name'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in Set-objectParams'
		}
		StrVersion               = @{
			Value  = 'Version'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in Set-objectParams and Start-ServerOrClient.ps1'
		}
		StrReader             = @{
			Value  = 'Reader'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in Set-objectParams'
		}
		StrWriter             = @{
			Value  = 'Writer'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in Set-objectParams'
		}
		StrDataObject         = @{
			Value  = 'DataObject'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in Set-objectParams'
		}
		StrServerClientParams = @{
			Value  = 'ServerClientParams'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in Set-objectParams'
		}
		StrSendRequestParams  = @{
			Value  = 'SendRequestParams'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in Set-objectParams'
		}
		StrChunkSize          = @{
			Value  = 'ChunkSize'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module for chunked transfers'
		}
		StrDepth              = @{
			Value  = 'Depth'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module for serialization depth'
		}
		StrServerWaitTimeout              = @{
			Value  = 'ServerWaitTimeout'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module for server wait timeout (seconds)'
		}
		StrClientConnectTimeout              = @{
			Value  = 'ClientConnectTimeout'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in NamedPipe module for client connect timeout (milliseconds)'
		}
		StrModuleToLoad                      = @{
			Value  = 'ModuleToLoad'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Hashtable with Name/Version of module to import in spawned server'
		}
		StrRedactPattern                     = @{
			Value  = 'RedactPattern'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Hashtable with Option/Pattern/Command for [Server] Executing: display redaction'
		}
		RedactBitBuiltIn                     = @{
			Value  = [Int]1
			Scope  = $VSScript
			Option = $VOReadOnly
			Use    = 'RedactPattern bitmask bit 1: built-in generic long Base64/hex redaction'
		}
		RedactBitPattern                     = @{
			Value  = [Int]2
			Scope  = $VSScript
			Option = $VOReadOnly
			Use    = 'RedactPattern bitmask bit 2: consumer-supplied regex Pattern'
		}
		RedactBitCommand                     = @{
			Value  = [Int]4
			Scope  = $VSScript
			Option = $VOReadOnly
			Use    = 'RedactPattern bitmask bit 4: consumer-supplied ScriptBlock Command'
		}
	}
}
Publish-Variables -Variables $MyVars
$MyVars = @{
	N09Finalise = @{
		DefineVariablesPipe = @{
			Value  = $True
			Scope  = $VSScript
			Option = $VOReadOnly
			Use    = 'Set-Window'
		}
	}
}
Publish-Variables -Variables $MyVars
