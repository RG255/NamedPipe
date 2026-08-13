Function Set-PipeIntegrityLabel
{
	<#
		.SYNOPSIS
		Applies a Windows mandatory integrity label to a named-pipe server stream so that a
		lower-integrity process cannot connect to it.

		.DESCRIPTION
		The pipe DACL grants access by SID - it cannot distinguish integrity levels, so a LOW
		integrity process running as the same user (an AppContainer app, a sandboxed browser
		renderer, a sandbox escape) can still open the elevated pipe. A mandatory integrity label
		closes that: labelling the pipe Medium with NoWriteUp+NoReadUp denies any subject BELOW
		Medium the read/write access that connecting requires. Medium and above are unaffected, so
		the normal (Medium) client still connects.

		This is a HARDENING layer (0.11, item 4.1b in PIPE-INJECTION-HARDENING-PLAN.md). It is applied
		AFTER the pipe is created - it does NOT change pipe creation and needs NO privilege
		(SetSecurityInfo with LABEL_SECURITY_INFORMATION at or below your own integrity level is
		allowed without SeSecurityPrivilege, elevated or not). It NEVER throws: on any failure it
		returns $false and the caller carries on with the DACL-only pipe. So the pipe is never broken
		by this call.

		VERIFIED 2026-07-17 (elevated and non-elevated): a Medium server labels its pipe (rc=0), a
		Medium client connects, a genuine Low-integrity client is refused with ACCESS_DENIED.

		CONSTRAINT: this works only when the pipe was created with a FINITE instance count. The module
		uses Instances=1. With maxInstances = -1 (unlimited) the creator handle lacks WRITE_OWNER and
		SetSecurityInfo returns rc=5 (ACCESS_DENIED) - the label is then skipped (logged), DACL stands.

		.PARAMETER Pipe
		The NamedPipeServerStream (or NamedPipeServerStreamAcl) instance to label. Its SafePipeHandle
		is used to set the label.

		.PARAMETER Level
		Integrity level for the label: Low, Medium (default) or High. Medium blocks only Low; that is
		the intended setting for the data pipe (the normal client is Medium).

		.OUTPUTS
		[Bool] - $true if the label was applied, $false if it was skipped (caller continues either way).

		.EXAMPLE
		$null = Set-PipeIntegrityLabel -Pipe $ServerClientParams.PipeInfo.Pipe
		Labels the data pipe Medium immediately after it is created.
	#>
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Best-effort internal hardening applied to a pipe the server just created; no user-facing state change to confirm, and it never throws')]
	[CmdletBinding()]
	[OutputType([Bool])]
	Param (
		[Parameter(Mandatory, HelpMessage = 'The NamedPipeServerStream to label')]
		$Pipe,
		[ValidateSet('Low', 'Medium', 'High')]
		[String]$Level = 'Medium'
	)

	# Compile the SetSecurityInfo P/Invoke once per process (guarded by type name so a module reload,
	# which cannot unload the type, does not re-add it).
	If (-not ('NamedPipe.MandatoryLabel' -as [Type]))
	{
		Try
		{
			Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace NamedPipe {
  public static class MandatoryLabel {
    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern uint SetSecurityInfo(IntPtr handle, int objectType, uint securityInfo,
        IntPtr owner, IntPtr group, IntPtr dacl, IntPtr sacl);
  }
}
'@
		}
		Catch
		{
			Write-Verbose ('Set-PipeIntegrityLabel: could not compile the native helper: {0}' -f $_.Exception.Message)
			return $false
		}
	}

	# SDDL integrity-level abbreviations. NWNR = NoWriteUp + NoReadUp (blocks below-label subjects).
	$Private:Abbrev = @{ 'Low' = 'LW'; 'Medium' = 'ME'; 'High' = 'HI' }[$Level]
	$Private:Sddl   = 'S:(ML;;NWNR;;;{0})' -f $Private:Abbrev

	Try
	{
		$Private:Handle = $Pipe.SafePipeHandle.DangerousGetHandle()
		$Private:Rsd    = New-Object System.Security.AccessControl.RawSecurityDescriptor($Private:Sddl)
		$Private:Bytes  = New-Object Byte[] $Private:Rsd.SystemAcl.BinaryLength
		$Private:Rsd.SystemAcl.GetBinaryForm($Private:Bytes, 0)
		$Private:Gc = [System.Runtime.InteropServices.GCHandle]::Alloc($Private:Bytes, 'Pinned')
		Try
		{
			$Private:SE_KERNEL_OBJECT           = 6
			$Private:LABEL_SECURITY_INFORMATION = 0x10
			$Private:Rc = [NamedPipe.MandatoryLabel]::SetSecurityInfo(
				$Private:Handle, $Private:SE_KERNEL_OBJECT, $Private:LABEL_SECURITY_INFORMATION,
				[IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero, $Private:Gc.AddrOfPinnedObject())
		}
		Finally
		{ $Private:Gc.Free() }

		If ($Private:Rc -eq 0)
		{
			Write-Verbose ('Set-PipeIntegrityLabel: applied {0} mandatory label to the pipe.' -f $Level)
			return $true
		}

		Write-Verbose ('Set-PipeIntegrityLabel: SetSecurityInfo rc={0} - label skipped, DACL still enforced (rc=5 means the pipe was created with unlimited instances).' -f $Private:Rc)
		return $false
	}
	Catch
	{
		Write-Verbose ('Set-PipeIntegrityLabel: {0} - label skipped, DACL still enforced.' -f $_.Exception.Message)
		return $false
	}
}
