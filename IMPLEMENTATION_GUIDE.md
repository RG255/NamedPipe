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
}
```

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
