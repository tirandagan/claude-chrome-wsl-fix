#!/usr/bin/env bash
# Route 2: let a WSL Claude session drive your WINDOWS Chrome over CDP.
#
#   install-windows-chrome.sh                 install helpers + config, then verify
#   install-windows-chrome.sh --dry-run       print exactly what would change, change nothing
#   install-windows-chrome.sh --set-mirrored  also add networkingMode=Mirrored to
#                                             %UserProfile%\.wslconfig (backed up first)
#   install-windows-chrome.sh --no-verify     skip starting Chrome at the end
#   install-windows-chrome.sh --uninstall     remove helpers + config (leaves .wslconfig
#                                             and the Chrome profile alone)
#
# Exit codes: 0 done (or waiting on the WSL restart it printed), 1 failed,
# 3 helpers installed but networking is not mirrored and --set-mirrored was not given.
#
# Installs into ~/.claude/bin:  launch-windows-chrome.sh, cdp, cdp.mjs
# Writes:                       ~/.config/claude-chrome-wsl-fix/windows-chrome.env
# Never runs `wsl --shutdown` — that would end this session. It tells you when to.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"
SRC="$HERE/windows-chrome"
CONF="$STATE_DIR/windows-chrome.env"
FILES=(launch-windows-chrome.sh cdp cdp.mjs)

DRY=0; MIRROR=0; VERIFY=1; UNINSTALL=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1;; --set-mirrored) MIRROR=1;; --no-verify) VERIFY=0;; --uninstall) UNINSTALL=1;;
    -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown option: $a" >&2; exit 64;;
  esac
done
run() { if [ "$DRY" = 1 ]; then inf "would: $*"; else "$@"; fi; }

if [ "$UNINSTALL" = 1 ]; then
  echo "Removing route 2 helpers"
  for f in "${FILES[@]}"; do [ -e "$BIN_DIR/$f" ] && run rm -f "$BIN_DIR/$f" && ok "removed $BIN_DIR/$f"; done
  [ -e "$CONF" ] && run rm -f "$CONF" && ok "removed $CONF"
  [ "$DRY" = 0 ] && state_set ROUTE2 removed
  inf "left alone: .wslconfig, and the Chrome automation profile on Windows (delete that folder yourself to drop its logins)"
  inf "a running automation Chrome keeps running; close its window, or run launch-windows-chrome.sh --stop before uninstalling"
  exit 0
fi

echo "Route 2 — Windows Chrome over CDP"; [ "$DRY" = 1 ] && echo "(dry run: nothing will change)"
echo "=========================================="

is_wsl || { no "not inside WSL"; exit 1; }
interop_ok || { no "Windows interop is off — cannot launch Windows programs from WSL"; exit 1; }
WC="$(win_chrome_path)" || { no "Chrome is not installed on Windows"; exit 1; }
ok "Windows Chrome: $WC"
find_node22 >/dev/null || warn "no Node >= 22 yet — cdp will refuse to run until you install one (nvm install 22)"

# Port and profile: keep an existing config; reuse an existing C:\claude-chrome-automation
# profile (earlier versions of this recipe used it, and it holds your logins).
PORT="${CDP_PORT:-9333}"; PROFILE=""
if [ -f "$CONF" ]; then
  # shellcheck disable=SC1090
  . "$CONF"; PORT="${CDP_PORT:-$PORT}"; PROFILE="${CHROME_PROFILE_DIR:-}"
  inf "keeping existing config $CONF"
fi
if [ -z "$PROFILE" ]; then
  if [ -d /mnt/c/claude-chrome-automation ]; then PROFILE='C:\claude-chrome-automation'
  else PROFILE="$(win_env LOCALAPPDATA)\\claude-chrome-automation"; fi
fi
ok "automation profile: $PROFILE  (separate from your everyday Chrome; starts signed out)"
ok "DevTools port: $PORT"

