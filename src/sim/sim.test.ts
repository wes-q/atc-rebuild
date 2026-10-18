import assert from 'node:assert/strict';
import { test } from 'node:test';
import { BLOCKS } from './arena.ts';
import * as C from './constants.ts';
import { addPlayer, createState, NEUTRAL_INPUT, removePlayer, step } from './sim.ts';
import type { GameState, Input } from './types.ts';

function run(state: GameState, ticks: number, inputs: Record<string, Partial<Input>> = {}): void {
  const full: Record<string, Input> = {};
  for (const [id, i] of Object.entries(inputs)) full[id] = { ...NEUTRAL_INPUT, ...i };
  for (let t = 0; t < ticks; t++) step(state, full);
}

function fightingState(): GameState {
  const s = createState(42);
  addPlayer(s, 'a', 'A');
  addPlayer(s, 'b', 'B');
  run(s, C.COUNTDOWN_TIME * C.TICK_RATE + 1);
  assert.equal(s.phase, 'fighting');
  return s;
}

/** Puts both mechs in open air above the rooftops, a given distance apart. */
function openGround(s: GameState, gap: number): void {
  const [a, b] = s.players;
  a.x = 40;
  b.x = 40 + gap;
  a.y = b.y = 55;
  a.vy = b.vy = 0;
  a.grounded = b.grounded = false;
}

test('second player starts the countdown, third is refused', () => {
  const s = createState();
  assert.ok(addPlayer(s, 'a', 'A'));
  assert.equal(s.phase, 'waiting');
  assert.ok(addPlayer(s, 'b', 'B'));
  assert.equal(s.phase, 'countdown');
  assert.equal(addPlayer(s, 'c', 'C'), null);
});

test('spawns face each other and are frozen during the countdown', () => {
  const s = createState();
  addPlayer(s, 'a', 'A');
  addPlayer(s, 'b', 'B');
  const [a, b] = s.players;
  assert.ok(a.x < 0 && b.x > 0);
  run(s, 30, { a: { moveX: 1 } });
  assert.equal(a.x, -70);
  assert.equal(a.facing, 1);
  assert.equal(b.facing, -1);
});

test('lock-on faces the opponent even when walking away', () => {
  const s = fightingState();
  const a = s.players[0];
  const x0 = a.x;
  run(s, 20, { a: { moveX: -1 } });
  assert.ok(a.x < x0);
  assert.equal(a.facing, 1);
});

test('without lock-on the mouse decides facing and aim', () => {
  const s = fightingState();
  const a = s.players[0];
  run(s, 1, { a: { lock: false, aimX: a.x - 10, aimY: a.y + C.MUZZLE_Y + 10 } });
  assert.equal(a.facing, -1);
  assert.ok(Math.abs(a.aim - (3 * Math.PI) / 4) < 0.01);
});

test('dash is fast, can go up, and drains the gauge into overheat', () => {
  const s = fightingState();
  const a = s.players[0];
  a.x = 75;
  run(s, 20, { a: { moveX: 1, moveY: 1, boost: true } });
  assert.ok(a.y > 6, `rose to ${a.y}`);
  assert.ok(a.boost < C.BOOST_MAX);
  let ticks = 0;
  while (!a.overheated && ticks < 6 * C.TICK_RATE) {
    run(s, 1, { a: { moveX: ticks % 120 < 60 ? 1 : -1, boost: true } });
    ticks++;
  }
  assert.equal(a.overheated, true);
  run(s, 1, { a: { moveX: 1, boost: true } });
  assert.equal(a.dashing, false);
  // Must land, then recover once the gauge refills.
  run(s, 2 * C.TICK_RATE + Math.ceil((C.BOOST_MAX / C.OVERHEAT_REGEN) * C.TICK_RATE));
  assert.equal(a.overheated, false);
});

test('hold jump to hover higher than a plain jump', () => {
  const s = fightingState();
  const a = s.players[0];
  let peak = 0;
  for (let i = 0; i < 90; i++) {
    run(s, 1, { a: { jump: true } });
    peak = Math.max(peak, a.y);
  }
  const plainPeak = (C.JUMP_SPEED * C.JUMP_SPEED) / (2 * C.GRAVITY);
  assert.ok(peak > plainPeak + 4, `peak ${peak} vs plain ${plainPeak}`);
});

test('buildings block walking and can be stood on', () => {
  const s = fightingState();
  const a = s.players[0];
  // Building at x -59..-45, 16 high, sits to the right of P1's spawn.
  run(s, 3 * C.TICK_RATE, { a: { moveX: 1 } });
  assert.ok(Math.abs(a.x - (-59 - C.HALF_W)) < 0.01, `x ${a.x}`);
  a.x = -52;
  a.y = 20;
  run(s, C.TICK_RATE);
  assert.equal(a.y, 16);
  assert.equal(a.grounded, true);
});

test('one-way decks catch you from above, let you through from below, drop with down', () => {
  const s = fightingState();
  const a = s.players[0];
  const deck = BLOCKS.find((r) => r.oneWay && r.x0 < -60 && r.x1 > -60)!;
  a.x = -60;
  a.y = deck.y1 - 6;
  a.vy = 25;
  run(s, 90);
  assert.equal(a.y, deck.y1, 'passed up through and landed');
  run(s, 30, { a: { moveY: -1 } });
  assert.ok(a.y < deck.y1 - 2, 'dropped through');
});

test('locked gun hits the opponent on open ground', () => {
  const s = fightingState();
  openGround(s, 30);
  const [a, b] = s.players;
  run(s, 20, { a: { fire: true } });
  assert.ok(b.hp < C.MAX_HP, `hp ${b.hp}`);
  assert.ok(a.ammo < C.AMMO_MAX);
});

test('buildings stop bullets', () => {
  const s = fightingState();
  const [a, b] = s.players;
  // Centre tower between them, both standing on the street.
  a.x = -12;
  b.x = 12;
  run(s, C.TICK_RATE, { a: { fire: true } });
  assert.equal(b.hp, C.MAX_HP);
  assert.ok(a.ammo < C.AMMO_MAX);
});

test('slash lunges in and lands a heavy hit', () => {
  const s = fightingState();
  openGround(s, 14);
  const b = s.players[1];
  run(s, 1, { a: { melee: true } });
  run(s, 40);
  assert.equal(b.hp, C.MAX_HP - C.MELEE_DAMAGE);
});

test('knockout ends the round, awards the win and restarts', () => {
  const s = fightingState();
  openGround(s, 8);
  s.players[1].hp = 1;
  run(s, 1, { a: { melee: true } });
  run(s, 40);
  assert.equal(s.phase, 'ended');
  assert.equal(s.winner, 'a');
  assert.equal(s.players[0].wins, 1);
  run(s, C.ENDED_TIME * C.TICK_RATE + 1);
  assert.equal(s.phase, 'countdown');
  assert.equal(s.players[1].hp, C.MAX_HP);
});

test('time out gives the round to the healthier mech', () => {
  const s = fightingState();
  s.players[0].hp = 500;
  s.phaseTime = 0.01;
  run(s, 2);
  assert.equal(s.winner, 'b');
});

test('a leaving player drops the match back to waiting', () => {
  const s = fightingState();
  removePlayer(s, 'b');
  assert.equal(s.phase, 'waiting');
  assert.ok(addPlayer(s, 'c', 'C'));
  assert.equal(s.players[1].slot, 1);
});
