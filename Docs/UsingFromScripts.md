# Using NamedPipe from a script

A practical guide for script authors. Use NamedPipe when a non-elevated script needs to run something elevated without
relaunching itself: `Start-PipeSession` spawns a separate (optionally administrator) PowerShell process and gives you a
duplex pipe to send scriptblocks to. For architecture, every option and the full API, see [USERGUIDE.md](../USERGUIDE.md).

Pin the version you tested against (`-RequiredVersion`), and repin every consumer when you move to a newer one.
`RedactPotentialSecrets` is on by default. The module does not export `Set-Window` / `Publish-SetWindowCode`; a consumer
that needs them carries its own copy.

**Server-side failures surface.** `Get-SBResult` sets `$ErrorActionPreference` in both the module and the global scope, so a
scriptblock that fails on the elevated server returns with `$StrError` populated instead of looking like a success. (A module
function resolves that preference from the global scope, never from its caller, so setting it only locally was not enough.)

## Minimal pattern

```powershell
Remove-Module -Name NamedPipe -Force -ErrorAction SilentlyContinue
Import-Module -Name NamedPipe -Force -RequiredVersion <version> -ErrorAction Stop

$Private:MyBoundParameters = $PSCmdlet.MyInvocation.BoundParameters
$Session = Start-PipeSession -MyParameters $Private:MyBoundParameters -Options @{
    $StrAdminRequired = $True       # spawns elevated server (single UAC prompt)
    $StrWait          = $False      # close server window after pipe closes
    $StrNoExitOnError = $False      # $True also echoes a server-side error to the console; you check .Error either way
    $StrInfoDisplay   = 0           # 0=silent, 1=progress, 2=verbose, 4=debug
    $StrDepth         = 4           # serialization depth (keep <=10 for ACLs)
}
$ServerClientParams = $Session.$StrServerClientParams
$SendRequestParams  = $Session.$StrSendRequestParams
$SendRequestParams.$StrType = $StrScriptBlock

try
{
    $cmd = 'Get-Service | Select-Object Name, Status'
    $SendRequestParams.$StrDataObject = $cmd | Send-Request @SendRequestParams
    $rows = $SendRequestParams.$StrDataObject.$StrResult
    if ($SendRequestParams.$StrDataObject.$StrError)
    { Write-Host ('server error: {0}' -f $SendRequestParams.$StrDataObject.$StrError) -ForegroundColor Red }
}
finally
{
    Stop-PipeSession -SendRequestParams $SendRequestParams `
        -PipeInfo $ServerClientParams.$StrPipeInfo
}
```

## Lazy-create-and-reuse pattern (one UAC prompt, multiple sections)

When a script has many independent sections, each requesting work over the pipe, lazy-create the session on first use and
reuse it. Use `Test-PipeSession` to detect a stale connection.

```powershell
$Script:PipeSession            = $null
$Script:PipeServerClientParams = $null
$Script:PipeSendRequestParams  = $null

function Get-AdminPipeSession
{
    if ($Script:PipeSession -and
        (Test-PipeSession -PipeInfo $Script:PipeServerClientParams.$StrPipeInfo))
    { return $Script:PipeSession }

    Remove-Module -Name NamedPipe -Force -ErrorAction SilentlyContinue
    Import-Module -Name NamedPipe -Force -RequiredVersion <version> -ErrorAction Stop

    $Private:MyBoundParameters = $PSCmdlet.MyInvocation.BoundParameters
    $Script:PipeSession = Start-PipeSession -MyParameters $Private:MyBoundParameters -Options @{
        $StrAdminRequired = $True
        $StrWait          = $False
        $StrNoExitOnError = $False
        $StrInfoDisplay   = 0
        $StrDepth         = 4
    }
    $Script:PipeServerClientParams = $Script:PipeSession.$StrServerClientParams
    $Script:PipeSendRequestParams  = $Script:PipeSession.$StrSendRequestParams
    $Script:PipeSendRequestParams.$StrType = $StrScriptBlock
    return $Script:PipeSession
}