# 1. helpers
run mkdir -p "$BIN_DIR"
for f in "${FILES[@]}"; do
  if [ -f "$BIN_DIR/$f" ] && ! cmp -s "$SRC/$f" "$BIN_DIR/$f"; then
    [ "$DRY" = 1 ] && inf "would back up the existing $BIN_DIR/$f" || backup_once "$BIN_DIR/$f"
  fi
  run install -m 0755 "$SRC/$f" "$BIN_DIR/$f" && [ "$DRY" = 0 ] && ok "installed $BIN_DIR/$f"
done

# 2. config
if [ "$DRY" = 1 ]; then
  inf "would write $CONF with CDP_PORT=$PORT, CHROME_PROFILE_DIR=$PROFILE, CHROME_EXE=$WC"
else
  mkdir -p "$STATE_DIR"
  {
    echo "# Written by claude-chrome-wsl-fix install-windows-chrome.sh — edit freely."
    printf 'CDP_PORT=%q\n' "$PORT"
    printf 'CHROME_PROFILE_DIR=%q\n' "$PROFILE"
    printf 'CHROME_EXE=%q\n' "$WC"
  } > "$CONF"
  ok "wrote $CONF"
  state_set ROUTE2 installed
fi

# 3. networking
MODE="$(wsl_net_mode)"
WINPROFILE="$(win_env USERPROFILE)"
WSLCONFIG="$(wslpath -u "$WINPROFILE\\.wslconfig")"
NEED_RESTART=0
if [ "$MODE" = mirrored ]; then
  ok "WSL networking is already mirrored"
elif grep -qiE '^\s*networkingMode\s*=\s*mirrored' "$WSLCONFIG" 2>/dev/null; then
  warn ".wslconfig already says Mirrored, but WSL has not restarted since"; NEED_RESTART=1
elif [ "$MIRROR" = 1 ]; then
  if [ "$DRY" = 1 ]; then
    inf "would back up and edit $WINPROFILE\\.wslconfig to set networkingMode=Mirrored under [wsl2]"
  else
    backup_once "$WSLCONFIG"
    python3 "$HERE/wslconfig-mirror.py" "$WSLCONFIG" >/dev/null || { no "could not edit $WSLCONFIG"; exit 1; }
    ok "set networkingMode=Mirrored in $WINPROFILE\\.wslconfig"
    NEED_RESTART=1
  fi
else
  no "WSL networking is '$MODE' — WSL cannot reach Windows Chrome's port yet"
  inf "re-run with --set-mirrored to add networkingMode=Mirrored to $WINPROFILE\\.wslconfig"
  inf "side effect worth knowing: with mirrored networking WSL and Windows share one set of ports"
  [ "$DRY" = 0 ] && state_set PENDING set-mirrored
  exit 3
fi

if [ "$NEED_RESTART" != 0 ]; then
  [ "$DRY" = 0 ] && state_set PENDING wsl-restart
  cat <<EOF

One step only you can do (it closes every WSL window, including this session):
  1. Save your work in VS Code.
  2. In Windows PowerShell:   wsl --shutdown
  3. Reopen VS Code, start a new Claude chat, and say:
       "Continue the claude-chrome-wsl-fix setup."
EOF
  exit 0
fi

# 4. verify for real: start Chrome and check it is the Windows one
if [ "$DRY" = 1 ] || [ "$VERIFY" = 0 ]; then exit 0; fi
echo; echo "Verifying (this opens a Chrome window on your Windows desktop)"
if "$BIN_DIR/launch-windows-chrome.sh"; then
  if "$BIN_DIR/cdp" version >/dev/null 2>&1; then
    ok "cdp reaches the Windows Chrome:"; "$BIN_DIR/cdp" version | sed 's/^/      /'
    state_set PENDING none
  else
    no "launcher succeeded but cdp failed — is Node >= 22 installed?"; exit 1
  fi
else
  no "verification failed (output above)"; exit 1
fi
cat <<EOF

Done. Claude drives this window with:
  launch-windows-chrome.sh                 (start it; safe to repeat)
  T=\$(cdp new https://example.com)         (open your own tab)
  cdp text --tab \$T  |  cdp shot out.png --tab \$T  |  cdp close \$T

The automation profile starts signed out. Sign in there only to accounts you are
happy for automation to use: any local process can drive it while the port is open.
EOF
