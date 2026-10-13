# NamedPipe Examples

Small, focused, runnable demos - one topic per script - meant to build confidence using NamedPipe in
your own code without having to read `Get-SBResult.ps1` or parse `Tests\Start-PipeTest.ps1` (a real
regression harness covering health checks, re-listen, PID hand-off, request-policy demos and raw
integrity-label reads all in one file - genuinely useful, but not a place to learn "how do I start a
session and send one command").

These are learning aids shipped for reference. They are **not** part of the module's test suite and
**not** required for normal module use.

Run each with:
```powershell
powershell.exe -NoProfile -File .\01-Basic-Session.ps1
```

## Run order

1. **`01-Basic-Session.ps1`** - the minimal round trip: start a session, send one command, stop the
   session. Start here.
2. **`02-Redaction-BuiltIn.ps1`** - sends a value that IS structurally valid base64 (standing in for a
   potential secret) and shows it come back masked as `<base64 encoded>` automatically, with zero
   `RedactPattern` configuration - controlled by `RedactPotentialSecrets` (default `$true`, 0.15).
3. **`03-Redaction-CustomPattern.ps1`** - proves the gap built-in redaction doesn't cover (a SHORT,
   human-typed secret like a passphrase isn't base64-encoded at all, so it isn't caught), then shows
   the fix: a consumer-supplied `RedactPattern.Pattern` matching your own parameter name. Copy this
   template if your session carries a short, human-typed secret.
4. **`04-Debug-Verbosity-Levels.ps1`** - runs the same request four times at `-InfoDisplay` 0, 1, 2,
   and 4 so you can directly compare what each bitmask level actually prints, instead of guessing from
   documentation.
5. **`05-FunctionTrace-Detail.ps1`** - turns on function tracing with both bits set
   (`Enable-MyFunctionTrace -Option 3`) and shows the resulting `Detail:[Request:[...]]` line in the
   shared trace log for a dispatched pipe request, redacted, next to an ordinary entry-trace line.
6. **`06-RedactPotentialSecrets-QuotedValues.ps1`** - shows why this check tests each QUOTED VALUE as
   one atomic unit rather than loose word fragments (an earlier, wrong version of this fixed the
   security gap but broke readability - see the script's own doc comment for the real Pester failure
   that caught it), makes explicit the "potential, not confirmed" distinction the option's own name
   carries, and demonstrates turning `RedactPotentialSecrets` off to see a real value in the log.
7. **`07-Timeout-And-Cancel.ps1`** (0.16) - a request that would take a minute with `-TimeoutSeconds 3`: it comes
   back as `Cancelled = $true` and the SAME session answers the next request. Then progress messages keeping a
   busy request alive past the inactivity timeout, and `-MaxRuntimeSeconds` as the cap progress cannot extend.
8. **`08-Status-And-Stop-From-Another-Runspace.ps1`** (0.16) - `Get-PipeRequestStatus` and `Stop-PipeRequest` from a
   second runspace while `Send-Request` is blocked, then a request that CANNOT be cancelled
   (`[Console]::ReadKey`): `-NoKillOnTimeout` leaves the decision with you and `Stop-PipeServer` ends it.
9. **`09-NonInteractive-And-Bounded-Wait.ps1`** (0.16) - `Read-Host` inside a request fails at once because the
   server is `-NonInteractive`, and the `Wait` option now closes the server window after `WaitSeconds` instead of
   waiting for ever. **This one pops a server window for the wait - do not click it away or press a key** if you
   want to see the full time.
