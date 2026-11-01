#!/usr/bin/env bash
# Route 1: install the Claude-in-Chrome launch wrapper and register it with VS Code.
# Idempotent: safe to re-run.
#
#   install.sh              install
#   install.sh --dry-run    print exactly what would change, change nothing
#   install.sh --uninstall  remove the setting (wrapper file stays, inert)
#
# Exit codes: 0 done, 1 failed, 2 wrapper installed but the setting must be added
# by hand (settings.json has // comments the installer will not rewrite).
#
# Writes exactly two things:
#   1. ~/.claude/bin/claude-chrome-wrapper.sh
#   2. "claudeCode.claudeProcessWrapper" in the Remote[WSL] Machine settings
# Nothing else on the system is touched.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"
DEST="$BIN_DIR/claude-chrome-wrapper.sh"
MS="${VSCODE_MACHINE_SETTINGS:-$HOME/.vscode-server/data/Machine/settings.json}"
SETTING="claudeCode.claudeProcessWrapper"

MODE=install
case "${1:-}" in
  --uninstall) MODE=uninstall;; --dry-run) MODE=dry;; "") ;;
  -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
  *) echo "unknown option: $1" >&2; exit 64;;
esac
[ "$MODE" = uninstall ] || copyright_banner

command -v python3 >/dev/null 2>&1 || { no "python3 is required to edit $MS safely"; \
  echo "    add this line to Remote [WSL] settings by hand instead:  \"$SETTING\": \"$DEST\""; exit 1; }

merge_setting() { # $1 = value, or empty to remove the key. Prints OK | UNPARSEABLE | UNCHANGED
python3 - "$MS" "$SETTING" "${1:-}" <<'PY'
import json, os, sys, shutil, tempfile
path, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
raw = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
try:
    data = json.loads(raw) if raw.strip() else {}
except json.JSONDecodeError:
    # VS Code settings may legally contain // comments (JSONC). Rather than
    # risk mangling a file we cannot parse, stop and let the user edit it.
    print("UNPARSEABLE"); sys.exit(0)
before = dict(data)
if value: data[key] = value
else: data.pop(key, None)
if data == before:
    print("UNCHANGED"); sys.exit(0)
os.makedirs(os.path.dirname(path), exist_ok=True)
if os.path.exists(path): shutil.copy(path, path + ".bak")
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
with os.fdopen(fd, "w", encoding="utf-8") as f: f.write(json.dumps(data, indent=2) + "\n")
os.replace(tmp, path)
print("OK")
PY
}

if [ "$MODE" = uninstall ]; then
  echo "Removing $SETTING ..."
  case "$(merge_setting "")" in
    OK) ok "setting removed (backup at $MS.bak)";;
    UNCHANGED) inf "setting was not present";;
    UNPARSEABLE) warn "$MS has comments; remove the \"$SETTING\" line by hand";;
    *) no "could not edit $MS"; exit 1;;
  esac
  inf "leaving $DEST in place (harmless; delete it if you like)"
  state_set ROUTE1 removed; state_set PENDING reload
  echo "Reload the VS Code window to return to stock behaviour."
  exit 0
fi

if [ "$MODE" = dry ]; then
  echo "Dry run — nothing will change. install.sh would:"
  inf "write $DEST (from scripts/claude-chrome-wrapper.sh, mode 0755)$( [ -e "$DEST" ] && echo ', replacing the existing file')"
  inf "self-test it against a stub binary, and stop if --no-chrome survives"
  if [ -f "$MS" ] && grep -q "\"$SETTING\"" "$MS"; then
    inf "update \"$SETTING\" in $MS (currently: $(grep -o "\"$SETTING\"[^,}]*" "$MS" | head -1 | cut -d: -f2- | tr -d ' '))"
  else
    inf "add \"$SETTING\": \"$DEST\" to $MS (backup at $MS.bak)"
  fi
  inf "ask you to reload the VS Code window (running sessions keep their old arguments)"
  exit 0
fi

echo "Installing the Claude-in-Chrome launch wrapper (route 1)"
echo "========================================================"

# 1. the wrapper
mkdir -p "$BIN_DIR"
if [ -f "$HERE/claude-chrome-wrapper.sh" ]; then
  install -m 0755 "$HERE/claude-chrome-wrapper.sh" "$DEST"
  ok "wrapper installed at $DEST"
else
  no "cannot find claude-chrome-wrapper.sh next to this script" >&2; exit 1
fi

# 2. prove it works before wiring it in — a broken wrapper means sessions that
#    will not start, and that is a bad thing to discover after a reload.
STUB=$(mktemp); printf '#!/usr/bin/env bash\nfor a in "$@"; do printf "[%%s]" "$a"; done\n' > "$STUB"; chmod +x "$STUB"
OUT=$("$DEST" "$STUB" --debug --no-chrome --add-dir "/a b" 2>&1)
rm -f "$STUB"
case "$OUT" in
  *"[--no-chrome]"*) no "self-test FAILED: --no-chrome survived. Not registering." >&2; exit 1;;
  "[--debug][--add-dir][/a b][--chrome]") ok "self-test passed: $OUT";;
  *) no "self-test FAILED: unexpected arguments ($OUT). Not registering." >&2; exit 1;;
esac

# 3. the setting — Machine scope, never User scope. User settings sync across
#    machines, and a Linux path would break Claude Code on a Mac or Windows host.
case "$(merge_setting "$DEST")" in
  OK) ok "$SETTING set in $MS (backup at $MS.bak)";;
  UNCHANGED) ok "$SETTING already set in $MS";;
  UNPARSEABLE)
    warn "$MS could not be parsed (it probably contains // comments)."
    echo "    Add this line by hand instead (Ctrl+Shift+P → Preferences: Open Remote Settings (JSON)):"
    echo "      \"$SETTING\": \"$DEST\""
    echo "    Then reload the VS Code window."
    state_set ROUTE1 needs-manual-setting
    exit 2
    ;;
  *) no "could not edit $MS"; exit 1;;
esac
state_set ROUTE1 installed; state_set PENDING reload

cat <<EOF

Done. One manual step remains:

  Reload the VS Code window  —  Ctrl+Shift+P → "Developer: Reload Window"

Sessions already running keep their old arguments; only new ones pick this up.
Reloading ends this Claude chat. In the new chat, say:
  "Verify the claude-chrome-wsl-fix setup."
EOF
