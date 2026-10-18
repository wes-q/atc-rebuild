import type { Rect } from './types.ts';

/** Night city stage, side view. Ground at y = 0, walls at +-half, open sky up to the ceiling. */
export const ARENA = {
  half: 110,
  ceiling: 75,
  spawns: [
    { x: -70, facing: 1 },
    { x: 70, facing: -1 },
  ],
};

const building = (cx: number, w: number, h: number): Rect => ({ x0: cx - w / 2, y0: 0, x1: cx + w / 2, y1: h });
const deck = (cx: number, w: number, y: number): Rect => ({ x0: cx - w / 2, y0: y - 1.2, x1: cx + w / 2, y1: y, oneWay: true });

/** Left half of the skyline. The right half is its mirror so neither spawn is favoured. */
const left: Rect[] = [
  building(-96, 12, 22),
  building(-52, 14, 16),
  building(-34, 8, 30),
  building(-18, 12, 11),
  // Floating platform above the gap.
  deck(-60, 12, 34),
];

export const BLOCKS: Rect[] = [
  ...left,
  ...left.map((r) => ({ ...r, x0: -r.x1, x1: -r.x0 })),
  // Centre tower and a high deck above it.
  building(0, 10, 20),
  deck(0, 20, 46),
];
