import { ARENA, BLOCKS } from '../sim/index.ts';
import type { Camera } from './camera.ts';

/** Night city backdrop in parallax layers, plus the solid buildings you fight on. */

interface Tower {
  x: number;
  w: number;
  h: number;
  lit: number[];
}

function seeded(seed: number): () => number {
  let s = seed;
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 0xffffffff;
  };
}

function skyline(seed: number, count: number, span: number, minH: number, maxH: number): Tower[] {
  const r = seeded(seed);
  const out: Tower[] = [];
  let x = -span;
  for (let i = 0; i < count && x < span; i++) {
    const w = 6 + r() * 14;
    const lit: number[] = [];
    for (let k = 0; k < 14; k++) lit.push(r());
    out.push({ x, w, h: minH + r() * (maxH - minH), lit });
    x += w + r() * 3;
  }
  return out;
}

const FAR = skyline(7, 90, 260, 20, 70);
const MID = skyline(19, 70, 220, 12, 45);
const CLOUDS = (() => {
  const r = seeded(3);
  return Array.from({ length: 22 }, () => ({ x: -300 + r() * 600, y: 45 + r() * 60, w: 18 + r() * 30, h: 4 + r() * 5 }));
})();

export function drawBackdrop(g: CanvasRenderingContext2D, cam: Camera, time: number): void {
  const { w, h } = cam;
  const sky = g.createLinearGradient(0, 0, 0, h);
  sky.addColorStop(0, '#0d1230');
  sky.addColorStop(0.55, '#2b2f66');
  sky.addColorStop(1, '#6b5f98');
  g.fillStyle = sky;
  g.fillRect(0, 0, w, h);

  // Moon, nearly fixed.
  const mx = w * 0.78 - cam.x * cam.ppm * 0.03;
  const my = h * 0.2 + (cam.y - 30) * cam.ppm * 0.03;
  const mr = h * 0.16;
  const moon = g.createRadialGradient(mx - mr * 0.3, my - mr * 0.3, mr * 0.1, mx, my, mr);
  moon.addColorStop(0, '#d9dcef');
  moon.addColorStop(1, '#8d90b8');
  g.fillStyle = moon;
  g.beginPath();
  g.arc(mx, my, mr, 0, Math.PI * 2);
  g.fill();
  g.fillStyle = 'rgba(110, 112, 150, 0.45)';
  for (const [dx, dy, rr] of [[-0.3, 0.1, 0.18], [0.25, -0.25, 0.12], [0.1, 0.35, 0.1], [-0.05, -0.45, 0.08]]) {
    g.beginPath();
    g.arc(mx + dx * mr, my + dy * mr, rr * mr, 0, Math.PI * 2);
    g.fill();
  }

  // Searchlight beams sweeping up from the city.
  g.save();
  g.globalCompositeOperation = 'lighter';
  for (let i = 0; i < 3; i++) {
    const base = w * (0.2 + i * 0.3) - cam.x * cam.ppm * 0.2;
    const ang = Math.sin(time * 0.25 + i * 2.1) * 0.5;
    const len = h * 1.3;
    const beam = g.createLinearGradient(base, h, base + Math.sin(ang) * len, h - Math.cos(ang) * len);
    beam.addColorStop(0, 'rgba(120, 200, 255, 0.16)');
    beam.addColorStop(1, 'rgba(120, 200, 255, 0)');
    g.fillStyle = beam;
    g.beginPath();
    g.moveTo(base - 6, h);
    g.lineTo(base + Math.sin(ang - 0.06) * len, h - Math.cos(ang - 0.06) * len);
    g.lineTo(base + Math.sin(ang + 0.06) * len, h - Math.cos(ang + 0.06) * len);
    g.lineTo(base + 6, h);
    g.fill();
  }
  g.restore();

  // Clouds drift slowly with light parallax.
  const p = 0.15;
  for (const c of CLOUDS) {
    let x = c.x + time * 1.2;
    x = ((x + 300) % 600) - 300;
    const sx = (x - cam.x * p) * cam.ppm * 0.6 + w / 2;
    const sy = h / 2 - (c.y - cam.y * p) * cam.ppm * 0.6;
    const cw = c.w * cam.ppm * 0.6;
    const chh = c.h * cam.ppm * 0.6;
    if (sx + cw < 0 || sx - cw > w) continue;
    g.fillStyle = 'rgba(206, 170, 210, 0.22)';
    g.beginPath();
    g.ellipse(sx, sy, cw * 0.5, chh * 0.5, 0, 0, Math.PI * 2);
    g.ellipse(sx - cw * 0.25, sy + chh * 0.15, cw * 0.3, chh * 0.45, 0, 0, Math.PI * 2);
    g.ellipse(sx + cw * 0.28, sy + chh * 0.1, cw * 0.32, chh * 0.4, 0, 0, Math.PI * 2);
    g.fill();
    g.fillStyle = 'rgba(255, 220, 240, 0.12)';
    g.beginPath();
    g.ellipse(sx, sy - chh * 0.2, cw * 0.4, chh * 0.25, 0, 0, Math.PI * 2);
    g.fill();
  }

  drawSkyline(g, cam, FAR, 0.3, '#161b3d', 'rgba(255, 220, 150, 0.25)');
  drawSkyline(g, cam, MID, 0.55, '#141f33', 'rgba(140, 230, 255, 0.25)');
  // Haze so the playfield reads in front of the backdrop.
  const haze = g.createLinearGradient(0, 0, 0, h);
  haze.addColorStop(0, 'rgba(12, 14, 40, 0.15)');
  haze.addColorStop(1, 'rgba(40, 30, 80, 0.35)');
  g.fillStyle = haze;
  g.fillRect(0, 0, w, h);
}

