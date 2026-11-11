# VENDORED from CommonScripts\0.2\Functions\Read-MyCatchAuditSpill.ps1 by Sync-SharedUtilities [SHA256 23A0FA9740BD7C184E49A6E993C164EF069E39AB68EAE0011D480B617E2CBCA4] - DO NOT EDIT (edit the master; Deploy-Modules re-syncs).
Function Read-MyCatchAuditSpill
{
	<#
		.SYNOPSIS
		Internal: reads and VALIDATES the catch-audit spill files this process is allowed to see. Changes nothing.

		.DESCRIPTION
		2026-11-08. The read half of the spill file (see Get-MyCatchAuditSpillPath). Shared by
		Import-MyCatchAuditSpill (which acts on the result when elevated), Show-MyCatchAuditSummary and
		Show-MyCatchAuditPendingNotice (which only COUNT what is waiting). A non-elevated process sees the names of
		everyone's files (the folder is listable) but can open only its own; the rest are counted as HiddenFiles.

		The persisted log is writable by administrators on purpose, so what comes out of a spill file must not be able
		to masquerade as a genuine trusted entry. Every line is therefore rebuilt from a strict whitelist, never
		passed through:
		  - the file name must be Spill-<user>-<pid>.jsonl, not a reparse point, and at most 1 MB; at most
		    $MaxFiles files are examined per call (the rest are left for the next run);
		  - at most 1000 lines per file, at most 16000 characters per line;
		  - the line must be a JSON object with EXACTLY the twelve fields Write-MyCatchAudit writes (Id, Timestamp,
		    Source, CallerLocation, ExceptionType, Message, ScriptName, LineNumber, ProcessId, UserName,
		    MachineName, IsTeardown) - a missing field, an unknown field (an 'Origin' someone forged, say), or a
		    value of the wrong type rejects the line;
		  - Id is 8 hex characters; Timestamp is ISO 8601, not before 2020 and not more than a day ahead; string
		    fields have length limits and no control characters (terminal escape sequences, bidi overrides);
		  - entries whose Id is already in the persisted file, or earlier in the same read, are counted as
		    duplicates (the in-memory relay may already have delivered the same entry). The in-memory log is NOT
		    consulted: it also holds the entries that were spilled precisely because they could not be persisted.
		Accepted entries are tagged Origin='Spill' with the spill file name and the file's real OWNER (SpillOwner),
		which unlike the UserName inside the line cannot be chosen by whoever wrote the line.

		.PARAMETER MaxFiles
		Most files examined per call. Default 50.

		.OUTPUTS
		[PSCustomObject] Folder, Files (one object per file: Name, Path, Length, BytesRead, Owner, Status = Ok |
		BadName | Reparse | Oversize | Unreadable, Lines, Entries, Duplicates, Rejected), Entries (all accepted new
		entries), Duplicates, RejectedCount, Rejected (first 200 reasons: File, Line, Reason), NotExamined,
		HiddenFiles.
	#>
	[CmdletBinding()]
	[OutputType([PSCustomObject])]
	Param ([ValidateRange(1, 1000)][Int]$MaxFiles = 50)

	$MaxFileBytes = 1048576
	$MaxLines = 1000
	$MaxLineChars = 16000
	$RejectListCap = 200
	$FieldLimit = @{ Source = 1000; CallerLocation = 1000; ExceptionType = 300; Message = 8000; ScriptName = 260; UserName = 256; MachineName = 256 }
	$SingleLine = @('Source', 'CallerLocation', 'ExceptionType', 'ScriptName', 'UserName', 'MachineName')
	$Allowed = @('Id', 'Timestamp', 'Source', 'CallerLocation', 'ExceptionType', 'Message', 'ScriptName', 'LineNumber', 'ProcessId', 'UserName', 'MachineName', 'IsTeardown')
	$BadCharSingle = '[\x00-\x1F\x7F-\x9F' + [Char]0x202A + '-' + [Char]0x202E + [Char]0x2066 + '-' + [Char]0x2069 + ']'
	$BadCharMulti = '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F' + [Char]0x202A + '-' + [Char]0x202E + [Char]0x2066 + '-' + [Char]0x2069 + ']'

	$Folder = Get-MyCatchAuditSpillPath -NoCreate
	$Files = New-Object System.Collections.Generic.List[Object]
	$AllEntries = New-Object System.Collections.Generic.List[Object]
	$Rejected = New-Object System.Collections.Generic.List[Object]
	$Totals = @{ Duplicates = 0; Rejected = 0; NotExamined = 0; Hidden = 0 }

	Function Add-Reject
	{
		Param ([String]$File, [Int]$Line, [String]$Reason)
		$Totals.Rejected++
		If ($Rejected.Count -lt $RejectListCap) { $Rejected.Add([PSCustomObject]@{ File = $File; Line = $Line; Reason = $Reason }) }
	}

	# Why this line is not acceptable, or '' with the rebuilt record in $Out.
	Function Test-SpillLine
	{
		Param ([String]$Text)
		If ($Text.Length -gt $MaxLineChars) { Return @{ Reason = 'line longer than 16000 characters' } }
		# Windows PowerShell 5.1 wraps a parsed JSON array in an object that passes the PSCustomObject test below.
		If ($Text.StartsWith('[')) { Return @{ Reason = 'not a JSON object' } }
		$Obj = $null
		Try { $Obj = $Text | ConvertFrom-Json -ErrorAction Stop }
		Catch { Return @{ Reason = 'not valid JSON' } }
		If ($Obj -isnot [PSCustomObject]) { Return @{ Reason = 'not a JSON object' } }
		$Names = @($Obj.PSObject.Properties.Name)
		ForEach ($N in $Names) { If ($Allowed -cnotcontains $N) { Return @{ Reason = ('unexpected field ''{0}''' -f $(If ($N.Length -gt 40) { $N.Substring(0, 40) } Else { $N })) } } }
		ForEach ($N in $Allowed) { If ($Names -cnotcontains $N) { Return @{ Reason = ('missing field ''{0}''' -f $N) } } }

		If ($Obj.Id -isnot [String] -or $Obj.Id -cnotmatch '^[0-9a-f]{8}$') { Return @{ Reason = 'Id is not 8 lower-case hex characters' } }

		$Stamp = $null
		If ($Obj.Timestamp -is [DateTime]) { $Stamp = $Obj.Timestamp.ToUniversalTime() }
		ElseIf ($Obj.Timestamp -is [String] -and $Obj.Timestamp -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,7})?(Z|[+-]\d{2}:\d{2})$')
		{
			$Parsed = [DateTime]::MinValue
			If ([DateTime]::TryParse($Obj.Timestamp, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$Parsed)) { $Stamp = $Parsed.ToUniversalTime() }
		}
		If ($null -eq $Stamp) { Return @{ Reason = 'Timestamp is not an ISO 8601 date-time' } }
		If ($Stamp.Year -lt 2020) { Return @{ Reason = 'Timestamp before 2020' } }
		If ($Stamp -gt [DateTime]::UtcNow.AddDays(1)) { Return @{ Reason = 'Timestamp more than a day in the future' } }

		ForEach ($F in @('Source', 'CallerLocation', 'ExceptionType', 'Message', 'ScriptName', 'UserName', 'MachineName'))
		{
			$V = $Obj.$F
			If ($null -eq $V) { If ($F -in 'ScriptName', 'Message') { Continue }; Return @{ Reason = ('{0} is null' -f $F) } }
			If ($V -isnot [String]) { Return @{ Reason = ('{0} is not a string' -f $F) } }
			If ($V.Length -gt $FieldLimit[$F]) { Return @{ Reason = ('{0} longer than {1} characters' -f $F, $FieldLimit[$F]) } }
			$Bad = $(If ($SingleLine -contains $F) { $BadCharSingle } Else { $BadCharMulti })
			If ($V -match $Bad) { Return @{ Reason = ('{0} contains control characters' -f $F) } }
		}
		If ([String]::IsNullOrWhiteSpace($Obj.Source) -or [String]::IsNullOrWhiteSpace($Obj.ExceptionType)) { Return @{ Reason = 'Source/ExceptionType empty' } }
		ForEach ($F in @('LineNumber', 'ProcessId'))
		{
			$V = $Obj.$F
			If (($V -isnot [Int32] -and $V -isnot [Int64]) -or $V -lt 0 -or $V -gt 2147483647) { Return @{ Reason = ('{0} is not a non-negative integer' -f $F) } }
		}
		If ($Obj.IsTeardown -isnot [Bool]) { Return @{ Reason = 'IsTeardown is not a boolean' } }

		Return @{ Reason = ''; Record = [PSCustomObject][Ordered]@{
				Id             = $Obj.Id
				Timestamp      = $Stamp.ToString('o')
				Source         = $Obj.Source
				CallerLocation = $Obj.CallerLocation
				ExceptionType  = $Obj.ExceptionType
				Message        = $Obj.Message
				ScriptName     = $Obj.ScriptName
				LineNumber     = [Int]$Obj.LineNumber
				ProcessId      = [Int]$Obj.ProcessId
				UserName       = $Obj.UserName
				MachineName    = $Obj.MachineName
				IsTeardown     = [Bool]$Obj.IsTeardown
				Origin         = 'Spill'
				SpillFile      = ''
				SpillOwner     = ''
				ImportedAt     = $null
			}
		}
	}

	Try
	{
		If (-not (Test-Path -LiteralPath $Folder -PathType Container))
		{ Return [PSCustomObject]@{ Folder = $Folder; Files = @(); Entries = @(); Duplicates = 0; RejectedCount = 0; Rejected = @(); NotExamined = 0; HiddenFiles = 0 } }

		# Ids that already exist: the persisted file, and (below) earlier in this read. The in-memory log is deliberately
		# NOT consulted: it holds every entry this process captured, including the very ones that were spilled because
		# they could NOT be persisted, so treating it as "already known" would make a spilled entry look delivered
		# (and be dropped on import, or not counted as pending). Only the persisted file proves delivery - which is also
		# where a relayed copy of the same entry shows up.
		$Known = New-Object 'System.Collections.Generic.HashSet[String]' ([StringComparer]::OrdinalIgnoreCase)
		Try
		{
			$PersistPath = Get-MyCatchAuditPersistPath
			If (Test-Path -LiteralPath $PersistPath -PathType Leaf)
			{
				$Fs = [System.IO.File]::Open($PersistPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
				Try
				{
					$Sr = New-Object System.IO.StreamReader($Fs, [System.Text.Encoding]::UTF8, $true)
					While ($null -ne ($PersistLine = $Sr.ReadLine()))
					{ If ($PersistLine -match '"Id"\s*:\s*"([0-9A-Fa-f]{8})"') { [void]$Known.Add($Matches[1]) } }
				}
				Finally { $Fs.Dispose() }
			}
		}
		# SILENT-OK: an unreadable persisted file only means fewer known Ids; a duplicate is then caught by the import's
		# own append being idempotent per Id on the next read, and nothing here may fail the read.
		Catch { $null = $_ }

		$Listed = @(Get-ChildItem -LiteralPath $Folder -File -Force -Filter 'Spill-*.jsonl' -ErrorAction SilentlyContinue | Sort-Object -Property LastWriteTimeUtc, Name)
		If ($Listed.Count -gt $MaxFiles) { $Totals.NotExamined = $Listed.Count - $MaxFiles; $Listed = @($Listed | Select-Object -First $MaxFiles) }

		ForEach ($Item in $Listed)
		{
			$Info = [PSCustomObject]@{ Name = $Item.Name; Path = $Item.FullName; Length = $Item.Length; BytesRead = 0; Owner = ''; Status = 'Ok'; Lines = 0; Entries = @(); Duplicates = 0; Rejected = 0 }
			$Files.Add($Info)
			If ($Item.Name -cnotmatch '^Spill-[A-Za-z0-9._-]{1,64}-\d{1,10}\.jsonl$')
			{ $Info.Status = 'BadName'; $Info.Rejected = 1; Add-Reject -File $Item.Name -Line 0 -Reason 'file name is not Spill-<user>-<pid>.jsonl'; Continue }
			If ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint)
			{ $Info.Status = 'Reparse'; $Info.Rejected = 1; Add-Reject -File $Item.Name -Line 0 -Reason 'file is a reparse point (link)'; Continue }
			If ($Item.Length -gt $MaxFileBytes)
			{ $Info.Status = 'Oversize'; $Info.Rejected = 1; Add-Reject -File $Item.Name -Line 0 -Reason ('file larger than {0} bytes' -f $MaxFileBytes); Continue }

			$Content = $null
			Try
			{
				$Fs = [System.IO.File]::Open($Item.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
				Try
				{
					$Info.BytesRead = $Fs.Length
					$Sr = New-Object System.IO.StreamReader($Fs, [System.Text.Encoding]::UTF8, $true)
					$Content = $Sr.ReadToEnd()
				}
				Finally { $Fs.Dispose() }
			}
			# SILENT-OK: a file this account may not open (another user's, which the folder ACL hides on purpose) is
			# counted as hidden, not an error; only an elevated import can act on it.
			Catch { $null = $_; $Info.Status = 'Unreadable'; $Totals.Hidden++; Continue }

			$Owner = '<unknown>'
			Try { $Owner = [String](Get-Acl -LiteralPath $Item.FullName -ErrorAction Stop).Owner }
			# SILENT-OK: the owner is extra provenance; '<unknown>' is recorded when it cannot be read.
			Catch { $null = $_ }
			$Info.Owner = $Owner

			$Accepted = New-Object System.Collections.Generic.List[Object]
			$LineNo = 0
			ForEach ($Raw in ($Content -split "`r?`n"))
			{
				$Text = $Raw.Trim([Char]0xFEFF).Trim()
				If (-not $Text) { Continue }
				$LineNo++
				$Info.Lines = $LineNo
				If ($LineNo -gt $MaxLines)
				{ $Info.Rejected++; Add-Reject -File $Item.Name -Line $LineNo -Reason 'beyond the 1000-line cap'; Continue }
				$Check = Test-SpillLine -Text $Text
				If ($Check.Reason)
				{ $Info.Rejected++; Add-Reject -File $Item.Name -Line $LineNo -Reason $Check.Reason; Continue }
				If (-not $Known.Add($Check.Record.Id))
				{ $Info.Duplicates++; $Totals.Duplicates++; Continue }
				$Check.Record.SpillFile = $Item.Name
				$Check.Record.SpillOwner = $Owner
				$Accepted.Add($Check.Record)
				$AllEntries.Add($Check.Record)
			}
			$Info.Entries = $Accepted.ToArray()
		}

		Return [PSCustomObject]@{
			Folder        = $Folder
			Files         = $Files.ToArray()
			Entries       = $AllEntries.ToArray()
			Duplicates    = $Totals.Duplicates
			RejectedCount = $Totals.Rejected
			Rejected      = $Rejected.ToArray()
			NotExamined   = $Totals.NotExamined
			HiddenFiles   = $Totals.Hidden
		}
	}
	Catch
	{
		Write-Warning -Message ('Read-MyCatchAuditSpill: could not read the spill folder: {0}' -f $_.Exception.Message)
		Return [PSCustomObject]@{ Folder = $Folder; Files = @(); Entries = @(); Duplicates = 0; RejectedCount = 0; Rejected = @(); NotExamined = 0; HiddenFiles = 0 }
	}
}
