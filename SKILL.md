---
name: claude-chrome-wsl-fix
description: Diagnoses and repairs "Claude in Chrome" when it will not connect for Claude Code running in the VS Code extension under WSL on Windows. The VS Code extension hardcodes --no-chrome into the CLI launch arguments and no setting turns it off, so the browser integration silently never starts. Use this skill whenever someone says Claude in Chrome is not working, not connecting, greyed out, or missing; whenever they ask how to enable, turn on, or force the Chrome integration or browser control in VS Code; whenever they mention --chrome, --no-chrome, or claudeProcessWrapper; and whenever they are on WSL and want Claude to see, drive, screenshot, or control a browser. Also use it when they reinstalled the Chrome extension and it still does not connect, since reinstalling never fixes this cause.
---

# Fixing Claude in Chrome under VS Code + WSL

## What is actually wrong

People reasonably assume the Chrome extension is broken, so they reinstall it,
sign in again, and restart the browser. None of that helps, because the failure
is upstream of the browser entirely.

The Claude Code **VS Code extension** builds the CLI's argument list with a
fixed block, and `--no-chrome` is in it:

```js
extraArgs:{debug:null,"debug-to-stderr":null,"enable-auth-status":null,
           "no-chrome":null,"replay-user-messages":null}
```

No `claudeCode.*` setting reads that value, so there is nothing to toggle in the
settings UI. It has survived extension updates. A session launched this way has
the integration disabled at the process level, and it cannot be switched on from
inside that session — it is a launch flag, not a runtime one.

The one supported interception point is **`claudeCode.claudeProcessWrapper`**,
documented as "Executable path used to launch the Claude process." When it is
set, the extension launches your script and passes the real binary as the first
argument:

```
<your wrapper> <real claude binary> <all the extension's args...>
```

So a small shim can drop `--no-chrome`, add `--chrome`, and forward the rest
untouched. That is the whole fix.

## Procedure

Work through this in order. Each step tells you what to expect, so you can stop
early when you find the real blocker — it is not always the flag.

### 1. Diagnose before changing anything

```bash
scripts/diagnose.sh
```

It is read-only and prints seven checks. The two that usually matter are
**section 4** (is the wrapper installed?) and **section 5** (is the setting
registered?). Section 3 lists running sessions and whether each got `--chrome`
or `--no-chrome`, which is how you confirm the fix later.

If sections 6 or 7 fail, fix those first — the flag is necessary but not
sufficient, and the reason is in the next section.

### 2. Install

```bash
scripts/install.sh
```

This writes the wrapper to `~/.claude/bin/`, **self-tests it against a stub
binary**, and only then registers the setting. The self-test matters: a broken
wrapper means sessions that refuse to start, and discovering that after a window
reload is a miserable way to learn it.

The setting goes into **Remote [WSL] Machine settings**, never User settings.
User settings sync across machines, and a Linux path pushed to someone's Mac
breaks Claude Code there.

### 3. Reload the VS Code window

`Ctrl+Shift+P` → **Developer: Reload Window**.

Sessions already running keep the arguments they started with. Only new ones
pick up the wrapper. This is the step people skip.

### 4. Confirm

Re-run `scripts/diagnose.sh`. Section 3 should now show at least one session
launched **with `--chrome`**. If every session still shows `--no-chrome`, the
window was not reloaded or the setting did not land — check section 5.

## The part that trips people up

Getting the flag set is necessary but **not sufficient**, and this is worth
explaining to anyone you are helping, because otherwise the fix looks like it
failed:

The Claude CLI is a **Linux process inside WSL**. It looks for the browser
extension in Linux profile directories (`~/.config/google-chrome` and
equivalents). **A Chrome installed on Windows is invisible to it**, no matter
what that browser has installed or who is signed into it.

So the browser that pairs has to be a **Linux-side browser inside WSL**. That is
not the hardship it sounds like — a Chrome installed in WSL renders on the
Windows desktop through WSLg and behaves like a normal window. Install Chrome
inside WSL, add the extension from `https://claude.ai/chrome`, sign in there.

If someone genuinely needs Claude to drive the **Windows** browser instead, the
extension route cannot do it and the answer is a different mechanism entirely —
see `references/cdp-fallback.md`.

## Reversing it

```bash
scripts/install.sh --uninstall
```

Removes the setting (keeping a `.bak`) and leaves the wrapper file in place,
where it is inert. Reload the window to return to stock behaviour.

## What to tell people about the risk

Once registered, **every** VS Code Claude session launches through this script,
including any already-running agents. If the script is deleted or the extension
changes its argument shape, sessions fail to spawn. That is why `install.sh`
self-tests, and why the uninstall path is one command. It is worth saying out
loud rather than discovering later.

## Deeper reading

- `references/root-cause.md` — the forensics: where the flag lives, how the
  wrapper contract was derived, how to re-verify after an extension update, and
  why the Windows-side native messaging host cannot reach a WSL session.
- `references/cdp-fallback.md` — the alternative when someone specifically needs
  the **Windows** Chrome driven, using the DevTools Protocol instead. Covers the
  Chrome 136+ restriction that blocks this on a default profile.