function Stop-AdminPipeSession
{
    if ($Script:PipeSession)
    {
        Stop-PipeSession -SendRequestParams $Script:PipeSendRequestParams `
            -PipeInfo $Script:PipeServerClientParams.$StrPipeInfo
        $Script:PipeSession = $null
    }
}

function Invoke-AdminCommand
{
    Param ([Parameter(Mandatory)][String]$Command)
    $null = Get-AdminPipeSession
    $Script:PipeSendRequestParams.$StrDataObject = $Command | Send-Request @Script:PipeSendRequestParams
    if ($Script:PipeSendRequestParams.$StrDataObject.$StrError)
    {
        Write-Host ('  ! server error: {0}' -f $Script:PipeSendRequestParams.$StrDataObject.$StrError) -ForegroundColor Red
    }
    return $Script:PipeSendRequestParams.$StrDataObject.$StrResult
}

# Each section just calls Invoke-AdminCommand; the UAC prompt fires once, on the first call.
# Always wrap the work in try/finally and call Stop-AdminPipeSession at the end.
```

## Sending work - what to put in `$Command`

`Send-Request` sends the value of `$SendRequestParams.$StrDataObject` (a string) and the server runs it as a scriptblock. The
result of the scriptblock comes back in `$StrResult`. Errors come back in `$StrError`.

- **Use a self-contained scriptblock string.** Every variable the body needs must either be defined inside the string or
  substituted in by the caller. The server has its own scope; `$Script:Foo`, `$using:Foo`, etc. from the caller are NOT available.
- **Return structured data.** Emit `[PSCustomObject]@{...}` records and process them on the caller side. Avoid `Write-Host`
  inside the command - it goes to the server's hidden window, not your console.
- **Helper functions.** Define them inside the command string (function definitions at the top of the scriptblock work fine),
  or build a `$Script:AdminPrelude` text variable and prepend it to every command.
- **Stamps and other caller state.** Embed the value by string-formatting it into the command before sending, e.g.
  `$cmd = ('$stamp = "{0}"; ...' -f $Script:Stamp)`.

## Requests that might hang - give them a timeout (0.16+)

By default `Send-Request` waits for ever. For anything that could loop or block, say how long you are prepared to wait:

```powershell
$SendRequestParams.$StrDataObject = $Command | Send-Request @SendRequestParams -TimeoutSeconds 60 -MaxRuntimeSeconds 1800
$r = $SendRequestParams.$StrDataObject
if ($r.$StrCancelled)      { <# stopped; the session is still open #> }
elseif ($r.$StrTimedOut)   { <# server was terminated; open a new session #> }
```

- `-TimeoutSeconds` is an inactivity limit: each `Send-ProgressInfo` message restarts it. `-MaxRuntimeSeconds` is the
  absolute cap that progress cannot extend. Use both for a long job that reports progress.
- A cancel keeps the session; a request that cannot be cancelled gets the server killed (use `-NoKillOnTimeout` to
  decide yourself). Either way the work is **abandoned, not rolled back** - keep destructive steps repeatable.
- From another runspace, `Get-PipeRequestStatus`, `Stop-PipeRequest` and `Stop-PipeServer` work on the same
  `PipeInfo`, including against an elevated server from a non-elevated caller.
- A server started with `Wait` stays open for `WaitSeconds` (default 300), not for ever.

## Common pitfalls

- **`$PipeOptions[$StrModuleToLoad]` from a consumer module's scope.** The exported `$Str*` variables are `$null` in PS7
  consumer-module scope, and `$PipeOptions[$null]` silently sets a null-keyed entry. Use the literal string `'ModuleToLoad'`
  in consumer code (see "Consumer Module Import" in the user guide).
- **Skipping `Stop-PipeSession`.** It leaves the elevated server window open. Always wrap requests in
  `try { } finally { Stop-PipeSession ... }`.
- **`Depth > 10` with ACL objects.** The recursive ACL graph causes an OutOfMemoryException. The default `$StrDepth = 2` is
  safe; only raise it if you know the payload shape.
- **`$_` in a built command string.** When you build the command with `-replace`, .NET regex expands `$_` in the replacement
  to the whole input string. Write `$$_` for a literal `$_`, or use `[regex]::Replace` with a scriptblock replacement.
