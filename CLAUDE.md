# autohotkey-scripts — agent notes

A pile of standalone AutoHotkey v2 scripts. Each `.ahk` is independent and uses
`#SingleInstance Force` so re-launching just hot-swaps the running copy.

## After editing any .ahk: validate, then reload

Run this. It does both: syntax-checks via `/ErrorStdOut`, then launches a fresh,
fully-detached instance which replaces the running one via `#SingleInstance
Force`. On syntax error it bails before touching the running script — safe.

**pwsh (preferred — captures syntax errors):**

Edit the `$file` line to point at the script you just changed, then run:

```bash
pwsh -NoProfile -Command '
    $file = "C:\Users\m\autohotkey-scripts\mouse-profiles.ahk"
    $ahk = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
    $err = [IO.Path]::GetTempFileName()
    try {
        $p = Start-Process $ahk -ArgumentList "/ErrorStdOut=UTF-8", $file `
               -PassThru -NoNewWindow -RedirectStandardError $err
        Start-Sleep -Milliseconds 700
        $msg = Get-Content $err -Raw -ErrorAction SilentlyContinue
        if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
        if ($msg) { Write-Host "Syntax error: $msg"; exit 1 }
        Start-Process $ahk -ArgumentList $file -WindowStyle Hidden | Out-Null
        Write-Host "Reloaded $file"
    } finally { Remove-Item $err -Force -ErrorAction SilentlyContinue }
'
```

After running, **wait ~5 seconds** and re-check `tasklist | grep AutoHotkey64`
to confirm the new PID is still alive — see the disown footgun below.

The two-phase shape (validate-then-launch) is load-bearing: Phase 1 launches
attached so we can read stderr, then kills it. Phase 2 launches detached
(`Start-Process`, no `-NoNewWindow`) so it survives the shell exit. Trying to do
both in one `Start-Process` either loses stderr (detached has no parent stdio)
or loses persistence (attached dies with the shell).

**bash quick reload (no syntax check — relies on AHK's error dialog):**

```bash
cmd //c start "" "C:/Program Files/AutoHotkey/v2/AutoHotkey64.exe" "C:/Users/m/autohotkey-scripts/mouse-profiles.ahk"
```

`cmd //c start ""` uses Win32 `CREATE_NEW_CONSOLE` / `DETACHED_PROCESS` so the
child is fully decoupled from the bash subshell. Reliable but no error capture
— if there's a syntax error you'll see AHK's dialog instead of a clean stderr
report.

## Conventions

- AHK v2 only (`#Requires AutoHotkey v2.0` at the top of every script)
- `#SingleInstance Force` so reloads don't pile up instances
- `Persistent` only when needed (hotkeys/timers keep most scripts alive on their own)
- Per-window remaps go through `#HotIf <state>` blocks driven by a periodic
  `SetTimer` checking `WinGetProcessName("A")` — see `mouse-profiles.ahk` for the pattern
- Helpers live at the bottom of the file under a `; ── helpers ──` divider

## Don't

- **Don't `"$ahk" "$file" & disown` from Git Bash.** Looks fine for the first
  few seconds — `tasklist` shows the process running. Then MSYS2 reaps it some
  seconds later and the script silently dies. Use `cmd //c start ""` (or pwsh
  `Start-Process`) instead. Burned ~30 minutes on this on 2026-05-04.
- **Don't `taskkill /IM AutoHotkey64.exe`** to "reset state" — that nukes every
  running AHK script, not just the one you're editing. Re-launch the specific
  file instead; `#SingleInstance Force` handles replacement cleanly.
- **Don't run AHK with `/validate`** — documented for v2.1-alpha but flaky/hangs
  in v2.0.x stable (which is what's installed at `C:\Program Files\AutoHotkey\v2\`).
  Use the `/ErrorStdOut` recipe above.
- **Don't try to redirect AHK stderr with bash `2>"$err"`** — MSYS doesn't
  forward AHK's Win32 stderr handle through bash's redirect. Use pwsh's
  `-RedirectStandardError` instead, which sets the actual Windows handle.
