import { router, promptAction } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { preferences } from '@kit.ArkData';
import { util, url } from '@kit.ArkTS';
import { ffiSessionNew, ffiSessionClose, ffiGetOption, ffiSetOption,
  SESSION_KIND_CONTROL } from '../ohos_ffi';
import { evStr, evBool, evNum, parseJsonArray } from '../model/Utils';
import { FavoriteConnections } from '../model/FavoriteConnections';
import { FavoriteConnection, favoriteScopeMatches, favoriteEditError } from '../model/FavoriteModel';
import { globalEvents, RdeskEvent, EventHandler } from '../model/RdeskEvents';

const OPT_ID_SERVER = 'custom-rendezvous-server';
const OPT_RELAY_SERVER = 'relay-server';
const OPT_KEY = 'key';
const RECENT_MAX = 10;

class RecentEntry {
  peerId: string = '';
}

class SessionParams {
  uuid: string = '';
  peerId: string = '';
  sessionKind: number = SESSION_KIND_CONTROL;
}

@Entry
@Component
struct Index {
  @StorageLink('rustpalmCoreReady') coreReady: boolean = false;
  @State peerIdInput: string = '';
  @State connecting: boolean = false;
  @State forceRelay: boolean = false;
  @State recent: RecentEntry[] = [];
  @State showSettings: boolean = false;
  @State setIdServer: string = '';
  @State setRelayServer: string = '';
  @State setKey: string = '';
  @State configuredServer: string = '';
  @State settingsError: string = '';
  @State favorites: FavoriteConnection[] = [];
  @State favoritesLoading: boolean = true;
  @State favoritesError: string = '';
  @State showFavoriteEditor: boolean = false;
  @State favoriteName: string = '';
  @State favoritePeerId: string = '';
  @State favoritePassword: string = '';
  @State favoriteRemovePassword: boolean = false;
  @State favoriteHadPassword: boolean = false;
  @State favoriteSaving: boolean = false;
  @State favoriteEditorError: string = '';
  private editingFavorite: FavoriteConnection | undefined = undefined;
  private favoriteStore: FavoriteConnections = new FavoriteConnections();
  private pageGeneration: number = 0;
  private backgroundHandler: EventHandler | null = null;
  private recentStore: preferences.Preferences | undefined = undefined;

  aboutToAppear(): void {
    this.loadRecent();
    this.configuredServer = ffiGetOption(OPT_ID_SERVER);
    this.forceRelay = ffiGetOption('rustpalm-force-relay') === 'Y';
    this.loadFavorites();
    this.backgroundHandler = (event: RdeskEvent): void => {
      if (event.name === 'rustpalm_app_background') { this.favoritePassword = ''; }
    };
    globalEvents.subscribe(this.backgroundHandler);
  }

  aboutToDisappear(): void {
    this.pageGeneration++;
    this.favoritePassword = '';
    if (this.backgroundHandler !== null) {
      globalEvents.unsubscribe(this.backgroundHandler);
      this.backgroundHandler = null;
    }
  }

  private async loadFavorites(): Promise<void> {
    this.favoritesLoading = true;
    this.favoritesError = '';
    try { this.favorites = await this.favoriteStore.list(); }
    catch (error) { this.favoritesError = '常用连接读取失败，请解锁手机后重试'; }
    finally { this.favoritesLoading = false; }
  }

  private openFavoriteEditor(item: FavoriteConnection | undefined): void {
    if (this.favoriteSaving || this.connecting) { return; }
    this.editingFavorite = item;
    this.favoriteName = item === undefined ? '' : item.name;
    this.favoritePeerId = item === undefined ? this.peerIdInput.replace(/\s+/g, '') : item.peerId;
    this.favoritePassword = '';
    this.favoriteHadPassword = item !== undefined && item.hasPassword;
    this.favoriteRemovePassword = false;
    this.favoriteEditorError = '';
    this.showFavoriteEditor = true;
  }

  private closeFavoriteEditor(): void {
    if (this.favoriteSaving) { return; }
    this.favoritePassword = '';
    this.showFavoriteEditor = false;
    this.editingFavorite = undefined;
  }

