/**
 * Records a short MP4 of a running game, HUD included, via headless Chrome's screencast.
 * Needs Google Chrome and ffmpeg. Open as a third connection so you spectate player 1.
 *
 *   npm run clip -- [seconds] [out.mp4] [url]
 *   npm run clip -- 15 clips/fight.mp4
 */
import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { WebSocket } from 'ws';

const secs = Number(process.argv[2] ?? 15);
const out = path.resolve(process.argv[3] ?? `clips/clip-${Date.now()}.mp4`);
const url = process.argv[4] ?? 'http://localhost:5173/';
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const PORT = 9333;

fs.mkdirSync(path.dirname(out), { recursive: true });
// Scratch frames live next to the output, then get removed.
const work = fs.mkdtempSync(path.join(path.dirname(out), '.clip-work-'));
const framesDir = path.join(work, 'frames');
fs.mkdirSync(framesDir);

const chrome = spawn(
  CHROME,
  [
    '--headless=new',
    `--remote-debugging-port=${PORT}`,
    `--user-data-dir=${path.join(work, 'profile')}`,
    '--window-size=1280,720',
    '--no-first-run',
    '--no-default-browser-check',
    'about:blank',
  ],
  { stdio: 'ignore' },
);

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
let target: { webSocketDebuggerUrl: string } | undefined;
for (let i = 0; i < 50 && !target; i++) {
  await sleep(200);
  try {
    const list = (await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json()) as { type: string; webSocketDebuggerUrl: string }[];
    target = list.find((t) => t.type === 'page');
  } catch {
    // Chrome still starting.
  }
}
if (!target) {
  chrome.kill();
  throw new Error('Chrome did not start');
}

const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r) => ws.on('open', r));
let id = 0;
const pending = new Map<number, () => void>();
const send = (method: string, params: object = {}) =>
  new Promise<void>((resolve) => {
    const n = ++id;
    pending.set(n, resolve);
    ws.send(JSON.stringify({ id: n, method, params }));
  });
const frames: { file: string; ts: number }[] = [];
ws.on('message', (raw) => {
  const m = JSON.parse(String(raw));
  if (m.id && pending.has(m.id)) pending.get(m.id)!();
  if (m.method === 'Page.screencastFrame') {
    const file = path.join(framesDir, `f${String(frames.length).padStart(5, '0')}.jpg`);
    fs.writeFileSync(file, Buffer.from(m.params.data, 'base64'));
    frames.push({ file, ts: m.params.metadata.timestamp });
    ws.send(JSON.stringify({ id: ++id, method: 'Page.screencastFrameAck', params: { sessionId: m.params.sessionId } }));
  }
});

await send('Page.enable');
await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 720, deviceScaleFactor: 1, mobile: false });
await send('Page.navigate', { url });
await sleep(1500);
await send('Page.startScreencast', { format: 'jpeg', quality: 85, maxWidth: 1280, maxHeight: 720 });
await sleep(secs * 1000);
await send('Page.stopScreencast');
ws.close();
chrome.kill();

if (frames.length < 2) throw new Error('No frames captured');
// Concat list with real frame timings, so the clip plays at true speed.
const lines: string[] = [];
for (let i = 0; i < frames.length; i++) {
  const dur = i + 1 < frames.length ? frames[i + 1].ts - frames[i].ts : 1 / 30;
  lines.push(`file '${frames[i].file}'`, `duration ${dur.toFixed(4)}`);
}
lines.push(`file '${frames[frames.length - 1].file}'`);
const list = path.join(work, 'list.txt');
fs.writeFileSync(list, lines.join('\n'));
const ff = spawnSync(
  'ffmpeg',
  ['-loglevel', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', list, '-vf', 'fps=30,format=yuv420p', '-c:v', 'libx264', '-crf', '22', '-movflags', '+faststart', out],
  { stdio: 'inherit' },
);
fs.rmSync(work, { recursive: true, force: true });
if (ff.status !== 0) process.exit(ff.status ?? 1);
console.log(`Saved ${out} (${frames.length} frames)`);
process.exit(0);
