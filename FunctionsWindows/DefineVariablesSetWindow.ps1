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
		StrForceMinimize   = @{
			Value  = 'ForceMinimize'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in Set-Window'
		}
		StrHide            = @{
			Value  = 'Hide'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in Set-Window'
		}
		StrMaximize        = @{
			Value  = 'Maximize'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in Set-Window'
		}
		StrMinimize        = @{
			Value  = 'Minimize'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in Set-Window'
		}
		StrRestore         = @{
			Value  = 'Restore'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in Set-Window'
		}
		StrShow            = @{
			Value  = 'Show'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in Set-Window'
		}
		StrShowDefault     = @{
			Value  = 'ShowDefault'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in Set-Window'
		}
		StrShowMaximized   = @{
			Value  = 'ShowMaximized'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in Set-Window'
		}
		StrShowMinimized   = @{
			Value  = 'ShowMinimized'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in Set-Window'
		}
		StrShowMinNoactive = @{
			Value  = 'ShowMinNoactive'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in Set-Window'
		}
		StrShowNa          = @{
			Value  = 'ShowNa'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in Set-Window'
		}
		StrShowNoActivate  = @{
			Value  = 'ShowNoActivate'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in Set-Window'
		}
		StrShowNormal      = @{
			Value  = 'ShowNormal'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in Set-Window'
		}
		StrGetChildHandles = @{
			Value  = 'GetChildHandles'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in Set-Window'
		}
		WindowStates       = @{
			Value  = [Ordered]@{
				'HIDE'          = [int]0
				'SHOWNORMAL'    = [int]1
				'SHOWMINIMIZED' = [int]2
				'SHOWMAXIMIZED' = [int]3
				'MAXIMIZE'      = [int]3
				'SHOWNOACTIVATE' = [int]4
				'SHOW'          = [int]5
				'MINIMIZE'      = [int]6
				'SHOWMINNOACTIVE' = [int]7
				'SHOWNA'        = [int]8
				'RESTORE'       = [int]9
				'SHOWDEFAULT'   = [int]10
				'FORCEMINIMIZE' = [int]11
				'0'             = 'Hidden'
				'1'             = 'Normal'
				'2'             = 'Minimized'
				'3'             = 'Maximized'
				'4'             = 'ShowMinNoActivate'
				'5'             = 'show'
				'6'             = 'Minimize'
				'7'             = 'ShowMinNoActivate'
				'8'             = 'ShowNA'
				'9'             = 'Restore'
				'10'            = 'ShowDefault'
				'11'            = 'ForceMinimize'
			}
			Scope  = $VSScript
			Option = $VOReadOnly
			Use    = 'Used in Set-Window'
		}
	}
}
Publish-Variables -Variables $MyVars
$MyVars = @{
	N09Finalise = @{
		DefineVariablesSetWindow = @{
			Value  = $True
			Scope  = $VSScript
			Option = $VOReadOnly
			Use    = 'Set-Window'
		}
	}
}
Publish-Variables -Variables $MyVars

