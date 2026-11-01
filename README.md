![wsl-browser-bridge](assets/banner.svg)

<p align="center">
  <em>A Claude Code plugin by <a href="https://bepreparedsolutions.co">Tiran Dagan</a> —
  because the fix took a day to find and should take you two minutes.</em>
</p>

# WSL Browser Bridge

**The problem.** If you run Claude Code inside WSL from an IDE such as VS Code
or Cursor, Claude in Chrome doesn't work out of the box. Install Chrome inside
WSL and Claude may open that one, but it's a second, Linux browser: it looks
and behaves differently from the Chrome on your Windows machine, and it has none
of your browsing history, logins or extensions, so you set all of that up again
just so Claude can use a browser.

**The fix.** This plugin lets Claude use a browser from WSL, two ways:

| | Route 1: Claude in Chrome | Route 2: your Windows Chrome |
|---|---|---|
| What Claude drives | A Chrome installed **inside WSL** (it shows on your Windows desktop through WSLg) | The Chrome installed on **Windows**, in its own profile |
| How | The official Claude in Chrome extension and its tools | The Chrome DevTools Protocol, through a small `cdp` command |
| The problem it solves | The VS Code extension launches Claude with `--no-chrome`, and no setting turns it off | The extension can never see a Windows browser from WSL |
| Works from | VS Code (the installer edits VS Code's settings), or `claude --chrome` in a terminal | Any WSL session: VS Code, Cursor, another IDE, a terminal |
| One-time cost | One VS Code window reload, sign in to the extension | Possibly one WSL restart (mirrored networking) |

**Route 2 keeps you in Windows.** Claude opens pages in the Chrome installed on
Windows, on your Windows desktop, so you go from your Windows browsing to your
WSL coding without a second browser. Chrome doesn't let automation attach to
your everyday profile (since Chrome 136), so Claude gets its own profile in your
Windows Chrome. Sign in to the sites you want it to use once, add the extensions
you need, and they stay there for every later session.

Install either route or both.

## Install as a plugin

In Claude Code, inside WSL:

```
/plugin install wsl-browser-bridge --marketplace tirandagan/claude-chrome-wsl-fix
```

That needs Claude Code 2.1.275 or later. On older versions, run
`/plugin marketplace add tirandagan/claude-chrome-wsl-fix`, then
`/plugin install wsl-browser-bridge@tirandagan`.

Then start a new chat and say **"Set up browser control on my computer"**, or run
`/wsl-browser-bridge:claude-chrome-wsl-fix`. Claude takes it from there, the same
way as the one-line install below.

## Or install with one line to Claude

Open Claude Code inside WSL and send:

```
Follow https://github.com/tirandagan/claude-chrome-wsl-fix/blob/main/SETUP.md to set up browser control on my computer.
```

Claude checks your environment first (read-only), asks which route you want,
shows you every change before making it, installs, has you do the one reload or
restart that ends the chat, and verifies in the next one. **[SETUP.md](SETUP.md)**
is that script, readable by you too. It ends with a manual install if you'd
rather type the commands yourself.

Already cloned? From the repo:

```bash
scripts/preflight.sh            # read-only check of both routes
scripts/install.sh              # Route 1   (--dry-run to preview, --uninstall to undo)
scripts/install-windows-chrome.sh   # Route 2   (--dry-run, --set-mirrored, --uninstall)
scripts/install-skills.sh       # make the plugin visible to Claude Code (links it into ~/.claude/skills)
scripts/show-welcome.sh         # the "you're all set" page, in whichever Chrome is set up
```

The repo is the plugin. A clone in `~/.claude/skills/` loads as the
`wsl-browser-bridge` plugin with both skills, with no marketplace involved.

## What to ask Claude

After setup, in any Claude Code chat inside WSL:

- "Open https://staging.example.com in Chrome and tell me whether the sign-up form submits."
- "Go to our pricing page, take a screenshot, and check the plan names match the ones in `pricing.ts`."
- "Read the release notes at https://example.com/changelog and list anything that breaks our build."
- "Claude in Chrome isn't connecting in VS Code. Find out why."
- "Undo the browser setup."

The first three use whichever route you installed. The last two are handled by
the setup skill.

## Route 1: why reinstalling the extension never fixes it

The failure is not in the browser. The VS Code extension hardcodes
`--no-chrome` into the arguments it passes to the Claude CLI:

```js
extraArgs:{debug:null,"debug-to-stderr":null,"enable-auth-status":null,
           "no-chrome":null,"replay-user-messages":null}
```

No `claudeCode.*` setting reads it, so there is nothing to switch off. It has
persisted across extension updates. Because it is a *launch* flag, a session
that started with it cannot enable the integration afterwards. That's why
restarting the browser, reinstalling the extension and signing in again all
appear to change nothing.

VS Code exposes one supported interception point,
`claudeCode.claudeProcessWrapper`. When set, the extension launches your script
instead of the binary and hands the real binary over as the first argument:

```
<your wrapper> <real claude binary> <all the extension's args...>
```

![How the fix works](assets/how-it-works.svg)

The wrapper drops `--no-chrome`, appends `--chrome`, and forwards everything
else byte for byte. About ten lines of shell.

**The catch:** the flag is necessary but not sufficient. The Claude CLI is a
Linux process inside WSL, and it looks for the extension in *Linux* browser
profiles. A Chrome installed on Windows is invisible to it. So Route 1's browser
is a Chrome **installed inside WSL**, with the extension installed and signed in
there. If you launch Claude from a plain WSL terminal, you don't need the
wrapper at all: `claude --chrome`.

## Route 2: driving the Windows Chrome

When you want Claude in the browser you actually use on Windows, the extension
can't help. Its Windows native host launches a *Windows* `claude.exe`, which a
WSL session never sees. Route 2 uses the DevTools Protocol instead:

- `launch-windows-chrome.sh` starts Windows Chrome on a **dedicated profile**
  with a debug port (9333). Chrome 136+ refuses debug ports on your default
  profile by design, so your everyday profile is never touched.
- WSL reaches that port through **mirrored networking** (`networkingMode=Mirrored`
  in `%UserProfile%\.wslconfig`).
- `cdp` is a dependency-free client (Node 22+): `new`, `goto`, `text`, `click`,
  `type`, `key`, `wait`, `eval`, `shot`, `close`. Clicks go only to **visible**
  elements and count as real user input.

```bash
launch-windows-chrome.sh
T=$(cdp new https://example.com); cdp text --tab $T; cdp shot page.png --tab $T; cdp close $T
```

The `windows-chrome` skill teaches Claude this routine, including the rules: its
own tab only, never type credentials, leave port 9222 to whatever uses it.
Details: [references/windows-chrome-cdp.md](references/windows-chrome-cdp.md).

## What gets changed

| Route | Path | Purpose |
|---|---|---|
| 1 | `~/.claude/bin/claude-chrome-wrapper.sh` | the launch shim |
| 1 | `~/.vscode-server/data/Machine/settings.json` | one key, `claudeCode.claudeProcessWrapper` (backup `.bak`) |
| 2 | `~/.claude/bin/launch-windows-chrome.sh`, `cdp`, `cdp.mjs` | launcher and client |
| 2 | `~/.config/claude-chrome-wsl-fix/windows-chrome.env` | port, profile, chrome.exe path |
| 2 | `%UserProfile%\.wslconfig` | only with `--set-mirrored`, backed up first |
| both | `~/.claude/skills/claude-chrome-wsl-fix` | link to this repo, only for a clone kept outside `~/.claude/skills` (`install-skills.sh`) |
| both | `~/.config/claude-chrome-wsl-fix/state.env` | progress, so Claude can resume after a reload |

Nothing is written until you (or Claude, after showing you the dry run and
getting your yes) run an installer. Installing the plugin by itself only adds
the two skills.

Route 1's setting goes in **Remote [WSL] Machine settings**, deliberately not User
settings. Those sync across machines, and a Linux path landing on your Mac would
break Claude Code there. The installer refuses to rewrite a settings file with
`//` comments and gives you the one line to paste instead.

## What it runs and connects to

- **Runs:** the bash scripts in `scripts/`, and `cdp`, a dependency-free Node 22
  client. Nothing runs in the background and there are no hooks. Scripts run
  when you or Claude call them.
- **Reads:** the Windows folder paths `%USERPROFILE%` and `%LOCALAPPDATA%`, to find
  `.wslconfig`, `chrome.exe`, and where to keep the automation profile and the welcome
  page. No tokens,
  passwords, cookies or other credentials are read, from the environment or anywhere else.
- **Connects to:** the Windows Chrome's DevTools port on `127.0.0.1` (9333 by
  default), from WSL, for Route 2. That traffic stays on your machine.
