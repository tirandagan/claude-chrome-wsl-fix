#!/usr/bin/env bash
# Claude Code launch shim — re-enables "Claude in Chrome" under VS Code.
#
# WHY THIS EXISTS
#   The Claude Code VS Code extension hardcodes --no-chrome into the argument
#   list it passes to the CLI. No claudeCode.* setting controls it. The only
#   supported interception point is claudeCode.claudeProcessWrapper, which
#   replaces the executable the extension launches.
#
# HOW THE EXTENSION CALLS THIS
#   When claudeProcessWrapper is set, the extension resolves:
#       pathToClaudeCodeExecutable = <this script>
#       executableArgs             = [<real claude binary>]
#   and then spawns:  <this script> <real claude binary> <all its args...>
#   So $1 is the real binary and "$@" (after the shift) is the argument list.
#
# WHAT IT DOES
#   Removes --no-chrome, drops any pre-existing --chrome so we never pass it
#   twice, and appends a single --chrome. Everything else is forwarded byte for
#   byte, which matters because the extension passes paths containing spaces.
#
# TO DISABLE
#   Remove the claudeCode.claudeProcessWrapper setting and reload the window.
#   Nothing else needs undoing; this script is inert when unreferenced.

set -uo pipefail

if [ "$#" -lt 1 ]; then
  echo "claude-chrome-wrapper: expected the Claude binary as \$1 (is claudeProcessWrapper set correctly?)" >&2
  exit 64
fi

BIN="$1"; shift

if [ ! -x "$BIN" ]; then
  echo "claude-chrome-wrapper: '$BIN' is not executable — refusing to launch." >&2
  exit 126
fi

args=()
for a in "$@"; do
  case "$a" in
    --no-chrome|--chrome) continue ;;
    *) args+=("$a") ;;
  esac
done

exec "$BIN" "${args[@]}" --chrome
