#!/usr/bin/env bash
# Install the Claude-in-Chrome launch wrapper and register it with VS Code.
# Idempotent: safe to re-run. Use --uninstall to reverse it.
#
# Writes exactly two things:
#   1. ~/.claude/bin/claude-chrome-wrapper.sh
#   2. "claudeCode.claudeProcessWrapper" in the Remote[WSL] Machine settings
# Nothing else on the system is touched.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.claude/bin/claude-chrome-wrapper.sh"
MS="$HOME/.vscode-server/data/Machine/settings.json"
KEY="claudeCode.claudeProcessWrapper"

merge_setting() { # $1 = value, or empty string to remove the key
python3 - "$MS" "$KEY" "${1:-}" <<'PY'
import json, os, re, sys, shutil
path, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(os.path.dirname(path), exist_ok=True)
raw = ""
if os.path.exists(path):
    raw = open(path, encoding="utf-8").read()
    shutil.copy(path, path + ".bak")
try:
    data = json.loads(raw) if raw.strip() else {}
except json.JSONDecodeError:
    # VS Code settings may legally contain // comments (JSONC). Rather than
    # risk mangling a file we cannot parse, stop and let the user edit it.
    print("UNPARSEABLE"); sys.exit(3)
if value:
    data[key] = value
else:
    data.pop(key, None)
open(path, "w", encoding="utf-8").write(json.dumps(data, indent=2) + "\n")
print("OK")
PY
}

if [ "${1:-}" = "--uninstall" ]; then
  echo "Removing $KEY ..."
  case "$(merge_setting "")" in
    OK) echo "  ✓ setting removed (backup at $MS.bak)";;
    UNPARSEABLE) echo "  ! $MS has comments; remove the \"$KEY\" line by hand";;
  esac
  echo "  · leaving $DEST in place (harmless; delete it if you like)"
  echo "Reload the VS Code window to return to stock behaviour."
  exit 0
fi

echo "Installing the Claude-in-Chrome wrapper"
echo "======================================"

# 1. the wrapper
mkdir -p "$(dirname "$DEST")"
if [ -f "$HERE/claude-chrome-wrapper.sh" ]; then
  install -m 0755 "$HERE/claude-chrome-wrapper.sh" "$DEST"
  echo "  ✓ wrapper installed at $DEST"
else
  echo "  ✗ cannot find claude-chrome-wrapper.sh next to this script" >&2; exit 1
fi

# 2. prove it works before wiring it in — a broken wrapper means sessions that
#    will not start, and that is a bad thing to discover after a reload.
STUB=$(mktemp); printf '#!/usr/bin/env bash\necho "$*"\n' > "$STUB"; chmod +x "$STUB"
OUT=$("$DEST" "$STUB" --debug --no-chrome --add-dir "/a b" 2>&1)
rm -f "$STUB"
case "$OUT" in
  *--no-chrome*) echo "  ✗ self-test FAILED: --no-chrome survived. Not registering." >&2; exit 1;;
  *--chrome*)    echo "  ✓ self-test passed: $OUT";;
  *)             echo "  ✗ self-test FAILED: no --chrome added ($OUT). Not registering." >&2; exit 1;;
esac

# 3. the setting — Machine scope, never User scope. User settings sync across
#    machines, and a Linux path would break Claude Code on a Mac or Windows host.
case "$(merge_setting "$DEST")" in
  OK) echo "  ✓ $KEY set in $MS";;
  UNPARSEABLE)
    echo "  ! $MS could not be parsed (it probably contains // comments)."
    echo "    Add this line by hand instead:"
    echo "      \"$KEY\": \"$DEST\""
    ;;
esac

cat <<EOF

Done. One manual step remains:

  Reload the VS Code window  —  Ctrl+Shift+P → "Developer: Reload Window"

Sessions already running keep their old arguments; only new ones pick this up.
Then re-run scripts/diagnose.sh — section 3 should show a session with --chrome.
EOF
