import { CHEST_Y, DT, MUZZLE_REACH, MUZZLE_Y } from '../sim/index.ts';
import type { Bullet, GameState, PlayerState } from '../sim/index.ts';
import type { ClientMessage, ServerMessage } from '../sim/protocol.ts';
import { Camera } from './camera.ts';
import { drawBullets, Effects } from './effects.ts';
import { Hud } from './hud.ts';
import { Controls } from './input.ts';
import { animate, drawMech, newPose } from './mech.ts';
import type { MechPose } from './mech.ts';
import { drawArena, drawBackdrop } from './stage.ts';

const canvas = document.getElementById('view') as HTMLCanvasElement;
const g = canvas.getContext('2d')!;
const cam = new Camera();
function resize(): void {
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  canvas.width = Math.round(window.innerWidth * dpr);
  canvas.height = Math.round(window.innerHeight * dpr);
  g.setTransform(dpr, 0, 0, dpr, 0, 0);
  cam.resize(window.innerWidth, window.innerHeight);
}
window.addEventListener('resize', resize);
resize();

const effects = new Effects();
const hud = new Hud();
const controls = new Controls(canvas);
controls.onToggleHelp = () => hud.toggleHelp();
const poses = new Map<string, MechPose>();
const SLOT_GLOW = ['95, 216, 255', '255, 122, 74'];

// Networking. The server is authoritative; this tab sends input and draws snapshots.
let myId: string | null = null;
let spectating = false;
let prev: GameState | null = null;
let curr: GameState | null = null;
let currAt = 0;

const params = new URLSearchParams(location.search);
const ws = new WebSocket(`${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/ws`);
const send = (m: ClientMessage) => {
  if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(m));
};
ws.addEventListener('open', () => send({ t: 'join', name: params.get('name') ?? '' }));
ws.addEventListener('close', () => {
  hud.disconnected = true;
});
ws.addEventListener('message', (ev) => {
  const msg = JSON.parse(ev.data as string) as ServerMessage;
  if (msg.t === 'welcome') {
    myId = msg.id;
    spectating = msg.slot === null;
  } else if (msg.t === 'snap') {
    prev = curr;
    curr = msg.s;
    currAt = performance.now();
    handleEvents(msg.s);
  }
});

// Read-only handle for debugging in the browser console.
Object.defineProperty(window, 'raycrash', {
  value: Object.freeze({
    get state() {
      return curr;
    },
    get myId() {
      return myId;
    },
  }),
});

function handleEvents(s: GameState): void {
  for (const e of s.events) {
    if (e.type === 'hit') {
      if (e.kind === 'melee') effects.slashHit(e.x, e.y);
      else effects.gunHit(e.x, e.y);
      const pose = poses.get(e.target);
      if (pose) pose.flash = e.kind === 'melee' ? 1 : Math.max(pose.flash, 0.3);
      hud.pop(e, cam);
    } else if (e.type === 'fire') {
      const p = s.players.find((q) => q.id === e.owner);
      if (p) effects.muzzle(p.x + Math.cos(p.aim) * MUZZLE_REACH, p.y + MUZZLE_Y + Math.sin(p.aim) * MUZZLE_REACH);
    } else if (e.type === 'round' && e.phase === 'ended' && e.winner) {
      const loser = s.players.find((p) => p.id !== e.winner);
      if (loser) effects.knockout(loser.x, loser.y + 2);
    }
  }
}

let last = performance.now();
let lastSend = 0;

function frame(now: number): void {
  requestAnimationFrame(frame);
  const dt = Math.min(0.05, (now - last) / 1000);
  last = now;
  const time = now / 1000;

  let players: PlayerState[] = [];
  let me: PlayerState | undefined;
  let other: PlayerState | undefined;
  let alpha = 1;
  if (curr) {
    // Draw one tick behind, blending the last two snapshots.
    alpha = Math.min(1, Math.max(0, (now - currAt) / (DT * 1000)));
    const before = new Map((prev?.players ?? []).map((p) => [p.id, p]));
    players = curr.players.map((p) => blend(before.get(p.id), p, alpha));
    me = spectating ? players.find((p) => p.slot === 0) : players.find((p) => p.id === myId);
    other = me ? players.find((p) => p.id !== me!.id) : undefined;

    // Camera sits on you, pulled part way toward the opponent but never far enough to lose you.
    if (me) {
      const maxX = (cam.w / cam.ppm) * 0.28;
      const maxY = (cam.h / cam.ppm) * 0.22;
      const ox = other ? clamp((other.x - me.x) * 0.35, -maxX, maxX) : 0;
      const oy = other ? clamp((other.y - me.y) * 0.3, -maxY, maxY) : 0;
      cam.follow(me.x + ox, me.y + CHEST_Y + oy + 3, dt);
    }

    if (!spectating && myId && now - lastSend >= 1000 / 60 - 1) {
      send({ t: 'input', input: controls.sample(cam.wx(controls.mouseX), cam.wy(controls.mouseY)) });
      lastSend = now;
    }
  }

  drawBackdrop(g, cam, time);
  drawArena(g, cam, time);

  for (const p of players) {
    let pose = poses.get(p.id);
    if (!pose) {
      pose = newPose();
      poses.set(p.id, pose);
    }
    animate(pose, p, dt);
    if ((p.dashing || p.hovering) && Math.random() < 0.7) {
      effects.trail(p.x - p.facing * 1.4, p.y + 2.6, SLOT_GLOW[p.slot % 2]);
    }
  }
  for (const id of poses.keys()) if (!players.some((p) => p.id === id)) poses.delete(id);

  // Opponent first so your own mech is drawn on top.
  const order = [...players].sort((a, b) => (a.id === me?.id ? 1 : 0) - (b.id === me?.id ? 1 : 0));
  for (const p of order) {
    drawMech(g, p, poses.get(p.id)!, cam.sx(p.x), cam.sy(p.y), cam.ppm, now);
    drawNameTag(p, p.id === me?.id);
  }
  if (curr) drawBullets(g, cam, curr.bullets, new Map<number, Bullet>((prev?.bullets ?? []).map((b) => [b.id, b])), alpha);
  effects.update(dt);
  effects.draw(g, cam);

  if (curr) hud.update(curr, me, other, spectating, cam, controls.mouseX, controls.mouseY);
}
requestAnimationFrame(frame);

function drawNameTag(p: PlayerState, mine: boolean): void {
  const x = cam.sx(p.x);
  const y = cam.sy(p.y + 4.9);
  g.font = '600 11px "Helvetica Neue", Arial, sans-serif';
  g.textAlign = 'center';
  g.fillStyle = mine ? '#7fe3ff' : '#ff8a7a';
  g.fillText(p.name, x, y);
}

function clamp(v: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, v));
}

function blend(a: PlayerState | undefined, b: PlayerState, t: number): PlayerState {
  if (!a) return b;
  const da = Math.atan2(Math.sin(b.aim - a.aim), Math.cos(b.aim - a.aim));
  return {
    ...b,
    x: a.x + (b.x - a.x) * t,
    y: a.y + (b.y - a.y) * t,
    vx: a.vx + (b.vx - a.vx) * t,
    vy: a.vy + (b.vy - a.vy) * t,
    aim: a.aim + da * t,
    boost: a.boost + (b.boost - a.boost) * t,
  };
}
