#!/usr/bin/env node
// Dependency-free Chrome DevTools Protocol client for the Windows Chrome that
// launch-windows-chrome.sh starts. Needs Node >= 22 (built-in WebSocket).
// Run it through the `cdp` shim, which finds a suitable Node for you.
//
//   cdp version                       which browser is on the port (UA must say Windows NT)
//   cdp list                          tabs: index, id, title, url
//   cdp new [url]                     open YOUR OWN tab; prints its id — use it with --tab
//   cdp close <tab>                   close a tab
//   cdp goto <url>        [--tab T]   navigate and wait for load
//   cdp text              [--tab T]   visible page text
//   cdp eval "<js>"       [--tab T]   evaluate an expression (promises awaited)
//   cdp wait "<css>" [ms] [--tab T]   wait until a VISIBLE element matches (default 15000 ms)
//   cdp click "<css>"     [--tab T]   real mouse click on the first VISIBLE match
//   cdp type "<text>"     [--tab T]   insert text at the focused element
//   cdp key <Enter|Tab|Escape|Backspace|ArrowDown|ArrowUp> [--tab T]
//   cdp shot <file.png>   [--tab T]   screenshot of the viewport
//
// T is a tab id (or unique id prefix) from `list`/`new`, or an index. Default:
// $CDP_TAB, else index 0 — but index 0 is usually the human's tab, so pass the
// id of a tab you opened with `new`. Older positional form `eval|goto|shot X T`
// still works. Port: $CDP_PORT, else the installer's config, else 9333.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { homedir } from 'node:os';

if (typeof WebSocket === 'undefined') {
  console.error(`cdp: Node ${process.versions.node} has no built-in WebSocket; use Node >= 22 (the cdp shim finds one).`);
  process.exit(1);
}

function configPort() {
  try {
    const base = process.env.XDG_CONFIG_HOME || `${homedir()}/.config`;
    const m = readFileSync(`${base}/claude-chrome-wsl-fix/windows-chrome.env`, 'utf8').match(/^CDP_PORT=["']?(\d+)/m);
    return m && m[1];
  } catch { return null; }
}
const PORT = process.env.CDP_PORT || configPort() || '9333';
const BASE = `http://127.0.0.1:${PORT}`;

// ---- argument parsing: --tab T anywhere; everything else positional
const raw = process.argv.slice(2);
let tabSel = process.env.CDP_TAB ?? null;
const pos = [];
for (let i = 0; i < raw.length; i++) {
  if (raw[i] === '--tab') tabSel = raw[++i];
  else if (raw[i].startsWith('--tab=')) tabSel = raw[i].slice(6);
  else pos.push(raw[i]);
}
const [cmd, a1, a2] = pos;
// legacy positional tab: eval/goto/shot <arg> <tab>
if (['eval', 'goto', 'shot', 'text', 'click', 'type'].includes(cmd) && a2 !== undefined && tabSel === (process.env.CDP_TAB ?? null)) tabSel = a2;

const die = (msg) => { console.error(`cdp: ${msg}`); process.exit(1); };

async function http(path, method = 'GET') {
  let r;
  try { r = await fetch(`${BASE}${path}`, { method }); }
  catch { die(`nothing answering on ${BASE}. Start it: launch-windows-chrome.sh`); }
  const body = await r.text();
  try { return JSON.parse(body); } catch { return body; }
}
const pages = async () => (await http('/json/list')).filter(t => t.type === 'page');

async function pickTab(sel) {
  const tabs = await pages();
  if (!tabs.length) die('no open tabs');
  if (sel === null || sel === undefined || sel === '') sel = '0';
  if (/^\d+$/.test(sel) && Number(sel) < tabs.length && sel.length < 4) return tabs[Number(sel)];
  const hits = tabs.filter(t => t.id === sel || t.id.startsWith(sel));
  if (hits.length === 1) return hits[0];
  die(hits.length ? `tab prefix "${sel}" is ambiguous` : `no tab "${sel}"; run: cdp list`);
}

async function session(sel) {
  const tab = await pickTab(sel);
  const ws = new WebSocket(tab.webSocketDebuggerUrl);
  await new Promise((ok, bad) => { ws.onopen = ok; ws.onerror = () => bad(new Error('websocket failed')); });
  let id = 0; const waiting = new Map(); const listeners = [];
  ws.onmessage = ev => {
    const m = JSON.parse(ev.data);
    if (m.id && waiting.has(m.id)) { waiting.get(m.id)(m); waiting.delete(m.id); }
    else if (m.method) listeners.forEach(f => f(m));
  };
  const send = (method, params = {}) => new Promise((res, rej) => {
    const n = ++id; waiting.set(n, m => m.error ? rej(new Error(`${method}: ${m.error.message}`)) : res(m.result));
    ws.send(JSON.stringify({ id: n, method, params }));
  });
  const once = (method, ms) => new Promise(res => {
    const t = setTimeout(() => res(false), ms);
    listeners.push(m => { if (m.method === method) { clearTimeout(t); res(true); } });
  });
  const evaluate = async (expression) => {
    const r = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true, userGesture: true });
    if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description || r.exceptionDetails.text);
    return r.result?.value;
  };
  return { tab, send, once, evaluate, close: () => ws.close() };
}