  private async saveFavorite(): Promise<void> {
    if (this.favoriteSaving) { return; }
    const peerId = this.favoritePeerId.replace(/\s+/g, '');
    this.favoriteEditorError = favoriteEditError(this.editingFavorite, peerId,
      this.favoritePassword, this.favoriteRemovePassword);
    if (this.favoriteEditorError.length > 0) { return; }
    if (this.editingFavorite === undefined) {
      this.favoriteEditorError = this.configurationError(ffiGetOption(OPT_ID_SERVER),
        ffiGetOption(OPT_RELAY_SERVER), ffiGetOption(OPT_KEY));
      if (this.favoriteEditorError.length > 0) { return; }
      if (this.favorites.length >= 30) { this.favoriteEditorError = '最多保存 30 个常用连接'; return; }
    }
    this.favoriteSaving = true;
    try {
      const saved = await this.favoriteStore.save(this.editingFavorite, this.favoriteName,
        peerId, ffiGetOption(OPT_ID_SERVER), ffiGetOption(OPT_KEY), this.favoritePassword,
        this.favoriteRemovePassword, this.favorites.length);
      this.favorites = [saved, ...this.favorites.filter((entry: FavoriteConnection) => entry.id !== saved.id)];
      this.showFavoriteEditor = false;
      this.editingFavorite = undefined;
    } catch (error) {
      this.favoriteEditorError = '常用连接保存失败，请解锁手机后重试；密码不会写入普通配置';
    } finally {
      this.favoritePassword = '';
      this.favoriteSaving = false;
    }
  }

  private async deleteFavorite(): Promise<void> {
    const item = this.editingFavorite;
    if (item === undefined || this.favoriteSaving) { return; }
    this.favoriteSaving = true;
    try {
      await this.favoriteStore.remove(item);
      this.favorites = this.favorites.filter((entry: FavoriteConnection) => entry.id !== item.id);
      this.showFavoriteEditor = false;
      this.editingFavorite = undefined;
    } catch (error) {
      this.favoriteEditorError = '删除失败，请重试；连接及其已保存密码尚未移除';
    } finally {
      this.favoritePassword = '';
      this.favoriteSaving = false;
    }
  }

  private async connectFavorite(item: FavoriteConnection): Promise<void> {
    if (this.connecting || !this.coreReady || this.favoriteSaving) { return; }
    if (!favoriteScopeMatches(item, ffiGetOption(OPT_ID_SERVER), ffiGetOption(OPT_KEY))) {
      promptAction.showToast({ message: '此常用连接属于另一套服务器配置，请先恢复保存时的服务器和公钥' });
      return;
    }
    this.connecting = true;
    const generation = this.pageGeneration;
    let password = '';
    try {
      password = await this.favoriteStore.password(item);
      if (generation !== this.pageGeneration || AppStorage.get<boolean>('rustpalmForeground') !== true ||
          !favoriteScopeMatches(item, ffiGetOption(OPT_ID_SERVER), ffiGetOption(OPT_KEY))) {
        this.connecting = false;
        return;
      }
      this.peerIdInput = item.peerId;
      this.openSession(item.peerId, password);
    } catch (error) {
      this.connecting = false;
      promptAction.showToast({ message: '已保存密码读取失败，请解锁手机后重试，或编辑此连接重新保存密码' });
    } finally { password = ''; }
  }

  private loadRecent(): void {
    preferences.getPreferences(getContext(this), 'rustpalm_index')
      .then((store: preferences.Preferences) => {
        this.recentStore = store;
        const list: RecentEntry[] = [];
        for (const item of parseJsonArray(store.getSync('recent_list', '') as string)) {
          const peerId = evStr(item['peerId']);
          if (!/^[0-9]{1,20}$/.test(peerId) || evBool(item['isFileTransfer'])
            || evNum(item['sessionKind']) !== SESSION_KIND_CONTROL) {
            continue;
          }
          const entry = new RecentEntry();
          entry.peerId = peerId;
          list.push(entry);
        }
        this.recent = list.slice(0, RECENT_MAX);
      }).catch((_error: BusinessError) => {
        promptAction.showToast({ message: '最近连接读取失败，可直接输入设备 ID 连接' });
      });
  }

