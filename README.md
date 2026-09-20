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

Clone or copy this repository into a folder named after the version, inside a module folder on your
`$env:PSModulePath`. For an all-users install (admin rights needed, and a location only administrators can
write to, which matters because this module can start elevated processes):

```powershell
# PowerShell 7
git clone https://github.com/RG255/NamedPipe "C:\Program Files\PowerShell\Modules\NamedPipe\0.15"
# Windows PowerShell 5.1
git clone https://github.com/RG255/NamedPipe "C:\Program Files\WindowsPowerShell\Modules\NamedPipe\0.15"
```

Then import:

```powershell
Import-Module NamedPipe -RequiredVersion 0.15
```

## Documentation

See [USERGUIDE.md](USERGUIDE.md) for full usage, architecture, and integration examples.
