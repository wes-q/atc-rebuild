import { ARENA } from '../sim/index.ts';

/** Side-view camera. World is metres with y up, screen is CSS pixels with y down. */
export class Camera {
  x = 0;
  y = 20;
  /** Pixels per metre. */
  ppm = 16;
  w = 1;
  h = 1;
  private ready = false;

  resize(w: number, h: number): void {
    this.w = w;
    this.h = h;
    // About 25 m of world fits the screen height, so a mech is roughly a sixth of it, as in the original.
    this.ppm = h / 25;
  }

  /** Eases toward a point, kept inside the arena so the walls stay at the screen edge. */
  follow(tx: number, ty: number, dt: number): void {
    const halfW = this.w / this.ppm / 2;
    const halfH = this.h / this.ppm / 2;
    const minX = -ARENA.half - 6 + halfW;
    const maxX = ARENA.half + 6 - halfW;
    tx = minX > maxX ? 0 : Math.min(maxX, Math.max(minX, tx));
    // Keep the street a quarter of the way up the screen so the HUD never covers your feet.
    ty = Math.min(ARENA.ceiling + 4 - halfH, Math.max(halfH * 0.5, ty));
    if (!this.ready) {
      this.x = tx;
      this.y = ty;
      this.ready = true;
      return;
    }
    const k = 1 - Math.exp(-6 * dt);
    this.x += (tx - this.x) * k;
    this.y += (ty - this.y) * k;
  }

  sx(wx: number): number {
    return (wx - this.x) * this.ppm + this.w / 2;
  }

  sy(wy: number): number {
    return this.h / 2 - (wy - this.y) * this.ppm;
  }

  wx(sx: number): number {
    return (sx - this.w / 2) / this.ppm + this.x;
  }

  wy(sy: number): number {
    return (this.h / 2 - sy) / this.ppm + this.y;
  }
}
