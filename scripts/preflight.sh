#!/usr/bin/env bash
# Read-only environment check for both routes. Changes nothing.
#
#   Route 1 — Claude in Chrome with a Chrome installed INSIDE WSL (the extension route)
#   Route 2 — Claude drives your WINDOWS Chrome over the DevTools Protocol (CDP)
#
# Ends with machine-readable lines SETUP.md relies on:
#   RESULT route1=ready|needs-setup|blocked route2=ready|needs-setup|blocked
#   BLOCKER <route> <text>    (one per hard blocker)
#   TODO <route> <text>       (one per step the installer or user still has to do)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"

PORT="${CDP_PORT:-9333}"
[ -f "$STATE_DIR/windows-chrome.env" ] && . "$STATE_DIR/windows-chrome.env" && PORT="${CDP_PORT:-$PORT}"
B1=(); T1=(); B2=(); T2=()

echo "claude-chrome-wsl-fix preflight (read-only)"
echo "==========================================="

echo; echo "1. Platform"
if is_wsl; then
  ok "WSL detected (${WSL_DISTRO_NAME:-unknown distro}, $(grep -oiE 'wsl2?' /proc/version | head -1 | tr 'a-z' 'A-Z'))"
else
  no "not running inside WSL — this project targets Windows + WSL"
  B1+=("not WSL"); B2+=("not WSL")
fi
if grep -qiE 'wsl2' /proc/version 2>/dev/null || [ -d /run/WSL ]; then :; else
  warn "could not confirm WSL2; WSL1 is untested"
fi

echo; echo "2. Basic tools"
for t in bash curl python3; do
  if command -v "$t" >/dev/null 2>&1; then ok "$t: $(command -v "$t")"
  else
    no "$t missing"
    [ "$t" = python3 ] && B1+=("python3 missing (installer edits VS Code settings JSON with it)")
    [ "$t" = curl ] && B2+=("curl missing (used to reach the CDP port)")
  fi
done
if N22="$(find_node22)"; then ok "Node >= 22: $N22"
else no "no Node >= 22 found (route 2's cdp client needs the built-in WebSocket)"; B2+=("Node >= 22 missing (nvm install 22)"); fi

echo; echo "3. How Claude Code is launched"
EXT=$(ls -d "$HOME"/.vscode-server/extensions/anthropic.claude-code-*-linux-* \
            "$HOME"/.vscode-server-insiders/extensions/anthropic.claude-code-*-linux-* 2>/dev/null | sort -V | tail -1)
if [ -n "$EXT" ]; then
  ok "VS Code extension: $(basename "$EXT")"
  if grep -q '"no-chrome":null' "$EXT/extension.js" 2>/dev/null; then
    inf "the extension hardcodes --no-chrome — route 1 needs the launch wrapper"
    if ! grep -q 'claudeProcessWrapper' "$EXT/extension.js" 2>/dev/null; then
      no "this build no longer reads claudeProcessWrapper — route 1's wrapper cannot attach"
      B1+=("extension dropped claudeProcessWrapper; see references/root-cause.md")
    fi
  else
    inf "no hardcoded --no-chrome in this build; route 1 may work without the wrapper"
  fi
else
  inf "no Claude Code VS Code extension under ~/.vscode-server — if you use the terminal CLI, route 1 is just: claude --chrome"
fi
CLAUDE_BIN="$(command -v claude 2>/dev/null || true)"
[ -n "$CLAUDE_BIN" ] && ok "claude CLI on PATH: $CLAUDE_BIN" || inf "claude CLI not on PATH (fine if you only use VS Code)"

echo; echo "4. Route 1 — Claude in Chrome with a WSL-side Chrome"
W="$BIN_DIR/claude-chrome-wrapper.sh"
MS="$HOME/.vscode-server/data/Machine/settings.json"
if [ -n "$EXT" ]; then
  if [ -x "$W" ] && grep -q 'claudeProcessWrapper' "$MS" 2>/dev/null; then ok "launch wrapper installed and registered"
  else inf "launch wrapper not installed yet"; T1+=("run scripts/install.sh, then reload the VS Code window"); fi
