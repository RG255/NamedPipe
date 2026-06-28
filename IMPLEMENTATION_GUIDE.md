# NamedPipe Implementation Guide

## Overview
This guide documents how to implement named pipe functionality in other PowerShell scripts using the NamedPipe module.

## Core Concepts

### Architecture
- **Named Pipes**: Windows IPC mechanism for process-to-process communication
- **Server**: Creates and waits for connections (can run elevated/as admin)
- **Client**: Connects to server and sends/receives data
- **Serialization**: Objects converted to Base64-encoded XML/JSON for transport
- **Bidirectional**: Both server and client can send and receive

### Key Components

1. **Start-PipeServerOrClient.ps1** - Main entry point for server/client creation
2. **Send-Data.ps1** - Serializes and sends objects through pipe
3. **Receive-Data.ps1** - Receives and deserializes objects from pipe
4. **Send-Request.ps1** - High-level wrapper for client requests
5. **Get-NewPipeName.ps1** - Generates unique pipe names
6. **Set-PipeSecurity.ps1** - Configures pipe access control

## Data Flow

### Server → Client Communication
1. Client sends request via `Send-Request` or `Send-Data`
2. Server receives via `Receive-Data`
3. Server processes request (executes ScriptBlock, queries security, etc.)
4. Server sends response via `Send-Data`
5. Client receives response via `Receive-Data`

### Object Structure - DataObject
```powershell
$DataObject = @{
    Type              # Request type: 'ScriptBlock', 'Security', 'ExitPipe'
    Request           # Current request identifier
    LastRequest       # Previous request (server side)
    Parameters        # Parameters for the request
    LastParameters    # Previous parameters (server side)
    Data              # Additional data payload
    LastData          # Previous data (server side)
    Result            # Result from server processing
    Error             # Error information if any
    ServerPID         # Process ID of server
    ServerUser        # Username running server
    ClientPID         # Process ID of client
    ClientUser        # Username running client
    FromServerOrClient # Direction indicator
    ProgressInfo      # Progress reporting data
    Query             # RESERVED - server->client needs-input/question payload (null in normal flow)
}
```

### Reserved: Query field (server->client "needs-input" convention)

**Status:** the `Query` field exists on the DataObject (reserved, always `$null` today) but has **no runtime behaviour yet**. It was added now so the eventual feature is an additive *consumer convention* rather than a protocol/shape change at that time (the DataObject shape is defined centrally in `Set-ObjectParams`, so reserving the slot keeps every DataObject uniform).

**Problem it will solve:** today the server returns only success (`Result`) or failure (`Error`). There is no first-class way for the server to say "I need the user to answer something before I can continue" - e.g. a disambiguation (two disks match X - which one?).

**Chosen approach - return-and-re-invoke (NOT a mid-execution channel):** when a server-side action reaches a decision it can resolve *before or between* steps, it returns normally with a structured payload in `Query`, e.g.:
```powershell
$DataObject.Query = @{ Id = 'disk-pick'; Kind = 'Choice'
    Prompt = 'Two disks match X - which?'; Choices = @('Disk2','Disk3'); Default = 'Disk2' }
```
The client, after `Send-Request`, checks `if ($DataObject.Query) { ... }`, resolves an answer, and **re-invokes the same action** with the answer added to `Parameters`. The server never blocks waiting on the client, so the deadlock/hang risk that `Send-ProgressInfo` was deliberately designed to avoid never arises.

**Payload may also carry a scriptblock (as text).** Like `Request`, the `Query` payload is just data and can include scriptblock *text* the client executes - e.g. a client-side validator or a custom answer resolver:
```powershell
$DataObject.Query = @{ Id = 'count'; Kind = 'Text'; Prompt = 'How many?'
    Validate = '{ param($a) ($a -as [int]) -in 2..5 }' }   # text, [ScriptBlock]::Create on the client, same as Request
```
Trust note: this is the **server handing the client code to run** - the reverse of the normal client->server flow. In the usual model (the client spawned the elevated server) that is acceptable, but treat it deliberately: the client should only execute `Query` scriptblocks from a server it started.

**Why a dedicated field, not the `Error` string:** overloading `Error` would make every existing `if ($DataObject.Error)` site treat a *question* as a *failure* (rollback/abort), and pattern-matching human-readable prose is brittle. A distinct field keeps "failed" and "needs input" cleanly separate.

