#!/usr/bin/env bash
# Offline test suite. Needs bash, python3 and Node >= 22; no WSL, no browser.
# Everything runs against a throwaway $HOME, so your real settings are never touched.
#   tests/run.sh          run all
#   tests/run.sh -v       show each passing check
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$ROOT/scripts"
VERBOSE=0; [ "${1:-}" = "-v" ] && VERBOSE=1
N_OK=0; N_FAIL=0
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"; [ -n "${SRV:-}" ] && kill "$SRV" 2>/dev/null' EXIT

good() { N_OK=$((N_OK+1)); [ "$VERBOSE" = 1 ] && echo "  ok   $1"; return 0; }
fail() { N_FAIL=$((N_FAIL+1)); echo "  FAIL $1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; return 0; }
check() { # $1 name, then a command; passes when the command succeeds
  local n="$1"; shift
  if out="$("$@" 2>&1)"; then good "$n"; else fail "$n" "$(printf '%s' "$out" | head -5)"; fi
}
eq() { [ "$2" = "$3" ] && good "$1" || fail "$1" "expected [$3] got [$2]"; }
has() { case "$2" in *"$3"*) good "$1";; *) fail "$1" "missing [$3] in: $(printf '%s' "$2" | head -3)";; esac; }
newhome() { H="$TMP/home$RANDOM"; mkdir -p "$H/.vscode-server/data/Machine"; echo "$H"; }

NODE=""
for n in "$(command -v node 2>/dev/null)" $(ls -d "$HOME"/.nvm/versions/node/v*/bin/node 2>/dev/null | sort -V -r); do
  [ -x "$n" ] && [ "$("$n" -p 'process.versions.node.split(".")[0]')" -ge 22 ] 2>/dev/null && { NODE="$n"; break; }
done

