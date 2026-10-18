import { AMMO_MAX, ARENA, BLOCKS, BOOST_MAX, CHEST_Y, MAX_HP, MELEE_LUNGE_RANGE, ROUND_TIME } from '../sim/index.ts';
import type { GameState, HitEvent, PlayerState } from '../sim/index.ts';
import type { Camera } from './camera.ts';

const $ = <T extends HTMLElement = HTMLElement>(id: string) => document.getElementById(id) as T;

export class Hud {
  private score = $('score');
  private pname = $('pname');
  private timer = $('timer');
  private boostVal = $('boost-val');
  private boostFill = $('boost-fill');
  private overheat = $('overheat');
  private ammo = $('ammo');
  private slotGun = $('slot-gun');
  private slotBlade = $('slot-blade');
  private hpFill = $('hp-fill');
  private hpText = $('hp-text');
  private lock = $('lock');
  private lockName = $('lock-name');
  private lockHp = $('lock-hp');
  private lockBoost = $('lock-boost');
  private lockDist = $('lock-dist');
  private crosshair = $('crosshair');
  private pops = $('pops');
  private center = $('center-msg');
  private sub = $('sub-msg');
  private help = $('help');
  private minimap = $<HTMLCanvasElement>('minimap').getContext('2d')!;
  private lastPop = 0;
  disconnected = false;

  toggleHelp(): void {
    this.help.classList.toggle('hidden');
  }

  update(s: GameState, me: PlayerState | undefined, other: PlayerState | undefined, spectating: boolean, cam: Camera, mouseX: number, mouseY: number): void {
    if (me) {
      this.score.textContent = String(me.wins).padStart(4, '0');
      this.pname.textContent = spectating ? `Spectating ${me.name}` : me.name;
      this.boostVal.textContent = String(Math.round(me.boost));
      this.boostFill.style.height = `${(me.boost / BOOST_MAX) * 100}%`;
      this.boostFill.classList.toggle('hot', me.overheated);
      this.overheat.classList.toggle('on', me.overheated);
      this.ammo.textContent = `${String(me.ammo).padStart(4, '0')} / ${String(AMMO_MAX).padStart(4, '0')}`;
      this.slotGun.classList.toggle('active', me.meleeT <= 0);
      this.slotBlade.classList.toggle('active', me.meleeT > 0);
      this.hpFill.style.width = `${(me.hp / MAX_HP) * 100}%`;
      this.hpFill.classList.toggle('low', me.hp < MAX_HP * 0.3);
      this.hpText.textContent = String(me.hp);
    }

    // Round clock in minutes, seconds and hundredths, like the original.
    const t = s.phase === 'fighting' ? s.phaseTime : s.phase === 'countdown' ? ROUND_TIME : s.phase === 'ended' ? 0 : -1;
    this.timer.textContent = t < 0 ? '--:--:--' : clock(t);

    // Lock-on ring on the opponent. Pinned to the screen edge when they are out of view.
    let showLock = false;
    if (me && other && me.locked) {
      showLock = true;
      const m = 60;
      const x = cam.sx(other.x);
      const y = cam.sy(other.y + CHEST_Y);
      const cx = Math.min(cam.w - m, Math.max(m, x));
      const cy = Math.min(cam.h - m, Math.max(m, y));
      this.lock.style.transform = `translate(${cx}px, ${cy}px)`;
      this.lock.classList.toggle('edge', cx !== x || cy !== y);
      const dist = Math.hypot(other.x - me.x, other.y - me.y);
      this.lock.classList.toggle('close', dist < MELEE_LUNGE_RANGE);
      this.lockName.textContent = other.name;
      this.lockHp.style.width = `${(other.hp / MAX_HP) * 100}%`;
      this.lockBoost.style.width = `${(other.boost / BOOST_MAX) * 100}%`;
      this.lockDist.textContent = `${Math.round(dist)}m`;
    }
    this.lock.classList.toggle('on', showLock);
    const free = !!me && !me.locked && !spectating;
    this.crosshair.classList.toggle('on', free);
    if (free) this.crosshair.style.transform = `translate(${mouseX}px, ${mouseY}px)`;

    this.updateMessage(s, me, spectating);
    this.drawMinimap(s.players, me, cam);
  }

