#!/usr/bin/env bash
# Route 1 diagnosis: why "Claude in Chrome" is not connecting under VS Code +
# WSL. Read-only. Run it before install.sh, and again after reloading the
# window, to confirm the fix took. (For an overview of both routes, run
# preflight.sh instead.)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"

echo "Claude in Chrome / WSL diagnosis"
echo "================================"

echo; echo "1. Environment"
if is_wsl; then
  ok "running inside WSL ($(grep -oiE 'wsl2?' /proc/version | head -1 | tr 'a-z' 'A-Z'))"
else
  no "not WSL — this skill targets VS Code + WSL on Windows; the fix may not apply"
fi

echo; echo "2. VS Code extension"
EXT=$(ls -d "$HOME"/.vscode-server/extensions/anthropic.claude-code-*-linux-* \
            "$HOME"/.vscode-server-insiders/extensions/anthropic.claude-code-*-linux-* 2>/dev/null | sort -V | tail -1)
if [ -n "$EXT" ]; then
  ok "installed: $(basename "$EXT")"
  if grep -q '"no-chrome":null' "$EXT/extension.js" 2>/dev/null; then
    no "extension hardcodes --no-chrome (this is the root cause; expected)"
  else
    inf "no hardcoded --no-chrome found — the extension may have changed; see references/root-cause.md"
  fi
  grep -q 'claudeProcessWrapper' "$EXT/extension.js" 2>/dev/null \
    || no "extension no longer mentions claudeProcessWrapper — the wrapper cannot attach"
else
  no "Claude Code VS Code extension not found under ~/.vscode-server/extensions"
fi

echo; echo "3. Live Claude sessions"
FOUND=0
while read -r pid args; do
  [ -z "${pid:-}" ] && continue
  FOUND=1
  if printf ' %s ' "$args" | grep -q ' --chrome '; then ok "pid $pid launched WITH --chrome"
  elif printf ' %s ' "$args" | grep -q ' --no-chrome '; then no "pid $pid launched with --no-chrome (started before the reload, or the setting did not land)"
  else inf "pid $pid: no chrome flag"; fi
done < <(pgrep -af 'native-binary/claude' 2>/dev/null | grep -v -- '--chrome-native-host')
[ "$FOUND" = 0 ] && inf "no running Claude Code sessions detected"

echo; echo "4. Wrapper"
W="$BIN_DIR/claude-chrome-wrapper.sh"
if [ -x "$W" ]; then ok "installed and executable: $W"
elif [ -f "$W" ]; then no "present but NOT executable: $W  (chmod +x it)"
else no "not installed — run scripts/install.sh"; fi

echo; echo "5. VS Code setting"
MS="${VSCODE_MACHINE_SETTINGS:-$HOME/.vscode-server/data/Machine/settings.json}"
if [ -f "$MS" ] && grep -q 'claudeProcessWrapper' "$MS" 2>/dev/null; then
  ok "claudeCode.claudeProcessWrapper set in Remote[WSL] settings"
  inf "$(grep -o '"claudeCode.claudeProcessWrapper"[^,}]*' "$MS" | head -1)"
else
  no "claudeCode.claudeProcessWrapper not set in $MS"
fi

echo; echo "6. Chrome extension on the Linux side"
# The CLI looks for the browser extension in LINUX profile paths, because the
# CLI process itself runs inside WSL. A Chrome installed on Windows is not
# visible to it, whatever its profile contains.
ID=fcoeoabgfenejglbffodgkkbkcdhcgfn
HIT=0
for base in "$HOME/.config/google-chrome" "$HOME/.config/chromium" \
            "$HOME/.config/BraveSoftware/Brave-Browser" "$HOME/.config/microsoft-edge"; do
  [ -d "$base" ] || continue
  if find "$base" -maxdepth 4 -type d -name "$ID" 2>/dev/null | grep -q .; then
    ok "extension present in $(basename "$base")"; HIT=1
  fi
done
[ "$HIT" = 0 ] && no "Claude extension not found in any WSL-side browser profile — install it from https://claude.ai/chrome in a Linux browser"

echo; echo "7. A Linux browser to pair with"
B=0
for b in /opt/google/chrome/chrome /usr/bin/google-chrome /usr/bin/chromium /usr/bin/chromium-browser /usr/bin/microsoft-edge; do
  [ -x "$b" ] && { ok "found $b"; B=1; }
done
[ "$B" = 0 ] && no "no Linux-side browser found — install Chrome inside WSL (it renders on the Windows desktop via WSLg)"

echo; echo "8. Native messaging host (written by the CLI the first time it runs with --chrome)"
NH=0
for base in "$HOME/.config/google-chrome" "$HOME/.config/chromium" \
            "$HOME/.config/BraveSoftware/Brave-Browser" "$HOME/.config/microsoft-edge"; do
  m="$base/NativeMessagingHosts/com.anthropic.claude_code_browser_extension.json"
  [ -f "$m" ] || continue
  NH=1
  p="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["path"])' "$m" 2>/dev/null || true)"
  if [ -n "$p" ] && [ -x "$p" ]; then ok "$(basename "$base"): host manifest → $p"
  else no "$(basename "$base"): host manifest points at a missing program (${p:-unreadable}); start a session with --chrome to rewrite it"; fi
done
[ "$NH" = 0 ] && inf "no host manifest yet — normal until a session has started with --chrome"

echo
echo "Next: if 4 or 5 failed, run scripts/install.sh, then reload the VS Code window."
echo "If 6, 7 or 8 failed, the browser side needs work — see SETUP.md, 'Route 1 browser'."
echo "Want Claude to drive your Windows Chrome instead? That is route 2: scripts/install-windows-chrome.sh"
