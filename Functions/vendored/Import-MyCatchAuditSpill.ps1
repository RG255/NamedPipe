# VENDORED from CommonScripts\0.2\Functions\Import-MyCatchAuditSpill.ps1 by Sync-SharedUtilities [SHA256 B9F8EC5E27E4793105B6A55E34150BDAA502704DF8C5C008658189B5DD7B1ED5] - DO NOT EDIT (edit the master; Deploy-Modules re-syncs).
Function Import-MyCatchAuditSpill
{
	<#
		.SYNOPSIS
		Imports catch-audit entries that non-elevated processes saved to the spill folder into the persisted log.
		Does nothing unless the caller is elevated.

		.DESCRIPTION
		2026-11-08. The second half of the spill file (see Get-MyCatchAuditSpillPath for why entries land there and
		Read-MyCatchAuditSpill for exactly how each line is validated). Called automatically, with no switch
		needed, by an elevated Get-MyCatchAuditLog, Show-MyCatchAuditSummary and Invoke-MyCatchAuditTriage, and by
		Deploy-Modules' elevated phase, so an ordinary deploy resolves any backlog.

		When ELEVATED, for each examined spill file:
		  - valid, new entries are appended to the persisted file, each tagged Origin='Spill' with SpillFile,
		    SpillOwner (the file's real owner) and ImportedAt; their original UserName / ProcessId / MachineName
		    are kept; an entry whose Id is already known is skipped;
		  - the consumed file is then MOVED (never deleted) to Spill\Imported\<name>.<UTC stamp>.imported;
		  - a file that is not trustworthy as a whole (bad name, a link, over 1 MB) is MOVED to Spill\Rejected\;
		  - a file that grew while it was being read is left in place for the next run;
		  - if the append fails the file is left untouched and a warning says so.
		What was imported, skipped and rejected is appended to Spill\Imported\Import.log, and a warning reports any
		rejection.

		When NOT elevated it imports nothing and touches nothing; the result's Pending says how many entries are
		waiting. It never throws.

		Supports -WhatIf (nothing is appended or moved).

		.PARAMETER MaxFiles
		Most spill files examined per call (the rest wait for the next run). Default 50.

		.OUTPUTS
		[PSCustomObject] Elevated, Imported, Duplicates, Rejected (lines), Pending (entries waiting; non-elevated),
		FilesArchived, FilesRejected, FilesLeft, NotExamined, Failed (any append, move or log write failed), LogPath.
	#>
	[CmdletBinding(SupportsShouldProcess)]
	[OutputType([PSCustomObject])]
	Param ([ValidateRange(1, 1000)][Int]$MaxFiles = 50)

	$Result = [PSCustomObject]@{
		Elevated = $false; Imported = 0; Duplicates = 0; Rejected = 0; Pending = 0
		FilesArchived = 0; FilesRejected = 0; FilesLeft = 0; NotExamined = 0; Failed = $false; LogPath = $null
	}

	Try
	{
		$Read = Read-MyCatchAuditSpill -MaxFiles $MaxFiles
		$Result.Elevated = [Bool](Test-MyCatchAuditElevated)
		$Result.NotExamined = [Int]$Read.NotExamined
		If (-not $Result.Elevated)
		{ $Result.Pending = @($Read.Entries).Count; Return $Result }
		If (@($Read.Files).Count -eq 0) { Return $Result }

		$Result.Duplicates = [Int]$Read.Duplicates
		$Result.Rejected = [Int]$Read.RejectedCount
		$Persist = Get-MyCatchAuditPersistPath
		$Folder = [String]$Read.Folder
		$ImportedDir = Join-Path -Path $Folder -ChildPath 'Imported'
		$RejectedDir = Join-Path -Path $Folder -ChildPath 'Rejected'
		$Stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
		$Notes = New-Object System.Collections.Generic.List[String]

		ForEach ($File in @($Read.Files))
		{
			If ($File.Status -eq 'Unreadable') { $Result.FilesLeft++; Continue }

			If ($File.Status -in 'BadName', 'Reparse', 'Oversize')
			{
				If ($PSCmdlet.ShouldProcess($File.Path, 'Move an untrusted spill file to Spill\Rejected'))
				{
					Try
					{
						If (-not (Test-Path -LiteralPath $RejectedDir -PathType Container)) { $null = New-Item -Path $RejectedDir -ItemType Directory -Force -ErrorAction Stop }
						Move-Item -LiteralPath $File.Path -Destination (Join-Path -Path $RejectedDir -ChildPath ('{0}.{1}.rejected' -f $File.Name, $Stamp)) -ErrorAction Stop
						$Result.FilesRejected++
						$Notes.Add(('  QUARANTINE {0}: {1}' -f $File.Name, $File.Status))
					}
					Catch { $Result.Failed = $true; $Result.FilesLeft++; Write-Warning -Message ('Import-MyCatchAuditSpill: could not move {0} to Spill\Rejected: {1}' -f $File.Name, $_.Exception.Message) }
				}
				Else { $Result.FilesLeft++ }
				Continue
			}

			If (-not $PSCmdlet.ShouldProcess($File.Path, ('Import {0} catch-audit entr(ies) into the persisted log and archive the file' -f @($File.Entries).Count)))
			{ $Result.FilesLeft++; Continue }

			If (@($File.Entries).Count -gt 0)
			{
				$When = [DateTime]::UtcNow.ToString('o')
				$Lines = New-Object System.Collections.Generic.List[String]
				ForEach ($Entry in @($File.Entries))
				{
					$Entry.ImportedAt = $When
					$Lines.Add(($Entry | ConvertTo-Json -Compress -Depth 3))
				}
				Try { Add-Content -LiteralPath $Persist -Value $Lines.ToArray() -Encoding utf8 -ErrorAction Stop }
				Catch
				{
					$Result.Failed = $true
					$Result.FilesLeft++
					Write-Warning -Message ('Import-MyCatchAuditSpill: could not append to the persisted log ({0}); {1} left in the spill folder.' -f $_.Exception.Message, $File.Name)
					Continue
				}
				$Result.Imported += $Lines.Count
			}

			Try
			{
				If ((Get-Item -LiteralPath $File.Path -ErrorAction Stop).Length -ne $File.BytesRead)
				{ $Result.FilesLeft++; $Notes.Add(('  LEFT {0}: grew while it was being read; the rest is picked up next run' -f $File.Name)); Continue }
				If (-not (Test-Path -LiteralPath $ImportedDir -PathType Container)) { $null = New-Item -Path $ImportedDir -ItemType Directory -Force -ErrorAction Stop }
				Move-Item -LiteralPath $File.Path -Destination (Join-Path -Path $ImportedDir -ChildPath ('{0}.{1}.imported' -f $File.Name, $Stamp)) -ErrorAction Stop
				$Result.FilesArchived++
			}
			Catch
			{
				# The entries are already in the persisted log; leaving the file only means the next run sees them as duplicates.
				$Result.Failed = $true
				$Result.FilesLeft++
				Write-Warning -Message ('Import-MyCatchAuditSpill: imported {0} but could not archive it: {1}' -f $File.Name, $_.Exception.Message)
			}
		}

		If ($WhatIfPreference) { Return $Result }

		ForEach ($Reject in @($Read.Rejected)) { $Notes.Add(('  REJECT {0}:{1}: {2}' -f $Reject.File, $Reject.Line, $Reject.Reason)) }
		If ($Result.Imported -gt 0 -or $Result.Rejected -gt 0 -or $Result.FilesRejected -gt 0 -or $Result.Duplicates -gt 0)
		{
			Try
			{
				If (-not (Test-Path -LiteralPath $ImportedDir -PathType Container)) { $null = New-Item -Path $ImportedDir -ItemType Directory -Force -ErrorAction Stop }
				$LogPath = Join-Path -Path $ImportedDir -ChildPath 'Import.log'
				$Head = '{0} user={1} imported={2} duplicates={3} rejectedLines={4} filesArchived={5} filesRejected={6} filesLeft={7}' -f $Stamp, [Environment]::UserName, $Result.Imported, $Result.Duplicates, $Result.Rejected, $Result.FilesArchived, $Result.FilesRejected, $Result.FilesLeft
				Add-Content -LiteralPath $LogPath -Value (@($Head) + $Notes.ToArray()) -Encoding utf8 -ErrorAction Stop
				$Result.LogPath = $LogPath
			}
			Catch { $Result.Failed = $true; Write-Warning -Message ('Import-MyCatchAuditSpill: could not write Import.log: {0}' -f $_.Exception.Message) }
		}
		If ($Result.Rejected -gt 0 -or $Result.FilesRejected -gt 0)
		{ Write-Warning -Message ('Import-MyCatchAuditSpill: rejected {0} spill line(s) and {1} spill file(s) as not trustworthy; details in {2}' -f $Result.Rejected, $Result.FilesRejected, $(If ($Result.LogPath) { $Result.LogPath } Else { 'the spill folder' })) }
		If ($Result.Imported -gt 0)
		{ Write-Information -MessageData ('Imported {0} catch-audit entr{1} from the spill folder into the persisted log (Origin=Spill).' -f $Result.Imported, $(If ($Result.Imported -eq 1) { 'y' } Else { 'ies' })) -InformationAction Continue }
		Return $Result
	}
	Catch
	{
		$Result.Failed = $true
		Write-Warning -Message ('Import-MyCatchAuditSpill: failed: {0}' -f $_.Exception.Message)
		Return $Result
	}
}
