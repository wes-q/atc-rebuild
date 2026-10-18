import { DASH_SPEED, MELEE_TIME } from '../sim/index.ts';
import type { PlayerState } from '../sim/index.ts';

/**
 * Side-view mech in the style of the original Raycrash frames: slim Gundam-like build,
 * big shoulder blocks, V-fin head, skirt armour, heavy lower legs and twin wing binders.
 * Drawn from shaded polygons so it can be swapped for real sprites later.
 */

interface Scheme {
  armor: string; // main plates
  panel: string; // secondary plates
  frame: string; // inner frame and joints
  accent: string; // fins, vents, trim
  visor: string;
  wing: string;
  wingEdge: string;
  glow: string; // thruster colour
  rifle: string;
}

const SCHEMES: Scheme[] = [
  // Player 1: white with blue-violet panels and gold, like the hero mech in screenshot 05.
  {
    armor: '#eef2f8',
    panel: '#4257c9',
    frame: '#454d60',
    accent: '#f2b233',
    visor: '#7ef7ff',
    wing: '#2c3656',
    wingEdge: '#9bb0ff',
    glow: '#6fd6ff',
    rifle: '#3a3f4c',
  },
  // Player 2: teal grey with orange, like the mechs in screenshots 02 and 07.
  {
    armor: '#9db7b5',
    panel: '#2f6670',
    frame: '#2c3438',
    accent: '#ff8a2a',
    visor: '#ff4a4a',
    wing: '#3a4648',
    wingEdge: '#ffb070',
    glow: '#ff9a5a',
    rifle: '#2a2e33',
  },
];

type Pt = [number, number];

const MODEL_SCALE = 0.9;
const LEG_EXTRA = 0.35;

export interface MechPose {
  walk: number;
  thighF: number;
  thighB: number;
  kneeF: number;
  kneeB: number;
  lean: number;
  wing: number;
  flash: number;
}

export function newPose(): MechPose {
  return { walk: 0, thighF: 0, thighB: 0, kneeF: 0.15, kneeB: 0.15, lean: 0, wing: 0, flash: 0 };
}

/** Advances the animation pose from the latest state. */
export function animate(pose: MechPose, p: PlayerState, dt: number): void {
  const vf = p.vx * p.facing; // forward speed in the mech's own frame
  let tf = 0.05;
  let tb = -0.05;
  let kf = 0.15;
  let kb = 0.2;
  if (p.dashing) {
    tf = -0.15;
    tb = -0.65;
    kf = 0.7;
    kb = 1.0;
  } else if (!p.grounded) {
    tf = 0.75;
    tb = -0.25;
    kf = 1.25;
    kb = 0.45;
  } else if (Math.abs(p.vx) > 0.5) {
    pose.walk += dt * Math.abs(p.vx) * 0.75;
    const s = Math.sin(pose.walk);
    const dir = vf >= 0 ? 1 : -1;
    tf = s * 0.55 * dir;
    tb = -s * 0.55 * dir;
    kf = Math.max(0.1, -Math.cos(pose.walk) * 0.9);
    kb = Math.max(0.1, Math.cos(pose.walk) * 0.9);
  }
  const k = 1 - Math.exp(-14 * dt);
  pose.thighF += (tf - pose.thighF) * k;
  pose.thighB += (tb - pose.thighB) * k;
  pose.kneeF += (kf - pose.kneeF) * k;
  pose.kneeB += (kb - pose.kneeB) * k;
  // Lean into the direction of travel. Negative tilts the top forward.
  const want = -(vf / DASH_SPEED) * (p.dashing ? 0.6 : 0.2) + (p.dashing ? (p.vy / DASH_SPEED) * 0.2 : 0);
  pose.lean += (want - pose.lean) * (1 - Math.exp(-10 * dt));
  // Wings spread under thrust and fold on the ground.
  const wingWant = p.dashing ? 1 : p.hovering ? 0.7 : p.grounded ? 0 : 0.4;
  pose.wing += (wingWant - pose.wing) * (1 - Math.exp(-8 * dt));
  pose.flash = Math.max(0, pose.flash - dt * 6);
}