  private updateMessage(s: GameState, me: PlayerState | undefined, spectating: boolean): void {
    let big = '';
    let small = '';
    let lose = false;
    if (this.disconnected) {
      big = 'DISCONNECTED';
      small = 'Restart the server, then reload this tab';
    } else if (s.phase === 'waiting') {
      big = 'WAITING';
      small = 'Open a second tab on this address to join as Player 2';
    } else if (s.phase === 'countdown') {
      big = String(Math.ceil(s.phaseTime));
      small = 'READY';
    } else if (s.phase === 'fighting' && ROUND_TIME - s.phaseTime < 1) {
      big = 'GO!';
    } else if (s.phase === 'ended') {
      const winner = s.players.find((p) => p.id === s.winner);
      if (!winner) big = 'DRAW';
      else if (spectating || !me) big = `${winner.name.toUpperCase()} WINS`;
      else if (winner.id === me.id) big = 'YOU WIN';
      else {
        big = 'YOU LOSE';
        lose = true;
      }
      small = `Next round in ${Math.ceil(s.phaseTime)}`;
    }
    this.center.textContent = big;
    this.center.classList.toggle('lose', lose);
    this.sub.textContent = small;
  }

  /** Floating "DAMAGE!" at the hit point. Gun hits are throttled so it stays readable. */
  pop(e: HitEvent, cam: Camera): void {
    const now = performance.now();
    if (e.kind === 'gun' && now - this.lastPop < 220) return;
    this.lastPop = now;
    const el = document.createElement('div');
    el.className = `pop ${e.kind}`;
    el.textContent = 'DAMAGE!';
    el.style.left = `${cam.sx(e.x)}px`;
    el.style.top = `${cam.sy(e.y) - 20}px`;
    this.pops.appendChild(el);
    setTimeout(() => el.remove(), 800);
  }

  /** Side-on map of the whole stage with both mechs and the current view. */
  private drawMinimap(players: PlayerState[], me: PlayerState | undefined, cam: Camera): void {
    const g = this.minimap;
    const W = g.canvas.width;
    const H = g.canvas.height;
    g.clearRect(0, 0, W, H);
    const pad = 6;
    const sc = Math.min((W - pad * 2) / (ARENA.half * 2), (H - pad * 2) / ARENA.ceiling);
    const ox = W / 2;
    const oy = H - pad - (H - pad * 2 - ARENA.ceiling * sc) / 2;
    const mx = (x: number) => ox + x * sc;
    const my = (y: number) => oy - y * sc;
    g.strokeStyle = 'rgba(120, 220, 255, 0.7)';
    g.lineWidth = 1;
    g.strokeRect(mx(-ARENA.half), my(ARENA.ceiling), ARENA.half * 2 * sc, ARENA.ceiling * sc);
    g.fillStyle = 'rgba(200, 225, 240, 0.4)';
    for (const r of BLOCKS) g.fillRect(mx(r.x0), my(r.y1), (r.x1 - r.x0) * sc, Math.max(1, (r.y1 - r.y0) * sc));
    g.strokeStyle = 'rgba(255, 255, 255, 0.35)';
    g.strokeRect(mx(cam.wx(0)), my(cam.wy(0)), (cam.w / cam.ppm) * sc, (cam.h / cam.ppm) * sc);
    for (const p of players) {
      g.fillStyle = p.id === me?.id ? '#7fe3ff' : '#ff4b3a';
      g.beginPath();
      g.arc(mx(p.x), my(p.y + 2), 3, 0, Math.PI * 2);
      g.fill();
    }
  }
}

function clock(seconds: number): string {
  const total = Math.max(0, Math.floor(seconds * 100));
  const m = Math.floor(total / 6000);
  const sec = Math.floor((total % 6000) / 100);
  const cs = total % 100;
  return [m, sec, cs].map((n) => String(n).padStart(2, '0')).join(':');
}