function drawSkyline(g: CanvasRenderingContext2D, cam: Camera, towers: Tower[], p: number, fill: string, win: string): void {
  const scale = cam.ppm * (0.5 + p * 0.5);
  const ground = cam.sy(0) + (1 - p) * cam.h * 0.08;
  for (const t of towers) {
    const sx = (t.x - cam.x * p) * scale + cam.w / 2;
    const sw = t.w * scale;
    if (sx + sw < 0 || sx > cam.w) continue;
    const sh = t.h * scale;
    g.fillStyle = fill;
    g.fillRect(sx, ground - sh, sw, sh + cam.h);
    g.fillStyle = win;
    const rows = Math.floor(t.h / 4);
    for (let r = 1; r < rows; r++) {
      for (let c = 0; c < 3; c++) {
        if (t.lit[(r * 3 + c) % t.lit.length] > 0.55) {
          g.fillRect(sx + sw * (0.15 + c * 0.27), ground - sh + r * 4 * scale, sw * 0.14, scale * 1.2);
        }
      }
    }
  }
}

export function drawArena(g: CanvasRenderingContext2D, cam: Camera, time: number): void {
  const { ppm } = cam;

  // Street.
  const gy = cam.sy(0);
  const street = g.createLinearGradient(0, gy, 0, cam.h);
  street.addColorStop(0, '#2a3446');
  street.addColorStop(1, '#0c1018');
  g.fillStyle = street;
  g.fillRect(0, gy, cam.w, cam.h - gy);
  g.fillStyle = '#7fe3ff';
  g.fillRect(0, gy, cam.w, Math.max(1, ppm * 0.12));
  g.fillStyle = 'rgba(230, 230, 200, 0.4)';
  const dash = 6;
  const start = Math.floor(cam.wx(0) / (dash * 2)) * dash * 2;
  for (let x = start; x < cam.wx(cam.w); x += dash * 2) g.fillRect(cam.sx(x), gy + ppm * 1.2, dash * ppm, ppm * 0.25);

  // Buildings and decks.
  for (const r of BLOCKS) {
    const x0 = cam.sx(r.x0);
    const x1 = cam.sx(r.x1);
    const y0 = cam.sy(r.y1);
    const y1 = cam.sy(r.y0);
    if (x1 < 0 || x0 > cam.w) continue;
    const bw = x1 - x0;
    const bh = y1 - y0;
    if (r.oneWay) {
      g.fillStyle = '#3d4a5c';
      g.fillRect(x0, y0, bw, bh);
      g.fillStyle = '#9fe9ff';
      g.fillRect(x0, y0, bw, Math.max(2, ppm * 0.15));
      g.strokeStyle = 'rgba(120, 220, 255, 0.5)';
      g.lineWidth = 1;
      for (let x = x0; x < x1; x += ppm * 1.5) {
        g.beginPath();
        g.moveTo(x, y0 + 2);
        g.lineTo(x + ppm * 0.75, y1);
        g.lineTo(x + ppm * 1.5, y0 + 2);
        g.stroke();
      }
      continue;
    }
    const body = g.createLinearGradient(x0, 0, x1, 0);
    body.addColorStop(0, '#3d8496');
    body.addColorStop(0.45, '#5aaabb');
    body.addColorStop(1, '#2c6574');
    g.fillStyle = body;
    g.fillRect(x0, y0, bw, bh);
    // Panel seams and window bands.
    g.strokeStyle = 'rgba(10, 30, 40, 0.35)';
    g.lineWidth = 1;
    for (let y = r.y1 - 3; y > r.y0; y -= 3) {
      const sy = cam.sy(y);
      g.beginPath();
      g.moveTo(x0, sy);
      g.lineTo(x1, sy);
      g.stroke();
      g.fillStyle = 'rgba(200, 250, 255, 0.28)';
      g.fillRect(x0 + bw * 0.12, sy + ppm * 0.6, bw * 0.76, ppm * 0.7);
    }
    g.fillStyle = '#9fe9ff';
    g.fillRect(x0, y0, bw, Math.max(2, ppm * 0.18));
    g.strokeStyle = 'rgba(8, 20, 30, 0.9)';
    g.lineWidth = 2;
    g.strokeRect(x0 + 1, y0 + 1, bw - 2, bh - 2);
    g.lineWidth = 1;
  }

  // Cyan grid boundary walls, like the original arena edges.
  g.save();
  g.globalCompositeOperation = 'lighter';
  for (const side of [-1, 1]) {
    const edge = cam.sx(side * ARENA.half);
    const outer = side < 0 ? 0 : cam.w;
    if ((side < 0 && edge < 0) || (side > 0 && edge > cam.w)) continue;
    g.fillStyle = `rgba(60, 170, 255, ${0.12 + Math.sin(time * 3) * 0.03})`;
    g.fillRect(Math.min(edge, outer), 0, Math.abs(outer - edge), cam.h);
    g.strokeStyle = 'rgba(90, 210, 255, 0.55)';
    g.lineWidth = 1;
    const cell = 3 * ppm;
    g.beginPath();
    for (let x = edge; side < 0 ? x > outer : x < outer; x += side * cell) {
      g.moveTo(x, 0);
      g.lineTo(x, cam.h);
    }
    for (let y = gy % cell; y < cam.h; y += cell) {
      g.moveTo(Math.min(edge, outer), y);
      g.lineTo(Math.max(edge, outer), y);
    }
    g.stroke();
    g.fillStyle = '#7fe3ff';
    g.fillRect(edge - 1.5, 0, 3, cam.h);
  }
  g.restore();
}
