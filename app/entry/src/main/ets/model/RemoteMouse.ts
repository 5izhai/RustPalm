// RustDesk src/common.rs: the low three bits encode the event type;
// button bits are shifted left by three. A wheel event has no button bits.
export const MOUSE_MOVE = 0;
export const LEFT_DOWN = 9;
export const LEFT_UP = 10;
export const RIGHT_DOWN = 17;
export const RIGHT_UP = 18;
export const WHEEL = 3;

export class MouseCommand {
  mask: number;
  x: number;
  y: number;

  constructor(mask: number, x: number, y: number) {
    this.mask = mask;
    this.x = x;
    this.y = y;
  }
}

// RustDesk's server only moves the pointer for MOVE. DOWN and UP ignore x/y
// and apply at the current pointer position, so move before each button edge.
export function pointerCommands(mask: number, x: number, y: number): MouseCommand[] {
  if (mask === MOUSE_MOVE) {
    return [new MouseCommand(MOUSE_MOVE, x, y)];
  }
  if (mask === LEFT_DOWN || mask === LEFT_UP || mask === RIGHT_DOWN || mask === RIGHT_UP) {
    return [new MouseCommand(MOUSE_MOVE, x, y), new MouseCommand(mask, 0, 0)];
  }
  return [];
}

// Wheel x/y contain deltas, not pointer coordinates. Anchor the pointer first
// so the column under the touch receives the scroll. Positive steps scroll up
// on Windows; an upward finger swipe should therefore pass negative steps.
export function wheelCommands(anchorX: number, anchorY: number, steps: number): MouseCommand[] {
  if (steps === 0) { return []; }
  return [new MouseCommand(MOUSE_MOVE, anchorX, anchorY), new MouseCommand(WHEEL, 0, steps)];
}
