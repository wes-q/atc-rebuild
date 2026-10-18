import { ARENA, BLOCKS } from './arena.ts';
import * as C from './constants.ts';
import type { Bullet, GameState, Input, PlayerState, Rect } from './types.ts';

export const NEUTRAL_INPUT: Input = {
  seq: 0,
  moveX: 0,
  moveY: 0,
  aimX: 0,
  aimY: 0,
  lock: true,
  boost: false,
  jump: false,
  fire: false,
  melee: false,
};

export function createState(seed = 1): GameState {
  return {
    tick: 0,
    phase: 'waiting',
    phaseTime: 0,
    players: [],
    bullets: [],
    nextBulletId: 1,
    rng: seed >>> 0 || 1,
    winner: null,
    events: [],
  };
}

/** Adds a player in the first free slot. Returns null when both slots are taken. */
export function addPlayer(state: GameState, id: string, name: string): PlayerState | null {
  if (state.players.length >= 2) return null;
  const slot = state.players.some((p) => p.slot === 0) ? 1 : 0;
  const p: PlayerState = {
    id,
    name,
    slot,
    x: 0,
    y: 0,
    vx: 0,
    vy: 0,
    facing: 1,
    aim: 0,
    hp: C.MAX_HP,
    boost: C.BOOST_MAX,
    overheated: false,
    grounded: true,
    dashing: false,
    hovering: false,
    locked: true,
    ammo: C.AMMO_MAX,
    fireCd: 0,
    meleeCd: 0,
    meleeT: 0,
    meleeHit: false,
    prevJump: false,
    prevMelee: false,
    wins: 0,
  };
  resetPlayer(p);
  state.players.push(p);
  state.players.sort((a, b) => a.slot - b.slot);
  if (state.players.length === 2) startCountdown(state);
  return p;
}

export function removePlayer(state: GameState, id: string): void {
  state.players = state.players.filter((p) => p.id !== id);
  state.bullets = state.bullets.filter((b) => b.owner !== id);
  if (state.players.length < 2) {
    state.phase = 'waiting';
    state.phaseTime = 0;
    state.winner = null;
    for (const p of state.players) resetPlayer(p);
  }
}

function resetPlayer(p: PlayerState): void {
  const s = ARENA.spawns[p.slot];
  p.x = s.x;
  p.y = 0;
  p.vx = p.vy = 0;
  p.facing = s.facing;
  p.aim = s.facing > 0 ? 0 : Math.PI;
  p.hp = C.MAX_HP;
  p.boost = C.BOOST_MAX;
  p.overheated = false;
  p.grounded = true;
  p.dashing = false;
  p.hovering = false;
  p.ammo = C.AMMO_MAX;
  p.fireCd = 0;
  p.meleeCd = 0;
  p.meleeT = 0;
  p.meleeHit = false;
}

function startCountdown(state: GameState): void {
  state.phase = 'countdown';
  state.phaseTime = C.COUNTDOWN_TIME;
  state.winner = null;
  state.bullets = [];
  for (const p of state.players) resetPlayer(p);
  state.events.push({ type: 'round', phase: 'countdown', winner: null });
}

function endRound(state: GameState, winner: string | null): void {
  state.phase = 'ended';
  state.phaseTime = C.ENDED_TIME;
  state.winner = winner;
  const w = state.players.find((p) => p.id === winner);
  if (w) w.wins += 1;
  state.events.push({ type: 'round', phase: 'ended', winner });
}

/** Deterministic 0..1 random from the state's own seed. */
function rand(state: GameState): number {
  let x = state.rng;
  x ^= x << 13;
  x ^= x >>> 17;
  x ^= x << 5;
  state.rng = x >>> 0;
  return state.rng / 0xffffffff;
}

export function opponentOf(state: GameState, id: string): PlayerState | undefined {
  return state.players.find((p) => p.id !== id);
}

