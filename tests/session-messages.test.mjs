import test from 'node:test';
import assert from 'node:assert/strict';
import { authenticationAction, sessionMessage } from '../app/entry/src/main/ets/model/SessionMessages.ts';

test('successful login keeps the connection alive while the first image arrives', () => {
  assert.equal(authenticationAction('success'), 'connected');
  assert.notEqual(authenticationAction('success'), 'error');
});

test('RustDesk No Password Access waits for the desktop user to accept', () => {
  assert.equal(authenticationAction('wait-remote-accept-nook'), 'waiting');
  assert.equal(authenticationAction('wait-remote-accept'), 'waiting');
});
test('incorrect credentials reopen the appropriate authentication prompt', () => {
  assert.equal(authenticationAction('re-input-password'), 'password');
  assert.equal(authenticationAction('input-2fa'), '2fa');
  assert.equal(authenticationAction('error'), 'error');
});
test('Windows UAC notifications leave the remote session alive', () => {
  assert.equal(authenticationAction('wait-uac'), 'notice');
  assert.equal(authenticationAction('custom-uac-nocancel'), 'notice');
  assert.equal(authenticationAction('custom-elevated-foreground-nocancel'), 'notice');
});

test('password rejection explains the actual failure instead of the generic retry text', () => {
  assert.match(sessionMessage('re-input-password', 'Wrong Password', 'Do you want to enter again?'), /密码错误/);
  assert.match(sessionMessage('input-password', 'Password Required', ''), /不是服务器公钥/);
});

test('errors with empty bodies retain their title and details remain visible', () => {
  assert.equal(sessionMessage('error', 'Connection Error', ''), 'Connection Error');
  assert.equal(sessionMessage('error', 'Connection Error', 'Timeout'), 'Connection Error\nTimeout');
  assert.equal(sessionMessage('error', '', 'Timeout'), 'Timeout');
  assert.equal(sessionMessage('error', 'Timeout', 'Timeout'), 'Timeout');
});
