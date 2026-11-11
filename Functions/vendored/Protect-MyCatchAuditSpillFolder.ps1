# VENDORED from CommonScripts\0.2\Functions\Protect-MyCatchAuditSpillFolder.ps1 by Sync-SharedUtilities [SHA256 A715AC96F0D460E05528AE4EDD40239055C5D10DDFC35B2C5B7BB431A5089748] - DO NOT EDIT (edit the master; Deploy-Modules re-syncs).
Function Protect-MyCatchAuditSpillFolder
{
	<#
		.SYNOPSIS
		Locks down the catch-audit spill folder so any local user can add a spill file but cannot read or change other
		people's - or, with -Check, reports whether it is locked down.

		.DESCRIPTION
		Non-elevated processes whose catch-audit entry cannot be written to the persisted log save it to
		<ProgramData>\CatchAudit\Spill (see Get-MyCatchAuditSpillPath). A folder created there by an ordinary process
		inherits ProgramData's loose defaults, so lock it down once from an ELEVATED prompt (Deploy-Modules does this
		on every deploy). Same pattern as Protect-MyFunctionTraceFolder:

		    SYSTEM, Administrators   full control (inherited by the spill files and the Imported / Rejected folders)
		    Users                    this folder ONLY (not inherited): read+execute (list it) and add a file.
		                             No read of other people's spill files, no subfolders.
		    CREATOR OWNER            modify, inherited by new files - so each writer keeps appending to, and can
		                             remove, its OWN spill file

		An elevated import (Import-MyCatchAuditSpill) runs as an administrator and can read, move and archive every
		file. -Check reports a folder with an inheritable Users allow entry or any Users right wider than list + add a file
		as NOT locked down, and also reports a folder whose Users entry lacks the add-a-file right, because the spill write would
		then silently fail and entries would be lost.

		Existing files are reset to inherit the new ACL. Nothing is deleted or moved.

		.PARAMETER Path
		The spill folder. Default: the folder Get-MyCatchAuditSpillPath resolves.

		.PARAMETER Check
		Report only; change nothing and need no elevation.

		.PARAMETER FolderOnly
		With -Check: inspect just the folder, not each existing file.

		.EXAMPLE
		Protect-MyCatchAuditSpillFolder            # apply, from an elevated prompt

		.EXAMPLE
		Protect-MyCatchAuditSpillFolder -Check     # is it locked down?

		.OUTPUTS
		[PSCustomObject] Path, LockedDown, Applied, Problems (and HiddenFiles: files owned by other accounts that this
		account cannot inspect - the intended protection, counted rather than hidden).
	#>
	[CmdletBinding(SupportsShouldProcess)]
	[OutputType([PSCustomObject])]
	Param (
		[String]$Path,
		[Switch]$Check,
		[Switch]$FolderOnly
	)

	Try
	{
		If (-not $Path) { $Path = Get-MyCatchAuditSpillPath -NoCreate }

		# Well-known SIDs, never account names (locale-proof): SYSTEM, Administrators, Users, CREATOR OWNER.
		$Loose = @('S-1-5-32-545', 'S-1-1-0', 'S-1-5-11')

		Function Get-SpillFolderProblem
		{
			Param ([String]$Folder, [Bool]$SkipFiles)
			$Problems = New-Object Collections.Generic.List[String]
			If (-not (Test-Path -LiteralPath $Folder))
			{
				[void]$Problems.Add('folder does not exist')
				Return @($Problems)
			}
			$Acl = Get-Acl -LiteralPath $Folder
			If (-not $Acl.AreAccessRulesProtected) { [void]$Problems.Add('inheritance from the parent folder is still enabled') }
			$UsersCanAdd = $false
			# The intended Users right on the folder is exactly list (read+execute) + add a file; anything beyond it is too wide.
			$AllowedBits = [int]([Security.AccessControl.FileSystemRights]::ReadAndExecute -bor [Security.AccessControl.FileSystemRights]::CreateFiles -bor [Security.AccessControl.FileSystemRights]::Synchronize)
			ForEach ($Rule in $Acl.Access)
			{
				$Sid = $null
				Try { $Sid = $Rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } Catch { Continue }
				If ($Loose -notcontains $Sid -or $Rule.AccessControlType -ne 'Allow') { Continue }
				If ($Rule.InheritanceFlags -band [Security.AccessControl.InheritanceFlags]::ObjectInherit)
				{ [void]$Problems.Add(('{0} has an inheritable (file-level) allow entry: {1}' -f $Rule.IdentityReference.Value, $Rule.FileSystemRights)) }
				ElseIf (([int]$Rule.FileSystemRights -band (-bnot $AllowedBits)) -ne 0)
				{ [void]$Problems.Add(('{0} has a wider allow entry than list + add a file: {1}' -f $Rule.IdentityReference.Value, $Rule.FileSystemRights)) }
				If ($Rule.FileSystemRights -band [Security.AccessControl.FileSystemRights]::CreateFiles) { $UsersCanAdd = $true }
			}
			If (-not $UsersCanAdd) { [void]$Problems.Add('Users cannot add a file to the folder (spill writes would fail)') }
			If (-not $SkipFiles)
			{
				$Exposed = 0
				ForEach ($File in @(Get-ChildItem -LiteralPath $Folder -File -Force))
				{
					$FileAcl = $null
					Try { $FileAcl = Get-Acl -LiteralPath $File.FullName }
					Catch
					{
						# A file whose ACL this account cannot even read is protected from this account - the
						# locked-down state, not a problem. Counted and reported; any other failure is real.
						If ($_.Exception -is [UnauthorizedAccessException]) { $State.Hidden++; Continue }
						Throw
					}
					ForEach ($Rule in $FileAcl.Access)
					{
						$Sid = $null
						Try { $Sid = $Rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } Catch { Continue }
						If ($Loose -contains $Sid -and $Rule.AccessControlType -eq 'Allow') { $Exposed++; Break }
					}
				}
				If ($Exposed -gt 0) { [void]$Problems.Add(('{0} existing file(s) still readable by Users/Everyone/Authenticated Users' -f $Exposed)) }
			}
			Return @($Problems)
		}

		$State = @{ Hidden = 0 }
		If ($Check)
		{
			$Found = @(Get-SpillFolderProblem -Folder $Path -SkipFiles ([Bool]$FolderOnly))
			Return [PSCustomObject]@{ Path = $Path; LockedDown = ($Found.Count -eq 0); Applied = $false; Problems = $Found; HiddenFiles = $State.Hidden }
		}

		$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
		If (-not $IsAdmin)
		{
			Write-Error -Message 'Protect-MyCatchAuditSpillFolder needs an elevated PowerShell to change the ACL. Use -Check to only report.'
			Return [PSCustomObject]@{ Path = $Path; LockedDown = $false; Applied = $false; Problems = @('not elevated'); HiddenFiles = 0 }
		}

		If ($PSCmdlet.ShouldProcess($Path, 'Restrict the ACL so users can add but not read each other''s spill files'))
		{
			If (-not (Test-Path -LiteralPath $Path)) { $null = New-Item -Path $Path -ItemType Directory -Force }
			& icacls.exe $Path /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(RX,WD)' '*S-1-3-0:(OI)(IO)(M)' | Out-Null
			If ($LASTEXITCODE -ne 0) { Throw ('icacls failed on {0} (exit {1})' -f $Path, $LASTEXITCODE) }
			If (@(Get-ChildItem -LiteralPath $Path -File -Force).Count -gt 0)
			{ & icacls.exe (Join-Path -Path $Path -ChildPath '*') /reset /C /Q | Out-Null }
			$After = @(Get-SpillFolderProblem -Folder $Path -SkipFiles $false)
			Return [PSCustomObject]@{ Path = $Path; LockedDown = ($After.Count -eq 0); Applied = $true; Problems = $After; HiddenFiles = $State.Hidden }
		}
		Return [PSCustomObject]@{ Path = $Path; LockedDown = $false; Applied = $false; Problems = @('-WhatIf: nothing changed'); HiddenFiles = 0 }
	}
	Catch
	{
		Write-MyCatchAudit -Source 'Protect-MyCatchAuditSpillFolder: locking down the spill folder' -ErrorRecord $_
		Throw
	}
}
