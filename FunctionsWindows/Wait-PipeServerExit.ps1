Function Wait-PipeServerExit
{
	<#
		.SYNOPSIS
		Keeps a server window open for a bounded time after the pipe exits, so its output can be read and copied.

		.DESCRIPTION
		0.16. Replaces the unbounded 'Pause' used when the Wait option is set. Pause is a PowerShell host input
		call, which cannot work in a server started with -NonInteractive; this helper uses only .NET console
		calls, so it works either way, and it ENDS: after -Seconds the window closes by itself, so a forgotten
		Wait window can no longer sit there for ever. A keypress ends the wait early. If the console offers no
		usable input (redirected stdin, no console), it simply waits out the time.

		The caller restores the window first (Set-MyWindowState -State Restore); this function does not.

		.PARAMETER Seconds
		How long to wait. Clamped to 1..3600.

		.EXAMPLE
		Wait-PipeServerExit -Seconds $ServerClientParams.$StrWaitSeconds

		.OUTPUTS
		None.
	#>
	[CmdletBinding()]
	Param(
		[Int]$Seconds = 300
	)
	If (1 -band ($env:MyFunctionTraceEnabled -as [Int])) { Write-MyFunctionTrace }

	$Private:Wait = [Math]::Min([Math]::Max($Seconds, 1), 3600)
	Write-Host ('Server finished. This window closes in {0} s - press any key to close it now.' -f $Private:Wait) -ForegroundColor Yellow
	$Private:Deadline = [DateTime]::UtcNow.AddSeconds($Private:Wait)
	$Private:KeysUsable = $true
	While ([DateTime]::UtcNow -lt $Private:Deadline)
	{
		If ($Private:KeysUsable)
		{
			Try
			{
				If ([Console]::KeyAvailable)
				{
					[void][Console]::ReadKey($true)
					Break
				}
			}
			Catch
			{
				# SILENT-OK: no usable console input here (redirected stdin / no console). That only means the
				# early-exit keypress is unavailable; the bounded wait itself still works, so stop polling keys.
				$Private:KeysUsable = $false
			}
		}
		Start-Sleep -Milliseconds 200
	}
}