fi
if [ -d /mnt/wslg ] || [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then ok "WSLg display available (Linux windows show on the Windows desktop)"
else no "no WSLg display — a WSL-side Chrome would have nowhere to draw"; B1+=("WSLg unavailable (update WSL: wsl --update)"); fi
LB=""
for b in /opt/google/chrome/chrome /usr/bin/google-chrome /usr/bin/chromium /usr/bin/chromium-browser /usr/bin/microsoft-edge; do
  [ -x "$b" ] && { LB="$b"; break; }
done
if [ -n "$LB" ]; then ok "Linux browser: $LB"
else inf "no Linux browser installed"; T1+=("install Chrome inside WSL (see SETUP.md, needs sudo)"); fi
ID=fcoeoabgfenejglbffodgkkbkcdhcgfn
EXTHIT=0
for base in "$HOME/.config/google-chrome" "$HOME/.config/chromium" \
            "$HOME/.config/BraveSoftware/Brave-Browser" "$HOME/.config/microsoft-edge"; do
  [ -d "$base" ] && find "$base" -maxdepth 4 -type d -name "$ID" 2>/dev/null | grep -q . && EXTHIT=1
done
if [ "$EXTHIT" = 1 ]; then ok "Claude extension installed in a WSL-side browser profile"
else inf "Claude extension not in any WSL-side profile"; T1+=("in the WSL Chrome, install https://claude.ai/chrome and sign in"); fi

echo; echo "5. Route 2 — Claude drives your Windows Chrome"
if interop_ok; then
  ok "Windows interop works (cmd.exe runs)"
  WINPROFILE="$(win_env USERPROFILE)"
  [ -n "$WINPROFILE" ] && inf "Windows user profile: $WINPROFILE"
  if WC="$(win_chrome_path)"; then
    WV="$(win_ps "(Get-Item '$WC').VersionInfo.ProductVersion")"
    ok "Windows Chrome: $WC ${WV:+($WV)}"
  else
    no "Chrome not found on Windows"; B2+=("install Google Chrome on Windows")
  fi
  MODE="$(wsl_net_mode)"
  WSLCONFIG="$(wslpath -u "$WINPROFILE\\.wslconfig" 2>/dev/null || true)"
  CONF_MIRRORED=0
  [ -n "$WSLCONFIG" ] && grep -qiE '^\s*networkingMode\s*=\s*mirrored' "$WSLCONFIG" 2>/dev/null && CONF_MIRRORED=1
  case "$MODE" in
    mirrored) ok "WSL networking is mirrored (WSL's 127.0.0.1 reaches Windows)";;
    *)
      if [ "$CONF_MIRRORED" = 1 ]; then
        warn "networkingMode=Mirrored is in .wslconfig but WSL reports '$MODE' — WSL has not restarted since"
        T2+=("from Windows PowerShell run: wsl --shutdown, then reopen VS Code")
      else
        inf "WSL networking is '$MODE'; route 2 needs networkingMode=Mirrored in $WINPROFILE\\.wslconfig"
        T2+=("set networkingMode=Mirrored (scripts/install-windows-chrome.sh --set-mirrored), then wsl --shutdown from Windows")
      fi;;
  esac
  [ "$MODE" = unknown ] && [ "$CONF_MIRRORED" = 1 ] && inf "this WSL has no wslinfo; trusting .wslconfig"
else
  no "Windows interop is off (cannot run cmd.exe from WSL)"; B2+=("enable WSL interop ([interop] enabled=true in /etc/wsl.conf)")
fi
if [ -x "$BIN_DIR/launch-windows-chrome.sh" ] && [ -x "$BIN_DIR/cdp" ]; then ok "route 2 helpers installed in $BIN_DIR"
else inf "route 2 helpers not installed yet"; T2+=("run scripts/install-windows-chrome.sh"); fi
V="$(curl -s -m 2 "http://127.0.0.1:$PORT/json/version" 2>/dev/null || true)"
if [ -z "$V" ]; then
  # Under mirrored networking a closed Windows port silently drops the connection
  # instead of refusing it, so the probe needs a timeout or it hangs forever.
  if timeout 2 bash -c 'exec 3<>"/dev/tcp/127.0.0.1/$1"' _ "$PORT" 2>/dev/null; then
    no "port $PORT is taken by something that is not Chrome DevTools"; B2+=("port $PORT busy; pick another with CDP_PORT=<port>")
  else
    inf "port $PORT is free (the automation Chrome is not running, which is fine)"
  fi
elif printf '%s' "$V" | grep -q 'Windows NT'; then ok "port $PORT: Windows Chrome is already answering"
else no "port $PORT answers but it is not a Windows Chrome (a Linux/headless browser holds it)"; B2+=("port $PORT held by a non-Windows browser; use CDP_PORT=<other>"); fi
if curl -s -m 1 http://127.0.0.1:9222/json/version >/dev/null 2>&1; then
  inf "port 9222 is in use by another tool — leave it alone; route 2 uses $PORT"
fi

verdict() { # $1 blockers count, $2 todos count
  if [ "$1" -gt 0 ]; then echo blocked; elif [ "$2" -gt 0 ]; then echo needs-setup; else echo ready; fi
}
R1=$(verdict ${#B1[@]} ${#T1[@]}); R2=$(verdict ${#B2[@]} ${#T2[@]})

echo; echo "Summary"
echo "  Route 1 (Claude in Chrome, WSL-side Chrome): $R1"
echo "  Route 2 (Windows Chrome over CDP):           $R2"
echo
echo "RESULT route1=$R1 route2=$R2"
for x in ${B1[@]+"${B1[@]}"}; do echo "BLOCKER route1 $x"; done
for x in ${T1[@]+"${T1[@]}"}; do echo "TODO route1 $x"; done
for x in ${B2[@]+"${B2[@]}"}; do echo "BLOCKER route2 $x"; done
for x in ${T2[@]+"${T2[@]}"}; do echo "TODO route2 $x"; done
exit 0
