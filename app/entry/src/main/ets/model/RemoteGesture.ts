export class GestureContact {
  id: number = 0;
  x: number = 0;
  y: number = 0;

  constructor(id: number = 0, x: number = 0, y: number = 0) {
    this.id = id;
    this.x = x;
    this.y = y;
  }
}

// TouchEvent.touches can still contain a finger on its Up event. Remove by
// identity instead of relying on a platform-specific array length or order.
export function activeContacts(touches: GestureContact[], changed: GestureContact[],
  isUp: boolean): GestureContact[] {
  if (!isUp) { return touches.slice(); }
  return touches.filter((touch: GestureContact): boolean => {
    return !changed.some((lifted: GestureContact): boolean => lifted.id === touch.id);
  });
}

// A wheel event carries integer notches, not screen coordinates. Accumulate
// small movements so slow gestures scroll and direction changes cancel out.
export class WheelAccumulator {
  private remainder: number = 0;

  add(deltaVp: number): number {
    if (!Number.isFinite(deltaVp)) { return 0; }
    this.remainder += deltaVp;
    const steps = Math.trunc(this.remainder / 24);
    this.remainder -= steps * 24;
    return steps === 0 ? 0 : steps;
  }

  reset(): void {
    this.remainder = 0;
  }
}
