#!/usr/bin/env bash
# Open the "Welcome to Claude Chrome under WSL" page in the Chrome that setup configured.
#
#   show-welcome.sh                 pick automatically: Windows Chrome (route 2) if its
#                                   DevTools port answers, else the Chrome inside WSL (route 1)
#   show-welcome.sh --route 1|2     force a route
#   show-welcome.sh --print-url     print the address it would open, open nothing
#
# Route 2 copies the page and its film to %LOCALAPPDATA%\claude-chrome-wsl-fix\ (Windows Chrome
# can't read files inside WSL by a plain path) and opens it in a NEW tab, leaving
# the user's tabs alone. Route 1 opens it in the Linux Chrome.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"
PAGE="$(cd "$HERE/.." && pwd)/assets/welcome.html"

ROUTE=auto; PRINT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --route) ROUTE="${2:-}"; shift;;
    --print-url) PRINT=1;;
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown option: $1" >&2; exit 64;;
  esac
  shift
done
[ -f "$PAGE" ] || { no "welcome page missing: $PAGE"; exit 1; }

PORT="${CDP_PORT:-9333}"
if [ -z "${CDP_PORT:-}" ] && [ -f "$STATE_DIR/windows-chrome.env" ]; then
  # shellcheck disable=SC1091
  PORT="$(. "$STATE_DIR/windows-chrome.env"; echo "${CDP_PORT:-9333}")"
fi
windows_chrome_up() { curl -s -m 2 "http://127.0.0.1:$PORT/json/version" 2>/dev/null | grep -q 'Windows NT'; }
linux_chrome() {
  local b
  for b in google-chrome google-chrome-stable chromium chromium-browser; do
    command -v "$b" >/dev/null 2>&1 && { command -v "$b"; return 0; }
  done
  return 1
}

if [ "$ROUTE" = auto ]; then
  if windows_chrome_up; then ROUTE=2
  elif linux_chrome >/dev/null; then ROUTE=1
  else no "no Chrome to show the page in (route 2 not running, no Chrome inside WSL)"; inf "open it yourself: $PAGE"; exit 1
  fi
fi

case "$ROUTE" in
  2)
    LAD="$(win_env LOCALAPPDATA)"
    [ -n "$LAD" ] || { no "cannot read %LOCALAPPDATA% from Windows"; exit 1; }
    WDIR="$LAD\\claude-chrome-wsl-fix"
    URL="file:///$(printf '%s' "$WDIR\\welcome.html" | tr '\\' '/' | sed 's/ /%20/g')?route=2"
    if [ "$PRINT" = 1 ]; then echo "$URL"; exit 0; fi
    windows_chrome_up || { no "Windows Chrome is not answering on port $PORT — run launch-windows-chrome.sh first"; exit 1; }
    UDIR="$(wslpath -u "$WDIR")"
    ADIR="$(dirname "$PAGE")"
    mkdir -p "$UDIR" && cp "$PAGE" "$ADIR"/welcome.webm "$ADIR"/welcome-poster.jpg "$UDIR/" \
      || { no "could not copy the page and its film to $WDIR"; exit 1; }
    ENC="$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$URL")"
    if curl -s -m 5 -X PUT "http://127.0.0.1:$PORT/json/new?$ENC" | grep -q '"id"'; then
      ok "welcome page opened in your Windows Chrome"
    else
      no "Chrome refused to open the page"; exit 1
    fi
    ;;
  1)
    URL="file://$PAGE?route=1"
    URL="${URL// /%20}"
    if [ "$PRINT" = 1 ]; then echo "$URL"; exit 0; fi
    B="$(linux_chrome)" || { no "no Chrome installed inside WSL"; exit 1; }
    # setsid -f detaches fully, so the window survives the end of this command.
    setsid -f "$B" --no-first-run "$URL" </dev/null >/dev/null 2>&1
    ok "welcome page opened in the Chrome inside WSL"
    ;;
  *) echo "--route must be 1 or 2" >&2; exit 64;;
esac
state_set WELCOME shown
