/**
 * Dev page: both mech schemes in every pose, large, for comparing against the
 * reference screenshots. Open /mech-preview.html on the dev server.
 */
import { AMMO_MAX, BOOST_MAX, DASH_SPEED, MAX_HP, MELEE_TIME } from '../sim/index.ts';
import type { PlayerState } from '../sim/index.ts';
import { animate, drawMech, newPose } from './mech.ts';
import type { MechPose } from './mech.ts';

const canvas = document.getElementById('c') as HTMLCanvasElement;
const g = canvas.getContext('2d')!;

const base = (slot: number): PlayerState => ({
  id: `p${slot}`,
  name: '',
  slot,
  x: 0,
  y: 0,
  vx: 0,
  vy: 0,
  facing: 1,
  aim: 0,
  hp: MAX_HP,
  boost: BOOST_MAX,
  overheated: false,
  grounded: true,
  dashing: false,
  hovering: false,
  locked: true,
  ammo: AMMO_MAX,
  fireCd: 0,
  meleeCd: 0,
  meleeT: 0,
  meleeHit: false,
  prevJump: false,
  prevMelee: false,
  wins: 0,
});

const POSES: { label: string; make: (p: PlayerState, t: number) => void }[] = [
  { label: 'idle', make: () => {} },
  { label: 'walk', make: (p) => (p.vx = 13) },
  { label: 'jump', make: (p) => ((p.grounded = false), (p.vy = 8)) },
  { label: 'hover, aim up', make: (p) => ((p.grounded = false), (p.hovering = true), (p.aim = 0.6)) },
  { label: 'dash', make: (p) => ((p.grounded = false), (p.dashing = true), (p.vx = DASH_SPEED)) },
  { label: 'slash', make: (p, t) => ((p.meleeT = MELEE_TIME * (1 - ((t * 1.2) % 1))), (p.aim = -0.3)) },
  { label: 'facing left', make: (p) => ((p.facing = -1), (p.aim = Math.PI - 0.2), (p.grounded = false), (p.vx = -8)) },
];

const poses = new Map<string, MechPose>();
let last = performance.now();

function frame(now: number): void {
  requestAnimationFrame(frame);
  const dt = Math.min(0.05, (now - last) / 1000);
  last = now;
  const dpr = window.devicePixelRatio || 1;
  const w = window.innerWidth;
  const h = window.innerHeight;
  if (canvas.width !== Math.round(w * dpr)) {
    canvas.width = Math.round(w * dpr);
    canvas.height = Math.round(h * dpr);
  }
  g.setTransform(dpr, 0, 0, dpr, 0, 0);
  const sky = g.createLinearGradient(0, 0, 0, h);
  sky.addColorStop(0, '#141a3e');
  sky.addColorStop(1, '#5d5592');
  g.fillStyle = sky;
  g.fillRect(0, 0, w, h);

  const cols = POSES.length;
  const cellW = w / cols;
  const cellH = h / 2 - 10;
  const ppm = Math.min(cellW / 7.5, cellH / 7.5);
  for (let slot = 0; slot < 2; slot++) {
    POSES.forEach((pose, i) => {
      const p = base(slot);
      pose.make(p, now / 1000);
      const key = `${slot}-${i}`;
      let mp = poses.get(key);
      if (!mp) {
        mp = newPose();
        poses.set(key, mp);
      }
      animate(mp, p, dt);
      const cx = cellW * (i + 0.5);
      const floor = cellH * (slot + 1) - 26;
      g.fillStyle = 'rgba(127, 227, 255, 0.4)';
      g.fillRect(cx - cellW * 0.4, floor, cellW * 0.8, 2);
      drawMech(g, p, mp, cx, floor - (p.grounded ? 0 : ppm * 0.6), ppm, now);
      g.fillStyle = '#cfe3f5';
      g.textAlign = 'center';
      g.fillText(pose.label, cx, floor + 16);
    });
  }
}
requestAnimationFrame(frame);
