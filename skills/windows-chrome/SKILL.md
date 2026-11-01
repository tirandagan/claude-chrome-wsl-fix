---
name: windows-chrome
description: Drive the user's WINDOWS Chrome from a Claude Code session running inside WSL, over the Chrome DevTools Protocol (port 9333), using the launch-windows-chrome.sh and cdp helpers that claude-chrome-wsl-fix installs. Use this whenever the user on WSL asks you to open a browser, open or check a web page, look at a live or staging site, read what a page says, fill in or test a form, click through a flow, sign-in handoffs, take a screenshot of a page, or "use Chrome", and whenever they say the browser opened inside WSL or on Linux and they wanted their Windows Chrome. Prefer it over the Claude in Chrome (mcp__claude-in-chrome__*) tools on WSL unless the user asks for Claude in Chrome by name, because those tools can only reach a Chrome installed inside WSL.
---

# Driving the Windows Chrome from WSL

Claude Code runs as a Linux process inside WSL, so the Claude in Chrome extension
can only pair with a Chrome installed *inside* WSL. To work in the user's
**Windows** Chrome instead, this skill uses the DevTools Protocol: a dedicated
Windows Chrome profile listens on `127.0.0.1:9333`, and WSL reaches it because
networking is mirrored.

If `launch-windows-chrome.sh` or `cdp` is not on the machine, this route is not
installed yet. Use the `claude-chrome-wsl-fix` skill (or the repo's SETUP.md) to
set it up first; don't improvise a launch command.

## The routine

```bash
~/.claude/bin/launch-windows-chrome.sh          # idempotent; prints the UA — must say "Windows NT"
T=$(~/.claude/bin/cdp new https://example.com)  # YOUR OWN tab; keep the id
~/.claude/bin/cdp text --tab "$T"               # read it
~/.claude/bin/cdp close "$T"                    # always close your tab when done
```

Shell variables don't survive between separate Bash tool calls, so either chain
the commands in one call or pass the literal tab id each time.

Rules that keep you out of trouble:

- **Never drive a tab you didn't open.** Index 0 is usually the human's own tab.
  Open your own with `cdp new` and pass `--tab <id>` to every command.
- **The profile is shared and may be signed in to real accounts.** Never type a
  password or one-time code. When a page needs a login, open it in your tab, ask
  the user to sign in there, then wait (`cdp wait "<selector of the signed-in page>" 120000`).
- **Port 9222 is not yours.** Other tools (headless test browsers, Lighthouse,
  the chrome-devtools MCP) often use it. Never kill a browser to free a port.
- **If the user is working in the window, don't navigate their tabs** and don't
  close the window. `launch-windows-chrome.sh --stop` closes the whole automation
  Chrome, so use it only when asked.
- Outside actions (submitting a real form, posting, buying, changing an account)
  still need the user's yes for that exact action, same as anywhere else.

## Commands

| Command | What it does |
|---|---|
| `cdp version` | Browser and UA on the port; exits 2 if it is not a Windows Chrome |
| `cdp list` | Tabs: index, id, title, URL |
| `cdp new [url]` | Opens a tab, prints its id |
| `cdp close <tab>` | Closes a tab |
| `cdp goto <url> --tab T` | Navigates and waits for the load event (30 s cap) |
| `cdp text --tab T` | Visible page text (`document.body.innerText`) |
| `cdp eval "<js>" --tab T` | Evaluates an expression; promises are awaited; JSON result |
| `cdp wait "<css>" [ms] --tab T` | Waits until a **visible** element matches (default 15 s) |
| `cdp click "<css>" --tab T` | Real mouse click (trusted input) on the first **visible** match |
| `cdp type "<text>" --tab T` | Inserts text into the focused element (click the field first) |
| `cdp key Enter --tab T` | Presses Enter, Tab, Escape, Backspace, ArrowDown or ArrowUp |
| `cdp shot <file.png> --tab T` | Viewport screenshot; then Read the PNG to see it |

`T` is a tab id, a unique id prefix, or an index. Port comes from `CDP_PORT`, else
`~/.config/claude-chrome-wsl-fix/windows-chrome.env`, else 9333.

## Patterns

**Fill a field and submit.** `cdp click "input[name=q]"`, `cdp type "…"`,
`cdp key Enter`. Confirm the result with `text` or `shot` before reporting it.

**Pages with hidden duplicate buttons.** Single-page apps often keep a stale,
hidden copy of a button from the previous view. `click` and `wait` only consider
visible elements and report `visible / total` matches. If more than one is
visible, narrow the selector before clicking anything that has an effect.

**Seeing the page.** `cdp shot` to a file in your scratch directory, then Read
the image. Screenshots are the viewport only; scroll with
`cdp eval "scrollBy(0, innerHeight)"` for more.

**Something that needs real input semantics** (e.g. checking that a click counts as a user gesture):
use `click`/`key`, which are dispatched as trusted input. `eval` runs with a
simulated gesture, so it is not a fair test of "user-initiated" logic.

## When it doesn't work

| Symptom | Meaning / fix |
|---|---|
| `nothing answering on 127.0.0.1:9333` | Not running: `launch-windows-chrome.sh` |
| Launcher says Chrome started but WSL can't reach the port | WSL networking isn't mirrored. `wslinfo --networking-mode` should print `mirrored`. Fix in `%UserProfile%\.wslconfig`, then the user runs `wsl --shutdown` from Windows. Never run `wsl --shutdown` yourself: it ends this session. |
| `cdp version` exits 2 / UA says Linux or HeadlessChrome | Another browser holds the port. Use another one: `CDP_PORT=9334 launch-windows-chrome.sh` and the same `CDP_PORT` for `cdp` |
| Launch just opens a tab and the port never appears | An automation-profile Chrome is running without the debug port; the launcher closes it and retries. If it persists, ask the user to close that window |
| `no Node >= 22 found` | Install one (`nvm install 22`) or set `CDP_NODE=/path/to/node` |
| Logged out of a site | The automation profile has its own logins, separate from the everyday Chrome. Ask the user to sign in there once |

Background, the Chrome 136+ restriction and the security trade-off are in the
repo's `references/windows-chrome-cdp.md`.
