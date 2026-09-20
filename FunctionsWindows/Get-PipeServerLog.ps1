Function Get-PipeServerLog
{
	<#
		.SYNOPSIS
		Finds NamedPipe server diagnostics log files for the current user (0.11 hardening 4.5, step 1c).

		.DESCRIPTION
		A consumer helper - surfaces the per-session server logs written under %APPDATA%\NamedPipe-Logs so a
		(non-admin) caller does not have to know the path. The server elevates as the SAME user, so its logs
		land in this user's own profile and are readable without elevation.

		Returns FileInfo objects, newest first. Filter to one session with -PipeName (the pipe's Name, e.g.
		from $Session.ServerClientParams.PipeInfo.Name), and/or limit with -Newest.

		.PARAMETER PipeName
		Optional. Restrict to logs for this pipe Name (matches the <pipename> part of the filename).

		.PARAMETER Newest
		Optional. Return only the newest N files. 0 (default) = all.

		.EXAMPLE
		Get-PipeServerLog -Newest 1 | Get-Content
		Show the most recent server log.

		.EXAMPLE
		Get-PipeServerLog -PipeName $Session.ServerClientParams.PipeInfo.Name
		Logs for one specific session.

		.OUTPUTS
		System.IO.FileInfo
	#>
	[CmdletBinding()]
	[OutputType([System.IO.FileInfo])]
	Param (
		[Parameter()]
		[String]$PipeName,
		[Parameter()]
		[ValidateRange(0, [int]::MaxValue)]
		[int]$Newest = 0
	)
	If (1 -band ($env:MyFunctionTraceEnabled -as [Int])) { Write-MyFunctionTrace }

	# 2026-09-15: wrapped - per the user's own stated principle, never assume the environment (e.g.
	# $env:APPDATA) is correctly configured. Returns an empty result on failure, matching this
	# function's own existing "nothing found" convention (the Test-Path miss above also returns empty).
	Try
	{
		$Private:LogDir = Join-Path -Path $env:APPDATA -ChildPath 'NamedPipe-Logs'
		if (-not (Test-Path -Path $Private:LogDir)) { return }
		$Private:Filter = if ($PipeName) { 'server-*-{0}.log' -f $PipeName } else { 'server-*.log' }
		$Private:Files = @(Get-ChildItem -Path $Private:LogDir -Filter $Private:Filter -File -ErrorAction SilentlyContinue |
				Sort-Object -Property LastWriteTime -Descending)
		if ($Newest -gt 0) { $Private:Files = @($Private:Files | Select-Object -First $Newest) }
		$Private:Files
	}
	Catch
	{
		Write-MyCatchAudit -Source 'Get-PipeServerLog: failed to enumerate server diagnostics logs' -ErrorRecord $_
	}
}
