# Fallback: driving the Windows browser over the DevTools Protocol

Use this only when someone specifically needs Claude to drive the **Windows**
Chrome — for example to reuse a browser they are already signed into on the
Windows side. The Claude-in-Chrome extension cannot do this from WSL (see
`root-cause.md`). The DevTools Protocol can.

This is a different capability with different properties. It gives page
navigation, JavaScript execution and screenshots, but not the extension's own
permission model or tool surface.

## The two constraints

**Chrome 136+ refuses `--remote-debugging-port` on the default profile.** This
is deliberate hardening: it stops a local process from attaching to the browser
you are signed into everywhere. The supported path is a dedicated
`--user-data-dir`, which starts signed out and holds its own logins. Do not try
to work around this by cloning a profile to make its cookies drivable.

**WSL must be able to reach the Windows loopback interface.** Add to
`%UserProfile%\.wslconfig` and restart WSL (`wsl --shutdown`):

```ini
[wsl2]
networkingMode=Mirrored
```

With mirroring, WSL's `127.0.0.1` reaches Windows listeners. A side effect worth
knowing: WSL and Windows then **share one port namespace**, so a port bound on
either side is unavailable to the other.

## Launching

```bash
cd /mnt/c/Users/$USER          # launch from a Windows-side cwd, or chrome.exe
                               # creates literal "C:\Users\..." directories
/mnt/c/Windows/System32/cmd.exe /c start "" \
  "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe" \
  --remote-debugging-port=9333 \
  --user-data-dir=C:\\claude-chrome-automation \
  --no-first-run --no-default-browser-check about:blank
```

Use `cmd.exe /c start`. Backgrounding `chrome.exe` directly under bash gets it
killed when the script exits.

Verify — the User-Agent tells you which browser you reached:

```bash
curl -s http://127.0.0.1:9333/json/version | grep User-Agent
# Windows NT 10.0 ... Chrome/…      → the Windows browser ✓
# X11; Linux ... HeadlessChrome/…   → a Linux headless instance ✗
```

## Two failure modes that waste time

**A live instance on that profile swallows new launches.** If a Chrome is
already running on the automation profile without a bound port, further launches
just open a tab in it and the port never appears. Kill that instance first, then
relaunch.

**`DevToolsActivePort` is an unreliable health check.** It has been observed
absent while CDP was serving correctly. Poll `/json/version` instead.

**Pick a port nothing else wants.** 9222 is the conventional default and is
frequently taken by other tooling — headless QA browsers, Lighthouse runs, other
agents. Taking it from them breaks their work. 9333 is a reasonable choice.

## Driving it

Node 18+ has a built-in `WebSocket`, so a CDP client needs no dependencies:
fetch `http://127.0.0.1:<port>/json/list`, pick a target, open its
`webSocketDebuggerUrl`, and send `{id, method, params}` messages —
`Runtime.evaluate`, `Page.navigate`, `Page.captureScreenshot`.

## The security point worth stating out loud

Anything signed into that automation profile can be driven by **any local
process** that can reach the port, including every other agent on the machine.
If someone signs into a production console there, an agent could act on it.
Keep that profile to logins you are willing to hand to automation, and say so
plainly rather than leaving it implicit.