- **Downloads:** the one-line install clones this repo from GitHub. If you choose
  Route 1 and have no Chrome in WSL, SETUP.md gives you a command to run
  yourself that downloads Chrome from `dl.google.com`.
- **Sends:** nothing. No telemetry, no analytics, no calls to the author or any
  third party. The welcome page is a local file and works offline.

## Risk, stated plainly

- **Route 1:** once registered, **every** VS Code Claude session launches through
  the wrapper, including agents already running. If the script is deleted or the
  extension changes its argument shape, sessions fail to start. `install.sh`
  self-tests the wrapper against a stub binary before registering it, and
  uninstall is one command. `CLAUDE_CHROME_WRAPPER=off` makes it pass arguments
  through untouched.
- **Route 2:** anything signed in to the automation profile can be driven by
  **any** local process while Chrome is running with the port open. Sign in there
  only to accounts you're willing to hand to automation, and
  `launch-windows-chrome.sh --stop` when you're done.

## Uninstall

```bash
scripts/install.sh --uninstall                 # Route 1, then reload the window
scripts/install-windows-chrome.sh --uninstall  # Route 2
scripts/install-skills.sh --uninstall          # the ~/.claude/skills link, if it made one
```

Installed as a plugin? Ask Claude to "undo the browser setup" **before** you
remove the plugin, because the uninstall scripts ship inside it. Then
`/plugin uninstall wsl-browser-bridge@tirandagan`. Removing the plugin alone
leaves the Route 1 setting and the Route 2 helpers in place.

