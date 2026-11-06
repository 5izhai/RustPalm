// This type deliberately contains no credential value. It is safe to render
// and serialize as asset attributes without loading any saved password.
export class FavoriteConnection {
  id: string = '';
  name: string = '';
  peerId: string = '';
  idServer: string = '';
  serverKey: string = '';
  hasPassword: boolean = false;
}

export function favoriteScopeMatches(item: FavoriteConnection, idServer: string, serverKey: string): boolean {
  return item.idServer === idServer.trim() && item.serverKey === serverKey.trim();
}

export function favoriteEditError(previous: FavoriteConnection | undefined, peerId: string,
  password: string, removePassword: boolean): string {
  if (!/^[0-9]{1,20}$/.test(peerId)) { return '请输入有效的数字设备 ID'; }
  if (password.indexOf('\0') >= 0 || password.length > 256) { return '访问密码格式无效或长度超过 256 个字符'; }
  if (previous !== undefined && previous.hasPassword && previous.peerId !== peerId &&
      password.length === 0 && !removePassword) {
    return '更换设备 ID 时，请输入新密码或勾选删除已保存密码';
  }
  return '';
}

export function favoriteKeepsPassword(previous: FavoriteConnection | undefined, password: string,
  removePassword: boolean): boolean {
  if (removePassword) { return false; }
  return password.length > 0 || (previous !== undefined && previous.hasPassword);
}
