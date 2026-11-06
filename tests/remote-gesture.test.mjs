import test from 'node:test';
import assert from 'node:assert/strict';
import { GestureContact, WheelAccumulator, activeContacts }
  from '../app/entry/src/main/ets/model/RemoteGesture.ts';

test('slow wheel movements accumulate into 24 vp notches and preserve excess travel', () => {
  const wheel = new WheelAccumulator();
  assert.equal(wheel.add(10), 0);
  assert.equal(wheel.add(10), 0);
  assert.equal(wheel.add(10), 1);
  assert.equal(wheel.add(18), 1);
  assert.equal(wheel.add(72), 3);
});

test('negative wheel movement is symmetric and reversals consume the remainder', () => {
  const wheel = new WheelAccumulator();
  assert.equal(wheel.add(-10), 0);
  assert.equal(wheel.add(-20), -1);
  assert.equal(wheel.add(6), 0);
  assert.equal(wheel.add(24), 1);
  assert.equal(wheel.add(-72), -3);
});

test('gesture reset discards unspent travel and invalid input cannot poison scrolling', () => {
  const wheel = new WheelAccumulator();
  assert.equal(wheel.add(23), 0);
  wheel.reset();
  assert.equal(wheel.add(1), 0);
  assert.equal(wheel.add(Number.NaN), 0);
  assert.equal(wheel.add(Infinity), 0);
  assert.equal(wheel.add(-Infinity), 0);
  assert.equal(wheel.add(23), 1);
});

test('two-finger release produces the same remaining contacts for both Up conventions', () => {
  const first = new GestureContact(7, 100, 200);
  const second = new GestureContact(42, 200, 200);
  const included = activeContacts([second, first], [first], true);
  const excluded = activeContacts([second], [first], true);
  assert.deepEqual(included, [second]);
  assert.deepEqual(excluded, included);
  assert.deepEqual(activeContacts([second], [second], true), []);
  assert.deepEqual(activeContacts([], [second], true), []);
});

test('simultaneous multi-touch release removes every lifted identity regardless of order', () => {
  const first = new GestureContact(7, 100, 200);
  const second = new GestureContact(42, 200, 200);
  assert.deepEqual(activeContacts([first, second], [second, first], true), []);
});

test('down and move retain the changed finger and do not mutate the supplied array', () => {
  const first = new GestureContact(7, 100, 200);
  const second = new GestureContact(42, 200, 200);
  const touches = [first, second];
  assert.deepEqual(activeContacts(touches, [second], false), touches);
  assert.notEqual(activeContacts(touches, [second], false), touches);
  assert.deepEqual(activeContacts(touches, [second], true), [first]);
  assert.deepEqual(touches, [first, second]);
});