// In-page helper: first VISIBLE element for a selector (hidden duplicates are a
// classic way to click the wrong thing), plus how many visible matches exist.
const visibleFn = (css) => `(() => {
  const all = [...document.querySelectorAll(${JSON.stringify(css)})];
  const vis = all.filter(e => { const r = e.getBoundingClientRect(); const s = getComputedStyle(e);
    return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none' && e.getClientRects().length; });
  if (!vis.length) return { total: all.length, visible: 0 };
  const e = vis[0]; e.scrollIntoView({ block: 'center', inline: 'center' });
  const r = e.getBoundingClientRect();
  return { total: all.length, visible: vis.length, x: r.left + r.width / 2, y: r.top + r.height / 2,
           label: (e.innerText || e.value || e.getAttribute('aria-label') || e.tagName).trim().slice(0, 60) };
})()`;

const KEYS = {
  Enter: { key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13, text: '\r' },
  Tab: { key: 'Tab', code: 'Tab', windowsVirtualKeyCode: 9 },
  Escape: { key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 },
  Backspace: { key: 'Backspace', code: 'Backspace', windowsVirtualKeyCode: 8 },
  ArrowDown: { key: 'ArrowDown', code: 'ArrowDown', windowsVirtualKeyCode: 40 },
  ArrowUp: { key: 'ArrowUp', code: 'ArrowUp', windowsVirtualKeyCode: 38 },
};

const USAGE = readFileSync(new URL(import.meta.url), 'utf8').split('\n')
  .filter(l => l.startsWith('//   cdp')).map(l => l.slice(5)).join('\n');

