import test from 'node:test';
import assert from 'node:assert/strict';
import {
  MOUSE_MOVE, LEFT_DOWN, LEFT_UP, RIGHT_DOWN, RIGHT_UP, WHEEL,
  pointerCommands, wheelCommands
} from '../app/entry/src/main/ets/model/RemoteMouse.ts';

// Model the server's contract rather than the command builder: only event
// type 0 moves the cursor; button/wheel events act at its existing location.
function applyLikeServer(commands, position = [12, 34]) {
  const result = { position, held: new Set(), buttonEvents: [], scrollEvents: [], dragMoves: [] };
  for (const command of commands) {
    const type = command.mask & 7;
    const button = command.mask >> 3;
    if (type === 0) {
      result.position = [command.x, command.y];
      if (result.held.has(1)) { result.dragMoves.push(result.position); }
    } else if (type === 1 || type === 2) {
      result.buttonEvents.push({ type, button, at: result.position });
      if (type === 1) { result.held.add(button); }
      else { result.held.delete(button); }
    } else if (type === 3) {
      result.scrollEvents.push({ at: result.position, x: command.x, y: command.y, button });
    }
  }
  return result;
}

test('pointer button masks match the RustDesk wire contract', () => {
  assert.deepEqual([MOUSE_MOVE, LEFT_DOWN, LEFT_UP, RIGHT_DOWN, RIGHT_UP, WHEEL],
    [0, 9, 10, 17, 18, 3]);
});

test('tap moves the remote pointer before clicking the requested input field', () => {
  const result = applyLikeServer([
    ...pointerCommands(LEFT_DOWN, 640, 360),
    ...pointerCommands(LEFT_UP, 640, 360)
  ]);
  assert.deepEqual(result.buttonEvents, [
    { type: 1, button: 1, at: [640, 360] },
    { type: 2, button: 1, at: [640, 360] }
  ]);
  assert.equal(result.held.size, 0);
});

test('drag moves while held and releases at the final mapped position', () => {
  const result = applyLikeServer([
    ...pointerCommands(LEFT_DOWN, 100, 200),
    ...pointerCommands(MOUSE_MOVE, 130, 240),
    ...pointerCommands(LEFT_UP, 160, 280)
  ]);
  assert.deepEqual(result.dragMoves, [[130, 240], [160, 280]]);
  assert.deepEqual(result.buttonEvents[1], { type: 2, button: 1, at: [160, 280] });
  assert.equal(result.held.size, 0);
});

test('right click opens at the touch location even when the pointer was elsewhere', () => {
  const result = applyLikeServer([
    ...pointerCommands(RIGHT_DOWN, -800, 600),
    ...pointerCommands(RIGHT_UP, -800, 600)
  ]);
  assert.deepEqual(result.buttonEvents, [
    { type: 1, button: 2, at: [-800, 600] },
    { type: 2, button: 2, at: [-800, 600] }
  ]);
  assert.equal(result.held.size, 0);
});

test('scroll targets the touched column and preserves vertical direction', () => {
  const result = applyLikeServer([
    ...wheelCommands(900, 400, -3),
    ...wheelCommands(300, 400, 2)
  ]);
  assert.deepEqual(result.scrollEvents, [
    { at: [900, 400], x: 0, y: -3, button: 0 },
    { at: [300, 400], x: 0, y: 2, button: 0 }
  ]);
  assert.equal(result.buttonEvents.length, 0);
});

test('a move emits only a move, and zero scroll emits no input', () => {
  assert.deepEqual(pointerCommands(MOUSE_MOVE, 10, 20).map(c => [c.mask, c.x, c.y]), [[0, 10, 20]]);
  assert.deepEqual(wheelCommands(10, 20, 0), []);
  assert.deepEqual(pointerCommands(99, 10, 20), []);
});
