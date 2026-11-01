# SETUP: browser control for Claude Code on Windows + WSL

**If you are a person:** open Claude Code inside WSL (the VS Code extension
or a WSL terminal) and send this one line:

```
Follow https://github.com/tirandagan/claude-chrome-wsl-fix/blob/main/SETUP.md to set up browser control on my computer.
```

or paste this whole file into the chat. Claude checks your machine first, asks
which browser you want it to drive, shows you every change before making it, and
tells you how to undo it. Expect a few minutes and one window reload.

Prefer a plugin? `/plugin install wsl-browser-bridge --marketplace tirandagan/claude-chrome-wsl-fix`,
then in a new chat say "Set up browser control on my computer". Claude follows
these same steps from the installed copy.

Prefer to do it yourself? Skip to [Manual install](#manual-install).

---

## Instructions for Claude

You are setting up browser control for the user's Claude Code, which runs inside
WSL on Windows. Follow the steps in order. The user may not be technical. Use
plain words, say what each step is for, and keep them informed between steps.

### Ground rules

1. **Read-only until step 4.** Steps 0–3 change nothing except the clone in step 0.
2. **Show, then ask.** Before any change, show the user the dry-run output: the
   exact files and settings. Wait for an explicit yes. A yes covers only what you
   showed.
3. **Never run `wsl --shutdown`, and never reload the VS Code window yourself.**
   Both end this session. Tell the user exactly what to do and what to say afterwards.
4. **Windows files** (`%UserProfile%\.wslconfig`) are edited only with a specific yes,
   and are backed up first (the installer does this).
5. **Never type passwords, sign in for the user, or install the Chrome extension for
   them.** Those are theirs to do. Tell them where and when.
6. **sudo is the user's to run.** If a step needs it, give them the command and wait.
7. **Report failures verbatim.** If a check fails, show its output before any summary.
   If you skip a step, say so.

### Step 0: Get the repo

**Already installed as a plugin?** If you're reading this from inside the
`wsl-browser-bridge` plugin (the user installed it with `/plugin install` or from
Anthropic's directory, and this file sits under `~/.claude/plugins/`), set `REPO`
to the folder this file is in and skip the clone below. Don't also clone into
`~/.claude/skills`: a second copy loads the skills twice.

Otherwise, clone into `~/.claude/skills/`. The repo is a plugin, and Claude Code
loads plugin folders found there at startup.

```bash
REPO=~/.claude/skills/claude-chrome-wsl-fix
if [ -d "$REPO/.git" ]; then git -C "$REPO" pull --ff-only
elif [ -e "$REPO" ]; then echo "EXISTS-NOT-GIT"
else git clone https://github.com/tirandagan/claude-chrome-wsl-fix.git "$REPO"; fi
```

- If you were handed this file from an existing clone somewhere else, use that path as `REPO`.
- `EXISTS-NOT-GIT` means an older copy of the skill is there. Ask the user before
  moving it, then: `mv "$REPO" ~/.claude/skill-backups/claude-chrome-wsl-fix-$(date +%Y%m%d)`
  and clone again. (Backups go outside `~/.claude/skills`, or they load as a duplicate skill.)
- If `git` is missing: `sudo apt install -y git` (the user runs it).

If `~/.config/claude-chrome-wsl-fix/state.env` exists, this is a **resumed**
setup. Read it (`PENDING=reload` or `PENDING=wsl-restart` tells you where the
user left off), say so, and go to step 6 for the route(s) already installed.

### Step 1: Verify the environment

```bash
"$REPO/scripts/preflight.sh"
```

The output starts with a boxed copyright notice. Show it to the user word for
word at the top of your reply, as a quote:

> **Claude Chrome for WSL**
> This is the Claude Chrome for WSL skill, written by Tiran Dagan, copyright 2026, tiran@tirandagan.com.

Then read the rest of the output and summarise it for the user in a few plain sentences.
The last lines are machine-readable:

```
RESULT route1=<ready|needs-setup|blocked> route2=<ready|needs-setup|blocked>
BLOCKER <route> <reason>
TODO <route> <step>
```

**Stop conditions.** Tell the user and don't continue with a blocked route:

| Blocker | What to tell them |
|---|---|
| `not WSL` | This setup is for Windows + WSL only. Claude Code on macOS, Linux or native Windows doesn't have this problem. |
| `python3 missing` | Route 1 needs it: `sudo apt install -y python3` |
| `Node >= 22 missing` | Route 2 needs it: `nvm install 22` (or install Node 22 another way) |
| `extension dropped claudeProcessWrapper` | Route 1 can't attach on this extension build. Offer Route 2 |
| `install Google Chrome on Windows` | Route 2 needs Chrome on Windows. They install it, then you re-run preflight |
| Windows interop off | Route 2 can't launch Windows programs. They set `[interop] enabled=true` in `/etc/wsl.conf` |
| port busy | Route 2 can use another port; pass `CDP_PORT=<free port>` to the installer |

If both routes are blocked, stop here and explain.

### Step 2: Choose the route

Explain the two routes in plain words and ask which they want. Use AskUserQuestion
if you have it.

- **Route 1, Claude in Chrome (a Chrome inside WSL).** Claude uses the official
  Claude in Chrome extension and its tools. The browser is a Chrome installed
  inside WSL. It shows up on the Windows desktop like a normal window, but it's a
  separate browser with its own bookmarks and logins. Needs one VS Code window
  reload, and signing in to the extension once.
- **Route 2, your Windows Chrome.** Claude drives the Chrome installed on
  Windows, in a separate automation profile (your everyday Chrome profile is
  never touched; Chrome doesn't allow that). Uses a small command-line tool
  instead of the extension. May need one WSL restart if networking isn't set up yet.

Recommend based on the preflight. If one route is `ready` or nearly so, say so.
If they said the browser "opened in WSL" and they wanted Windows, recommend
Route 2. Both can be installed. Also run step 4c in every case.

### Step 3: Show the plan

Run the dry run(s) for what they chose, and show the output:

```bash
"$REPO/scripts/install.sh" --dry-run                 # Route 1
"$REPO/scripts/install-windows-chrome.sh" --dry-run  # Route 2 (add --set-mirrored if preflight said networking isn't mirrored)
"$REPO/scripts/install-skills.sh" --dry-run          # skills
```

Then tell them, in one short list:

- what will be written (from the dry runs),
- the risk:
  - **Route 1:** every VS Code Claude session will launch through a small script.
    If it's deleted, sessions won't start until the setting is removed.
  - **Route 2:** anything they sign in to in the automation profile can be used
    by any program on this computer while it's open, so sign in there only to
    accounts they're happy for automation to use.
- how to undo it (step 8).

Ask for a yes. Wait.

### Step 4: Install

**4a. Route 1**
```bash
"$REPO/scripts/install.sh"
```
Exit 0: done. Exit 2: their settings file has comments. Give them the line it
printed, and tell them to paste it via `Ctrl+Shift+P` → *Preferences: Open Remote
Settings (JSON)*. Exit 1: show the output and stop.

If preflight had `TODO route1 install Chrome inside WSL`, give them:
```bash
cd /tmp && wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
  && sudo apt install -y ./google-chrome-stable_current_amd64.deb
```
(Debian/Ubuntu. On other distros, use their package manager.)

**4b. Route 2**
```bash
"$REPO/scripts/install-windows-chrome.sh" --no-welcome    # add --set-mirrored only if they agreed to the .wslconfig edit
```
If networking was already mirrored, this also opens a Chrome window on their
Windows desktop and checks it is the Windows browser. If it printed the
`wsl --shutdown` instructions, relay them (step 5). Exit 3 means networking isn't
mirrored and they didn't agree to `--set-mirrored`. Route 2 can't work until it
is, so explain that and ask again, or stop there.

**4c. Skills**
```bash
"$REPO/scripts/install-skills.sh"
```
It makes the plugin visible and removes the pre-2.2 `~/.claude/skills/windows-chrome`
link, which would otherwise load that skill twice. For a plugin install or a clone
already in `~/.claude/skills` it links nothing and says so. Exit 2 means a folder
named `claude-chrome-wsl-fix` that isn't this repo already exists in
`~/.claude/skills`. Ask before re-running with `--replace`, which moves it to
`~/.claude/skill-backups/`.

### Step 5: Hand the restart steps to the user

These end the current chat, so say them clearly and stop:

- **Route 1:** "Reload the VS Code window: `Ctrl+Shift+P` → *Developer: Reload
  Window*. Then start a new Claude chat and say: **Verify the claude-chrome-wsl-fix setup.**"
- **Route 2, if networking had to change:** "Save your work. In Windows PowerShell
  run `wsl --shutdown`. Reopen VS Code, start a new Claude chat and say:
  **Continue the claude-chrome-wsl-fix setup.**"

If both apply, the WSL restart covers the reload too. Give only that one.

If nothing needs a restart (for example Route 2 only, already mirrored), go
straight to step 6.

### Step 6: Verify (also where a resumed setup lands)

Re-run `"$REPO/scripts/preflight.sh"` first, then:

**Route 1**
```bash
"$REPO/scripts/diagnose.sh"
```
Section 3 must show this session launched **with `--chrome`**. Then the browser side:

1. Ask the user to open Chrome inside WSL. Run it for them as a background job
   (`google-chrome --no-first-run https://claude.ai/chrome`). A plain `&` job
   dies when your command ends.
2. In that window, they install the extension from <https://claude.ai/chrome> and
   **sign in** with the same Claude account Claude Code uses.
3. Load the Claude in Chrome tools, call `list_connected_browsers`, and if more
   than one browser is listed, ask which one is this computer before selecting it.
4. Open a tab on a harmless page (`https://example.com`) and read its title back to them.

**Route 2**
```bash
~/.claude/bin/launch-windows-chrome.sh
T=$(~/.claude/bin/cdp new https://example.com) && ~/.claude/bin/cdp text --tab "$T" | head -3 && ~/.claude/bin/cdp close "$T"
```
The launcher's user agent line must contain `Windows NT`. Tell them the window on
their desktop is the one Claude will use, and that it starts signed out.

If anything fails, use [references/troubleshooting.md](references/troubleshooting.md)
before improvising.

### Step 7: Welcome page

Once everything they chose is verified, open the welcome page. It's a short
"you're all set" page with the project credits and a link to the GitHub repo:

```bash
"$REPO/scripts/show-welcome.sh"     # Windows Chrome if route 2 is running, else the Chrome inside WSL
```

It opens in a new tab and leaves the user's tabs alone. Tell them it's there. If it
fails, say so; the setup itself is still fine.

### Step 8: Report

Finish with a short report:

- **Installed:** route(s), and the `wsl-browser-bridge` plugin with its two skills.
- **Changed:** the exact files from the installer output.
- **Checked:** what you verified in step 6, with the actual result. If anything is
  still unverified, say so.
- **How to use it:** Route 1, "ask me to open a page in Chrome". Route 2, the same;
  the `windows-chrome` skill takes it from there.
- **How to undo:** the simplest is to say "undo the browser setup" in a chat. By
  hand, with `REPO` written out as the real path:
  ```bash
  "$REPO/scripts/install.sh" --uninstall                # Route 1, then reload
  "$REPO/scripts/install-windows-chrome.sh" --uninstall # Route 2
  "$REPO/scripts/install-skills.sh" --uninstall         # the ~/.claude/skills link, if one was made
  ```
  Route 2's uninstall leaves `.wslconfig` and the automation profile alone; say so.
  For a plugin install, run these before `/plugin uninstall`, because the scripts
  are inside the plugin.

---

## Manual install

Everything Claude does above, by hand. Run these inside WSL.

```bash
# 0. get it
git clone https://github.com/tirandagan/claude-chrome-wsl-fix.git ~/.claude/skills/claude-chrome-wsl-fix
cd ~/.claude/skills/claude-chrome-wsl-fix

# 1. check (read-only)
scripts/preflight.sh

# 2a. Route 1: Claude in Chrome with a Chrome inside WSL
scripts/install.sh --dry-run && scripts/install.sh
#     install Chrome in WSL if you don't have it (Debian/Ubuntu):
#     wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
#     sudo apt install -y ./google-chrome-stable_current_amd64.deb
#     then Ctrl+Shift+P → Developer: Reload Window, open Chrome in WSL,
#     install https://claude.ai/chrome there and sign in.

# 2b. Route 2: your Windows Chrome
scripts/install-windows-chrome.sh --dry-run && scripts/install-windows-chrome.sh
#     if it reports networking isn't mirrored:
#     scripts/install-windows-chrome.sh --set-mirrored, then `wsl --shutdown` in
#     Windows PowerShell, reopen VS Code, and run scripts/install-windows-chrome.sh again.

# 3. skills: a clone in ~/.claude/skills already loads as the plugin; this only
#    removes the pre-2.2 windows-chrome link (or links a clone kept elsewhere)
scripts/install-skills.sh

# 4. confirm
scripts/diagnose.sh                      # Route 1: §3 shows a session WITH --chrome
~/.claude/bin/cdp version                # Route 2: user agent says Windows NT
scripts/show-welcome.sh                  # the welcome page, in whichever Chrome is set up
```

<details>
<summary>Route 1 settings change by hand, instead of install.sh</summary>

`Ctrl+Shift+P` → **Preferences: Open Remote Settings (JSON)**. Pick the *Remote
[WSL]* one, not User Settings, and add:

```json
"claudeCode.claudeProcessWrapper": "/home/YOUR_USERNAME/.claude/bin/claude-chrome-wrapper.sh"
```

Copy `scripts/claude-chrome-wrapper.sh` to that path first and `chmod +x` it.
**Remote, not User:** User settings sync across machines, and a Linux path
arriving on a Mac breaks Claude Code there.
</details>

Terminal users don't need Route 1's wrapper. `claude --chrome` is enough.

## Undoing everything

```bash
cd ~/.claude/skills/claude-chrome-wsl-fix
scripts/install.sh --uninstall                # then reload the VS Code window
scripts/install-windows-chrome.sh --uninstall
scripts/install-skills.sh --uninstall
```

Left in place on purpose: `.wslconfig` (other tools may rely on mirrored
networking) and the Windows automation profile folder (it holds logins; delete it
yourself if you want them gone). Backups: `settings.json.bak`, `*.bak-<date>`.
