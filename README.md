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
| `Send-Request` | Send a command string to the server and return the result (`-TimeoutSeconds` / `-MaxRuntimeSeconds` to bound a long request) |
| `Get-PipeRequestStatus` | Ask the server whether it is idle or busy (works from another runspace) |
| `Stop-PipeRequest` | Cancel the running request; the session stays open |
| `Stop-PipeServer` | Terminate the server process (last resort for a request that cannot be cancelled) |

Every line on the pipe is an authenticated, integrity-checked frame (0.17), and a request that hangs can be cancelled or its
server killed from a non-elevated caller (0.16). See the user guide's "What's New" sections.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Windows only (named pipe server/client)

## Installation

Clone or copy this repository into a folder named after the version, inside a module folder on your
`$env:PSModulePath`. For an all-users install (admin rights needed, and a location only administrators can
write to, which matters because this module can start elevated processes):

```powershell
# PowerShell 7
git clone https://github.com/RG255/NamedPipe "C:\Program Files\PowerShell\Modules\NamedPipe\0.17"
# Windows PowerShell 5.1
git clone https://github.com/RG255/NamedPipe "C:\Program Files\WindowsPowerShell\Modules\NamedPipe\0.17"
```

Then import:

```powershell
Import-Module NamedPipe -RequiredVersion 0.17
```

## Tests

The Pester suite needs Pester 5. Install the module (see Installation) before running it, because tests that start a server
process load `NamedPipe` 0.17 by name and version from your module path:

```powershell
Invoke-Pester -Path .\Tests\NamedPipe.Tests.ps1 -Output Detailed
```

Run it under both Windows PowerShell 5.1 and PowerShell 7. The tests that deliberately provoke integrity-frame rejections redirect
`$env:ProgramData` to a temporary folder, so they do not write to your real catch-audit log. The scripts in `Tests\` named
`Test-*.ps1` / `Start-PipeTest*.ps1` are live end-to-end checks that start real server processes (`Test-ElevatedCancel.ps1` raises one UAC prompt).

## Documentation

See [USERGUIDE.md](USERGUIDE.md) for full usage, architecture, and integration examples, and
[Docs/UsingFromScripts.md](Docs/UsingFromScripts.md) for a short guide to the session patterns and pitfalls when
calling NamedPipe from your own scripts.
