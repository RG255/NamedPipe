Function Add-ServerLogEntry
{
	<#
		.SYNOPSIS
		Appends a timestamped milestone line to the in-memory server diagnostics buffer (0.11 hardening 4.5, step 1a).

		.DESCRIPTION
		Internal. The spawned pipe server calls this to record lifecycle milestones (pipe created, client
		connected, request received, outcome) into a module-scope ring buffer. The buffer is later flushed to
		a file by Save-ServerLog ONLY on a failure outcome, or on a clean exit when InfoDisplay bit 8 is set;
		otherwise it is discarded. Nothing is written to disk here - this is pure in-memory capture, so it is
		cheap on the common (clean, silent) path.

		Content discipline: milestones must be secrets-free. NEVER pass the nonce, request arguments, or full
		paths - Save-ServerLog additionally redacts drive-letter paths as a backstop.

		.PARAMETER Message
		The milestone text. May be empty.
	#>
	[CmdletBinding()]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Appends to an in-memory buffer; no external state change.')]
	Param (
		[Parameter(Mandatory, HelpMessage = 'Milestone text to record')]
		[AllowEmptyString()]
		[String]$Message
	)
	if ($null -eq $Script:ServerLogBuffer)
	{ $Script:ServerLogBuffer = [System.Collections.Generic.List[string]]::new() }
	# Ring cap: bound growth so a long-lived or flooded server cannot grow the buffer without limit.
	if ($Script:ServerLogBuffer.Count -ge 1000)
	{ $Script:ServerLogBuffer.RemoveAt(0) }
	$Script:ServerLogBuffer.Add(('{0:HH:mm:ss.fff}  {1}' -f (Get-Date), $Message))
}