echo "syntax"
for f in "$S"/*.sh "$S"/windows-chrome/*.sh "$S"/windows-chrome/cdp tests/run.sh; do
  f="${f#"$ROOT/"}"; check "bash -n $f" bash -n "$ROOT/$f"
done
check "python parses wslconfig-mirror.py" python3 -c "import ast,sys;ast.parse(open(sys.argv[1]).read())" "$S/wslconfig-mirror.py"
if [ -n "$NODE" ]; then check "node --check cdp.mjs" "$NODE" --check "$S/windows-chrome/cdp.mjs"
else fail "Node >= 22 available for tests" "install Node 22"; fi
for f in "$S"/*.sh "$S"/windows-chrome/*.sh "$S"/windows-chrome/cdp "$S"/windows-chrome/cdp.mjs; do
  [ -x "$f" ] && good "executable ${f#"$ROOT/"}" || fail "executable ${f#"$ROOT/"}"
done
if command -v shellcheck >/dev/null 2>&1; then
  check "shellcheck" shellcheck -S warning -x "$S"/*.sh "$S"/windows-chrome/*.sh "$S"/windows-chrome/cdp "$ROOT/tests/run.sh"
fi

echo "wrapper"
STUB="$TMP/stub"; printf '#!/usr/bin/env bash\nfor a in "$@"; do printf "[%%s]" "$a"; done\n' > "$STUB"; chmod +x "$STUB"
W="$S/claude-chrome-wrapper.sh"
eq "strips --no-chrome, appends --chrome" "$("$W" "$STUB" --a --no-chrome b)" "[--a][b][--chrome]"
eq "keeps argument boundaries with spaces" "$("$W" "$STUB" --add-dir "/x y/z" "")" "[--add-dir][/x y/z][][--chrome]"
eq "never passes --chrome twice" "$("$W" "$STUB" --chrome --chrome)" "[--chrome]"
eq "works with no extra args" "$("$W" "$STUB")" "[--chrome]"
eq "CLAUDE_CHROME_WRAPPER=off passes through" "$(CLAUDE_CHROME_WRAPPER=off "$W" "$STUB" --no-chrome x)" "[--no-chrome][x]"
"$W" >/dev/null 2>&1; eq "no binary → exit 64" "$?" "64"
"$W" "$TMP/missing" >/dev/null 2>&1; eq "non-executable binary → exit 126" "$?" "126"

echo "install.sh (route 1)"
H="$(newhome)"; MS="$H/.vscode-server/data/Machine/settings.json"
echo '{"editor.fontSize": 14}' > "$MS"
HOME="$H" "$S/install.sh" --dry-run >/dev/null
eq "dry run changes nothing" "$(cat "$MS")" '{"editor.fontSize": 14}'
[ ! -e "$H/.claude/bin/claude-chrome-wrapper.sh" ] && good "dry run writes no wrapper" || fail "dry run writes no wrapper"
OUT="$(HOME="$H" "$S/install.sh" 2>&1)"; RC=$?
eq "install exits 0" "$RC" "0"
has "self-test passes" "$OUT" "self-test passed"
eq "setting added, other keys kept" "$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["editor.fontSize"], d["claudeCode.claudeProcessWrapper"].endswith("/.claude/bin/claude-chrome-wrapper.sh"))' "$MS")" "14 True"
[ -f "$MS.bak" ] && good "settings backed up" || fail "settings backed up"
has "re-run is idempotent" "$(HOME="$H" "$S/install.sh" 2>&1)" "already set"
has "state records reload" "$(cat "$H/.config/claude-chrome-wsl-fix/state.env")" "PENDING=reload"
HOME="$H" "$S/install.sh" --uninstall >/dev/null
eq "uninstall removes only the key" "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])))' "$MS")" "{'editor.fontSize': 14}"
H="$(newhome)"; MS="$H/.vscode-server/data/Machine/settings.json"
printf '{\n  // my comment\n  "a": 1\n}\n' > "$MS"; ORIG="$(cat "$MS")"
HOME="$H" "$S/install.sh" >/dev/null 2>&1; RC=$?
eq "JSONC settings → exit 2" "$RC" "2"
eq "JSONC settings left byte-identical" "$(cat "$MS")" "$ORIG"
H="$(newhome)"; rm -rf "$H/.vscode-server"
HOME="$H" "$S/install.sh" >/dev/null 2>&1
[ -f "$H/.vscode-server/data/Machine/settings.json" ] && good "creates settings file when absent" || fail "creates settings file when absent"

echo "install-skills.sh"
H="$(newhome)"
HOME="$H" "$S/install-skills.sh" --dry-run >/dev/null; [ -z "$(ls -A "$H/.claude/skills" 2>/dev/null)" ] && good "dry run links nothing" || fail "dry run links nothing"
HOME="$H" "$S/install-skills.sh" >/dev/null; RC=$?
eq "links the plugin once (windows-chrome comes with it)" "$RC.$([ -L "$H/.claude/skills/claude-chrome-wsl-fix" ] && echo y).$([ -f "$H/.claude/skills/claude-chrome-wsl-fix/skills/windows-chrome/SKILL.md" ] && echo y).$([ -e "$H/.claude/skills/windows-chrome" ] || echo n)" "0.y.y.n"
has "re-run is idempotent" "$(HOME="$H" "$S/install-skills.sh")" "already in place"
HOME="$H" "$S/install-skills.sh" --uninstall >/dev/null
[ ! -e "$H/.claude/skills/claude-chrome-wsl-fix" ] && good "uninstall removes the link" || fail "uninstall removes the link"
ln -s "$ROOT/skills/windows-chrome" "$H/.claude/skills/windows-chrome"
HOME="$H" "$S/install-skills.sh" >/dev/null
[ ! -e "$H/.claude/skills/windows-chrome" ] && good "removes the pre-2.2 windows-chrome link" || fail "removes the pre-2.2 windows-chrome link"
HOME="$H" "$S/install-skills.sh" --uninstall >/dev/null
mkdir -p "$H/.claude/skills/windows-chrome"; echo mine > "$H/.claude/skills/windows-chrome/SKILL.md"
HOME="$H" "$S/install-skills.sh" >/dev/null; HOME="$H" "$S/install-skills.sh" --uninstall >/dev/null
eq "leaves a windows-chrome folder it didn't make alone" "$(cat "$H/.claude/skills/windows-chrome/SKILL.md")" "mine"
mkdir -p "$H/.claude/skills/claude-chrome-wsl-fix"; echo old > "$H/.claude/skills/claude-chrome-wsl-fix/SKILL.md"
HOME="$H" "$S/install-skills.sh" >/dev/null 2>&1; eq "existing folder → exit 2, untouched" "$?.$(cat "$H/.claude/skills/claude-chrome-wsl-fix/SKILL.md")" "2.old"
HOME="$H" "$S/install-skills.sh" --uninstall >/dev/null
eq "uninstall leaves foreign folder alone" "$(cat "$H/.claude/skills/claude-chrome-wsl-fix/SKILL.md")" "old"
HOME="$H" "$S/install-skills.sh" --replace >/dev/null; RC=$?
eq "--replace links and backs up outside skills/" "$RC.$([ -L "$H/.claude/skills/claude-chrome-wsl-fix" ] && echo y).$(find "$H/.claude/skill-backups" -maxdepth 1 -name "claude-chrome-wsl-fix-*" | wc -l | tr -d " ")" "0.y.1"
mini_copy() { mkdir -p "$1/scripts" "$1/skills/windows-chrome"; cp "$ROOT/SKILL.md" "$1/"; cp "$ROOT/skills/windows-chrome/SKILL.md" "$1/skills/windows-chrome/"; cp "$S/install-skills.sh" "$S/lib.sh" "$1/scripts/"; }
# A marketplace install lands in ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/;
# install-skills.sh only checks for the ~/.claude/plugins/ prefix, so these names are placeholders.
H="$(newhome)"; P="$H/.claude/plugins/cache/example-marketplace/example-plugin/0.0.0"; mini_copy "$P"
OUT="$(HOME="$H" "$P/scripts/install-skills.sh")"; RC=$?
eq "marketplace install → links nothing" "$RC.$(ls -A "$H/.claude/skills" 2>/dev/null | wc -l | tr -d ' ')" "0.0"
has "marketplace install → says why" "$OUT" "installed as a plugin"
H="$(newhome)"; P="$H/.claude/skills/claude-chrome-wsl-fix"; mini_copy "$P"
has "clone inside ~/.claude/skills → loads in place" "$(HOME="$H" "$P/scripts/install-skills.sh")" "load from there"

echo "wslconfig-mirror.py"
M="$S/wslconfig-mirror.py"; f="$TMP/wslconfig"
t() { printf '%b' "$2" > "$f"; python3 "$M" "$f" >/dev/null; eq "$1" "$(tr -d '\r' < "$f")" "$(printf '%b' "$3")"; }
rm -f "$f"; python3 "$M" "$f" >/dev/null; eq "creates file" "$(tr -d '\r' < "$f")" "$(printf '[wsl2]\nnetworkingMode=Mirrored')"
t "adds to existing [wsl2]" '[wsl2]\nmemory=8GB\n' '[wsl2]\nmemory=8GB\nnetworkingMode=Mirrored'
t "replaces NAT" '[wsl2]\nnetworkingMode=NAT\nswap=0\n' '[wsl2]\nnetworkingMode=Mirrored\nswap=0'
t "inserts before next section" '[wsl2]\nmemory=8GB\n[experimental]\nx=1\n' '[wsl2]\nmemory=8GB\nnetworkingMode=Mirrored\n[experimental]\nx=1'
t "adds [wsl2] when only other sections" '[experimental]\nx=1\n' '[experimental]\nx=1\n\n[wsl2]\nnetworkingMode=Mirrored'
printf '[wsl2]\r\nnetworkingMode=Mirrored\r\n' > "$f"; eq "already mirrored → UNCHANGED" "$(python3 "$M" "$f")" "UNCHANGED"
grep -q $'\r$' "$f" && good "writes CRLF" || fail "writes CRLF"

echo "preflight.sh"
OUT="$(HOME="$(newhome)" "$S/preflight.sh" 2>&1)"; RC=$?
eq "exits 0" "$RC" "0"
has "prints RESULT line" "$OUT" "RESULT route1="
if ! grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
  has "off WSL both routes blocked" "$OUT" "route1=blocked route2=blocked"
fi

echo "copyright banner"
has "preflight shows the copyright line 1" "$OUT" "This is the Claude Chrome for WSL skill,"
has "preflight shows the copyright line 2" "$OUT" "written by Tiran Dagan, copyright 2026,"
has "preflight shows the email" "$OUT" "tiran@tirandagan.com."
OUT2="$(HOME="$(newhome)" "$S/install.sh" --dry-run 2>&1)"
has "install.sh shows the banner" "$OUT2" "Claude Chrome for WSL"
OUT3="$(CCWF_NO_BANNER=1 HOME="$(newhome)" "$S/preflight.sh" 2>&1)"
case "$OUT3" in *"copyright 2026"*) fail "CCWF_NO_BANNER=1 hides it";; *) good "CCWF_NO_BANNER=1 hides it";; esac
N="$(bash -c ". '$S/lib.sh'; copyright_banner; copyright_banner" | grep -c 'copyright 2026')"
eq "banner prints once per run" "$N" "1"
W="$(bash -c ". '$S/lib.sh'; copyright_banner" | grep '│' | awk '{print length}' | sort -u | wc -l | tr -d ' ')"
eq "banner box lines all the same width" "$W" "1"

echo "welcome page"
P="$ROOT/assets/welcome.html"
check "welcome.html exists" test -f "$P"
WP="$(cat "$P")"
has "welcome: title" "$WP" "Welcome to Claude Chrome under WSL"
has "welcome: credit" "$WP" "written by Tiran Dagan"
has "welcome: site link" "$WP" 'href="https://tirandagan.com"'
has "welcome: GitHub link" "$WP" 'href="https://github.com/tirandagan/claude-chrome-wsl-fix"'
has "welcome: copyright" "$WP" "© 2026 Tiran Dagan"
case "$WP" in *'src="http'*|*"@import"*|*'<link rel="stylesheet"'*) fail "welcome: no external resources";; *) good "welcome: no external resources";; esac
python3 - "$P" <<'PY' && good "welcome: HTML tags balance" || fail "welcome: HTML tags balance"
import sys
from html.parser import HTMLParser
VOID = {"meta","link","br","img","input","hr","source","circle","rect","ellipse","path","stop"}
class P(HTMLParser):
    def __init__(s): super().__init__(); s.st=[]; s.bad=0
    def handle_starttag(s,t,a):
        if t not in VOID: s.st.append(t)
    def handle_startendtag(s,t,a): pass
    def handle_endtag(s,t):
        if t in VOID: return
        if s.st and s.st[-1]==t: s.st.pop()
        else: s.bad+=1
p=P(); p.feed(open(sys.argv[1],encoding="utf-8").read())
sys.exit(1 if p.bad or p.st else 0)
PY
check "welcome: welcome.webm present" test -s "$ROOT/assets/welcome.webm"
has "welcome: plays the film" "$WP" '<source src="welcome.webm"'
has "show-welcome copies the film" "$(cat "$S/show-welcome.sh")" 'welcome.webm'
U1="$(HOME="$(newhome)" "$S/show-welcome.sh" --route 1 --print-url 2>&1)"
has "show-welcome route 1 URL" "$U1" "assets/welcome.html?route=1"
case "$U1" in *" "*) fail "route 1 URL has no raw spaces" "$U1";; *) good "route 1 URL has no raw spaces";; esac
RC=0; HOME="$(newhome)" "$S/show-welcome.sh" --route 9 >/dev/null 2>&1 || RC=$?
eq "show-welcome rejects a bad route" "$RC" "64"

echo "cdp.mjs against a fake DevTools endpoint"
if [ -n "$NODE" ]; then
  PORT=$((20000 + RANDOM % 20000))
  "$NODE" -e '
    const ua = process.argv[2], port = +process.argv[1];
    require("http").createServer((q, r) => {
      r.setHeader("content-type", "application/json");
      if (q.url === "/json/version") return r.end(JSON.stringify({ Browser: "Chrome/155", "User-Agent": ua }));
      if (q.url === "/json/list") return r.end(JSON.stringify([
        { id: "AAAA1111", type: "page", title: "Human tab", url: "https://a.example/" },
        { id: "BBBB2222", type: "page", title: "Mine", url: "about:blank" },
        { id: "CCCC", type: "service_worker", title: "sw", url: "x" }]));
      if (q.url.startsWith("/json/new?") && q.method === "PUT") return r.end(JSON.stringify({ id: "NEW999", type: "page" }));
      if (q.url.startsWith("/json/close/")) return r.end("Target is closing");
      r.statusCode = 404; r.end("{}");
    }).listen(port, "127.0.0.1");' "$PORT" "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/155" &
  SRV=$!
  for _ in $(seq 1 50); do curl -s "http://127.0.0.1:$PORT/json/version" >/dev/null 2>&1 && break; sleep 0.1; done
  C() { CDP_PORT=$PORT HOME="$TMP" "$S/windows-chrome/cdp" "$@"; }
  has "version shows Windows UA" "$(C version)" "Windows NT"
  OUT="$(C list)"; has "list shows pages" "$OUT" "BBBB2222"
  case "$OUT" in *service_worker*|*CCCC*) fail "list hides non-page targets";; *) good "list hides non-page targets";; esac
  eq "new prints tab id" "$(C new https://example.com)" "NEW999"
  has "close by id prefix" "$(C close BBBB)" "closing"
  C close ZZZ >/dev/null 2>&1; eq "unknown tab → exit 1" "$?" "1"
  C bogus >/dev/null 2>&1; eq "unknown command → exit 64" "$?" "64"
  has "help lists commands" "$(C help)" "cdp click"
  kill "$SRV" 2>/dev/null; wait "$SRV" 2>/dev/null; SRV=""
  CDP_PORT=$PORT HOME="$TMP" "$S/windows-chrome/cdp" list >/dev/null 2>&1; eq "nothing on port → exit 1" "$?" "1"
  "$NODE" -e 'require("http").createServer((q,r)=>r.end(JSON.stringify({Browser:"HeadlessChrome/1","User-Agent":"Mozilla/5.0 (X11; Linux x86_64) HeadlessChrome/1"}))).listen(+process.argv[1],"127.0.0.1")' "$PORT" &
  SRV=$!; for _ in $(seq 1 50); do curl -s "http://127.0.0.1:$PORT/" >/dev/null 2>&1 && break; sleep 0.1; done
  C version >/dev/null 2>&1; eq "non-Windows browser → exit 2" "$?" "2"
  kill "$SRV" 2>/dev/null; wait "$SRV" 2>/dev/null; SRV=""
  mkdir -p "$TMP/cfg/claude-chrome-wsl-fix"; echo "CDP_PORT=$PORT" > "$TMP/cfg/claude-chrome-wsl-fix/windows-chrome.env"
  has "reads port from config" "$(XDG_CONFIG_HOME="$TMP/cfg" HOME="$TMP" "$S/windows-chrome/cdp" list 2>&1)" "127.0.0.1:$PORT"
fi

echo "docs"
for f in SKILL.md skills/windows-chrome/SKILL.md; do
  head -1 "$ROOT/$f" | grep -q '^---$' && sed -n '2,4p' "$ROOT/$f" | grep -q '^name: ' && grep -q '^description: ' "$ROOT/$f" \
    && good "$f frontmatter" || fail "$f frontmatter"
done
eq "skill folder name matches name:" "$(sed -n 's/^name: //p' "$ROOT/skills/windows-chrome/SKILL.md")" "windows-chrome"
MANIFEST="$(cd "$ROOT" && python3 - <<'PY'
import json, re, os
p = json.load(open(".claude-plugin/plugin.json")); m = json.load(open(".claude-plugin/marketplace.json"))
top = re.search(r"^## (\S+)", open("CHANGELOG.md").read(), re.M).group(1)
errs = []
if p["name"] != "wsl-browser-bridge": errs.append("plugin name changed: " + p["name"])
if p["name"].startswith(("claude-", "anthropic-")): errs.append("reserved name prefix")
if p["version"] != top: errs.append(f"plugin.json version {p['version']} != CHANGELOG {top}")
if [e["name"] for e in m["plugins"]] != [p["name"]]: errs.append("marketplace entry name != plugin name")
if not os.path.isfile(p["icon"]): errs.append("icon missing: " + p["icon"])
print("\n".join(errs))
PY
)"
[ -z "$MANIFEST" ] && good "plugin manifest: name, version = CHANGELOG, marketplace entry, icon" || fail "plugin manifest" "$MANIFEST"
BROKEN="$(cd "$ROOT" && python3 - <<'PY'
import re, os, glob
bad = []
for md in glob.glob("*.md") + glob.glob("references/*.md") + glob.glob("skills/*/SKILL.md"):
    text = open(md, encoding="utf-8").read()
    text = re.sub(r"```.*?```", "", text, flags=re.S)
    for link in re.findall(r"\]\(([^)#\s]+)(?:#[^)]*)?\)", text):
        if re.match(r"[a-z]+:", link): continue
        if not os.path.exists(os.path.normpath(os.path.join(os.path.dirname(md), link))):
            bad.append(f"{md} -> {link}")