/** Advances the game by one fixed tick. Missing inputs count as neutral. */
export function step(state: GameState, inputs: Record<string, Input>): void {
  const dt = C.DT;
  state.tick += 1;
  state.events = [];

  if (state.phase !== 'waiting') state.phaseTime = Math.max(0, state.phaseTime - dt);
  if (state.phase === 'countdown' && state.phaseTime <= 0) {
    state.phase = 'fighting';
    state.phaseTime = C.ROUND_TIME;
    state.events.push({ type: 'round', phase: 'fighting', winner: null });
  } else if (state.phase === 'ended' && state.phaseTime <= 0) {
    startCountdown(state);
  }

  // Free movement while waiting for an opponent, frozen during countdown and results.
  const canAct = state.phase === 'fighting' || state.phase === 'waiting';
  for (const p of state.players) {
    const input = inputs[p.id] ?? NEUTRAL_INPUT;
    stepPlayer(state, p, canAct ? input : { ...NEUTRAL_INPUT, lock: input.lock, aimX: input.aimX, aimY: input.aimY }, dt);
  }
  stepBullets(state, dt);

  if (state.phase === 'fighting') {
    const alive = state.players.filter((p) => p.hp > 0);
    if (alive.length < state.players.length) {
      endRound(state, alive.length === 1 ? alive[0].id : null);
    } else if (state.phaseTime <= 0) {
      const [a, b] = state.players;
      endRound(state, a.hp === b.hp ? null : a.hp > b.hp ? a.id : b.id);
    }
  }
}