/** Draws the mech with its feet at (sx, sy) in screen pixels. */
export function drawMech(g: CanvasRenderingContext2D, p: PlayerState, pose: MechPose, sx: number, sy: number, ppm: number, now: number): void {
  if (p.hp <= 0 && Math.floor(now / 70) % 2 === 0) return;
  const c = SCHEMES[p.slot % SCHEMES.length];
  const d = new Painter(g);

  g.save();
  g.translate(sx, sy);
  // Local frame: model units, x toward facing, y up. The model is drawn a touch large and
  // scaled down so its proportions stay slim while it fits the 4 m hitbox.
  g.scale(ppm * p.facing * MODEL_SCALE, -ppm * MODEL_SCALE);
  g.lineJoin = 'round';

  const thrust = p.dashing ? 1 : p.hovering ? 0.7 : 0;
  // Gun aim in the mech's own frame, so it points at the target whichever way it faces.
  const aimLocal = Math.atan2(Math.sin(p.aim), Math.cos(p.aim) * p.facing);
  const slashT = p.meleeT > 0 ? 1 - p.meleeT / MELEE_TIME : -1;

  // Everything above the hips leans together.
  const HIP: Pt = [0, 2.0 + LEG_EXTRA];
  g.save();
  g.translate(HIP[0], HIP[1]);
  g.rotate(pose.lean);
  g.translate(-HIP[0], -HIP[1]);
  // Long legs lift the whole upper body.
  g.translate(0, LEG_EXTRA);

  // Thruster flame from the backpack, trailing opposite the motion.
  if (thrust > 0) {
    const ang = p.dashing ? Math.atan2(-p.vy, -Math.abs(p.vx) || -1) - pose.lean : -2.2;
    d.flame(-1.0, 2.55, ang, (2.0 + Math.random() * 0.8) * thrust, 0.32, c.glow);
  }

  // Far wing, far arm and far leg sit behind the body, darker.
  const wingBase = 2.45 - pose.wing * 0.45;
  drawWing(d, c, wingBase + 0.28, true);
  drawBladeArm(d, c, slashT);
  drawLeg(d, c, pose.thighB, pose.kneeB, true);

  // Rear skirt, backpack, waist, chest.
  d.poly([[-0.55, 2.25], [-0.12, 2.25], [-0.22, 1.62], [-0.72, 1.78]], c.panel);
  d.poly([[-0.5, 2.45], [-1.05, 2.55], [-1.15, 3.25], [-0.85, 3.42], [-0.45, 3.35]], c.frame);
  d.poly([[-1.12, 2.45], [-0.82, 2.45], [-0.85, 2.62], [-1.12, 2.62]], c.accent);
  d.poly([[-0.32, 1.98], [0.3, 1.98], [0.34, 2.32], [-0.36, 2.32]], c.frame);
  d.poly([[-0.1, 2.0], [0.22, 2.0], [0.28, 2.28], [-0.1, 2.3]], c.accent);
  d.poly([[-0.55, 2.3], [0.45, 2.32], [0.78, 2.88], [0.62, 3.36], [-0.48, 3.42], [-0.7, 2.92]], c.armor);
  d.poly([[0.08, 2.5], [0.74, 2.86], [0.62, 3.3], [0.06, 3.24]], c.panel);
  d.poly([[0.32, 2.9], [0.6, 2.95], [0.56, 3.12], [0.3, 3.08]], c.accent);
  d.poly([[-0.48, 2.36], [0.4, 2.38], [0.46, 2.5], [-0.5, 2.48]], c.frame);

  // Near wing over the backpack.
  drawWing(d, c, wingBase, false);

  // Head: neck, helmet, face mask, visor, V-fin.
  d.poly([[-0.12, 3.4], [0.14, 3.4], [0.14, 3.62], [-0.12, 3.62]], c.frame);
  d.poly([[-0.26, 3.56], [0.26, 3.58], [0.44, 3.7], [0.42, 3.92], [0.2, 4.1], [-0.2, 4.09], [-0.32, 3.82]], c.armor);
  d.poly([[-0.3, 3.66], [-0.04, 3.66], [-0.06, 3.9], [-0.28, 3.88]], c.panel);
  d.poly([[0.2, 3.58], [0.44, 3.7], [0.42, 3.78], [0.18, 3.74]], c.panel);
  d.glowRect(0.22, 3.81, 0.44, 3.87, c.visor);
  d.poly([[0.12, 3.97], [0.26, 4.01], [0.02, 4.62], [-0.05, 4.59]], c.accent);
  d.poly([[0.2, 3.99], [0.32, 3.97], [0.62, 4.4], [0.56, 4.44]], c.accent);

  // Near leg, then the side skirt that hangs over its thigh.
  drawLeg(d, c, pose.thighF, pose.kneeF, false);
  d.poly([[0.12, 2.22], [0.62, 2.16], [0.56, 1.58], [0.22, 1.66]], c.armor);
  d.poly([[0.42, 2.0], [0.6, 1.98], [0.57, 1.62], [0.46, 1.66]], c.panel);
  g.save();
  g.translate(0, 2.2);
  g.rotate(pose.thighF * 0.5);
  d.poly([[-0.34, 0.06], [0.3, 0.06], [0.24, -0.66], [-0.3, -0.7]], c.armor);
  d.poly([[-0.34, -0.42], [0.27, -0.42], [0.24, -0.66], [-0.3, -0.7]], c.panel);
  g.restore();

  // Big shoulder block.
  d.poly([[-0.5, 2.92], [0.42, 2.9], [0.56, 3.38], [0.34, 3.6], [-0.4, 3.6], [-0.58, 3.34]], c.armor);
  d.poly([[-0.55, 3.1], [0.5, 3.1], [0.53, 3.24], [-0.57, 3.26]], c.panel);
  d.poly([[0.3, 3.4], [0.5, 3.36], [0.42, 3.54], [0.28, 3.56]], c.accent);

  // Gun arm and rifle.
  drawGunArm(d, c, aimLocal);

  if (pose.flash > 0) d.flash(pose.flash);
  g.restore();
  g.restore();
}

