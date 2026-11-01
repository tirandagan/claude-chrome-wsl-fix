# Changelog

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
