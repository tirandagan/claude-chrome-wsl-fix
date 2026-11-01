#!/usr/bin/env bash
# Bring up the HOST WINDOWS Chrome (a dedicated automation profile) with a
# DevTools port that WSL can reach, so a WSL Claude session can drive it.
#
#   launch-windows-chrome.sh            start it (idempotent: no-op if already up)
#   launch-windows-chrome.sh --status   report, change nothing
#   launch-windows-chrome.sh --stop     close the automation Chrome only
#
# Config: ~/.config/claude-chrome-wsl-fix/windows-chrome.env (written by
# install-windows-chrome.sh). Environment variables override it:
#   CDP_PORT            default 9333 (9222 is often owned by other tooling)
#   CHROME_PROFILE_DIR  Windows path of the automation profile
#   CHROME_EXE          Windows path of chrome.exe
#
# Why each piece is the way it is:
# - Chrome 136+ refuses --remote-debugging-port on the DEFAULT profile, so this
#   uses a separate profile with its own logins. Your everyday Chrome is untouched.
# - WSL reaches Windows' 127.0.0.1 only with networkingMode=Mirrored in .wslconfig.
# - A live automation-profile Chrome WITHOUT a bound port swallows new launches
#   (they just open a tab in it), so that stale instance is closed first.
# - `cmd.exe /c start` detaches properly; backgrounding chrome.exe directly under
#   bash gets it killed when the script exits.
# - Launch from a Windows-side cwd, or chrome.exe can create literal "C:\Users\..."
#   directories in your Linux working directory.
set -uo pipefail

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/claude-chrome-wsl-fix/windows-chrome.env"
_port="${CDP_PORT:-}"; _prof="${CHROME_PROFILE_DIR:-}"; _exe="${CHROME_EXE:-}"
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"
PORT="${_port:-${CDP_PORT:-9333}}"
PROFILE="${_prof:-${CHROME_PROFILE_DIR:-}}"
EXE="${_exe:-${CHROME_EXE:-C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe}}"

CMD=/mnt/c/Windows/System32/cmd.exe
PS=/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
ps_run() { (cd /mnt/c && "$PS" -NoProfile -NonInteractive -Command "$1" 2>/dev/null | tr -d '\r'); }

if [ -z "$PROFILE" ]; then
  LAD="$(cd /mnt/c && "$CMD" /c 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r')"
  PROFILE="${LAD}\\claude-chrome-automation"
fi

version() { curl -s -m 2 "http://127.0.0.1:$PORT/json/version" 2>/dev/null; }
is_windows_chrome() { version | grep -q 'Windows NT'; }
# PowerShell -like treats [ ] as wildcards; the profile path has none.
PROF_LIKE="*${PROFILE}*"
automation_pids() {
  ps_run "Get-CimInstance Win32_Process -Filter \"name='chrome.exe'\" | Where-Object { \$_.CommandLine -like '$PROF_LIKE' -and \$_.CommandLine -notlike '*--type=*' } | ForEach-Object { \$_.ProcessId }"
}
stop_automation() {
  ps_run "Get-CimInstance Win32_Process -Filter \"name='chrome.exe'\" | Where-Object { \$_.CommandLine -like '$PROF_LIKE' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force -ErrorAction SilentlyContinue }" >/dev/null
}

case "${1:-}" in
  --status)
    if is_windows_chrome; then
      echo "up: Windows Chrome answering on 127.0.0.1:$PORT"; version | grep -E '"(Browser|User-Agent)"'
    elif [ -n "$(version)" ]; then
      echo "port $PORT answers, but NOT with a Windows Chrome:"; version | grep '"User-Agent"'; exit 2
    else
      p="$(automation_pids)"
      if [ -n "$p" ]; then echo "automation Chrome running (pid $p) but port $PORT unreachable — see --help / networkingMode"; exit 3
      else echo "down: automation Chrome not running"; exit 1; fi
    fi
    exit 0;;
  --stop)
    stop_automation; sleep 1
    if [ -z "$(automation_pids)" ]; then echo "stopped automation Chrome ($PROFILE)"; else echo "could not stop it" >&2; exit 1; fi
    exit 0;;
  -h|--help)
    sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
  "") ;;
  *) echo "unknown option: $1 (try --help)" >&2; exit 64;;
esac

if is_windows_chrome; then echo "CDP already up on $PORT"; exit 0; fi
if [ -n "$(version)" ]; then
  echo "port $PORT is held by a browser that is not the Windows Chrome:" >&2
  version | grep '"User-Agent"' >&2
  echo "pick another port: CDP_PORT=<port> $0   (don't kill another tool's browser)" >&2
  exit 2
fi

stale="$(automation_pids)"
if [ -n "$stale" ]; then
  echo "closing the automation Chrome that is running without a debug port (pid $(echo $stale))"
  stop_automation; sleep 3
fi

WINEXE_UNIX="$(wslpath -u "$EXE" 2>/dev/null || true)"
if [ -z "$WINEXE_UNIX" ] || [ ! -f "$WINEXE_UNIX" ]; then
  echo "chrome.exe not found at $EXE — set CHROME_EXE in $CONF" >&2; exit 1
fi

cd /mnt/c || exit 1
"$CMD" /c start "" "$EXE" \
  --remote-debugging-port="$PORT" --user-data-dir="$PROFILE" \
  --no-first-run --no-default-browser-check about:blank \
  </dev/null >/dev/null 2>&1 &
disown 2>/dev/null || true

for i in $(seq 1 30); do
  if is_windows_chrome; then
    echo "CDP up on $PORT after ${i}s"; version | grep '"User-Agent"'; exit 0
  fi
  sleep 1
done

if [ -n "$(automation_pids)" ]; then
  echo "Chrome started on Windows, but WSL cannot reach 127.0.0.1:$PORT." >&2
  echo "Most likely WSL networking is not mirrored. Check: wslinfo --networking-mode" >&2
  echo "Fix: networkingMode=Mirrored under [wsl2] in %UserProfile%\\.wslconfig, then 'wsl --shutdown' from Windows." >&2
else
  echo "timed out: Chrome did not start (exe: $EXE)" >&2
fi
exit 1