function drawWing(d: Painter, c: Scheme, ang: number, far: boolean): void {
  const g = d.g;
  g.save();
  g.translate(-0.8, 3.15);
  g.rotate(ang);
  const wing = far ? tone(c.wing, -0.3) : c.wing;
  d.poly([[0, -0.2], [2.5, -0.1], [3.05, 0.22], [2.7, 0.32], [0.15, 0.24]], wing);
  d.poly([[0.6, 0.1], [2.65, 0.17], [2.95, 0.24], [0.6, 0.24]], far ? tone(c.wingEdge, -0.35) : c.wingEdge);
  d.poly([[-0.1, -0.28], [0.55, -0.26], [0.55, 0.3], [-0.1, 0.3]], far ? tone(c.frame, -0.3) : c.frame);
  g.restore();
}

function drawLeg(d: Painter, c: Scheme, thigh: number, knee: number, far: boolean): void {
  const g = d.g;
  const dk = far ? -0.32 : 0;
  g.save();
  g.translate(0, 2.0);
  g.rotate(thigh);
  // Thigh.
  d.poly([[-0.24, 0.05], [0.24, 0.05], [0.21, -1.1], [-0.21, -1.1]], tone(c.frame, dk + 0.15));
  d.poly([[-0.05, -0.15], [0.26, -0.18], [0.23, -0.9], [-0.04, -0.87]], tone(c.armor, dk - 0.1));
  g.translate(0, -1.1);
  g.rotate(-knee);
  // Lower leg: heavy armoured shin with a pointed knee guard.
  d.poly([[-0.3, 0.08], [0.24, 0.08], [0.37, -0.66], [0.3, -1.08], [-0.36, -1.08], [-0.43, -0.48]], tone(c.armor, dk));
  d.poly([[0.12, 0.24], [0.39, 0.0], [0.35, -0.5], [0.12, -0.36]], tone(c.panel, dk));
  d.poly([[-0.43, -0.42], [-0.2, -0.36], [-0.24, -0.98], [-0.38, -1.03]], tone(c.panel, dk));
  // Foot.
  d.poly([[-0.42, -1.03], [0.38, -1.03], [0.74, -1.19], [0.7, -1.25], [-0.46, -1.25]], tone(c.frame, dk + 0.1));
  d.poly([[0.2, -1.05], [0.52, -1.12], [0.54, -1.19], [0.2, -1.19]], tone(c.accent, dk));
  g.restore();
}