function stepPlayer(state: GameState, p: PlayerState, input: Input, dt: number): void {
  const target = opponentOf(state, p.id);
  p.locked = input.lock && !!target;

  // Aim point: the opponent's chest when locked, the mouse otherwise.
  const ax = p.locked && target ? target.x : input.aimX;
  const ay = p.locked && target ? target.y + C.CHEST_Y : input.aimY;
  const sx = p.x;
  const sy = p.y + C.MUZZLE_Y;
  if (Math.abs(ax - sx) > 0.3) p.facing = ax > sx ? 1 : -1;
  p.aim = Math.atan2(ay - sy, ax - sx);

  const mx = clamp1(input.moveX);
  const my = clamp1(input.moveY);
  const jumpPressed = input.jump && !p.prevJump;
  const meleePressed = input.melee && !p.prevMelee;
  p.prevJump = input.jump;
  p.prevMelee = input.melee;
  p.fireCd = Math.max(0, p.fireCd - dt);
  p.meleeCd = Math.max(0, p.meleeCd - dt);

  // Beam blade: a short lunge toward the target, then one hit check.
  if (meleePressed && p.meleeCd <= 0 && p.meleeT <= 0) {
    p.meleeT = C.MELEE_TIME;
    p.meleeHit = false;
    p.meleeCd = C.MELEE_COOLDOWN;
  }
  const slashing = p.meleeT > 0;
  if (slashing) {
    const elapsed = C.MELEE_TIME - p.meleeT;
    if (target) {
      const dx = target.x - p.x;
      const dy = target.y - p.y;
      const d = Math.hypot(dx, dy);
      if (elapsed < C.MELEE_LUNGE_TIME && d < C.MELEE_LUNGE_RANGE && d > C.MELEE_REACH * 0.5) {
        p.vx = (dx / d) * C.MELEE_LUNGE_SPEED;
        p.vy = (dy / d) * C.MELEE_LUNGE_SPEED;
      }
      if (!p.meleeHit && elapsed >= C.MELEE_LUNGE_TIME) {
        p.meleeHit = true;
        if (d < C.MELEE_REACH && target.hp > 0 && state.phase === 'fighting') {
          damage(state, p, target, C.MELEE_DAMAGE, 'melee', target.x, target.y + C.CHEST_Y);
          target.vx = Math.sign(dx || p.facing) * C.MELEE_KNOCKBACK;
          target.vy = 10;
          target.meleeT = 0;
        }
      }
    }
    p.meleeT = Math.max(0, p.meleeT - dt);
  }

  // Boost gauge gates dashing and hovering.
  const canBoost = !p.overheated && p.boost > 0;
  const steering = Math.abs(mx) > 0.01 || (!p.grounded && Math.abs(my) > 0.01) || (p.grounded && my > 0.01);
  p.dashing = !slashing && input.boost && steering && canBoost;
  p.hovering = !slashing && !p.grounded && input.jump && !jumpPressed && canBoost && !p.dashing;

  if (!slashing) {
    if (p.dashing) {
      // Eight-way dash. Flat glide when no vertical input.
      let dx = mx;
      let dy = my;
      if (p.grounded && dy < 0) dy = 0;
      const n = Math.hypot(dx, dy) || 1;
      dx /= n;
      dy /= n;
      p.vx = approach(p.vx, dx * C.DASH_SPEED, C.DASH_ACCEL * dt);
      p.vy = approach(p.vy, dy * C.DASH_SPEED, C.DASH_ACCEL * dt);
      if (dy > 0) p.grounded = false;
    } else {
      const speed = p.grounded ? C.WALK_SPEED : C.AIR_SPEED;
      const accel = p.grounded ? C.GROUND_ACCEL : C.AIR_ACCEL;
      p.vx = approach(p.vx, mx * speed, accel * dt);
      if (p.grounded && jumpPressed) {
        p.vy = C.JUMP_SPEED;
        p.grounded = false;
      } else if (p.hovering) {
        p.vy = approach(p.vy, C.HOVER_RISE, C.HOVER_ACCEL * dt);
      } else {
        p.vy -= (C.GRAVITY + (my < 0 && !p.grounded ? C.FAST_FALL : 0)) * dt;
      }
    }
  } else if (!p.grounded) {
    p.vy -= C.GRAVITY * 0.3 * dt;
  }

  const drain = (p.dashing ? C.DASH_DRAIN : 0) + (p.hovering ? C.HOVER_DRAIN : 0);
  if (drain > 0) {
    p.boost = Math.max(0, p.boost - drain * dt);
    if (p.boost <= 0) p.overheated = true;
  } else if (p.grounded) {
    p.boost = Math.min(C.BOOST_MAX, p.boost + (p.overheated ? C.OVERHEAT_REGEN : C.BOOST_REGEN) * dt);
    if (p.overheated && p.boost >= C.BOOST_MAX) p.overheated = false;
  }

  // Down while standing on a deck drops through it.
  moveAndCollide(p, dt, p.grounded && my < -0.5 && !p.dashing);

  if (input.fire && !slashing && p.fireCd <= 0 && p.ammo > 0) {
    p.fireCd = C.FIRE_INTERVAL;
    p.ammo -= 1;
    fireBullet(state, p);
  }
}

function fireBullet(state: GameState, p: PlayerState): void {
  const a = p.aim + (rand(state) - 0.5) * 2 * C.BULLET_SPREAD;
  const ca = Math.cos(p.aim);
  const sa = Math.sin(p.aim);
  // Muzzle sits at the end of the rifle, which pivots at the shoulder.
  const b: Bullet = {
    id: state.nextBulletId++,
    owner: p.id,
    x: p.x + ca * C.MUZZLE_REACH,
    y: p.y + C.MUZZLE_Y + sa * C.MUZZLE_REACH,
    vx: Math.cos(a) * C.BULLET_SPEED,
    vy: Math.sin(a) * C.BULLET_SPEED,
    life: C.BULLET_LIFE,
  };
  state.bullets.push(b);
  state.events.push({ type: 'fire', owner: p.id });
}

const SUBSTEPS = 3;

