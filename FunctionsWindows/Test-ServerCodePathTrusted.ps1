Function Test-ServerCodePathTrusted
{
	<#
		.SYNOPSIS
		Reports why a path an elevated server is about to load code from is not admin-only.

		.DESCRIPTION
		An elevated server imports NamedPipe and the consumer module from disk. If a standard user
		can modify those files (or replace the folder that holds them), that user can have their
		code run elevated. This function inspects the path, its immediate subfolders and the folders
		above it, and returns one text line per problem found: an owner that is not an
		administrator/SYSTEM/TrustedInstaller, or an Allow rule that gives any other account a
		write, delete or permission-change right that applies to the item itself. An empty result
		means the path is admin-only.

		Read-only: it only reads ACLs. A path that cannot be read is reported as a problem.

		.PARAMETER Path
		File or folder to check.

		.EXAMPLE
		Test-ServerCodePathTrusted -Path 'C:\Program Files\PowerShell\Modules\NamedPipe\0.17'

		.OUTPUTS
		System.String[] - one line per problem; empty when the path is admin-only.
	#>
	[CmdletBinding()]
	[OutputType([String[]])]
	Param(
		[Parameter(Mandatory)][AllowEmptyString()][String]$Path
	)
	If (1 -band ($env:MyFunctionTraceEnabled -as [Int])) { Write-MyFunctionTrace }

	If ([String]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path))
	{ return }

	# SYSTEM, Administrators, TrustedInstaller, CREATOR OWNER (inherit-only template for new children).
	$Private:Trusted = @('S-1-5-18', 'S-1-5-32-544', 'S-1-3-0', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
	$Private:Write = [System.Security.AccessControl.FileSystemRights]'WriteData, AppendData, Delete, DeleteSubdirectoriesAndFiles, ChangePermissions, TakeOwnership'
	# Folders above the item can only replace it (delete/rename/re-permission); creating a sibling is harmless.
	$Private:AncestorWrite = [System.Security.AccessControl.FileSystemRights]'Delete, DeleteSubdirectoriesAndFiles, ChangePermissions, TakeOwnership'

	$Private:Findings = [System.Collections.Generic.List[String]]::new()
	# Each work item is a path plus the rights mask that matters for it.
	$Private:Work = [System.Collections.Generic.List[Object]]::new()
	$Private:Item = (Resolve-Path -LiteralPath $Path).ProviderPath
	$Private:Work.Add(@($Private:Item, $Private:Write))
	If (Test-Path -LiteralPath $Private:Item -PathType Container)
	{
		# The module loader runs every .ps1 in the module's subfolders, so a writable subfolder counts.
		ForEach ($Private:Sub in (Get-ChildItem -LiteralPath $Private:Item -Directory -ErrorAction SilentlyContinue))
		{ $Private:Work.Add(@($Private:Sub.FullName, $Private:Write)) }
	}
	$Private:Up = [System.IO.Path]::GetDirectoryName($Private:Item.TrimEnd('\'))
	While (-not [String]::IsNullOrEmpty($Private:Up))
	{
		$Private:Work.Add(@($Private:Up, $Private:AncestorWrite))
		$Private:Up = [System.IO.Path]::GetDirectoryName($Private:Up.TrimEnd('\'))
	}

	ForEach ($Private:W in $Private:Work)
	{
		$Private:Where = [String]$Private:W[0]
		$Private:Mask = $Private:W[1]
		Try
		{
			$Private:Acl = Get-Acl -LiteralPath $Private:Where -ErrorAction Stop
			$Private:Owner = $Private:Acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value
			If ($Private:Owner -notin $Private:Trusted)
			{ $Private:Findings.Add(('{0}: owned by {1}' -f $Private:Where, $Private:Owner)) }
			ForEach ($Private:Rule in $Private:Acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
			{
				If ($Private:Rule.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow) { Continue }
				If ($Private:Rule.PropagationFlags -band [System.Security.AccessControl.PropagationFlags]::InheritOnly) { Continue }
				If ($Private:Rule.IdentityReference.Value -in $Private:Trusted) { Continue }
				If (($Private:Rule.FileSystemRights -band $Private:Mask) -ne 0)
				{ $Private:Findings.Add(('{0}: {1} may write ({2})' -f $Private:Where, $Private:Rule.IdentityReference.Value, $Private:Rule.FileSystemRights)) }
			}
		}
		Catch
		{ $Private:Findings.Add(('{0}: ACL could not be read ({1})' -f $Private:Where, $_.Exception.Message)) }
	}
	$Private:Findings.ToArray()
}
