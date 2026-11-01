# Root cause forensics

Everything here was verified by reading the installed extension bundle, not
inferred from documentation. Re-run these checks after an extension update.

## Contents
- [Where the flag lives](#where-the-flag-lives)
- [The wrapper contract](#the-wrapper-contract)
- [Re-verifying after an update](#re-verifying-after-an-update)
- [Why the Windows browser cannot pair](#why-the-windows-browser-cannot-pair)
- [What the CLI itself supports](#what-the-cli-itself-supports)

## Where the flag lives

`~/.vscode-server/extensions/anthropic.claude-code-<version>-linux-x64/extension.js`
contains a literal argument block:

```js
extraArgs:{debug:null,"debug-to-stderr":null,"enable-auth-status":null,
           "no-chrome":null,"replay-user-messages":null}
```

Confirmed present in **2.1.278**, **2.1.280** and **2.1.314** (re-checked
2026-10-31 with the commands under [Re-verifying after an update](#re-verifying-after-an-update)).
It has survived months of updates, so treat it as intentional rather than a
transient bug.

Every `claudeCode.*` setting the extension contributes was enumerated from its
`package.json` and none of them gates this block. The settings surface simply
does not expose it.

## The wrapper contract

Resolution, from the current bundle (identifier names are minified and change
between builds; the semantics have not):

```js
function U9$(ctx, env) {
  let wrapper = e4("claudeProcessWrapper");
  let realBinary = Y31(ctx);
  if (wrapper) return { pathToClaudeCodeExecutable: wrapper,
                        executableArgs: realBinary ? [realBinary] : [],
                        env, viaProcessWrapper: true };
  ...
}
```

Composition:

```js
if (X.length > 0) return { command: Q, args: [...X, ...J] }
```

Where `X` is `executableArgs` and `J` is the extension's own arguments.
Therefore the spawn is:

```
<wrapper> <real claude binary> <extension args...>
```

which is why the wrapper takes `$1` as the binary, shifts, and forwards `"$@"`.
Note the extension passes paths containing spaces (`--add-dir`), so any
reimplementation must preserve argument boundaries — never flatten to a string.

## Re-verifying after an update

```bash
EXT=$(ls -d ~/.vscode-server/extensions/anthropic.claude-code-*-linux-* | sort -V | tail -1)

# 1. is the flag still hardcoded?
grep -o 'extraArgs:{[^}]*}' "$EXT/extension.js"

# 2. is the wrapper hook still honoured?
grep -o 'claudeProcessWrapper' "$EXT/extension.js" | head -1

# 3. is the composition still <wrapper> <binary> <args>?
grep -oE 'if\([A-Za-z0-9_$]+\.length>0\)return\{command:[^}]*\}' "$EXT/extension.js"
```

If (1) stops matching, the flag may have been removed upstream — test whether
the integration works without the wrapper before keeping it. If (2) stops
matching, the hook is gone and this approach no longer applies.

## Why the Windows browser cannot pair

Two independent reasons, and both have to be understood or the fix looks broken.

**The CLI searches Linux paths.** The Claude binary runs inside WSL and probes
Linux browser profile directories — `~/.config/google-chrome`,
`~/.config/chromium`, `~/.config/BraveSoftware/Brave-Browser`,
`~/.config/microsoft-edge`. It never looks at
`/mnt/c/Users/<you>/AppData/Local/Google/Chrome/User Data`.

**The Windows native messaging host targets a Windows binary.** On a Windows
host, Chrome's registry entry for
`com.anthropic.claude_code_browser_extension` points at a manifest whose `path`
is a `.bat` that launches `claude.exe` — a *Windows-native* Claude Code. The
native host and the CLI session rendezvous over local IPC, and a Windows process
cannot see a WSL process's socket. So a Windows Chrome pairs with a Windows
Claude Code, not with your WSL session.

Practical consequence: for Claude in Chrome, install Chrome **inside WSL**. WSLg
renders it on the Windows desktop, so it looks and behaves like any other window.
To work in the **Windows** Chrome instead, use route 2, the DevTools Protocol
([windows-chrome-cdp.md](windows-chrome-cdp.md)), which does not involve the extension at all.

Redirecting that `.bat` through `wsl.exe` is theoretically possible but is not
recommended — the file is generated and marked "do not edit manually", a Windows
Claude Code update will overwrite it, and it breaks the Windows-native pairing
that the file exists to serve.

## What the CLI itself supports

The CLI has always had the capability; only the extension suppresses it:

```
--chrome       Enable Claude in Chrome integration
--no-chrome    Disable Claude in Chrome integration
```

Running `claude --chrome` in a plain WSL terminal needs no wrapper at all. The
wrapper exists solely to reach sessions launched *by the VS Code extension*.
