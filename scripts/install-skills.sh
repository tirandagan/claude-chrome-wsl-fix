#!/usr/bin/env bash
# Make this repo's skills visible to Claude Code by linking them into ~/.claude/skills.
#
#   install-skills.sh              link both skills
#   install-skills.sh --dry-run    show what would be linked
#   install-skills.sh --replace    move a conflicting existing skill folder aside first
#   install-skills.sh --uninstall  remove only the links this script made
#
# Skills:
#   claude-chrome-wsl-fix  (repo root)          setup, diagnosis and repair for both routes
#   windows-chrome         (skills/windows-chrome)  day-to-day: drive the Windows Chrome
#
# Links (not copies), so `git pull` in the repo updates the skills. If you cloned
# the repo straight into ~/.claude/skills/claude-chrome-wsl-fix, the root skill is
# already in place and only windows-chrome gets linked.
#
# Replaced folders go to ~/.claude/skill-backups/, NOT next to the skills: a backup
# left inside ~/.claude/skills would still load as a duplicate skill.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd -P)"
BACKUPS="$HOME/.claude/skill-backups"

DRY=0; REPLACE=0; UNINSTALL=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1;; --replace) REPLACE=1;; --uninstall) UNINSTALL=1;;
    -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown option: $a" >&2; exit 64;;
  esac
done

LINKS=("claude-chrome-wsl-fix|$REPO" "windows-chrome|$REPO/skills/windows-chrome")
mkdir -p "$SKILLS_DIR" 2>/dev/null || true
RC=0

for pair in "${LINKS[@]}"; do
  name="${pair%%|*}"; src="${pair#*|}"; dst="$SKILLS_DIR/$name"
  [ -f "$src/SKILL.md" ] || { no "$src/SKILL.md missing"; RC=1; continue; }
  dst_real="$(cd "$dst" 2>/dev/null && pwd -P || true)"

  if [ "$UNINSTALL" = 1 ]; then
    if [ -L "$dst" ] && [ "$dst_real" = "$src" ]; then
      [ "$DRY" = 1 ] && inf "would remove link $dst" || { rm "$dst"; ok "removed link $dst"; }
    elif [ "$dst_real" = "$src" ]; then
      inf "$dst is the repo itself — left alone"
    else
      inf "$dst is not a link made by this script — left alone"
    fi
    continue
  fi

  if [ "$dst_real" = "$src" ]; then ok "$name: already in place ($dst)"; continue; fi
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    if [ "$REPLACE" = 1 ]; then
      bk="$BACKUPS/$name-$(date +%Y%m%d-%H%M%S)"
      if [ "$DRY" = 1 ]; then inf "would move existing $dst → $bk"
      else mkdir -p "$BACKUPS"; mv "$dst" "$bk"; inf "moved existing $dst → $bk"; fi
    else
      no "$name: $dst already exists and is not this repo's copy"
      inf "re-run with --replace to move it to $BACKUPS/ and link this repo instead"
      RC=2; continue
    fi
  fi
  if [ "$DRY" = 1 ]; then inf "would link $dst → $src"
  else ln -s "$src" "$dst" && ok "$name: linked $dst → $src"; fi
done

[ "$UNINSTALL" = 0 ] && [ "$DRY" = 0 ] && [ "$RC" = 0 ] && \
  inf "new skills load in new Claude sessions (start a new chat, or reload the window)"
exit "$RC"
