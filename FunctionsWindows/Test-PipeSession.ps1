Function Test-PipeSession
{
	<#
		.SYNOPSIS
		Tests whether a named pipe session is still connected and healthy.

		.DESCRIPTION
		Performs a two-phase health check on the pipe session.

		Phase 1 (passive): verifies that the PipeInfo object, pipe stream,
		reader, and writer are non-null and the pipe reports IsConnected.

		Phase 2 (active): connects to the dedicated health pipe (PipeName.Health)
		started automatically by Start-PipeServerOrClient in the server process,
		sends a PING with a per-call random nonce, and expects PONG echoing the
		same nonce back. A successful PONG confirms the server process is alive
		and responding. The nonce prevents replay attacks and makes a squatting
		process unable to pass the check without relaying the exact challenge value.

		Returns $false immediately if Phase 1 fails. Returns the result of the
		PING/PONG exchange for Phase 2.

		.PARAMETER PipeInfo
		The PipeInfo object from the session's ServerClientParams.

		.PARAMETER TimeoutMs
		Milliseconds to wait for the health pipe connection and PONG response.
		Default 2000.

		.EXAMPLE
		if (Test-PipeSession -PipeInfo $Session.ServerClientParams.PipeInfo)
		{
			# Session is healthy - safe to send commands
		}

		.OUTPUTS
		System.Boolean - $true if both phases pass, $false otherwise.
	#>

	[CmdletBinding()]
	Param(
		[Parameter(Mandatory)]
		[AllowNull()]
		[PSObject]$PipeInfo,
		[Int]$TimeoutMs = 2000
	)
	If ($Script:FTrace)
	{Write-MyLog -PathToLogFile $Script:FTLogFilePath -CallStack (Get-PSCallStack)}

	# Phase 1: passive object check
	try
	{
		if (-not $PipeInfo)
		{return $false}
		if (-not $PipeInfo.$StrPipe)
		{return $false}
		if (-not $PipeInfo.$StrPipe.IsConnected)
		{return $false}
		if (-not $PipeInfo.$StrReader)
		{return $false}
		if (-not $PipeInfo.$StrWriter)
		{return $false}
		# Check writer's base stream is accessible (not disposed)
		$null = $PipeInfo.$StrWriter.BaseStream
	}
	catch
	{return $false}

	# Phase 2: active PING/PONG on the dedicated health pipe.
	# A per-call nonce is generated and echoed back so a squatting process
	# cannot pass without relaying the exact challenge value.
	$HealthPipeName = $PipeInfo.$StrName + '.Health'
	$Nonce          = [guid]::NewGuid().ToString('N')
	$HealthClient   = $null
	try
	{
		$HealthClient = [System.IO.Pipes.NamedPipeClientStream]::new(
			'.', $HealthPipeName,
			[System.IO.Pipes.PipeDirection]::InOut
		)
		$HealthClient.Connect($TimeoutMs)
		$HWriter = [System.IO.StreamWriter]::new($HealthClient)
		$HReader = [System.IO.StreamReader]::new($HealthClient)
		$HWriter.AutoFlush        = $true

		$HWriter.WriteLine("PING:$Nonce")
		$Response = $HReader.ReadLine()
		$Response -eq "PONG:$Nonce"
	}
	catch
	{$false}
	finally
	{
		if ($HealthClient) {try {$HealthClient.Dispose()} catch { $null = $_ }}
	}
}
