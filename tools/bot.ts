/**
 * Headless second player. Connects over the same WebSocket a browser tab uses,
 * so it exercises the real network path. Useful for solo practice and testing.
 *
 *   npm run bot                         # joins ws://localhost:5173/ws as "Bot"
 *   npm run bot -- ws://host:port/ws Name
 */
import { WebSocket } from 'ws';
import type { GameState, Input } from '../src/sim/index.ts';
import type { ServerMessage } from '../src/sim/protocol.ts';

const url = process.argv[2] ?? 'ws://localhost:5173/ws';
const name = process.argv[3] ?? 'Bot';
const ws = new WebSocket(url);
let id = '';
let state: GameState | null = null;
let seq = 0;
let stuck = 0;

ws.on('open', () => ws.send(JSON.stringify({ t: 'join', name })));
ws.on('message', (data) => {
  const msg = JSON.parse(String(data)) as ServerMessage;
  if (msg.t === 'welcome') {
    id = msg.id;
    console.log(msg.slot === null ? 'Both slots taken, bot is spectating.' : `${name} joined in slot ${msg.slot + 1}.`);
  } else {
    state = msg.s;
  }
});
ws.on('close', () => {
  console.log('Disconnected.');
  process.exit(0);
});

// Keeps a middle distance, weaves up and down with dashes, fires in range, slashes up close.
setInterval(() => {
  if (!state || !id) return;
  const me = state.players.find((p) => p.id === id);
  const foe = state.players.find((p) => p.id !== id);
  if (!me) return;
  const t = state.tick / 60 + (me.slot ? 1.7 : 0);
  const dx = foe ? foe.x - me.x : 0;
  const dist = foe ? Math.hypot(dx, foe.y - me.y) : 99;
  const toward = Math.sign(dx) || 1;
  const close = dist < 14;
  let moveX = dist > 35 ? toward : close ? -toward : Math.sin(t * 1.3) > 0 ? toward : -toward;
  if (Math.sin(t * 0.37) > 0.8) moveX = toward; // occasional charge
  const weave = Math.sin(t * 1.1);
  // Walking into a building: climb it.
  const blocked = moveX !== 0 && Math.abs(me.vx) < 1 && state.phase === 'fighting';
  if (blocked) stuck += 1;
  else stuck = Math.max(0, stuck - 2);
  const input: Input = {
    seq: ++seq,
    moveX,
    moveY: weave > 0.3 ? 1 : weave < -0.6 ? -1 : 0,
    aimX: foe?.x ?? 0,
    aimY: foe?.y ?? 0,
    lock: true,
    boost: !me.overheated && me.boost > 35 && Math.sin(t * 2.3) > 0.2,
    jump: stuck > 6 || (me.grounded && Math.sin(t * 0.9) > 0.6) || (!me.grounded && me.boost > 50 && weave > 0),
    fire: dist < 80,
    melee: dist < 12 && Math.sin(t * 3) > 0,
  };
  ws.send(JSON.stringify({ t: 'input', input }));
}, 1000 / 60);
