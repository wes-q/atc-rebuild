import type { GameState, Input } from './types.ts';

export type ClientMessage = { t: 'join'; name: string } | { t: 'input'; input: Input };

export type ServerMessage =
  | { t: 'welcome'; id: string; slot: number | null }
  | { t: 'snap'; s: GameState };

const num = (v: unknown, lo: number, hi: number): number =>
  typeof v === 'number' && Number.isFinite(v) ? Math.max(lo, Math.min(hi, v)) : 0;

/** Never trust the wire. Coerces anything into a valid Input. */
export function sanitizeInput(raw: unknown): Input {
  const r = (raw ?? {}) as Record<string, unknown>;
  return {
    seq: Math.trunc(num(r.seq, 0, Number.MAX_SAFE_INTEGER)),
    moveX: num(r.moveX, -1, 1),
    moveY: num(r.moveY, -1, 1),
    aimX: num(r.aimX, -1e4, 1e4),
    aimY: num(r.aimY, -1e4, 1e4),
    lock: r.lock !== false,
    boost: r.boost === true,
    jump: r.jump === true,
    fire: r.fire === true,
    melee: r.melee === true,
  };
}

export function sanitizeName(raw: unknown, fallback: string): string {
  const s = typeof raw === 'string' ? raw.replace(/[^\p{L}\p{N} _-]/gu, '').trim().slice(0, 16) : '';
  return s || fallback;
}
