![claude-chrome-wsl-fix](assets/banner.svg)

<p align="center">
  <em>A Claude Code skill by <a href="https://bepreparedsolutions.co">Tiran Dagan</a> —
  because the fix took a day to find and should take you two minutes.</em>
</p>

# claude-chrome-wsl-fix

Re-enables **Claude in Chrome** for Claude Code running in the **VS Code
extension under WSL on Windows**, where it is disabled at launch and no setting
turns it back on.

## Install

**Clone straight into your skills folder** (recommended — you get updates with `git pull`):

```bash
git clone https://github.com/tirandagan/claude-chrome-wsl-fix.git \
  ~/.claude/skills/claude-chrome-wsl-fix
```

**Or download the packaged skill** from
[Releases](https://github.com/tirandagan/claude-chrome-wsl-fix/releases) and unzip
it into `~/.claude/skills/`.

Then, in a Claude Code session:

```
Use the claude-chrome-wsl-fix skill — Claude in Chrome isn't connecting.
```

Claude runs the diagnostic, explains what is wrong, and walks you through it.
Prefer to drive yourself? See **[SETUP.md](SETUP.md)**, or run:

```bash
~/.claude/skills/claude-chrome-wsl-fix/scripts/diagnose.sh   # read-only
~/.claude/skills/claude-chrome-wsl-fix/scripts/install.sh    # applies the fix
```

Then reload the VS Code window.

## Who this is for

You are on Windows. You run VS Code with the WSL remote extension. You use
Claude Code through the VS Code extension rather than a terminal. You installed
the Claude Chrome extension, signed in, and Claude still cannot see or drive a
browser.

If you launch Claude from a plain WSL terminal, you do not need this — just run
`claude --chrome`.

## Why reinstalling the extension never fixes it

The failure is not in the browser. The VS Code extension hardcodes
`--no-chrome` into the arguments it passes to the Claude CLI:

```js
extraArgs:{debug:null,"debug-to-stderr":null,"enable-auth-status":null,
           "no-chrome":null,"replay-user-messages":null}
```

No `claudeCode.*` setting reads it, so there is nothing to switch off. It has
persisted across extension updates. Because it is a *launch* flag, a session
that started with it cannot enable the integration afterwards — which is why
restarting the browser, reinstalling the extension, and signing in again all
appear to change nothing.

## How the fix works

VS Code exposes one supported interception point,
`claudeCode.claudeProcessWrapper`. When set, the extension launches your script
instead of the binary and hands the real binary over as the first argument:

```
<your wrapper> <real claude binary> <all the extension's args...>
```

![How the fix works](assets/how-it-works.svg)

The wrapper drops `--no-chrome`, appends `--chrome`, and forwards everything
else byte for byte. About ten lines of shell.

## Install

```bash
scripts/diagnose.sh     # read-only; shows what is actually wrong
scripts/install.sh      # writes the wrapper, self-tests it, registers it
```

Then **reload the VS Code window** (`Ctrl+Shift+P` → *Developer: Reload
Window*). Sessions already running keep their old arguments — this is the step
most people miss.

Confirm with `scripts/diagnose.sh` again: section 3 should list a session
launched **with `--chrome`**.

Prefer to be walked through it conversationally? Paste [SETUP.md](SETUP.md) to
Claude.

## The catch worth knowing up front

Setting the flag is **necessary but not sufficient**. The Claude CLI is a Linux
process inside WSL, and it looks for the browser extension in *Linux* profile
directories. **A Chrome installed on Windows is invisible to it.**

So the browser that pairs must be a Chrome **installed inside WSL**. That is
less awkward than it sounds — WSLg renders it on your Windows desktop like any
normal window. Install Chrome in WSL, add the extension from
<https://claude.ai/chrome>, and sign in there.

If you specifically need Claude to drive your **Windows** Chrome, the extension
cannot do it; see [references/cdp-fallback.md](references/cdp-fallback.md) for
the DevTools Protocol route.

## What gets changed

Exactly two things:

| Path | Purpose |
|---|---|
| `~/.claude/bin/claude-chrome-wrapper.sh` | the shim |
| `~/.vscode-server/data/Machine/settings.json` | one key, `claudeCode.claudeProcessWrapper` |

The setting goes in **Remote [WSL] Machine settings**, deliberately not User
settings — those sync across machines, and a Linux path landing on your Mac
would break Claude Code there. The installer backs the file up to `.bak` before
touching it and refuses to write if the file contains comments it cannot parse
safely.

## Risk, stated plainly

Once registered, **every** VS Code Claude session launches through this script,
including agents already running. If the script is deleted or the extension
changes its argument shape, sessions fail to start. `install.sh` self-tests the
wrapper against a stub binary before registering it, precisely so that failure
surfaces now rather than after a reload.

## Uninstall

```bash
scripts/install.sh --uninstall
```

Removes the setting (keeping a backup) and leaves the wrapper file inert on
disk. Reload the window to return to stock behaviour.

## Layout

```
claude-chrome-wsl-fix/
├── SKILL.md                      instructions Claude follows
├── README.md                     this file
├── SETUP.md                      paste-to-Claude guided setup
├── scripts/
│   ├── diagnose.sh               read-only, 7 checks
│   ├── install.sh                install / --uninstall
│   └── claude-chrome-wrapper.sh  the shim itself
└── references/
    ├── root-cause.md             forensics + how to re-verify after updates
    └── cdp-fallback.md           driving Windows Chrome instead
```

## Verified against

Claude Code VS Code extension **2.1.278** and **2.1.280**, Chrome 153, WSL2 on
Windows. `references/root-cause.md` has the commands to re-confirm on a newer
build — worth running if the fix ever stops working.

---

![Built by Tiran Dagan, co-founder of BePrepared Solutions](assets/built-by.svg)

## Who made this, and why it exists

This skill is a by-product. It exists because I hit the bug myself, spent a day
inside a minified extension bundle working out that the browser was never the
problem, and decided nobody else should have to.

I'm **[Tiran Dagan](https://bepreparedsolutions.co)**, co-founder of
**[BePrepared Solutions](https://bepreparedsolutions.co)**. I've advised
executives and boards at global firms across media, telecom, healthcare and
tech, and I teach graduate students how to build with AI. These days I spend
most of my time building — which is how a WSL argument-forwarding bug ended up
costing me an afternoon.

### What BePrepared is

> The world's most comprehensive preparedness ecosystem. Monitoring, planning,
> supplies, and expert consulting, all built around your household's specific
> situation.

Most preparedness advice is a 400-page PDF and a shopping list that assumes your
life looks like someone else's. We built the opposite: a system that starts from
*your* address, *your* household, *your* actual risks, and tells you what to do
next.

Four products, one plan:

| | |
|---|---|
| **BeAware** | Live monitoring for your address — FEMA IPAWS alerts, utility outages, local emergencies. *So you never find out last.* |
| **BeReady** | An AI-generated preparedness plan: risk assessment, evacuation routes, day-by-day timeline, the skills you'd actually need. |
| **BeEquipped** | Curated kits matched to your plan, not to a generic checklist. |
| **BeAdvised** | Time with real experts — founders and consultants who've done this for a living. |

### Why a developer might find it interesting

If you build things, the engineering is the part worth a look. BeAware ingests
the **FEMA IPAWS** alert feeds, resolves **which utility actually serves a given
street address** against thousands of service-territory polygons in PostGIS, and
discovers the JSON endpoints behind utility outage maps so it can normalise wildly
inconsistent data into one schema. The planning side runs an AI pipeline that
scales supply quantities by household composition and time horizon, and generates
evacuation routing that changes depending on whether you'd be on foot or in a car.

It's a genuinely hard data problem wearing a calm consumer interface.

**→ [bepreparedsolutions.co](https://bepreparedsolutions.co)**

### If this skill saved you an afternoon

Take a look at what else I'm building — or just send this skill to the next
person who says "Claude in Chrome isn't working and I've reinstalled it twice."

---

<sub>Licensed for free use and redistribution. Not affiliated with or endorsed by
Anthropic. "Claude" and "Claude Code" are trademarks of Anthropic.</sub>
