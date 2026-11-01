# Changelog

## 2.2.1 (2026-11-01)

**Fixed**
- The plugin directory's portal refused to validate the repo ("Couldn't validate that
  repository"): it rejects `.gitattributes` rules that rewrite file contents, and ours
  set `text eol=lf`. The file is gone. Every script is committed with LF, and WSL's Git
  doesn't convert line endings, so clones inside WSL are unchanged.
- `tests/run.sh` now guards that instead: it fails if a committed text file has CRLF
  endings or a `.gitattributes` rule the directory rejects comes back.

## 2.2.0 (2026-11-01)

The repo is now a Claude Code plugin, **wsl-browser-bridge**, ready for Anthropic's
plugin directory. (Plugin names may not start with `claude-`, so the plugin can't
share the repo's name. The repo, URLs, skill names and config folders are unchanged.)

**Added**
- `.claude-plugin/plugin.json`: name, display name "WSL Browser Bridge", directory
  listing fields, and `"skills": ["./"]` so the root skill loads alongside
  `skills/windows-chrome`.
- `.claude-plugin/marketplace.json` (marketplace `tirandagan`), so it installs today with
  `/plugin install wsl-browser-bridge --marketplace tirandagan/claude-chrome-wsl-fix`.
- A 1024×1024 listing icon in `.claude-plugin/`, with its SVG source in `assets/`.
- README: the problem statement (Claude in Chrome doesn't work under WSL from VS Code,
  Cursor and other IDEs; a WSL-side Chrome is a second browser without your history,
  logins or extensions), plugin install, example prompts, and a "What it runs and
  connects to" disclosure.
- Tests for the plugin manifest and for each `install-skills.sh` install shape.

**Changed**
- `install-skills.sh`: links one folder, the plugin, instead of two skills. It links
  nothing when the repo is already in `~/.claude/skills` or was installed from a
  marketplace, and removes the pre-2.2 `~/.claude/skills/windows-chrome` link, which
  would otherwise load that skill twice.
- SETUP.md and SKILL.md handle running from an installed plugin, and say to run the
  uninstall scripts before removing the plugin.
- README: the BePrepared section is shortened to a credit; the built-by graphic stays.
  Banner relabelled.

## 2.1.0 (2026-11-01)

**Added**
- Copyright notice at the start of `preflight.sh`, `install.sh` and
  `install-windows-chrome.sh` ("This is the Claude Chrome for WSL skill, written by
  Tiran Dagan, copyright 2026, tiran@tirandagan.com."). SETUP.md has Claude show it
  to the user. `CCWF_NO_BANNER=1` turns it off.
- Welcome page (`assets/welcome.html`, self-contained, works offline) and
  `scripts/show-welcome.sh` (`--route 1|2`, `--print-url`), which opens it in a new
  tab of whichever Chrome setup configured. SETUP.md opens it as its last step;
  `install-windows-chrome.sh` opens it after verifying (`--no-welcome` to skip).
- The page opens with an 8.5-second animated film made with HyperFrames
  (a 159 KB WebM, which Chrome always plays, plus a JPEG still for reduced-motion
  users), with a "Play again" button. The film's
  source project is kept outside this repo so installs stay small.

**Fixed**
- `preflight.sh` hung forever when the automation Chrome was not running: under
  mirrored networking a closed Windows port drops the connection instead of
  refusing it. The port probe now times out after 2 seconds.

## 2.0.0 (2026-10-31)

Two routes instead of one, and an install you hand to Claude.

**Added**
- **Route 2: drive the Windows Chrome over CDP.** `scripts/install-windows-chrome.sh`
  (`--dry-run`, `--set-mirrored`, `--no-verify`, `--uninstall`) installs
  `launch-windows-chrome.sh` (start, `--status`, `--stop`), the `cdp` client and its
  Node-finding shim into `~/.claude/bin`, and writes `~/.config/claude-chrome-wsl-fix/windows-chrome.env`.
- `cdp` commands: `version`, `list`, `new`, `close`, `goto` (waits for load), `text`,
  `eval`, `wait`, `click` (trusted input, visible elements only), `type`, `key`, `shot`.
  Tabs by id, id prefix or index.
- **`windows-chrome` skill** (`skills/windows-chrome/SKILL.md`): day-to-day use of Route 2,
  with the own-tab / no-credentials / leave-9222-alone rules.
- `scripts/preflight.sh`: read-only check of both routes with machine-readable
  `RESULT` / `BLOCKER` / `TODO` lines.
- `scripts/install-skills.sh`: links both skills into `~/.claude/skills`; `--replace`
  backs conflicting folders up to `~/.claude/skill-backups/` (outside the skills folder,
  so backups never load as duplicate skills).
- `scripts/wslconfig-mirror.py`: merges `networkingMode=Mirrored` into `.wslconfig`.
- Resume state in `~/.config/claude-chrome-wsl-fix/state.env`, so a new chat after the
  reload or WSL restart can pick up where the old one ended.
- `references/troubleshooting.md`, `tests/run.sh` (offline suite), GitHub Actions CI.

**Changed**
- `SETUP.md` rewritten as a prompt for Claude: get the repo, verify, choose a route,
  show the dry run, install, hand off the restart, verify, report and explain undo.
- `SKILL.md` covers both routes, resume and undo; its description triggers on CDP,
  port 9333 and "the browser opened in WSL".
- `install.sh`: `--dry-run`; atomic settings write; `.bak` only when something changes;
  stricter self-test (checks exact argument boundaries); exit 2 when a commented
  `settings.json` needs the line pasted by hand; clear message when python3 is missing.
- `claude-chrome-wrapper.sh`: `CLAUDE_CHROME_WRAPPER=off` pass-through; safe on bash < 4.4
  with no arguments.
- `diagnose.sh`: exact flag matching, VS Code Insiders, a check that the extension still
  reads `claudeProcessWrapper`, and an 8th check for the native messaging host manifest.
- `references/cdp-fallback.md` → `references/windows-chrome-cdp.md`, rewritten for the
  installed tooling.
- Re-verified the root cause on extension 2.1.314.

## 1.0.0

- Launch wrapper, `install.sh`, `diagnose.sh`, skill and forensics for re-enabling
  Claude in Chrome under VS Code + WSL.
