# NamedPipe

A PowerShell module providing persistent Inter-Process Communication (IPC) between
PowerShell processes using Windows Named Pipes. Allows a non-elevated client to dispatch
commands to an elevated server process and receive results - without re-prompting UAC
for each operation.

## Key Functions

| Function | Description |
|----------|-------------|
| `Start-PipeSession` | Start an elevated pipe server and return session parameters |
| `Stop-PipeSession` | Shut down the pipe server cleanly |
| `Test-PipeSession` | Check whether a pipe session is still alive |
| `Send-Request` | Send a command string to the server and return the result |

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Windows only (named pipe server/client)

## Installation

Deploy with the repo's standard deployment script (installs to the admin-only, AllUsers
Program Files module path):

```powershell
powershell.exe -NoProfile -File "D:\PowerShellScripts\Modules\Deploy-Modules.ps1" -Module NamedPipe -Version 0.13
```

Then import:

```powershell
Import-Module NamedPipe -RequiredVersion 0.13
```

## Documentation

See [USERGUIDE.md](USERGUIDE.md) for full usage, architecture, and integration examples.
