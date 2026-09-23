# Guided setup

Two ways through this: let Claude walk you through it, or do it by hand.

---

## Option A — let Claude do it (recommended)

Open Claude Code in VS Code and paste this:

> I'm on Windows, using VS Code with the WSL remote extension, and I run Claude
> Code through the VS Code extension. Claude in Chrome isn't connecting — I've
> already installed the Chrome extension and signed in, and it still doesn't
> work.
>
> Please use the `claude-chrome-wsl-fix` skill to sort this out. Start by
> running its diagnostic and tell me what it finds before changing anything. I
> want to understand what's wrong before we fix it.
>
> Two things I care about:
> - Tell me exactly what you're going to change before you change it.
> - Tell me how to undo it.

Claude will run the read-only diagnostic, explain what is actually broken,
install the wrapper, and tell you when to reload the window.

### If you want to be more specific

Add whichever of these applies:

> I also want Claude to be able to drive my **Windows** Chrome, not a browser
> inside WSL.

(That needs a different mechanism — Claude will point you at the DevTools
Protocol route instead, and explain why the extension cannot do it.)

> I have other Claude sessions or agents running right now.

(Worth saying. The change affects how *all* VS Code Claude sessions launch,
though only ones started after the reload.)

---

## Option B — do it yourself

### 0. Find where the skill landed

Install location varies (personal skill, plugin, cloned repo), so resolve it
once and reuse it:

```bash
SKILL=$(find ~/.claude -type d -name claude-chrome-wsl-fix 2>/dev/null | head -1)
echo "$SKILL"     # sanity-check this is not empty
```

If that comes back empty, you are sitting in the skill folder already — use
`SKILL=$(pwd)`.

### 1. See what is wrong

```bash
"$SKILL/scripts/diagnose.sh"
```

Read-only, seven checks. Read the output before continuing — occasionally the
blocker is something else entirely, like having no Linux-side browser at all.

### 2. Install

```bash
"$SKILL/scripts/install.sh"
```

This writes `~/.claude/bin/claude-chrome-wrapper.sh`, tests it against a stub
binary, and only then adds one key to your Remote [WSL] settings. If the
self-test fails it stops without registering anything — a broken wrapper would
mean sessions that will not start.

<details>
<summary>Doing the settings change by hand instead</summary>

`Ctrl+Shift+P` → **Preferences: Open Remote Settings (JSON)** — the *Remote
[WSL]* one, not User Settings — and add:

```json
"claudeCode.claudeProcessWrapper": "/home/YOUR_USERNAME/.claude/bin/claude-chrome-wrapper.sh"
```

Use your real username. **Remote, not User:** User settings sync across
machines, and a Linux path arriving on a Mac breaks Claude Code there.
</details>

### 3. Reload the window

`Ctrl+Shift+P` → **Developer: Reload Window**

Do not skip this. Running sessions keep the arguments they launched with; only
new ones pick up the wrapper. Most reports of "it didn't work" are a missing
reload.

### 4. Confirm

```bash
"$SKILL/scripts/diagnose.sh"
```

Section 3 should now list a session launched **with `--chrome`**. Older sessions
still showing `--no-chrome` are expected — those started before the reload.

---

## Getting the browser side right

The flag alone is not enough, and this is where people get stuck.

The Claude CLI runs **inside WSL**, and it looks for the browser extension in
Linux profile directories. **Your Windows Chrome is invisible to it**, no matter
what is installed there or who is signed in.

So you need Chrome **inside WSL**:

```bash
# Debian/Ubuntu under WSL
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo apt install -y ./google-chrome-stable_current_amd64.deb
google-chrome &     # WSLg renders it on your Windows desktop
```

Then in *that* browser, install the extension from <https://claude.ai/chrome>
and sign in. Diagnostic sections 6 and 7 confirm both.

It behaves like a normal Windows window — WSLg handles the display. You are not
giving up a usable browser.

---

## If it still will not connect

Re-run the diagnostic and match the failing section:

| Failing section | What it means |
|---|---|
| 4 — wrapper | not installed, or not executable (`chmod +x`) |
| 5 — setting | not registered; if your settings file has `//` comments the installer will have told you to add the line by hand |
| 3 — all sessions `--no-chrome` | window was not reloaded, or the setting did not land |
| 6 — extension | installed in a *Windows* browser instead of a WSL one |
| 7 — browser | no Linux-side browser installed |

If section 2 reports **no hardcoded `--no-chrome`**, the extension may have
changed upstream. Test whether Claude in Chrome works without the wrapper before
keeping it — and if it does, uninstall:

```bash
"$SKILL/scripts/install.sh" --uninstall
```

`references/root-cause.md` has the exact commands to re-verify the fix against a
newer extension build.

---

## Undoing everything

```bash
"$SKILL/scripts/install.sh" --uninstall
```

Removes the setting (backup at `settings.json.bak`), leaves the wrapper inert on
disk. Reload the window. Nothing else was ever touched.
