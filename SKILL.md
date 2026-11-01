---
name: claude-chrome-wsl-fix
description: Sets up, diagnoses and repairs browser control for Claude Code on Windows + WSL. Covers both routes. Route 1 is Claude in Chrome with a Chrome installed inside WSL: the VS Code extension hardcodes --no-chrome into the CLI launch arguments and no setting turns it off, so the integration silently never starts. Route 2 is driving the user's Windows Chrome over the DevTools Protocol. Use this skill whenever someone says Claude in Chrome is not working, not connecting, greyed out, or missing; asks how to enable, turn on, or force the Chrome integration or browser control in VS Code; mentions --chrome, --no-chrome, claudeProcessWrapper, CDP, remote debugging, or port 9333; says the browser opened inside WSL when they wanted their Windows Chrome; wants Claude to see, drive, screenshot or control a browser from WSL; asks to install, verify, continue or undo this setup (including "Follow SETUP.md" and "Continue the claude-chrome-wsl-fix setup"); or reinstalled the Chrome extension and it still does not connect, since reinstalling never fixes this.
---

# Browser control for Claude Code on Windows + WSL

Paths below are relative to this skill's folder (the repo root). `SETUP.md` is the
full guided install, written for you to follow. Use it for a first-time setup.
This file is the short map for diagnosis, repair, resume and undo.

## Two routes, and how to choose

| | Route 1: Claude in Chrome, WSL-side Chrome | Route 2: Windows Chrome over CDP |
|---|---|---|
| Browser | A Chrome installed **inside WSL**, shown on the Windows desktop by WSLg | The user's **Windows** Chrome, in a dedicated automation profile |
| Tools | `mcp__claude-in-chrome__*` (the extension's own tools) | `~/.claude/bin/cdp` (see the `windows-chrome` skill) |
| Needs | Launch wrapper (VS Code only), Chrome in WSL, extension signed in there | `networkingMode=Mirrored`, Chrome on Windows, Node ≥ 22 |
| Pick it when | They want the Claude in Chrome tool surface | They want their Windows browser, or Route 1 keeps failing to pair |

Ask which they want if they haven't said. "The browser opened in WSL, I wanted
Windows" means Route 2. Both can be installed side by side.

Why Route 1 can never drive the Windows Chrome: the CLI runs inside WSL and only
looks in Linux browser profiles, and the Windows extension's native host launches
a *Windows* `claude.exe`. Details: `references/root-cause.md`.

## Always start read-only

```bash
scripts/preflight.sh      # both routes; ends with RESULT/BLOCKER/TODO lines
scripts/diagnose.sh       # Route 1 in depth (8 checks)
```

Read the output before changing anything, and tell the user what you found.

## Route 1: the launch flag

The VS Code extension builds the CLI arguments with a fixed block containing
`"no-chrome":null`. The supported hook `claudeCode.claudeProcessWrapper` makes
the extension spawn `<wrapper> <real binary> <args…>`, so a shim drops
`--no-chrome` and appends `--chrome`.

1. `scripts/install.sh --dry-run`: show the user the exact change.
2. With their yes, `scripts/install.sh`. It writes `~/.claude/bin/claude-chrome-wrapper.sh`,
   self-tests it against a stub binary, and only then sets the key in
   **Remote [WSL] Machine settings**, never User settings (those sync to other
   machines, where a Linux path would break Claude Code). Exit code 2 means the
   settings file has comments: give the user the one line to paste.
3. The user reloads the VS Code window. **That ends this chat**, so tell them to
   say "Verify the claude-chrome-wsl-fix setup" in the new one.
4. Verify with `scripts/diagnose.sh`. Section 3 should show a session launched with `--chrome`.

The flag is necessary but not sufficient. The browser side needs Chrome installed
in WSL (sudo, so the user runs it), and the extension from
`https://claude.ai/chrome` installed **and signed in** in that browser. If two
browsers show up on the account, call `list_connected_browsers` and ask which
one to use before driving anything.

Terminal users (no VS Code) need no wrapper: `claude --chrome`.

## Route 2: the Windows Chrome

1. `scripts/install-windows-chrome.sh --dry-run`, then (with a yes) without `--dry-run`.
   It installs `launch-windows-chrome.sh`, `cdp` and `cdp.mjs` into `~/.claude/bin`, writes
   `~/.config/claude-chrome-wsl-fix/windows-chrome.env`, and verifies by starting
   Chrome and checking that the user agent says `Windows NT`.
2. If networking isn't mirrored: `--set-mirrored` edits `%UserProfile%\.wslconfig`
   (backed up). Ask first, because it's a Windows file. Then the **user** runs
   `wsl --shutdown` from Windows PowerShell. Never run it yourself: it kills this session.
3. Day-to-day use is the `windows-chrome` skill.

## Skills and resume

`scripts/install-skills.sh` links this skill and `skills/windows-chrome` into
`~/.claude/skills` (`--replace` moves a conflicting folder to `~/.claude/skill-backups/`).

Installers record progress in `~/.config/claude-chrome-wsl-fix/state.env`
(`ROUTE1=`, `ROUTE2=`, `PENDING=reload|wsl-restart|none`). When asked to continue
or verify the setup, read it, re-run `scripts/preflight.sh`, and finish whatever is pending.

## Banner and welcome page

`preflight.sh`, `install.sh` and `install-windows-chrome.sh` start with a boxed
copyright notice. Show it to the user word for word, as SETUP.md step 1 says. When
setup is done and verified, run `scripts/show-welcome.sh` to open the welcome page
in a new tab of whichever Chrome is set up.

## Risk, said out loud

- Route 1: once registered, **every** VS Code Claude session launches through the
  wrapper. If the file is deleted or the extension changes its argument shape,
  sessions fail to start. That's why install self-tests and uninstall is one command.
- Route 2: anything signed in to the automation profile can be driven by **any**
  local process while the port is open. The profile should only hold logins the
  user is happy to hand to automation.

## Undo

```bash
scripts/install.sh --uninstall                # Route 1 (then reload the window)
scripts/install-windows-chrome.sh --uninstall # Route 2 (.wslconfig and the profile are left alone)
scripts/install-skills.sh --uninstall         # skill links
```

## Deeper reading

- `references/root-cause.md`: where the flag lives, the wrapper contract, how to
  re-verify after an extension update, why the Windows native host can't reach WSL.
- `references/windows-chrome-cdp.md`: Route 2 internals, Chrome 136+ profile rule,
  mirrored networking, failure modes, security.
- `references/troubleshooting.md`: symptom → cause table for both routes.
