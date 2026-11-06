import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { toolbarKeyCommand, lockScreenCommand } from '../app/entry/src/main/ets/model/RemoteKeys.ts';

test('Escape preserves explicit modifiers and stays plain when none are selected', () => {
  // Ctrl+Escape intentionally opens Windows Start; Ctrl+Shift+Escape opens
  // Task Manager. The key remains Escape, never a substituted Windows key.
  for (const alt of [false, true]) {
    for (const ctrl of [false, true]) {
      for (const shift of [false, true]) {
        const key = toolbarKeyCommand('VK_ESCAPE', alt, ctrl, shift);
        assert.equal(key.name, 'VK_ESCAPE');
        assert.deepEqual([key.alt, key.ctrl, key.shift, key.command], [alt, ctrl, shift, false]);
        assert.deepEqual([key.down, key.press], [false, true]);
      }
    }
  }
});

test('common key names agree with the pinned RustDesk protocol mapping', () => {
  // Validate against the actual receiver-facing adapter, so a future native
  // baseline change cannot silently turn these UI actions into another key.
  const core = readFileSync(new URL('../third_party/rustdesk/src/client.rs', import.meta.url), 'utf8');
  for (const [input, control] of [
    ['VK_ESCAPE', 'Escape'], ['VK_TAB', 'Tab'], ['VK_RETURN', 'Return'], ['VK_BACK', 'Backspace']
  ]) {
    const key = toolbarKeyCommand(input, false, false, false);
    assert.ok(core.includes(`("${key.name}", Key::ControlKey(ControlKey::${control}))`), input);
  }
});

test('letter shortcuts and Shift+Tab preserve only the selected modifiers', () => {
  for (const letter of ['a', 'c', 'v', 'z']) {
    const key = toolbarKeyCommand(letter, false, true, false);
    assert.equal(key.name, `VK_${letter.toUpperCase()}`);
    assert.deepEqual([key.alt, key.ctrl, key.shift, key.command], [false, true, false, false]);
  }
  const tab = toolbarKeyCommand('VK_TAB', false, false, true);
  assert.deepEqual([tab.name, tab.alt, tab.ctrl, tab.shift, tab.command], ['VK_TAB', false, false, true, false]);
  const enter = toolbarKeyCommand('VK_RETURN', true, false, false);
  assert.equal(enter.alt, true);
});

test('unsupported toolbar keys cannot accidentally inject a Windows/Meta key', () => {
  for (const name of ['VK_ESC', 'VK_LWIN', 'Meta', '', '\u0000']) {
    assert.equal(toolbarKeyCommand(name, true, true, true).name, '');
  }
});

test('lock action matches the native LockScreen down-only Legacy contract', () => {
  const key = lockScreenCommand();
  assert.deepEqual([key.name, key.down, key.press], ['LOCK_SCREEN', true, false]);

  const core = readFileSync(new URL('../third_party/rustdesk/src/client.rs', import.meta.url), 'utf8');
  assert.ok(core.includes(`("${key.name}", Key::ControlKey(ControlKey::LockScreen))`));
  const keyboard = readFileSync(new URL('../third_party/rustdesk/src/keyboard.rs', import.meta.url), 'utf8');
  const nativeLock = keyboard.match(/pub fn event_lock_screen\(\)[\s\S]*?\n    }/)[0];
  assert.match(nativeLock, /set_control_key\(ControlKey::LockScreen\)/);
  assert.match(nativeLock, /key_event\.down\s*=\s*true/);
  assert.match(nativeLock, /key_event\.mode\s*=\s*KeyboardMode::Legacy\.into\(\)/);

  const adapter = readFileSync(new URL('../third_party/rustdesk/src/ui_session_interface.rs', import.meta.url), 'utf8');
  const inputKey = adapter.match(/fn _input_key\([\s\S]*?\n    }/)[0];
  assert.match(inputKey, /key_event\.mode\s*=\s*KeyboardMode::Legacy\.into\(\)/);
});

test('lock action cannot inherit modifiers or mutable state from previous shortcuts', () => {
  const shortcut = toolbarKeyCommand('VK_ESCAPE', true, true, true);
  assert.equal(shortcut.ctrl, true);
  const firstLock = lockScreenCommand();
  assert.deepEqual([firstLock.alt, firstLock.ctrl, firstLock.shift, firstLock.command],
    [false, false, false, false]);
  firstLock.ctrl = true;
  assert.equal(lockScreenCommand().ctrl, false);
});
