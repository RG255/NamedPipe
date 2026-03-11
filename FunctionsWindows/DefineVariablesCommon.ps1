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
	N00ConstantVars = @{
		StrProgressInfo    = @{
			Value  = 'ProgressInfo'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'various functions'
		}
		StrNormal          = @{
			Value  = 'Normal'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in Start-Process -WindowStyle'
		}
		StrHidden          = @{
			Value  = 'Hidden'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in Start-Process -WindowStyle'
		}
		StrMinimized       = @{
			Value  = 'Minimized'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in Start-Process -WindowStyle'
		}
		StrWindowStyleList = @{
			Value  = 'Minimized|Maximized|hidden|Normal'
			Scope  = $VSScript
			Option = $VONone
			Use    = 'Used in Start-Process -WindowStyle'
		}
	}
}
Publish-Variables -Variables $MyVars
$MyVars = @{
	N09Finalise = @{
		DefineVariablesCommon = @{
			Value  = $True
			Scope  = $VSScript
			Option = $VOReadOnly
			Use    = 'Set-Window'
		}
	}
}
Publish-Variables -Variables $MyVars