  private saveRecent(): void {
    if (this.recentStore === undefined) {
      return;
    }
    try {
      this.recentStore.putSync('recent_list', JSON.stringify(this.recent));
      this.recentStore.flush().catch((_error: BusinessError) => {
        promptAction.showToast({ message: '最近连接保存失败' });
      });
    } catch (e) {
      promptAction.showToast({ message: '最近连接保存失败' });
    }
  }

  private openSettings(): void {
    this.setIdServer = ffiGetOption(OPT_ID_SERVER);
    this.setRelayServer = ffiGetOption(OPT_RELAY_SERVER);
    this.setKey = ffiGetOption(OPT_KEY);
    this.settingsError = '';
    this.showSettings = true;
  }

  private validServer(address: string): boolean {
    // Hostnames/IPv4 and bracketed IPv6 share the optional port suffix.
    const match = /^(?:[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?|\[[0-9A-Fa-f:.]+\])(?::([0-9]{1,5}))?$/.exec(address);
    if (match === null) {
      return false;
    }
    if (match[1] !== undefined && (Number(match[1]) < 1 || Number(match[1]) > 65535)) {
      return false;
    }
    try {
      const host = url.URL.parseURL(`http://${address}`).hostname;
      return host.startsWith('[') || (host.length <= 253 && host.split('.').every((label: string) => {
        return /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$/.test(label);
      }));
    } catch (e) {
      return false;
    }
  }

  private configurationError(idServer: string, relayServer: string, key: string): string {
    if (!this.validServer(idServer)) {
      return '请输入有效的 ID 服务器地址，支持域名或 IP，以及可选端口';
    }
    if (relayServer.length > 0 && !this.validServer(relayServer)) {
      return '请检查中继服务器地址和端口';
    }
    if (!/^[A-Za-z0-9+/]{43}=$/.test(key)) {
      return '请输入服务器 id_ed25519.pub 中的完整公钥';
    }
    try {
      if (new util.Base64Helper().decodeSync(key).length !== 32) {
        return '服务器公钥格式错误';
      }
    } catch (e) {
      return '服务器公钥格式错误';
    }
    return '';
  }

  private saveSettings(): void {
    const idServer = this.setIdServer.trim();
    const relayServer = this.setRelayServer.trim();
    const key = this.setKey.trim();
    this.settingsError = this.configurationError(idServer, relayServer, key);
    if (this.settingsError.length > 0) {
      return;
    }
    const oldIdServer = ffiGetOption(OPT_ID_SERVER);
    const oldRelayServer = ffiGetOption(OPT_RELAY_SERVER);
    const oldKey = ffiGetOption(OPT_KEY);
    if (ffiSetOption(OPT_ID_SERVER, idServer) !== 0
      || ffiSetOption(OPT_RELAY_SERVER, relayServer) !== 0
      || ffiSetOption(OPT_KEY, key) !== 0) {
      ffiSetOption(OPT_ID_SERVER, oldIdServer);
      ffiSetOption(OPT_RELAY_SERVER, oldRelayServer);
      ffiSetOption(OPT_KEY, oldKey);
      this.settingsError = '服务器设置保存失败，请重新打开应用后重试';
      return;
    }
    this.configuredServer = idServer;
    this.showSettings = false;
    promptAction.showToast({ message: '服务器设置已保存' });
  }

  private addRecent(peerId: string): void {
    const entry = new RecentEntry();
    entry.peerId = peerId;
    this.recent = [entry, ...this.recent.filter((item: RecentEntry) => item.peerId !== peerId)]
      .slice(0, RECENT_MAX);
    this.saveRecent();
  }

  private removeRecent(peerId: string): void {
    this.recent = this.recent.filter((item: RecentEntry) => item.peerId !== peerId);
    this.saveRecent();
  }

  private connect(): void {
    if (this.connecting || !this.coreReady) {
      return;
    }
    const configError = this.configurationError(ffiGetOption(OPT_ID_SERVER),
      ffiGetOption(OPT_RELAY_SERVER), ffiGetOption(OPT_KEY));
    if (configError.length > 0) {
      this.openSettings();
      this.settingsError = configError;
      return;
    }
    const peerId = this.peerIdInput.replace(/\s+/g, '');
    if (!/^[0-9]{1,20}$/.test(peerId)) {
      promptAction.showToast({ message: '请输入电脑端 RustDesk 的数字设备 ID' });
      return;
    }
    this.connecting = true;
    this.openSession(peerId, '');
  }

  private openSession(peerId: string, password: string): void {
    const uuid = ffiSessionNew(peerId, SESSION_KIND_CONTROL, password, this.forceRelay);
    if (uuid.length === 0) {
      this.connecting = false;
      promptAction.showToast({ message: '无法创建连接，请重新打开应用后重试' });
      return;
    }
    const params = new SessionParams();
    params.uuid = uuid;
    params.peerId = peerId;
    // RemotePage subscribes to events before starting the native session.
    router.pushUrl({ url: 'pages/RemotePage', params: params }).then(() => {
      this.addRecent(peerId);
    }).catch((_error: BusinessError) => {
      ffiSessionClose(uuid);
      this.connecting = false;
      promptAction.showToast({ message: '远程桌面打开失败，请重试' });
    });
  }

  onPageShow(): void {
    this.connecting = false;
  }

  onBackPress(): boolean {
    if (this.showFavoriteEditor) {
      this.closeFavoriteEditor();
      return true;
    }
    if (this.showSettings) {
      this.showSettings = false;
      return true;
    }
    return false;
  }

  private showAbout(): void {
    promptAction.showDialog({
      title: 'RustPalm 0.1.6',
      message: '基于 RustDesk 的 HarmonyOS 远程桌面主控端。\n\n采用 AGPL-3.0 开源许可证，源代码与许可证随项目一并交付。',
      buttons: [{ text: '知道了', color: '#176B62' }]
    }).catch((_error: BusinessError) => {});
  }

  @Builder
  favoriteEditor() {
    Column({ space: 16 }) {
      Row() {
        Text('常用连接').fontSize(24).fontWeight(FontWeight.Bold).layoutWeight(1)
        Button('返回', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.favoriteSaving)
          .onClick(() => this.closeFavoriteEditor())
      }.width('100%')
      TextInput({ text: this.favoriteName, placeholder: '名称（选填，例如家中电脑）' })
        .maxLength(40).height(48).fontColor('#102035').backgroundColor('#FFFFFF')
        .onChange((value: string) => { this.favoriteName = value; })
      TextInput({ text: this.favoritePeerId, placeholder: 'RustDesk 设备 ID' })
        .type(InputType.Number).maxLength(24).height(48).fontColor('#102035').backgroundColor('#FFFFFF')
        .onChange((value: string) => { this.favoritePeerId = value; })
      Text(this.favoriteHadPassword ? '已保存访问密码。留空保留，输入新密码替换。' : '访问密码（选填）')
        .fontSize(14).fontColor('#526176').width('100%')
      TextInput({ text: this.favoritePassword, placeholder: this.favoriteHadPassword ? '输入新访问密码' : 'RustDesk 访问密码' })
        .type(InputType.Password).showPasswordIcon(false).maxLength(256).height(48)
        .fontColor('#102035').backgroundColor('#FFFFFF').enabled(!this.favoriteRemovePassword)
        .onChange((value: string) => { this.favoritePassword = value; })
      if (this.favoriteHadPassword) {
        Row({ space: 12 }) {
          Text('删除已保存密码').fontSize(14).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.favoriteRemovePassword })
            .onChange((enabled: boolean) => { this.favoriteRemovePassword = enabled; this.favoritePassword = ''; })
        }.width('100%')
      }
      Text('密码仅保存在本机系统安全存储中，点击常用连接时用于认证。编辑时不会显示原密码。')
        .fontSize(13).fontColor('#526176').width('100%')
      Text('保存时的 ID 服务器：' + (this.editingFavorite === undefined ? this.configuredServer : this.editingFavorite.idServer))
        .fontSize(12).fontColor('#526176').width('100%')
      if (this.favoriteEditorError.length > 0) {
        Text(this.favoriteEditorError).fontColor('#B23D2A').fontSize(14).width('100%')
      }
      Button(this.favoriteSaving ? '正在保存…' : '保存常用连接').width('100%').height(48)
        .backgroundColor('#176B62').enabled(!this.favoriteSaving).onClick(() => { this.saveFavorite(); })
      if (this.editingFavorite !== undefined) {
        Button('删除此连接及已保存密码', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .fontColor('#B23D2A').enabled(!this.favoriteSaving).onClick(() => { this.deleteFavorite(); })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  favoriteList() {
    Column({ space: 10 }) {
      Row() {
        Text('常用连接').fontSize(18).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button('添加', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .enabled(!this.favoritesLoading && !this.connecting).fontColor('#176B62')
          .onClick(() => this.openFavoriteEditor(undefined))
      }.width('100%')
      if (this.favoritesLoading) {
        Text('正在读取常用连接…').fontSize(13).fontColor('#596B73')
      } else if (this.favoritesError.length > 0) {
        Text(this.favoritesError).fontSize(13).fontColor('#B23D2A')
        Button('重新读取', { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick(() => { this.loadFavorites(); })
      } else if (this.favorites.length === 0) {
        Text('保存常用电脑的 ID 和访问密码，下次点选即可连接。').fontSize(13).fontColor('#596B73').width('100%')
      }
      ForEach(this.favorites, (item: FavoriteConnection) => {
        Row({ space: 8 }) {
          Button({ type: ButtonType.Normal }) {
            Column({ space: 4 }) {
              Text(item.name.length > 0 ? item.name : item.peerId).fontSize(16).fontColor('#203A3A')
              Text((item.name.length > 0 ? item.peerId + ' · ' : '') + (item.hasPassword ? '已保存密码' : '连接时认证'))
                .fontSize(12).fontColor('#596B73')
            }.alignItems(HorizontalAlign.Start).width('100%')
          }.layoutWeight(1).padding(14).backgroundColor('#FFFFFF').borderRadius(12)
            .enabled(this.coreReady && !this.connecting).onClick(() => { this.connectFavorite(item); })
          Button('编辑', { buttonStyle: ButtonStyleMode.TEXTUAL }).fontColor('#176B62')
            .enabled(!this.connecting).onClick(() => this.openFavoriteEditor(item))
        }.width('100%').backgroundColor('#FFFFFF').borderRadius(12).clip(true)
      }, (item: FavoriteConnection) => item.id)
    }.width('100%')
  }

  @Builder
  serverSettings() {
    Column({ space: 16 }) {
      Row() {
        Text('服务器设置').fontSize(24).fontWeight(FontWeight.Bold).layoutWeight(1)
        Button('返回', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .onClick(() => { this.showSettings = false; })
      }.width('100%')
      Text('填写与你的电脑端相同的 RustDesk 自建服务器。')
        .fontSize(14).fontColor('#596B73').width('100%')
      Column({ space: 8 }) {
        Text('ID 服务器').fontSize(14).width('100%')
        TextInput({ placeholder: '例如 rd.example.com:21116', text: this.setIdServer })
          .height(48).onChange((value: string) => { this.setIdServer = value; })
        Text('中继服务器（选填）').fontSize(14).width('100%').margin({ top: 8 })
        TextInput({ placeholder: '留空时使用 ID 服务器提供的中继', text: this.setRelayServer })
          .height(48).onChange((value: string) => { this.setRelayServer = value; })
        Text('服务器公钥').fontSize(14).width('100%').margin({ top: 8 })
        TextArea({ placeholder: '粘贴 id_ed25519.pub 文件内容', text: this.setKey })
          .height(100).onChange((value: string) => { this.setKey = value; })
      }.width('100%')
      if (this.settingsError.length > 0) {
        Text(this.settingsError).fontSize(14).fontColor('#B23D2A').width('100%')
      }
      Button('保存服务器设置').width('100%').height(48).backgroundColor('#176B62')
        .enabled(this.coreReady).onClick(() => { this.saveSettings(); })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  connectionHome() {
    Column({ space: 20 }) {
      Row({ space: 12 }) {
        Image($r('app.media.rustpalm_icon')).width(48).height(48)
        Column({ space: 3 }) {
          Text('RustPalm').fontSize(28).fontWeight(FontWeight.Bold)
          Text('掌上连接你的电脑').fontSize(14).fontColor('#596B73')
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      }.width('100%').margin({ top: 12, bottom: 12 })

      if (!this.coreReady) {
        Text('连接组件初始化失败，请重新打开应用。如仍失败，请重新安装完整应用包。')
          .fontSize(14).fontColor('#B23D2A').padding(16)
          .backgroundColor('#FFF0EA').borderRadius(16).width('100%')
      }

      Column({ space: 16 }) {
        Text('连接电脑').fontSize(20).fontWeight(FontWeight.Medium).width('100%')
        TextInput({ placeholder: '电脑端 RustDesk 设备 ID', text: this.peerIdInput })
          .height(52).fontSize(18).type(InputType.Number)
          .onChange((value: string) => { this.peerIdInput = value; })
          .onSubmit(() => { this.connect(); })
        Button(this.connecting ? '正在连接…' : '连接')
          .width('100%').height(50).fontSize(17).backgroundColor('#176B62')
          .enabled(this.coreReady && !this.connecting).onClick(() => { this.connect(); })
        Text('连接后在电脑端允许访问，或输入访问密码。')
          .fontSize(13).fontColor('#596B73').width('100%')
        Row({ space: 12 }) {
          Text('强制中继连接').fontSize(14).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.forceRelay })
            .onChange((enabled: boolean) => {
              if (ffiSetOption('rustpalm-force-relay', enabled ? 'Y' : '') === 0) {
                this.forceRelay = enabled;
              }
            })
        }.width('100%')
      }.padding(20).backgroundColor('#FFFFFF').borderRadius(20).width('100%')

      this.favoriteList()

      Button({ type: ButtonType.Normal }) {
        Row({ space: 12 }) {
          Column({ space: 5 }) {
            Text('自建服务器').fontSize(15).fontColor('#203A3A')
            Text(this.configuredServer.length > 0 ? this.configuredServer : '首次连接前完成设置')
              .fontSize(13).fontColor('#596B73').maxLines(2)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Text('设置').fontSize(14).fontColor('#176B62')
        }.width('100%').padding(18)
      }.width('100%').backgroundColor('#E8F0ED').borderRadius(16)
        .onClick(() => { this.openSettings(); })

      if (this.recent.length > 0) {
        Column({ space: 8 }) {
          Text('最近连接').fontSize(16).fontWeight(FontWeight.Medium).width('100%')
          ForEach(this.recent, (entry: RecentEntry) => {
            Row({ space: 8 }) {
              Button(entry.peerId, { buttonStyle: ButtonStyleMode.TEXTUAL })
                .fontColor('#203A3A').layoutWeight(1).height(48)
                .onClick(() => { this.peerIdInput = entry.peerId; })
              Button('移除', { buttonStyle: ButtonStyleMode.TEXTUAL })
                .fontColor('#596B73').height(48)
                .accessibilityText(`移除设备 ${entry.peerId}`)
                .onClick(() => { this.removeRecent(entry.peerId); })
            }.width('100%').backgroundColor('#FFFFFF').borderRadius(12)
          }, (entry: RecentEntry) => entry.peerId)
        }.width('100%')
      }
      Text('切换应用或来电时保留会话；长时间后台运行受系统限制。').fontSize(12).fontColor('#6C7E82').width('100%')
      Button('关于与开源说明', { buttonStyle: ButtonStyleMode.TEXTUAL })
        .fontSize(13).fontColor('#596B73').onClick(() => { this.showAbout(); })
    }.width('100%')
  }

  build() {
    Scroll() {
      Column() {
        if (this.showFavoriteEditor) {
          this.favoriteEditor()
        } else if (this.showSettings) {
          this.serverSettings()
        } else {
          this.connectionHome()
        }
      }.width('100%').padding({ left: 24, right: 24, top: 16, bottom: 32 })
    }.width('100%').height('100%').align(Alignment.Top)
      .backgroundColor('#F4F7F5').scrollBar(BarState.Auto)
  }
}
