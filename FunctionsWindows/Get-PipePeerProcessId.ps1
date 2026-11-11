Function Get-PipePeerProcessId
{
	<#
		.SYNOPSIS
		Returns the process id of the process at the other end of a connected pipe, as reported by the kernel.

		.DESCRIPTION
		0.18. Wraps GetNamedPipeClientProcessId / GetNamedPipeServerProcessId. The value is set by the operating system when the
		connection is made and cannot be claimed by the peer, so it is the basis for the checks that decide whether to admit a client
		(server side) or to send a secret to a server (client side).

		The P/Invoke type is created once per process under the name NamedPipe.PeerPid. A .NET type outlives the module that defined
		it, so never change the shape of a type that already carries this name; give a changed shape a new name instead.

		.PARAMETER Pipe
		A connected pipe stream (NamedPipeServerStream or NamedPipeClientStream).

		.PARAMETER Peer
		Client: return the PID of the client (call this on the server's pipe).
		Server: return the PID of the server (call this on the client's pipe).

		.OUTPUTS
		[uint32] the peer's process id, or 0 when it could not be determined (not connected, API unavailable).
	#>
	[CmdletBinding()]
	[OutputType([uint32])]
	Param (
		[Parameter(Mandatory)]
		[System.IO.Pipes.PipeStream]$Pipe,

		[Parameter(Mandatory)]
		[ValidateSet('Client', 'Server')]
		[String]$Peer
	)
	If (1 -band ($env:MyFunctionTraceEnabled -as [Int])) { Write-MyFunctionTrace }

	Try
	{
		If (-not ('NamedPipe.PeerPid' -as [type]))
		{
			Add-Type -Namespace 'NamedPipe' -Name 'PeerPid' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetNamedPipeClientProcessId(System.IntPtr Pipe, out uint ClientProcessId);
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetNamedPipeServerProcessId(System.IntPtr Pipe, out uint ServerProcessId);
'@ -ErrorAction Stop
		}
		$Private:Found = [uint32]0
		$Private:Handle = $Pipe.SafePipeHandle.DangerousGetHandle()
		If ($Peer -eq 'Client')
		{ $Private:Ok = [NamedPipe.PeerPid]::GetNamedPipeClientProcessId($Private:Handle, [ref]$Private:Found) }
		Else
		{ $Private:Ok = [NamedPipe.PeerPid]::GetNamedPipeServerProcessId($Private:Handle, [ref]$Private:Found) }
		If ($Private:Ok) { $Private:Found } Else { [uint32]0 }
	}
	Catch
	{
		# 0 is the documented "unknown" answer and every caller treats it as a failed check (fail closed).
		Write-MyCatchAudit -Source 'Get-PipePeerProcessId: reading the peer process id of a pipe failed - 0 (unknown) is returned and the caller refuses' -ErrorRecord $_
		[uint32]0
	}
}