**Client-side answer resolution (when built):** programmatic handler first -> timed interactive prompt (console-guarded, like the DnsTools root-hints prompt: `[Console]::KeyAvailable` throws in the VS Code/PSES console, so fall back to a notice) -> default on timeout / non-interactive. Add a max-rounds guard so a misbehaving server cannot loop the client forever.

**Boundary - what this does NOT cover:** a question that arises *deep inside a single, non-resumable* server operation (re-invoking would re-run the whole thing). Only that narrow case would justify a true mid-execution question channel (server sends a question, then blocks on a bounded/timeout read for the answer). Defer that until a concrete need appears.

**When implementing, also update:** `Send-Data` role-based field clearing must keep `Query` on a server->client send and clear it on a client send; `Send-Request`'s receive loop gains a `Query` branch; add a small client `Resolve-PipeQuery` helper. None of that exists yet - this is only the reserved slot.

### Object Structure - ServerClientParams
```powershell
$ServerClientParams = @{
    Server              # Boolean: true if this is server
    Client              # Boolean: true if this is client
    Spawned             # Boolean: true if spawned process
    AdminRequired       # Boolean: server needs elevation
    Wait                # Boolean: pause server on exit
    WindowStyle         # Window style for spawned server
    InfoDisplay         # Bitmask: 1=progress, 2=verbose data, 4=debug (0=silent, 7=all)
    AccessIdentifier    # Array of security ACL identifiers
    ServerWaitTimeout   # Timeout in seconds for server to wait for connection (default: 60)
    ClientConnectTimeout # Timeout in milliseconds for client connection (default: 10000)
    PipeName            # Name of the pipe
    PipeInfo = @{
        Name            # Full pipe name
        Pipe            # The pipe stream object
        Reader          # StreamReader for reading
        Writer          # StreamWriter for writing
    }
    PipeParams = @{
        Direction       # In, Out, or InOut
        Instances       # Max concurrent instances
        Mode            # Message or Byte mode
        Options         # Async, WriteThrough, etc.
        PipeServer      # Server name (usually '.')
        PipeBufferSizeR # Read buffer size
        PipeBufferSizeS # Send buffer size
    }
}
```

## Implementation Examples

### Example 1: Basic Client-Server Communication

```powershell
# Import the module
Import-Module NamedPipe -RequiredVersion 0.9

# Generate unique pipe name
$pipeName = Get-NewPipeName -PipeName 'MyApp'

# Create server parameters
$serverParams = @{
    Server = $true
    AdminRequired = $false
    PipeName = $pipeName
    AccessIdentifier = @('Users')  # Allow Users group access
}

# Start server (spawns new process)
$serverPID = Start-PipeServerOrClient -ServerClientParams $serverParams

# Create client and connect
$clientParams = @{
    Client = $true
    PipeName = $pipeName
}
$pipeInfo = Start-PipeServerOrClient -ServerClientParams $clientParams

# Send request to server
$request = @{
    Type = 'ScriptBlock'
    Request = 'Get-Process'
    Parameters = @{Name = 'powershell'}
}
$result = Send-Request -Request $request -PipeInfo $pipeInfo

# Results are in $result.Result
$processes = $result.Result

# Close the pipe
Send-Request -Request @{Type = 'ExitPipe'} -PipeInfo $pipeInfo
```

### Example 2: Elevated Server Operations

```powershell
# Server needs admin rights
$serverParams = @{
    Server = $true
    AdminRequired = $true  # Will prompt for elevation
    PipeName = Get-NewPipeName
    WindowStyle = 'Hidden'
    AccessIdentifier = @(
        $env:USERNAME  # Only current user can access
    )
}

$serverPID = Start-PipeServerOrClient -ServerClientParams $serverParams

# Client connects and sends admin-level request
$pipeInfo = Start-PipeServerOrClient -ServerClientParams @{
    Client = $true
    PipeName = $serverParams.PipeName
}

$result = Send-Request -Request @{
    Type = 'ScriptBlock'
    Request = 'Get-Service'
    Parameters = @{Name = 'wuauserv'}
} -PipeInfo $pipeInfo
```

### Example 3: Custom Timeout Configuration

