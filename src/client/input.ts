import type { Input } from '../sim/index.ts';

const BLOCK_DEFAULT = new Set(['Space', 'Tab', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight']);

/** Keyboard and mouse state, sampled once per frame into an Input. */
export class Controls {
  private keys = new Set<string>();
  private mouseL = false;
  private mouseR = false;
  private seq = 0;
  /** Mouse position in screen pixels. */
  mouseX = 0;
  mouseY = 0;
  lock = true;
  onToggleHelp: () => void = () => {};

  constructor(canvas: HTMLCanvasElement) {
    window.addEventListener('keydown', (e) => {
      if (BLOCK_DEFAULT.has(e.code)) e.preventDefault();
      if (!e.repeat && (e.code === 'Tab' || e.code === 'KeyQ')) this.lock = !this.lock;
      if (!e.repeat && e.code === 'KeyH') this.onToggleHelp();
      this.keys.add(e.code);
    });
    window.addEventListener('keyup', (e) => this.keys.delete(e.code));
    // A tab that loses focus must not keep a key held down on the server.
    window.addEventListener('blur', () => this.clear());
    document.addEventListener('visibilitychange', () => {
      if (document.hidden) this.clear();
    });
    canvas.addEventListener('mousedown', (e) => {
      if (e.button === 0) this.mouseL = true;
      if (e.button === 2) this.mouseR = true;
    });
    window.addEventListener('mouseup', (e) => {
      if (e.button === 0) this.mouseL = false;
      if (e.button === 2) this.mouseR = false;
    });
    canvas.addEventListener('contextmenu', (e) => e.preventDefault());
    window.addEventListener('mousemove', (e) => {
      this.mouseX = e.clientX;
      this.mouseY = e.clientY;
    });
  }

  private clear(): void {
    this.keys.clear();
    this.mouseL = false;
    this.mouseR = false;
  }

  private down(...codes: string[]): boolean {
    return codes.some((c) => this.keys.has(c));
  }

  /** aimX and aimY are the mouse position already converted to world metres. */
  sample(aimX: number, aimY: number): Input {
    const up = this.down('KeyW', 'ArrowUp');
    return {
      seq: ++this.seq,
      moveX: (this.down('KeyD', 'ArrowRight') ? 1 : 0) - (this.down('KeyA', 'ArrowLeft') ? 1 : 0),
      moveY: (up ? 1 : 0) - (this.down('KeyS', 'ArrowDown') ? 1 : 0),
      aimX,
      aimY,
      lock: this.lock,
      boost: this.down('ShiftLeft', 'ShiftRight'),
      jump: up || this.down('Space'),
      fire: this.mouseL || this.down('KeyJ'),
      melee: this.mouseR || this.down('KeyK'),
    };
  }
}
