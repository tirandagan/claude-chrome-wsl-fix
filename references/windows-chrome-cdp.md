# Route 2: driving the Windows Chrome over the DevTools Protocol

The Claude in Chrome extension cannot reach a Windows browser from WSL (see
[root-cause.md](root-cause.md)). The Chrome DevTools Protocol (CDP) can. This is
a different capability with different properties: navigation, page text,
JavaScript, trusted clicks and keys, and screenshots, through the `cdp` command
rather than the extension's tool surface and permission model.

`scripts/install-windows-chrome.sh` sets all of this up. This page explains what
it does and why, so you can debug it or do it by hand.

## Contents
- [The moving parts](#the-moving-parts)
- [Constraint 1: Chrome 136+ and the default profile](#constraint-1-chrome-136-and-the-default-profile)
- [Constraint 2: WSL must reach Windows' loopback](#constraint-2-wsl-must-reach-windows-loopback)
- [Launching](#launching)
- [Driving it](#driving-it)
- [Failure modes that waste time](#failure-modes-that-waste-time)
- [Security](#security)
- [Doing it by hand](#doing-it-by-hand)
- [Using the chrome-devtools MCP instead of cdp](#using-the-chrome-devtools-mcp-instead-of-cdp)

## The moving parts

| Piece | Where | Job |
|---|---|---|
| `launch-windows-chrome.sh` | `~/.claude/bin/` | Starts Windows Chrome on the automation profile with `--remote-debugging-port`; `--status`, `--stop` |
| `cdp` + `cdp.mjs` | `~/.claude/bin/` | Dependency-free CDP client; the shim finds a Node ≥ 22 |
| `windows-chrome.env` | `~/.config/claude-chrome-wsl-fix/` | `CDP_PORT`, `CHROME_PROFILE_DIR`, `CHROME_EXE` |
| Automation profile | `%LOCALAPPDATA%\claude-chrome-automation` (or an existing `C:\claude-chrome-automation`) | Chrome profile with its own logins |
| `.wslconfig` | `%UserProfile%\.wslconfig` | `networkingMode=Mirrored` |

## Constraint 1: Chrome 136+ and the default profile

Chrome 136 and later refuse `--remote-debugging-port` on the **default** profile.
This is deliberate hardening: it stops a local process from attaching to the
browser you are signed into everywhere. The supported path is a dedicated
`--user-data-dir`, which starts signed out and keeps its own logins.

Do not work around this by copying your everyday profile so its cookies become
drivable. The separate profile is the safety boundary.

## Constraint 2: WSL must reach Windows' loopback

Chrome's debug port listens on Windows' `127.0.0.1`. WSL2's default NAT network
can't see it. Mirrored networking fixes that. In `%UserProfile%\.wslconfig`:

```ini
[wsl2]
networkingMode=Mirrored
```

Then restart WSL from Windows PowerShell with `wsl --shutdown`. That closes every
WSL window, including the Claude session that made the change, so the installer
never runs it. Check the result inside WSL:

```bash
wslinfo --networking-mode     # → mirrored
```

Side effect: WSL and Windows then **share one port namespace**. A port bound on
either side is unavailable to the other.

## Launching

`launch-windows-chrome.sh` does, in order:

1. If `127.0.0.1:$CDP_PORT/json/version` answers with a `Windows NT` user agent, it
   stops there: already up.
2. If something else holds the port (a Linux or headless browser), it refuses
   rather than killing another tool's browser.
3. If an automation-profile Chrome is running **without** the port, it closes it:
   such an instance swallows new launches by opening a tab in itself.
4. Launches through `cmd.exe /c start "" chrome.exe --remote-debugging-port=… --user-data-dir=…`
   from a Windows-side working directory. `start` detaches properly; a plain
   backgrounded `chrome.exe` dies when the shell exits. A Linux working
   directory can also make `chrome.exe` create literal `C:\Users\…` folders in it.
5. Polls `/json/version` for up to 30 s. If Chrome is running but unreachable, it
   says that networking is the likely cause.

Check which browser you reached:

```bash
cdp version
# Chrome/155…  Mozilla/5.0 (Windows NT 10.0; …)   → the Windows browser ✓
# … X11; Linux … HeadlessChrome/…                 → some Linux browser ✗ (exit 2)
```

## Driving it

`cdp.mjs` talks to `http://127.0.0.1:<port>/json/*` for tab management and to
each tab's `webSocketDebuggerUrl` for `Runtime.evaluate`, `Page.navigate`,
`Input.dispatchMouseEvent`, `Input.insertText`, `Input.dispatchKeyEvent` and
`Page.captureScreenshot`. Node 22+ ships a global `WebSocket`, so it needs no
packages. The full command list and usage patterns are in
[skills/windows-chrome/SKILL.md](../skills/windows-chrome/SKILL.md).

Two design choices worth knowing:

- `click` and `wait` only consider **visible** elements and report
  `visible / total` matches. Single-page apps often keep a hidden copy of a
  button from the previous view, and clicking it can act on the wrong record.
- `click` and `key` are dispatched as trusted input (`event.isTrusted === true`).
  `eval` runs with a simulated user gesture, which is not a fair test of
  "user-initiated" logic.

## Failure modes that waste time

**A live instance on that profile swallows new launches.** Covered by step 3
above. If it persists, close the automation Chrome window by hand.

**`DevToolsActivePort` is an unreliable health check.** It has been observed
absent while CDP was serving correctly. Poll `/json/version` instead.

**Pick a port nothing else wants.** 9222 is the conventional default and is often
taken by headless test browsers, Lighthouse runs, other agents, or a
chrome-devtools MCP. Taking it from them breaks their work. 9333 is the default
here; change it with `CDP_PORT` in `windows-chrome.env`.

**Mirrored in `.wslconfig` but not in effect.** WSL hasn't restarted since the
edit. `wslinfo --networking-mode` tells you.

**Old Node.** Node 18–21 has no stable global `WebSocket`. The `cdp` shim finds an
nvm-installed Node 22+ even when the default `node` is older.

## Security

Anything signed in to the automation profile can be driven by **any local
process** that can reach the port while Chrome is running, including every
other agent on the machine. If someone signs in to a production console there,
an agent could act on it. Keep that profile to logins you are willing to hand to
automation, close it (`launch-windows-chrome.sh --stop`) when you don't need it,
and say this plainly to whoever you set it up for.

## Doing it by hand

```bash
# 1. networking (then: wsl --shutdown from Windows PowerShell)
printf '[wsl2]\nnetworkingMode=Mirrored\n' >> "$(wslpath "$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')")/.wslconfig"

# 2. launch
cd /mnt/c
/mnt/c/Windows/System32/cmd.exe /c start "" \
  "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe" \
  --remote-debugging-port=9333 \
  --user-data-dir=%LOCALAPPDATA%\\claude-chrome-automation \
  --no-first-run --no-default-browser-check about:blank

# 3. check
curl -s http://127.0.0.1:9333/json/version | grep User-Agent
```

Step 1 appends blindly. If your `.wslconfig` already has a `[wsl2]` section, edit it
instead, or use `install-windows-chrome.sh --set-mirrored`, which merges properly.

## Using the chrome-devtools MCP instead of cdp

If you prefer MCP tools to a CLI, point a **separate** chrome-devtools MCP server
at this port rather than repointing one that other work relies on:

```bash
claude mcp add windows-chrome -- npx -y chrome-devtools-mcp@latest -u http://127.0.0.1:9333
```

It needs Node 22+ on that server's PATH. The same rules apply: own tab, no
credentials, 9222 left alone.
