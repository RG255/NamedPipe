$HealthPipeName='Pipe-134200483911676730.health'
					$StopClient = [System.IO.Pipes.NamedPipeClientStream]::new('.', $HealthPipeName, [System.IO.Pipes.PipeDirection]::InOut)
					$StopClient.Connect(1000)
					$StopWriter = [System.IO.StreamWriter]::new($StopClient)
					$StopReader = [System.IO.StreamReader]::new($StopClient)
					$StopWriter.AutoFlush = $true
					$StopWriter.WriteLine('PING:-1234')
					$Reply=$StopReader.Readline()
					Write-host -Object $Reply
#exit
					$StopWriter.WriteLine('STOP')
					$StopClient.Dispose()
