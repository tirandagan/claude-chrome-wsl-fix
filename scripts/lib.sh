# Shared helpers for the claude-chrome-wsl-fix scripts. Source, don't run.
# shellcheck shell=bash

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  _G=$'\033[32m'; _R=$'\033[31m'; _Y=$'\033[33m'; _N=$'\033[0m'
else
  _G=""; _R=""; _Y=""; _N=""
fi
ok()   { printf '  %s✓%s %s\n' "$_G" "$_N" "$1"; }
no()   { printf '  %s✗%s %s\n' "$_R" "$_N" "$1"; }
warn() { printf '  %s!%s %s\n' "$_Y" "$_N" "$1"; }
inf()  { printf '  · %s\n' "$1"; }

# shellcheck disable=SC2034  # used by the scripts that source this file
STATE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claude-chrome-wsl-fix"
# shellcheck disable=SC2034
BIN_DIR="$HOME/.claude/bin"
# shellcheck disable=SC2034
SKILLS_DIR="$HOME/.claude/skills"

is_wsl() { grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; }

# Windows interop: run a cmd.exe line from a Windows-side cwd (a Linux cwd makes
# cmd.exe print a UNC warning and fall back to C:\Windows).
CMD_EXE=/mnt/c/Windows/System32/cmd.exe
PS_EXE=/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
win_cmd() { (cd /mnt/c 2>/dev/null && "$CMD_EXE" /c "$@" 2>/dev/null | tr -d '\r'); }
win_ps()  { (cd /mnt/c 2>/dev/null && "$PS_EXE" -NoProfile -NonInteractive -Command "$@" 2>/dev/null | tr -d '\r'); }
interop_ok() { [ -x "$CMD_EXE" ] && [ -n "$(win_cmd 'echo ok')" ]; }

# Windows %USERPROFILE% / %LOCALAPPDATA% as Windows paths, e.g. C:\Users\me
win_env() { win_cmd "echo %$1%"; }

# First Windows chrome.exe found, as a Windows path. Empty if none.
win_chrome_path() {
  local lad; lad="$(win_env LOCALAPPDATA)"
  local c
  for c in 'C:\Program Files\Google\Chrome\Application\chrome.exe' \
           'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe' \
           "${lad}\\Google\\Chrome\\Application\\chrome.exe"; do
    [ -n "$c" ] && [ -f "$(wslpath -u "$c" 2>/dev/null)" ] && { printf '%s\n' "$c"; return 0; }
  done
  return 1
}

# Networking mode as WSL reports it: mirrored | nat | unknown
wsl_net_mode() {
  if command -v wslinfo >/dev/null 2>&1; then
    wslinfo --networking-mode 2>/dev/null | tr -d '\r' | tr 'A-Z' 'a-z'
  else
    echo unknown
  fi
}

# Node >= 22 (built-in WebSocket). Prints the node binary path or nothing.
find_node22() {
  local n v
  for n in "$(command -v node 2>/dev/null)" $(ls -d "$HOME"/.nvm/versions/node/v*/bin/node 2>/dev/null | sort -V -r) \
           /usr/local/bin/node /usr/bin/node; do
    [ -n "$n" ] && [ -x "$n" ] || continue
    v="$("$n" -p 'process.versions.node.split(".")[0]' 2>/dev/null)" || continue
    [ "${v:-0}" -ge 22 ] 2>/dev/null && { printf '%s\n' "$n"; return 0; }
  done
  return 1
}

# Back a file up once per run before replacing it. $1 = path
backup_once() {
  [ -e "$1" ] || return 0
  local b; b="$1.bak-$(date +%Y%m%d-%H%M%S)"
  cp -p "$1" "$b" && inf "backed up $1 → $b"
}

state_set() { # $1 = key, $2 = value — small KEY=value file the skills read on resume
  mkdir -p "$STATE_DIR"
  local f="$STATE_DIR/state.env"
  touch "$f"
  grep -v "^$1=" "$f" > "$f.tmp" 2>/dev/null || true
  printf '%s=%s\n' "$1" "$2" >> "$f.tmp"
  mv "$f.tmp" "$f"
}
