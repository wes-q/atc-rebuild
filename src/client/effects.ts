import type { Bullet } from '../sim/index.ts';
import type { Camera } from './camera.ts';

/** World-space particles: sparks, glows and rings. Drawn additively. */
interface Particle {
  kind: 'spark' | 'glow' | 'ring';
  x: number;
  y: number;
  vx: number;
  vy: number;
  t: number;
  life: number;
  size: number;
  color: string;
}

export class Effects {
  private parts: Particle[] = [];

  private add(p: Omit<Particle, 't'>): void {
    if (this.parts.length < 900) this.parts.push({ ...p, t: 0 });
  }

  burst(x: number, y: number, color: string, count: number, speed: number, size: number, life: number): void {
    for (let i = 0; i < count; i++) {
      const a = Math.random() * Math.PI * 2;
      const s = speed * (0.4 + Math.random() * 0.8);
      this.add({ kind: 'spark', x, y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, life: life * (0.6 + Math.random() * 0.6), size, color });
    }
  }

  glow(x: number, y: number, color: string, size: number, life: number): void {
    this.add({ kind: 'glow', x, y, vx: 0, vy: 0, life, size, color });
  }

  ring(x: number, y: number, color: string, size: number, life: number): void {
    this.add({ kind: 'ring', x, y, vx: 0, vy: 0, life, size, color });
  }

  /** Faint afterimage left behind a dashing or hovering mech. */
  trail(x: number, y: number, color: string): void {
    this.add({ kind: 'glow', x, y, vx: 0, vy: -2, life: 0.25, size: 0.9, color });
  }

  gunHit(x: number, y: number): void {
    this.glow(x, y, '255, 200, 120', 1.6, 0.18);
    this.burst(x, y, '255, 220, 150', 5, 18, 0.5, 0.18);
  }

  slashHit(x: number, y: number): void {
    this.glow(x, y, '255, 110, 210', 6, 0.4);
    this.ring(x, y, '255, 150, 230', 6, 0.35);
    this.burst(x, y, '255, 170, 235', 18, 40, 1.2, 0.35);
    this.burst(x, y, '255, 255, 255', 8, 30, 0.8, 0.25);
  }

  knockout(x: number, y: number): void {
    this.glow(x, y, '255, 150, 70', 10, 0.8);
    this.glow(x, y, '255, 255, 255', 5, 0.3);
    this.ring(x, y, '255, 190, 120', 12, 0.6);
    this.burst(x, y, '255, 180, 90', 40, 45, 1.4, 0.8);
  }

  muzzle(x: number, y: number): void {
    this.glow(x, y, '255, 230, 170', 1.1, 0.06);
  }

  update(dt: number): void {
    this.parts = this.parts.filter((p) => {
      p.t += dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vx *= 1 - 3 * dt;
      p.vy *= 1 - 3 * dt;
      return p.t < p.life;
    });
  }

  draw(g: CanvasRenderingContext2D, cam: Camera): void {
    g.save();
    g.globalCompositeOperation = 'lighter';
    for (const p of this.parts) {
      const k = p.t / p.life;
      const a = 1 - k;
      const sx = cam.sx(p.x);
      const sy = cam.sy(p.y);
      if (p.kind === 'spark') {
        g.strokeStyle = `rgba(${p.color}, ${a})`;
        g.lineWidth = Math.max(1, p.size * cam.ppm * 0.15);
        g.beginPath();
        g.moveTo(sx, sy);
        g.lineTo(sx - p.vx * cam.ppm * 0.03, sy + p.vy * cam.ppm * 0.03);
        g.stroke();
      } else if (p.kind === 'glow') {
        const r = p.size * cam.ppm * (0.6 + k * 0.6);
        const grad = g.createRadialGradient(sx, sy, 0, sx, sy, r);
        grad.addColorStop(0, `rgba(${p.color}, ${a})`);
        grad.addColorStop(1, `rgba(${p.color}, 0)`);
        g.fillStyle = grad;
        g.beginPath();
        g.arc(sx, sy, r, 0, Math.PI * 2);
        g.fill();
      } else {
        g.strokeStyle = `rgba(${p.color}, ${a})`;
        g.lineWidth = 3 * a + 1;
        g.beginPath();
        g.arc(sx, sy, p.size * cam.ppm * (0.2 + k), 0, Math.PI * 2);
        g.stroke();
      }
    }
    g.restore();
  }
}

/** Bullets as glowing tracers, blended between the last two snapshots. */
export function drawBullets(g: CanvasRenderingContext2D, cam: Camera, list: Bullet[], prev: Map<number, Bullet>, alpha: number): void {
  g.save();
  g.globalCompositeOperation = 'lighter';
  g.lineCap = 'round';
  for (const b of list) {
    const a = prev.get(b.id);
    const x = a ? a.x + (b.x - a.x) * alpha : b.x;
    const y = a ? a.y + (b.y - a.y) * alpha : b.y;
    const sx = cam.sx(x);
    const sy = cam.sy(y);
    const tx = sx - b.vx * cam.ppm * 0.03;
    const ty = sy + b.vy * cam.ppm * 0.03;
    g.strokeStyle = 'rgba(255, 190, 90, 0.5)';
    g.lineWidth = cam.ppm * 0.4;
    g.beginPath();
    g.moveTo(sx, sy);
    g.lineTo(tx, ty);
    g.stroke();
    g.strokeStyle = 'rgba(255, 250, 220, 1)';
    g.lineWidth = Math.max(1.5, cam.ppm * 0.14);
    g.beginPath();
    g.moveTo(sx, sy);
    g.lineTo(tx, ty);
    g.stroke();
  }
  g.restore();
}