function drawGunArm(d: Painter, c: Scheme, aim: number): void {
  const g = d.g;
  g.save();
  g.translate(0.0, 3.25);
  g.rotate(aim);
  // Upper arm, elbow, armoured forearm, fist.
  d.poly([[-0.05, -0.17], [0.72, -0.15], [0.72, 0.15], [-0.05, 0.17]], c.frame);
  d.poly([[0.62, -0.25], [1.42, -0.22], [1.48, 0.12], [0.62, 0.24]], c.armor);
  d.poly([[0.62, 0.05], [1.45, 0.05], [1.48, 0.12], [0.62, 0.24]], c.panel);
  // Rifle: stock, body, scope, magazine, long barrel.
  d.poly([[0.95, -0.3], [2.35, -0.3], [2.4, 0.0], [1.0, 0.02]], c.rifle);
  d.poly([[1.35, 0.02], [2.05, 0.02], [2.0, 0.16], [1.4, 0.16]], tone(c.rifle, 0.25));
  d.poly([[1.55, -0.3], [1.85, -0.3], [1.8, -0.62], [1.58, -0.6]], tone(c.rifle, 0.1));
  d.poly([[2.35, -0.2], [3.1, -0.18], [3.1, -0.08], [2.35, -0.06]], c.rifle);
  d.poly([[1.0, -0.12], [2.3, -0.12], [2.3, -0.06], [1.0, -0.06]], c.accent);
  d.poly([[1.2, -0.08], [1.5, -0.1], [1.5, 0.12], [1.2, 0.1]], c.frame);
  g.restore();
}

function drawBladeArm(d: Painter, c: Scheme, slashT: number): void {
  const g = d.g;
  // Hangs relaxed, or sweeps from overhead to low in front during a slash.
  let ang = -1.35;
  if (slashT >= 0) {
    const t = Math.min(1, slashT / 0.6);
    ang = 2.2 + (-1.2 - 2.2) * (1 - (1 - t) * (1 - t));
  }
  // Slash arc behind the blade.
  if (slashT >= 0 && slashT < 0.85) {
    g.save();
    g.globalCompositeOperation = 'lighter';
    g.fillStyle = `rgba(255, 120, 220, ${0.45 * (1 - slashT)})`;
    g.beginPath();
    g.arc(-0.1, 3.25, 5.1, Math.max(-1.2, ang), 2.2);
    g.arc(-0.1, 3.25, 3.6, 2.2, Math.max(-1.2, ang), true);
    g.closePath();
    g.fill();
    g.restore();
  }
  g.save();
  g.translate(-0.1, 3.25);
  g.rotate(ang);
  d.poly([[-0.05, -0.15], [0.7, -0.14], [0.7, 0.14], [-0.05, 0.15]], tone(c.frame, -0.3));
  d.poly([[0.62, -0.22], [1.38, -0.2], [1.42, 0.2], [0.62, 0.22]], tone(c.armor, -0.32));
  d.poly([[1.38, -0.08], [1.75, -0.08], [1.75, 0.08], [1.38, 0.08]], tone(c.frame, -0.1));
  if (slashT >= 0) {
    g.save();
    g.globalCompositeOperation = 'lighter';
    g.fillStyle = 'rgba(255, 110, 210, 0.95)';
    g.fillRect(1.75, -0.1, 3.3, 0.2);
    g.fillStyle = 'rgba(255, 255, 255, 0.9)';
    g.fillRect(1.75, -0.04, 3.1, 0.08);
    g.restore();
  }
  g.restore();
}

