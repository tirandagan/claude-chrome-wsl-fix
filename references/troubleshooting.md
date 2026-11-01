# Troubleshooting

Start with `scripts/preflight.sh` (both routes) or `scripts/diagnose.sh`
(Route 1 in depth), then match the symptom.

## Route 1: Claude in Chrome with a WSL-side Chrome

| Symptom | Cause | Fix |
|---|---|---|
| Claude says Chrome tools are unavailable; diagnose §3 shows `--no-chrome` | The session started before the wrapper was registered, or without it | Reload the VS Code window (`Developer: Reload Window`) and open a new chat |
| §4 wrapper missing / not executable | Not installed, or `chmod` lost (e.g. copied through Windows) | `scripts/install.sh` |
| §5 setting missing | Installer skipped a commented `settings.json` (exit 2) | Paste the line it printed into *Preferences: Open Remote Settings (JSON)* |
| §6 extension missing | Extension installed in the **Windows** Chrome | Install it from <https://claude.ai/chrome> in the Chrome inside WSL |
| §7 no Linux browser | Chrome not installed in WSL | See SETUP.md, "Route 1 browser" |
| §8 host manifest points at a missing program | Claude Code moved or was reinstalled | Start any session with `--chrome`; it rewrites the manifest |
| "Selected Chrome extension disconnected", or no browsers listed | Extension not signed in, or signed in to a different Claude account | Sign in to the extension in the WSL Chrome with the account Claude Code uses |
| Two browsers listed; the wrong one gets driven | Another computer's Chrome is on the same account | `list_connected_browsers`, then pick this computer's browser |
| Sign-in lost after every restart | No keyring under WSL ("Failed to decrypt token" in Chrome's log) | Sign in again, or install and unlock a keyring (`gnome-keyring`) |
| WSL Chrome closes when the session's last tab closes | Expected; the window belonged to that tab | Start it again next time |
| A launched `google-chrome &` disappears when the command ends | Background jobs die with the tool call | Start it with a long-running background command, or from your own terminal |
| §2 shows **no** hardcoded `--no-chrome` | The extension changed upstream | Test without the wrapper (`CLAUDE_CHROME_WRAPPER=off`); if it works, `scripts/install.sh --uninstall` |
| Sessions fail to start at all after install | Wrapper deleted, or the extension changed its argument shape | `scripts/install.sh --uninstall`, reload, then check `references/root-cause.md` |

## Route 2: Windows Chrome over CDP

| Symptom | Cause | Fix |
|---|---|---|
| `nothing answering on 127.0.0.1:9333` | Automation Chrome not running | `launch-windows-chrome.sh` |
| Chrome opens on Windows, but the launcher times out reaching the port | WSL networking not mirrored | `wslinfo --networking-mode`; set `networkingMode=Mirrored`, then `wsl --shutdown` from Windows |
| `.wslconfig` says Mirrored, `wslinfo` says nat | WSL not restarted since the edit | `wsl --shutdown` from Windows, reopen VS Code |
| `cdp version` exit 2, Linux/Headless user agent | Another browser holds the port | Pick another port: `CDP_PORT=9334` in `~/.config/claude-chrome-wsl-fix/windows-chrome.env` |
| Each launch just opens a tab; port never appears | A running automation Chrome has no debug port | The launcher closes it automatically; if not, close that window |
| `chrome.exe not found` | Chrome installed somewhere unusual | Set `CHROME_EXE` (a Windows path) in `windows-chrome.env` |
| `no Node >= 22 found` | Only older Node installed | `nvm install 22`, or `CDP_NODE=/path/to/node` |
| Signed out everywhere | The automation profile is separate from your everyday Chrome by design | Sign in there once (only to accounts you'd hand to automation) |
| Folders named like `C:\Users\…` appear in a Linux project | `chrome.exe` launched from a Linux working directory | The launcher always `cd`s to `/mnt/c`; delete the stray folders |
| `click` says "no visible match" though the element exists | It is hidden, inside an iframe, or in a shadow root | Narrow the selector; for iframes and shadow DOM use `eval` with the right document |

## Both

| Symptom | Fix |
|---|---|
| Skill not offered by Claude | `scripts/install-skills.sh`, then start a new chat |
| `install-skills.sh` says a skill folder already exists | An older copy; `--replace` moves it to `~/.claude/skill-backups/` |
| Scripts fail with `bash\r: No such file or directory` | The repo was cloned on the Windows side with CRLF endings. Clone inside WSL; `.gitattributes` keeps `*.sh` at LF |