try {
  switch (cmd) {
    case 'version': {
      const v = await http('/json/version');
      console.log(`${v.Browser}\n${v['User-Agent']}`);
      if (!/Windows NT/.test(v['User-Agent'])) { console.error('cdp: WARNING this is not a Windows Chrome'); process.exit(2); }
      break;
    }
    case 'list':
      (await pages()).forEach((t, i) => console.log(`${String(i).padEnd(3)}${t.id}  ${t.title.slice(0, 50).padEnd(50)}  ${t.url.slice(0, 90)}`));
      break;
    case 'new': {
      const t = await http(`/json/new?${encodeURIComponent(a1 || 'about:blank')}`, 'PUT');
      if (!t.id) die(`could not open a tab: ${typeof t === 'string' ? t : JSON.stringify(t)}`);
      console.log(t.id);
      break;
    }
    case 'close': {
      const t = await pickTab(a1 ?? tabSel);
      console.log(await http(`/json/close/${t.id}`));
      break;
    }
    case 'goto': {
      if (!a1) die('usage: cdp goto <url> [--tab T]');
      const s = await session(tabSel);
      await s.send('Page.enable');
      const loaded = s.once('Page.loadEventFired', 30000);
      const r = await s.send('Page.navigate', { url: a1 });
      if (r.errorText) die(`navigation failed: ${r.errorText}`);
      const ok = await loaded;
      console.log(`${ok ? 'loaded' : 'still loading after 30s'}: ${await s.evaluate('location.href')}\ntitle: ${await s.evaluate('document.title')}`);
      s.close(); break;
    }
    case 'text': {
      const s = await session(tabSel);
      console.log(await s.evaluate('document.body ? document.body.innerText : ""'));
      s.close(); break;
    }
    case 'eval': {
      if (!a1) die('usage: cdp eval "<js>" [--tab T]');
      const s = await session(tabSel);
      const v = await s.evaluate(a1);
      console.log(typeof v === 'string' ? v : JSON.stringify(v, null, 2));
      s.close(); break;
    }
    case 'wait': {
      if (!a1) die('usage: cdp wait "<css>" [ms] [--tab T]');
      const ms = Number(a2) || 15000; const s = await session(tabSel); const t0 = Date.now();
      for (;;) {
        const v = await s.evaluate(visibleFn(a1));
        if (v.visible) { console.log(`visible after ${Date.now() - t0} ms: ${v.label}`); break; }
        if (Date.now() - t0 > ms) { s.close(); die(`no visible "${a1}" after ${ms} ms (${v.total} hidden matches)`); }
        await new Promise(r => setTimeout(r, 250));
      }
      s.close(); break;
    }
    case 'click': {
      if (!a1) die('usage: cdp click "<css>" [--tab T]');
      const s = await session(tabSel);
      const v = await s.evaluate(visibleFn(a1));
      if (!v.visible) { s.close(); die(`no visible match for "${a1}" (${v.total} hidden)`); }
      for (const type of ['mouseMoved', 'mousePressed', 'mouseReleased'])
        await s.send('Input.dispatchMouseEvent', { type, x: v.x, y: v.y, button: 'left', clickCount: 1 });
      console.log(`clicked "${v.label}" (${v.visible} visible / ${v.total} total matches)`);
      s.close(); break;
    }
    case 'type': {
      if (a1 === undefined) die('usage: cdp type "<text>" [--tab T]   (click the field first)');
      const s = await session(tabSel);
      await s.send('Input.insertText', { text: a1 });
      console.log(`typed ${a1.length} chars into: ${await s.evaluate('document.activeElement && (document.activeElement.name || document.activeElement.id || document.activeElement.tagName)')}`);
      s.close(); break;
    }
    case 'key': {
      const k = KEYS[a1]; if (!k) die(`key must be one of: ${Object.keys(KEYS).join(', ')}`);
      const s = await session(tabSel);
      await s.send('Input.dispatchKeyEvent', { type: 'keyDown', ...k });
      await s.send('Input.dispatchKeyEvent', { type: 'keyUp', key: k.key, code: k.code, windowsVirtualKeyCode: k.windowsVirtualKeyCode });
      console.log(`pressed ${a1}`);
      s.close(); break;
    }
    case 'shot': {
      if (!a1) die('usage: cdp shot <file.png> [--tab T]');
      const s = await session(tabSel);
      const r = await s.send('Page.captureScreenshot', { format: 'png' });
      mkdirSync(dirname(a1), { recursive: true });
      writeFileSync(a1, Buffer.from(r.data, 'base64'));
      console.log(`saved ${a1}`);
      s.close(); break;
    }
    default:
      console.log(USAGE);
      if (cmd && cmd !== 'help' && cmd !== '--help' && cmd !== '-h') process.exit(64);
  }
} catch (e) { die(e.message); }
process.exit(0);
