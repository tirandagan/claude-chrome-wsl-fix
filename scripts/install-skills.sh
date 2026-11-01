#!/usr/bin/env bash
# Make this repo's skills visible to Claude Code.
#
#   install-skills.sh              link the plugin into ~/.claude/skills
#   install-skills.sh --dry-run    show what would change
#   install-skills.sh --replace    move a conflicting existing folder aside first
#   install-skills.sh --uninstall  remove only the links this script made
#
# The repo is a Claude Code plugin, wsl-browser-bridge (.claude-plugin/plugin.json),
# with two skills: claude-chrome-wsl-fix (repo root) and windows-chrome
# (skills/windows-chrome). Claude Code loads a plugin folder it finds in
# ~/.claude/skills at startup, so one link, ~/.claude/skills/claude-chrome-wsl-fix
# → this repo, makes both skills visible. A link, not a copy, so `git pull` in the
# repo updates them. If the repo already sits in ~/.claude/skills, there is
# nothing to link.
#
# Installed from a marketplace or Anthropic's directory (this script then runs
# from ~/.claude/plugins/...)? The skills already load and nothing is linked.
#
# Before 2.2 this script also linked ~/.claude/skills/windows-chrome. The plugin
# now provides that skill, so the old link would load it twice. Every mode,
# --uninstall included, removes it when it points into a copy of this plugin.
#
# Replaced folders go to ~/.claude/skill-backups/, NOT next to the skills: a backup
# left inside ~/.claude/skills would still load as a duplicate skill.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd -P)"
BACKUPS="$HOME/.claude/skill-backups"
PLUGIN_NAME="wsl-browser-bridge"
NAME="claude-chrome-wsl-fix"

DRY=0; REPLACE=0; UNINSTALL=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1;; --replace) REPLACE=1;; --uninstall) UNINSTALL=1;;
    -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown option: $a" >&2; exit 64;;
  esac
done

realdir() { (cd "$1" 2>/dev/null && pwd -P) || true; }
is_this_plugin() { grep -q "\"name\": *\"$PLUGIN_NAME\"" "$1/.claude-plugin/plugin.json" 2>/dev/null; }
[ -f "$REPO/SKILL.md" ] && is_this_plugin "$REPO" || { no "$REPO is not the $PLUGIN_NAME plugin (SKILL.md or .claude-plugin/plugin.json missing)"; exit 1; }

# 1. The pre-2.2 windows-chrome link, if it points into any copy of this plugin.
legacy="$SKILLS_DIR/windows-chrome"
if [ -L "$legacy" ]; then
  tgt="$(realdir "$legacy")"
  if [ -z "$tgt" ]; then
    case "$(readlink "$legacy")" in
      */skills/windows-chrome)
        if [ "$DRY" = 1 ]; then inf "would remove broken link $legacy"
        else rm "$legacy" && ok "removed broken link $legacy"; fi;;
    esac
  elif [ "${tgt##*/}" = windows-chrome ] && is_this_plugin "$tgt/../.."; then
    if [ "$DRY" = 1 ]; then inf "would remove old link $legacy (the plugin provides windows-chrome now)"
    else rm "$legacy" && ok "removed old link $legacy (the plugin provides windows-chrome now)"; fi
  fi
fi

# 2. Installed as a marketplace or synced plugin: nothing to link.
PLUGINS_ROOT="$(realdir "${CLAUDE_CODE_PLUGIN_CACHE_DIR:-$HOME/.claude/plugins}")"
if [ -n "$PLUGINS_ROOT" ]; then
  case "$REPO/" in "$PLUGINS_ROOT/"*)
    ok "installed as a plugin ($REPO): both skills already load, nothing to link"; exit 0;;
  esac
fi

# 3. The repo already sits in ~/.claude/skills (under any folder name): it loads in place.
SKILLS_REAL="$(realdir "$SKILLS_DIR")"
if [ -n "$SKILLS_REAL" ] && [ "$(dirname "$REPO")" = "$SKILLS_REAL" ]; then
  if [ "$UNINSTALL" = 1 ]; then inf "$REPO is the repo itself — left alone"
  else ok "$REPO is in $SKILLS_DIR: the plugin and both skills load from there"; fi
  exit 0
fi

# 4. The repo lives elsewhere: link it in.
mkdir -p "$SKILLS_DIR" 2>/dev/null || true
dst="$SKILLS_DIR/$NAME"
dst_real="$(realdir "$dst")"

if [ "$UNINSTALL" = 1 ]; then
  if [ -L "$dst" ] && [ "$dst_real" = "$REPO" ]; then
    if [ "$DRY" = 1 ]; then inf "would remove link $dst"; else rm "$dst" && ok "removed link $dst"; fi
  else
    inf "$dst is not a link made by this script — left alone"
  fi
  exit 0
fi

if [ "$dst_real" = "$REPO" ]; then ok "$NAME: already in place ($dst)"; exit 0; fi
if [ -e "$dst" ] || [ -L "$dst" ]; then
  if [ "$REPLACE" = 1 ]; then
    bk="$BACKUPS/$NAME-$(date +%Y%m%d-%H%M%S)"
    if [ "$DRY" = 1 ]; then inf "would move existing $dst → $bk"
    else mkdir -p "$BACKUPS" && mv "$dst" "$bk" && inf "moved existing $dst → $bk"; fi
  else
    no "$dst already exists and is not this repo"
    inf "re-run with --replace to move it to $BACKUPS/ and link this repo instead"
    exit 2
  fi
fi
if [ "$DRY" = 1 ]; then inf "would link $dst → $REPO"; exit 0; fi
ln -s "$REPO" "$dst" || exit 1
ok "linked $dst → $REPO (plugin $PLUGIN_NAME: skills $NAME and windows-chrome)"
inf "the skills load in new Claude sessions (start a new chat, or run /reload-plugins)"
