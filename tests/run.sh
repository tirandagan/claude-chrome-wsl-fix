#!/usr/bin/env bash
# Offline test suite. Needs bash, python3 and Node >= 22; no WSL, no browser.
# Everything runs against a throwaway $HOME, so your real settings are never touched.
#   tests/run.sh          run all
#   tests/run.sh -v       show each passing check
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="$ROOT/scripts"
VERBOSE=0; [ "${1:-}" = "-v" ] && VERBOSE=1
PASS=0; FAIL=0
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"; [ -n "${SRV:-}" ] && kill "$SRV" 2>/dev/null' EXIT

pass() { PASS=$((PASS+1)); [ "$VERBOSE" = 1 ] && echo "  ok   $1"; return 0; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL $1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; return 0; }
check() { # $1 name, then a command; passes when the command succeeds
  local n="$1"; shift
  if out="$("$@" 2>&1)"; then pass "$n"; else fail "$n" "$(printf '%s' "$out" | head -5)"; fi
}
eq() { [ "$2" = "$3" ] && pass "$1" || fail "$1" "expected [$3] got [$2]"; }
has() { case "$2" in *"$3"*) pass "$1";; *) fail "$1" "missing [$3] in: $(printf '%s' "$2" | head -3)";; esac; }
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
  [ -x "$f" ] && pass "executable ${f#"$ROOT/"}" || fail "executable ${f#"$ROOT/"}"
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
[ ! -e "$H/.claude/bin/claude-chrome-wrapper.sh" ] && pass "dry run writes no wrapper" || fail "dry run writes no wrapper"
OUT="$(HOME="$H" "$S/install.sh" 2>&1)"; RC=$?
eq "install exits 0" "$RC" "0"
has "self-test passes" "$OUT" "self-test passed"
eq "setting added, other keys kept" "$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["editor.fontSize"], d["claudeCode.claudeProcessWrapper"].endswith("/.claude/bin/claude-chrome-wrapper.sh"))' "$MS")" "14 True"
[ -f "$MS.bak" ] && pass "settings backed up" || fail "settings backed up"
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
[ -f "$H/.vscode-server/data/Machine/settings.json" ] && pass "creates settings file when absent" || fail "creates settings file when absent"

echo "install-skills.sh"
H="$(newhome)"
HOME="$H" "$S/install-skills.sh" --dry-run >/dev/null; [ -z "$(ls -A "$H/.claude/skills" 2>/dev/null)" ] && pass "dry run links nothing" || fail "dry run links nothing"
HOME="$H" "$S/install-skills.sh" >/dev/null; RC=$?
eq "links both skills" "$RC.$([ -L "$H/.claude/skills/claude-chrome-wsl-fix" ] && echo y).$([ -f "$H/.claude/skills/windows-chrome/SKILL.md" ] && echo y)" "0.y.y"
has "re-run is idempotent" "$(HOME="$H" "$S/install-skills.sh")" "already in place"
HOME="$H" "$S/install-skills.sh" --uninstall >/dev/null
[ ! -e "$H/.claude/skills/windows-chrome" ] && pass "uninstall removes links" || fail "uninstall removes links"
mkdir -p "$H/.claude/skills/windows-chrome"; echo old > "$H/.claude/skills/windows-chrome/SKILL.md"
HOME="$H" "$S/install-skills.sh" >/dev/null 2>&1; eq "existing folder → exit 2, untouched" "$?.$(cat "$H/.claude/skills/windows-chrome/SKILL.md")" "2.old"
HOME="$H" "$S/install-skills.sh" --uninstall >/dev/null
eq "uninstall leaves foreign folder alone" "$(cat "$H/.claude/skills/windows-chrome/SKILL.md")" "old"
HOME="$H" "$S/install-skills.sh" --replace >/dev/null; RC=$?
eq "--replace links and backs up outside skills/" "$RC.$([ -L "$H/.claude/skills/windows-chrome" ] && echo y).$(find "$H/.claude/skill-backups" -maxdepth 1 -name "windows-chrome-*" | wc -l | tr -d " ")" "0.y.1"

echo "wslconfig-mirror.py"
M="$S/wslconfig-mirror.py"; f="$TMP/wslconfig"
t() { printf '%b' "$2" > "$f"; python3 "$M" "$f" >/dev/null; eq "$1" "$(tr -d '\r' < "$f")" "$(printf '%b' "$3")"; }
rm -f "$f"; python3 "$M" "$f" >/dev/null; eq "creates file" "$(tr -d '\r' < "$f")" "$(printf '[wsl2]\nnetworkingMode=Mirrored')"
t "adds to existing [wsl2]" '[wsl2]\nmemory=8GB\n' '[wsl2]\nmemory=8GB\nnetworkingMode=Mirrored'
t "replaces NAT" '[wsl2]\nnetworkingMode=NAT\nswap=0\n' '[wsl2]\nnetworkingMode=Mirrored\nswap=0'
t "inserts before next section" '[wsl2]\nmemory=8GB\n[experimental]\nx=1\n' '[wsl2]\nmemory=8GB\nnetworkingMode=Mirrored\n[experimental]\nx=1'
t "adds [wsl2] when only other sections" '[experimental]\nx=1\n' '[experimental]\nx=1\n\n[wsl2]\nnetworkingMode=Mirrored'
printf '[wsl2]\r\nnetworkingMode=Mirrored\r\n' > "$f"; eq "already mirrored → UNCHANGED" "$(python3 "$M" "$f")" "UNCHANGED"
grep -q $'\r$' "$f" && pass "writes CRLF" || fail "writes CRLF"

echo "preflight.sh"
OUT="$(HOME="$(newhome)" "$S/preflight.sh" 2>&1)"; RC=$?
eq "exits 0" "$RC" "0"
has "prints RESULT line" "$OUT" "RESULT route1="
if ! grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
  has "off WSL both routes blocked" "$OUT" "route1=blocked route2=blocked"
fi

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
  case "$OUT" in *service_worker*|*CCCC*) fail "list hides non-page targets";; *) pass "list hides non-page targets";; esac
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
    && pass "$f frontmatter" || fail "$f frontmatter"
done
eq "skill folder name matches name:" "$(sed -n 's/^name: //p' "$ROOT/skills/windows-chrome/SKILL.md")" "windows-chrome"
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
[ -z "$BROKEN" ] && pass "relative links resolve" || fail "relative links resolve" "$BROKEN"
grep -rn 'cdp-fallback' "$ROOT" --include='*.md' --include='*.sh' --exclude-dir=tests --exclude-dir=.git --exclude=CHANGELOG.md >/dev/null && fail "no references to the old cdp-fallback.md" || pass "no references to the old cdp-fallback.md"

echo
echo "passed $PASS, failed $FAIL"
[ "$FAIL" = 0 ]