print("\n".join(bad))
PY
)"
[ -z "$BROKEN" ] && good "relative links resolve" || fail "relative links resolve" "$BROKEN"
grep -rn 'cdp-fallback' "$ROOT" --include='*.md' --include='*.sh' --exclude-dir=tests --exclude-dir=.git --exclude=CHANGELOG.md >/dev/null && fail "no references to the old cdp-fallback.md" || good "no references to the old cdp-fallback.md"

echo "plugin directory rules"
# The directory refuses to validate a repo whose .gitattributes rewrites file contents
# (eol, text, filter, LFS, ...), so LF line endings are guarded here instead: the
# scripts run in WSL, and a CRLF script fails with "bash\r: No such file or directory".
BADATTR="$(find "$ROOT" -name .gitattributes -not -path '*/.git/*' -exec grep -HnE '(^|[[:space:]])-?(text|eol|crlf|filter|ident|working-tree-encoding|export-ignore|export-subst)([=[:space:]]|$)' {} + 2>/dev/null)"
[ -z "$BADATTR" ] && good "no .gitattributes rule the directory rejects" || fail "no .gitattributes rule the directory rejects" "$BADATTR"
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  CRLF="$(git -C "$ROOT" ls-files --eol | awk '$1 ~ /crlf/ {print $NF}')"
  [ -z "$CRLF" ] && good "every committed text file uses LF" || fail "every committed text file uses LF" "$CRLF"
fi

echo
echo "passed $N_OK, failed $N_FAIL"
[ "$N_FAIL" = 0 ]