function stepBullets(state: GameState, dt: number): void {
  const keep: Bullet[] = [];
  outer: for (const b of state.bullets) {
    b.life -= dt;
    if (b.life <= 0) continue;
    for (let i = 0; i < SUBSTEPS; i++) {
      b.x += (b.vx * dt) / SUBSTEPS;
      b.y += (b.vy * dt) / SUBSTEPS;
      if (b.y < 0 || Math.abs(b.x) > ARENA.half + 30 || b.y > ARENA.ceiling + 30) continue outer;
      for (const r of BLOCKS) if (!r.oneWay && b.x > r.x0 && b.x < r.x1 && b.y > r.y0 && b.y < r.y1) continue outer;
      for (const p of state.players) {
        if (p.id === b.owner || p.hp <= 0) continue;
        const cy = Math.min(Math.max(b.y, p.y + 0.9), p.y + C.HEIGHT - 0.6);
        if (Math.hypot(b.x - p.x, b.y - cy) < C.HIT_RADIUS) {
          if (state.phase === 'fighting') {
            const owner = state.players.find((q) => q.id === b.owner);
            if (owner) damage(state, owner, p, C.BULLET_DAMAGE, 'gun', b.x, b.y);
          }
          continue outer;
        }
      }
    }
    keep.push(b);
  }
  state.bullets = keep;
}

function damage(state: GameState, attacker: PlayerState, target: PlayerState, amount: number, kind: 'gun' | 'melee', x: number, y: number): void {
  target.hp = Math.max(0, target.hp - amount);
  state.events.push({ type: 'hit', kind, attacker: attacker.id, target: target.id, amount, x, y });
}

/** Axis-separated movement against the ground, walls, ceiling and blocks. */
function moveAndCollide(p: PlayerState, dt: number, dropThrough: boolean): void {
  const lim = ARENA.half - C.HALF_W;

  p.x += p.vx * dt;
  for (const r of BLOCKS) {
    if (!r.oneWay && overlaps(p, r)) {
      p.x = p.vx > 0 ? r.x0 - C.HALF_W - 1e-4 : r.x1 + C.HALF_W + 1e-4;
      p.vx = 0;
    }
  }
  if (Math.abs(p.x) > lim) {
    p.x = Math.sign(p.x) * lim;
    p.vx = 0;
  }

  const prevY = p.y;
  p.y += p.vy * dt;
  p.grounded = false;
  for (const r of BLOCKS) {
    if (!overlaps(p, r)) continue;
    if (r.oneWay) {
      // Only catches a mech falling onto it from above.
      if (p.vy <= 0 && prevY >= r.y1 - 1e-3 && !dropThrough) {
        p.y = r.y1;
        p.vy = 0;
        p.grounded = true;
      }
    } else if (p.vy <= 0) {
      p.y = r.y1;
      p.vy = 0;
      p.grounded = true;
    } else {
      p.y = r.y0 - C.HEIGHT - 1e-4;
      p.vy = 0;
    }
  }
  if (p.y <= 0) {
    p.y = 0;
    p.vy = 0;
    p.grounded = true;
  }
  if (p.y + C.HEIGHT > ARENA.ceiling) {
    p.y = ARENA.ceiling - C.HEIGHT;
    p.vy = Math.min(0, p.vy);
  }
  // Resting exactly on a top surface still counts as grounded.
  if (!p.grounded && p.vy <= 0 && !dropThrough) {
    for (const r of BLOCKS) {
      if (Math.abs(p.y - r.y1) < 1e-3 && p.x + C.HALF_W > r.x0 && p.x - C.HALF_W < r.x1) {
        p.grounded = true;
        break;
      }
    }
  }
}

function overlaps(p: PlayerState, r: Rect): boolean {
  return p.x + C.HALF_W > r.x0 && p.x - C.HALF_W < r.x1 && p.y + C.HEIGHT > r.y0 && p.y < r.y1;
}

function approach(v: number, target: number, maxDelta: number): number {
  return v < target ? Math.min(target, v + maxDelta) : Math.max(target, v - maxDelta);
}

function clamp1(v: number): number {
  return Math.max(-1, Math.min(1, v || 0));
}