`.wslconfig` and the Windows automation profile are left alone on purpose.

## Layout

```
claude-chrome-wsl-fix/              the plugin root
├── .claude-plugin/                plugin.json (plugin wsl-browser-bridge), marketplace.json, listing icon
├── SETUP.md                       guided install, written for Claude to follow
├── SKILL.md                       skill: claude-chrome-wsl-fix (setup, diagnosis, repair)
├── skills/windows-chrome/SKILL.md skill: windows-chrome (day-to-day Route 2 use)
├── scripts/
│   ├── preflight.sh               read-only check of both routes
│   ├── diagnose.sh                Route 1 in depth, 8 checks
│   ├── install.sh                 Route 1 install / --dry-run / --uninstall
│   ├── claude-chrome-wrapper.sh   the Route 1 shim
│   ├── install-windows-chrome.sh  Route 2 install / --dry-run / --set-mirrored / --uninstall
│   ├── windows-chrome/            launch-windows-chrome.sh, cdp, cdp.mjs (installed to ~/.claude/bin)
│   ├── install-skills.sh          link a clone into ~/.claude/skills so the plugin loads
│   ├── show-welcome.sh            open the welcome page when setup is done
│   └── lib.sh                     shared helpers
├── references/
│   ├── root-cause.md              forensics + how to re-verify after updates
│   ├── windows-chrome-cdp.md      Route 2 internals and security
│   └── troubleshooting.md         symptom → fix, both routes
├── assets/                        README graphics, and the welcome page with its short film
├── tests/run.sh                   offline test suite (CI runs it)
└── CHANGELOG.md
```

## Verified against

Claude Code VS Code extension **2.1.278**, **2.1.280** and **2.1.314**; Chrome 155
on Windows and 156 in WSL; WSL2 (Debian) on Windows with mirrored networking.
Plugin loading checked with Claude Code **2.1.316**.
`references/root-cause.md` has the commands to re-confirm on a newer build.
Worth running if the fix ever stops working.

---

![Built by Tiran Dagan, co-founder of BePrepared Solutions](assets/built-by.svg)

## Who made this

This plugin is a by-product. I hit the bug myself, spent a day inside a minified
extension bundle working out that the browser was never the problem, and decided
nobody else should have to.

I'm **[Tiran Dagan](https://bepreparedsolutions.co)**, co-founder of
**[BePrepared Solutions](https://bepreparedsolutions.co)**, where we build
household preparedness tools: live alerts for your address, an AI-generated
plan, matched supplies, and time with experts. If this saved you an afternoon,
send it to the next person who says "Claude in Chrome isn't working and I've
reinstalled it twice."

---

<sub>Licensed for free use and redistribution. Not affiliated with or endorsed by
Anthropic. "Claude" and "Claude Code" are trademarks of Anthropic.</sub>
