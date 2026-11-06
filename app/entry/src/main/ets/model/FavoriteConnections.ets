import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { FavoriteConnection, favoriteEditError, favoriteKeepsPassword } from './FavoriteModel';

const NAMESPACE = 'rustpalm-favorites-v1';
const ALIAS_PREFIX = 'rustpalm.favorite.';
const MAX_FAVORITES = 30;

function bytes(value: string): Uint8Array { return new util.TextEncoder().encodeInto(value); }
function text(value: asset.Value | undefined): string {
  return value instanceof Uint8Array ? new util.TextDecoder().decodeWithStream(value) : '';
}
function notFound(error: Object): boolean {
  return (error as BusinessError).code === asset.ErrorCode.NOT_FOUND;
}

function queryFor(id: string): asset.AssetMap {
  if (!/^[0-9a-f-]{36}$/i.test(id)) { throw new Error('Invalid favorite identifier'); }
  const query: asset.AssetMap = new Map();
  query.set(asset.Tag.ALIAS, bytes(ALIAS_PREFIX + id));
  query.set(asset.Tag.DATA_LABEL_CRITICAL_1, bytes(NAMESPACE));
  return query;
}

function metadataFrom(attributes: asset.AssetMap): FavoriteConnection | undefined {
  try {
    const raw = JSON.parse(text(attributes.get(asset.Tag.DATA_LABEL_NORMAL_1))) as FavoriteConnection;
    if (typeof raw.id !== 'string' || !/^[0-9a-f-]{36}$/i.test(raw.id) ||
        text(attributes.get(asset.Tag.ALIAS)) !== ALIAS_PREFIX + raw.id ||
        typeof raw.peerId !== 'string' || !/^[0-9]{1,20}$/.test(raw.peerId) ||
        typeof raw.name !== 'string' || typeof raw.idServer !== 'string' ||
        typeof raw.serverKey !== 'string' || typeof raw.hasPassword !== 'boolean') { return undefined; }
    const item = new FavoriteConnection();
    item.id = raw.id;
    item.name = raw.name.slice(0, 40);
    item.peerId = raw.peerId;
    item.idServer = raw.idServer;
    item.serverKey = raw.serverKey;
    item.hasPassword = raw.hasPassword;
    return item;
  } catch (error) { return undefined; }
}

// All favorite records live in the app-private system Asset Store. Listing
// reads ATTRIBUTES only. Creating/updating a record and its password is one
// atomic asset operation, avoiding plaintext preferences and split-store state.
export class FavoriteConnections {
  async list(): Promise<FavoriteConnection[]> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.DATA_LABEL_CRITICAL_1, bytes(NAMESPACE));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ATTRIBUTES);
    try {
      const results = await asset.query(query);
      const items: FavoriteConnection[] = [];
      for (const result of results) {
        const item = metadataFrom(result);
        if (item !== undefined) { items.push(item); }
      }
      return items;
    } catch (error) {
      if (notFound(error as Object)) { return []; }
      throw new Error('Secure asset query failed');
    }
  }

  async save(previous: FavoriteConnection | undefined, name: string, peerId: string,
    idServer: string, serverKey: string, password: string, removePassword: boolean,
    existingCount: number): Promise<FavoriteConnection> {
    const validation = favoriteEditError(previous, peerId, password, removePassword);
    if (validation.length > 0) { throw new Error(validation); }
    if (previous === undefined && existingCount >= MAX_FAVORITES) { throw new Error('最多保存 30 个常用连接'); }
    const item = new FavoriteConnection();
    item.id = previous === undefined ? util.generateRandomUUID() : previous.id;
    item.name = name.trim().slice(0, 40);
    item.peerId = peerId;
    // Editing labels/IDs never silently rebinds a secret to another server.
    item.idServer = previous === undefined ? idServer.trim() : previous.idServer;
    item.serverKey = previous === undefined ? serverKey.trim() : previous.serverKey;
    item.hasPassword = favoriteKeepsPassword(previous, password, removePassword);
    const attributes: asset.AssetMap = new Map();
    attributes.set(asset.Tag.DATA_LABEL_NORMAL_1, bytes(JSON.stringify(item)));
    let secret: Uint8Array | undefined = undefined;
    if (previous === undefined || removePassword || password.length > 0) {
      // SECRET must not be empty. A no-password record uses an unused zero byte.
      secret = item.hasPassword ? bytes(password) : new Uint8Array([0]);
      attributes.set(asset.Tag.SECRET, secret);
    }
    try {
      if (previous === undefined) {
        attributes.set(asset.Tag.ALIAS, bytes(ALIAS_PREFIX + item.id));
        attributes.set(asset.Tag.DATA_LABEL_CRITICAL_1, bytes(NAMESPACE));
        attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_UNLOCKED);
        attributes.set(asset.Tag.AUTH_TYPE, asset.AuthType.NONE);
        attributes.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
        await asset.add(attributes);
      } else {
        await asset.update(queryFor(item.id), attributes);
      }
      return item;
    } finally {
      secret?.fill(0);
    }
  }

  async password(item: FavoriteConnection): Promise<string> {
    if (!item.hasPassword) { return ''; }
    const query = queryFor(item.id);
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    const results = await asset.query(query);
    if (results.length !== 1) { throw new Error('Saved credential unavailable'); }
    const secret = results[0].get(asset.Tag.SECRET);
    if (!(secret instanceof Uint8Array)) { throw new Error('Saved credential unavailable'); }
    try { return text(secret); } finally { secret.fill(0); }
  }

  async remove(item: FavoriteConnection): Promise<void> {
    try { await asset.remove(queryFor(item.id)); }
    catch (error) { if (!notFound(error as Object)) { throw new Error('Secure asset removal failed'); } }
  }
}
