export type Phase = 'waiting' | 'countdown' | 'fighting' | 'ended';

/**
 * One frame of player intent. The game is a side view: x is right, y is up.
 */
export interface Input {
  seq: number;
  /** -1 left .. 1 right */
  moveX: number;
  /** -1 down .. 1 up. Steers air dashes, down also drops faster. */
  moveY: number;
  /** World point the mouse is over. Used for aiming when lock-on is off. */
  aimX: number;
  aimY: number;
  lock: boolean;
  boost: boolean;
  /** Held: jump on the ground, hover in the air. */
  jump: boolean;
  fire: boolean;
  melee: boolean;
}

export interface PlayerState {
  id: string;
  name: string;
  slot: number;
  /** Feet position. */
  x: number;
  y: number;
  vx: number;
  vy: number;
  /** 1 faces right, -1 faces left. */
  facing: number;
  /** Gun angle in radians, world space. */
  aim: number;
  hp: number;
  boost: number;
  overheated: boolean;
  grounded: boolean;
  dashing: boolean;
  hovering: boolean;
  locked: boolean;
  ammo: number;
  fireCd: number;
  meleeCd: number;
  /** Seconds left in the current slash, 0 when not slashing. */
  meleeT: number;
  meleeHit: boolean;
  prevJump: boolean;
  prevMelee: boolean;
  wins: number;
}

export interface Bullet {
  id: number;
  owner: string;
  x: number;
  y: number;
  vx: number;
  vy: number;
  life: number;
}

export interface HitEvent {
  type: 'hit';
  kind: 'gun' | 'melee';
  attacker: string;
  target: string;
  amount: number;
  x: number;
  y: number;
}

export interface FireEvent {
  type: 'fire';
  owner: string;
}

export interface RoundEvent {
  type: 'round';
  phase: Phase;
  winner: string | null;
}

export type GameEvent = HitEvent | FireEvent | RoundEvent;

export interface GameState {
  tick: number;
  phase: Phase;
  /** Seconds left in the current phase. Round clock while fighting. */
  phaseTime: number;
  players: PlayerState[];
  bullets: Bullet[];
  nextBulletId: number;
  rng: number;
  /** Set when a round ends. null with phase 'ended' means a draw. */
  winner: string | null;
  /** Events produced by the most recent step only. */
  events: GameEvent[];
}

/** Axis-aligned solid block. */
export interface Rect {
  x0: number;
  y0: number;
  x1: number;
  y1: number;
  /** Can be passed from below and stood on from above. */
  oneWay?: boolean;
}
