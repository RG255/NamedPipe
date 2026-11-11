Function Write-PipePolicyAuditEvent
{
	<#
		.SYNOPSIS
		Records, in the Application Event Log, that a request policy running in Audit mode would have blocked a request.

		.DESCRIPTION
		0.18. Called by Get-SBResult when RequestPolicy.Mode is 'Audit' and the policy check fails; the request then runs unchanged.
		Writes one Warning entry (source NamedPipe, event id 4514) and a line in the server diagnostics log buffer. The text carries the
		request id, the first command name and the blocking reasons without the request text or any argument value: Test-RequestPolicy
		reasons are reduced to their category, except the name of a command that is not on the allowlist, which is exactly what a person
		building an AllowedCommands list needs to see. Never throws.

		.PARAMETER Reason
		The Reason string returned by Test-RequestPolicy.

		.PARAMETER Request
		The assembled request text; only the first command name is taken from it.

		.PARAMETER RequestId
		The frame id of the request being answered (0 if unknown).

		.OUTPUTS
		System.String - the text that was recorded.
	#>
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Writes one audit record; there is nothing to preview.')]
	[CmdletBinding()]
	[OutputType([string])]
	Param (
		[Parameter(Mandatory)]
		[AllowEmptyString()]
		[String]$Reason,

		[Parameter(Mandatory)]
		[AllowEmptyString()]
		[String]$Request,

		[Int]$RequestId = 0
	)
	If (1 -band ($env:MyFunctionTraceEnabled -as [Int])) { Write-MyFunctionTrace }

	Try
	{
		# Reasons look like 'category: <snippet of the request>'; keep the category, and the command name where the category is
		# 'command not allowed'.
		$Private:Safe = @(($Reason -split '; ') | ForEach-Object {
				If ($_ -match "^command not allowed: '[^']{1,128}'$") { $_ } ElseIf ($_ -match '^([^:]{1,80}):') { $Matches[1] } Else { 'other' }
			} | Select-Object -Unique)
		$Private:Cmd = '<none>'
		$Private:Parsed = [System.Management.Automation.Language.Parser]::ParseInput($Request, [ref]$null, [ref]$null)
		$Private:First = $Private:Parsed.Find({ param($Node) $Node -is [System.Management.Automation.Language.CommandAst] }, $true)
		If ($Private:First -and $Private:First.GetCommandName()) { $Private:Cmd = $Private:First.GetCommandName() }
		$Private:Text = 'NamedPipe request policy AUDIT (PID {0}, request {1}): would have blocked, request allowed to run. First command: {2}. Reasons: {3}' -f $PID, $RequestId, $Private:Cmd, ($Private:Safe -join '; ')
		Add-ServerLogEntry -Message $Private:Text
		Write-PipeEventLogEntry -EventId 4514 -EntryType Warning -Text $Private:Text
		$Private:Text
	}
	Catch
	{
		Write-MyCatchAudit -Source 'Write-PipePolicyAuditEvent: building the audit record failed - the request still runs (Audit mode never blocks)' -ErrorRecord $_
	}
}
