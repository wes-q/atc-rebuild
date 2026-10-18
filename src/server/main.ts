import { randomUUID } from 'node:crypto';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createServer as createVite } from 'vite';
import { WebSocket, WebSocketServer } from 'ws';
import { addPlayer, createState, DT, removePlayer, step } from '../sim/index.ts';
import type { Input } from '../sim/index.ts';
import { sanitizeInput, sanitizeName } from '../sim/protocol.ts';
import type { ClientMessage, ServerMessage } from '../sim/protocol.ts';

const PORT = Number(process.env.PORT ?? 5173);
const HOST = process.env.HOST ?? '127.0.0.1';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

// One process serves the client (through Vite) and the game socket at /ws.
const httpServer = http.createServer();
const vite = await createVite({
  configFile: false,
  root: path.join(root, 'src/client'),
  appType: 'spa',
  clearScreen: false,
  server: {
    middlewareMode: true,
    // Live-reload socket. Override to run a second server side by side.
    hmr: { port: Number(process.env.HMR_PORT ?? 24678) },
    // Serve only the game's own source. Keeps the archive folder and anything else in the
    // project off the network when the server listens on the LAN.
    fs: { allow: [path.join(root, 'src')] },
  },
});
httpServer.on('request', (req, res) => vite.middlewares(req, res));

const wss = new WebSocketServer({ noServer: true });
httpServer.on('upgrade', (req, socket, head) => {
  if (new URL(req.url ?? '/', 'http://x').pathname !== '/ws') return;
  wss.handleUpgrade(req, socket, head, (ws) => wss.emit('connection', ws, req));
});

const state = createState(Date.now());
const inputs: Record<string, Input> = {};
const ids = new Map<WebSocket, string>();

function send(ws: WebSocket, msg: ServerMessage): void {
  if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(msg));
}

wss.on('connection', (ws) => {
  const id = randomUUID().slice(0, 8);
  ids.set(ws, id);

  ws.on('message', (data) => {
    let msg: ClientMessage;
    try {
      msg = JSON.parse(String(data));
    } catch {
      return;
    }
    if (msg.t === 'join') {
      if (state.players.some((p) => p.id === id)) return;
      const slot = state.players.some((p) => p.slot === 0) ? 2 : 1;
      const player = addPlayer(state, id, sanitizeName(msg.name, `Player ${slot}`));
      send(ws, { t: 'welcome', id, slot: player ? player.slot : null });
      console.log(player ? `${player.name} joined in slot ${player.slot + 1}` : `spectator ${id} joined`);
    } else if (msg.t === 'input') {
      inputs[id] = sanitizeInput(msg.input);
    }
  });

  ws.on('close', () => {
    const p = state.players.find((q) => q.id === id);
    if (p) console.log(`${p.name} left`);
    removePlayer(state, id);
    delete inputs[id];
    ids.delete(ws);
  });
});

// Fixed 60 Hz simulation. Every tick is broadcast so clients never miss events.
let last = performance.now();
let acc = 0;
setInterval(() => {
  const now = performance.now();
  acc += (now - last) / 1000;
  last = now;
  let steps = 0;
  while (acc >= DT && steps < 5) {
    step(state, inputs);
    const msg = JSON.stringify({ t: 'snap', s: state } satisfies ServerMessage);
    for (const ws of ids.keys()) if (ws.readyState === WebSocket.OPEN) ws.send(msg);
    acc -= DT;
    steps++;
  }
  if (steps === 5) acc = 0;
}, 4);

httpServer.listen(PORT, HOST, () => {
  console.log(`\nATC Raycrash server on http://localhost:${PORT}`);
  if (HOST === '0.0.0.0') {
    for (const list of Object.values(os.networkInterfaces())) {
      for (const a of list ?? []) {
        if (a.family === 'IPv4' && !a.internal) console.log(`  LAN: http://${a.address}:${PORT}`);
      }
    }
  }
  console.log('Open it in two browser tabs to play. Ctrl+C to stop.\n');
});

process.on('SIGINT', async () => {
  await vite.close();
  process.exit(0);
});
