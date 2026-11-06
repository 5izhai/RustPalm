import test from 'node:test';
import assert from 'node:assert/strict';
import { FavoriteConnection, favoriteScopeMatches, favoriteEditError, favoriteKeepsPassword }
  from '../app/entry/src/main/ets/model/FavoriteModel.ts';

function existing() {
  const favorite = new FavoriteConnection();
  favorite.peerId = '123456789';
  favorite.idServer = 'rd.example.test:21116';
  // Synthetic bytes for scope comparison; never a real server public key.
  favorite.serverKey = Buffer.alloc(32, 0).toString('base64');
  favorite.hasPassword = true;
  return favorite;
}

test('saved credentials cannot be selected under a different server or public key', () => {
  const favorite = existing();
  assert.equal(favoriteScopeMatches(favorite, favorite.idServer, favorite.serverKey), true);
  assert.equal(favoriteScopeMatches(favorite, 'other.example.test:21116', favorite.serverKey), false);
  assert.equal(favoriteScopeMatches(favorite, favorite.idServer, 'different-key'), false);
});

test('changing the target requires clearing or replacing its existing password', () => {
  const favorite = existing();
  assert.notEqual(favoriteEditError(favorite, '987654321', '', false), '');
  assert.equal(favoriteEditError(favorite, '987654321', '', true), '');
  assert.equal(favoriteEditError(favorite, '987654321', 'replacement', false), '');
  assert.equal(favoriteEditError(favorite, favorite.peerId, '', false), '');
});

test('blank edit preserves a password while explicit removal takes precedence', () => {
  assert.equal(favoriteKeepsPassword(existing(), '', false), true);
  assert.equal(favoriteKeepsPassword(existing(), '', true), false);
  assert.equal(favoriteKeepsPassword(existing(), 'ignored', true), false);
  assert.equal(favoriteKeepsPassword(undefined, '', false), false);
  assert.equal(favoriteKeepsPassword(undefined, 'new-secret', false), true);
});

test('metadata cannot accidentally serialize the entered credential', () => {
  const favorite = existing();
  assert.deepEqual(Object.keys(favorite).sort(), ['hasPassword', 'id', 'idServer', 'name', 'peerId', 'serverKey']);
  assert.equal(Object.hasOwn(favorite, 'password'), false);
});

test('rejects invalid IDs and credentials that cannot cross the C string ABI', () => {
  assert.notEqual(favoriteEditError(undefined, 'not-a-peer', 'abc', false), '');
  assert.notEqual(favoriteEditError(undefined, '123', 'a\0b', false), '');
  assert.notEqual(favoriteEditError(undefined, '123', 'x'.repeat(257), false), '');
});