```powershell
# v0.9+ feature: Configurable timeouts
$serverParams = @{
    Server = $true
    PipeName = Get-NewPipeName
    ServerWaitTimeout = 120        # Wait up to 2 minutes for connection
    ClientConnectTimeout = 20000   # Client has 20 seconds to connect
}

$clientParams = @{
    Client = $true
    PipeName = $serverParams.PipeName
    ClientConnectTimeout = 20000   # Must match or be less than server
}
```

### Example 4: Security ACL Configuration

```powershell
# Multiple security identifiers
$accessList = @(
    'DOMAIN\User1'              # Specific user: ReadWrite/Allow
    'DOMAIN\User2:Deny'         # Specific user: ReadWrite/Deny
    'Administrators:Allow:FullControl'  # Full control for admins
    'S-1-5-11'                  # Well-known SID (Authenticated Users)
)

$serverParams = @{
    Server = $true
    PipeName = Get-NewPipeName
    AccessIdentifier = $accessList
}
```

## Serialization Functions

### ConvertTo-Serial
Converts any PowerShell object to Base64 string for transmission.

```powershell
$object = @{Name = 'Test'; Value = 123}
$serialized = ConvertTo-Serial -Object $object
# Output: Base64 string
```

### ConvertFrom-Serial
Restores PowerShell object from Base64 string.

```powershell
$object = ConvertFrom-Serial -Text $serialized
# Output: Original object structure
```

## Error Handling

### Client Side
```powershell
try {
    $pipeInfo = Start-PipeServerOrClient -ServerClientParams $clientParams
    $result = Send-Request -Request $myRequest -PipeInfo $pipeInfo

    if ($result.Error) {
        Write-Error "Server returned error: $($result.Error)"
    }
}
catch {
    Write-Error "Pipe communication failed: $_"
}
```

### Server Side
Errors are automatically captured and returned in `$DataObject.Error` by the server loop.

## Best Practices

1. **Always use unique pipe names** - Use `Get-NewPipeName` to avoid conflicts
2. **Match timeouts** - Client timeout should not exceed server timeout
3. **Close pipes explicitly** - Send `ExitPipe` request when done
4. **Use try-finally for cleanup** - Ensure resources are disposed (v0.9+ does this automatically)
5. **Test security ACLs** - Verify correct users have access before deployment
6. **Handle errors gracefully** - Check for `$result.Error` after each request
7. **Limit admin elevation** - Only use `AdminRequired = $true` when necessary

## Troubleshooting

### Connection Timeout
- Increase `ServerWaitTimeout` and `ClientConnectTimeout`
- Check if server process started successfully
- Verify pipe name matches between client and server

### Access Denied
- Check `AccessIdentifier` includes current user/group
- Verify client user has permission to access pipe
- On Windows, use `Get-Acl` to inspect pipe permissions

### Serialization Errors
- Ensure objects being sent are serializable
- Avoid circular references in objects
- Large objects may need chunking (not built-in)

## Performance Considerations

- **Buffer sizes**: Adjust `PipeBufferSizeR` and `PipeBufferSizeS` for large data transfers
- **Serialization overhead**: Base64 encoding increases size by ~33%
- **Process spawning**: Server spawn has ~500ms-2s overhead
- **Async mode**: Use `PipeOptions.Asynchronous` for better concurrency

## Integration Patterns

### Pattern 1: Long-Running Background Service
Server runs continuously, multiple clients connect/disconnect.

### Pattern 2: On-Demand Elevation
Client spawns elevated server only when admin operations needed.

### Pattern 3: Progress Reporting
Server sends progress updates via `ProgressInfo` property.

### Pattern 4: Request-Response Queue
Multiple sequential requests over single pipe connection.

## Version Compatibility

### v0.8 → v0.9 Migration
- All v0.8 code works unchanged in v0.9
- New timeout properties are optional (use defaults)
- Resource cleanup improved (automatic in v0.9)

### PowerShell Version Support
- **PowerShell 5.1**: Full support (Windows PowerShell)
- **PowerShell 7+**: Full support (PowerShell Core)
- Automatic version detection and appropriate .NET types used

## Additional Resources

- See `CHANGELOG.md` for detailed change history
- Review example scripts in project directory (if available)
- Windows Named Pipes documentation: https://learn.microsoft.com/en-us/windows/win32/ipc/named-pipes