/** Small helper that fills polygons with a top-lit gradient and a dark outline. */
class Painter {
  g: CanvasRenderingContext2D;

  constructor(g: CanvasRenderingContext2D) {
    this.g = g;
  }

  poly(pts: Pt[], base: string): void {
    const g = this.g;
    let y0 = Infinity;
    let y1 = -Infinity;
    for (const [, y] of pts) {
      y0 = Math.min(y0, y);
      y1 = Math.max(y1, y);
    }
    // Local y is up, so the highlight goes on the larger y.
    const grad = g.createLinearGradient(0, y1, 0, y0);
    grad.addColorStop(0, tone(base, 0.3));
    grad.addColorStop(0.45, base);
    grad.addColorStop(1, tone(base, -0.3));
    g.beginPath();
    g.moveTo(pts[0][0], pts[0][1]);
    for (let i = 1; i < pts.length; i++) g.lineTo(pts[i][0], pts[i][1]);
    g.closePath();
    g.fillStyle = grad;
    g.fill();
    g.lineWidth = 0.045;
    g.strokeStyle = 'rgba(12, 16, 30, 0.85)';
    g.stroke();
  }

  glowRect(x0: number, y0: number, x1: number, y1: number, color: string): void {
    const g = this.g;
    g.save();
    g.globalCompositeOperation = 'lighter';
    g.fillStyle = color;
    g.fillRect(x0, y0, x1 - x0, y1 - y0);
    g.globalAlpha = 0.35;
    g.fillRect(x0 - 0.05, y0 - 0.05, x1 - x0 + 0.1, y1 - y0 + 0.1);
    g.restore();
  }

  flame(x: number, y: number, ang: number, len: number, width: number, color: string): void {
    const g = this.g;
    g.save();
    g.globalCompositeOperation = 'lighter';
    g.translate(x, y);
    g.rotate(ang);
    const grad = g.createLinearGradient(0, 0, len, 0);
    grad.addColorStop(0, '#ffffff');
    grad.addColorStop(0.2, color);
    grad.addColorStop(1, 'rgba(0,0,0,0)');
    g.fillStyle = grad;
    g.beginPath();
    g.moveTo(0, -width);
    g.quadraticCurveTo(len * 0.4, -width * 0.9, len, 0);
    g.quadraticCurveTo(len * 0.4, width * 0.9, 0, width);
    g.closePath();
    g.fill();
    g.restore();
  }

  flash(amount: number): void {
    const g = this.g;
    g.save();
    g.globalCompositeOperation = 'lighter';
    const fl = g.createRadialGradient(0, 2.7, 0, 0, 2.7, 2.3);
    fl.addColorStop(0, `rgba(255, 240, 220, ${amount * 0.45})`);
    fl.addColorStop(1, 'rgba(255, 240, 220, 0)');
    g.fillStyle = fl;
    g.beginPath();
    g.arc(0, 2.7, 2.3, 0, Math.PI * 2);
    g.fill();
    g.restore();
  }
}

const toneCache = new Map<string, string>();

/** Lightens (f > 0) toward white or darkens (f < 0) toward black. */
function tone(hex: string, f: number): string {
  const key = hex + f;
  const hit = toneCache.get(key);
  if (hit) return hit;
  let rgb: number[];
  if (hex.startsWith('#')) {
    const n = parseInt(hex.slice(1), 16);
    rgb = [(n >> 16) & 255, (n >> 8) & 255, n & 255];
  } else {
    rgb = (hex.match(/\d+/g) ?? ['0', '0', '0']).slice(0, 3).map(Number);
  }
  const ch = rgb.map((v) =>
    Math.round(f >= 0 ? v + (255 - v) * f : v * (1 + f)),
  );
  const out = `rgb(${ch[0]}, ${ch[1]}, ${ch[2]})`;
  toneCache.set(key, out);
  return out;
}
