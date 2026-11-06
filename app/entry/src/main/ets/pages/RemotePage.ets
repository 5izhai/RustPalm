import { router, window, promptAction } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ffiSessionStart, ffiSessionClose, ffiSessionLogin, ffiSessionSend2fa,
  ffiSendMouse, ffiInputKey, ffiInputString, ffiInitVideo, ffiDeinitVideo,
  ffiRefreshVideo, ffiToggleOption, ffiGetToggleOption
} from '../ohos_ffi';
import { globalEvents, RdeskEvent, EventHandler } from '../model/RdeskEvents';
import { routerParams, evStr, evNum, evBool, parseJsonArray } from '../model/Utils';
import { mapRemotePoint, clampOffset } from '../model/RemoteGeometry';
import { authenticationAction, sessionMessage } from '../model/SessionMessages';
import { MOUSE_MOVE, LEFT_DOWN, LEFT_UP, RIGHT_DOWN, RIGHT_UP,
  pointerCommands, wheelCommands } from '../model/RemoteMouse';
import { GestureContact, activeContacts, WheelAccumulator } from '../model/RemoteGesture';
import { toolbarKeyCommand, lockScreenCommand } from '../model/RemoteKeys';

class CursorShape {
  width: number = 0;
  height: number = 0;
  hotX: number = 0;
  hotY: number = 0;
  pixels: image.PixelMap | undefined = undefined;
}

@Entry
@Component
struct RemotePage {
  @StorageLink('rustpalmLandscape') @Watch('layoutModeChanged') landscape: boolean = false;
  @State availableWidth: number = 0;
  @State availableHeight: number = 0;
  @State showMore: boolean = false;
  private textController: TextInputController = new TextInputController();
  private uuid: string = '';
  @State peerId: string = '';
  @State status: string = '正在连接…';
  @State route: string = '';
  @State ready: boolean = false;
  @State closed: boolean = false;
  @State disconnecting: boolean = false;
  private pageActive: boolean = false;
  @State keyboardAllowed: boolean = true;
  @State viewOnly: boolean = false;
  @State remoteWidth: number = 0;
  @State remoteHeight: number = 0;
  @State originX: number = 0;
  @State originY: number = 0;
  private displayIndex: number = 0;
  @State containerWidth: number = 0;
  @State containerHeight: number = 0;
  @State zoom: number = 1;
  @State offsetX: number = 0;
  @State offsetY: number = 0;
  @State inputMode: string = 'pointer';
  @State textInputVisible: boolean = false;
  @State inputText: string = '';
  @State protectInput: boolean = true;
  @State backgroundSuspended: boolean = false;
  @State ctrl: boolean = false;
  @State alt: boolean = false;
  @State shift: boolean = false;
  @State authPrompt: string = '';
  @State authValue: string = '';
  @State authMessage: string = '';
  @State codec: string = '';
  @State delay: string = '';
  @State cursorX: number = 0;
  @State cursorY: number = 0;
  @State cursor: CursorShape = new CursorShape();
  @State cursorEmbedded: boolean = false;
  private cursorId: string = '';
  private cursorCache: Map<string, CursorShape> = new Map();
  private controller: XComponentController = new XComponentController();
  private surfaceReady: boolean = false;
  private videoBound: boolean = false;
  private eventHandler: EventHandler | null = null;
  private connectionTimer: number = -1;
  private connectionTimeoutMessage: string = '';
  private timeoutPaused: boolean = false;
  private pressTimer: number = -1;
  private leftHeld: boolean = false;
  private moved: boolean = false;
  private longPressed: boolean = false;
  private startX: number = 0;
  private startY: number = 0;
  private remoteMouseX: number = 0;
  private remoteMouseY: number = 0;
  private multiTouch: boolean = false;
  private suppressTouch: boolean = false;
  private pinchDistance: number = 0;
  private pinchZoom: number = 1;
  private pinchActive: boolean = false;
  private midpointX: number = 0;
  private midpointY: number = 0;
  private wheel: WheelAccumulator = new WheelAccumulator();
  private scrollAnchorX: number = 0;
  private scrollAnchorY: number = 0;
  private scrollAnchorValid: boolean = false;
  private singleY: number = 0;
  private singleX: number = 0;

  aboutToAppear(): void {
    this.pageActive = true;
    const params = routerParams();
    this.uuid = evStr(params['uuid']);
    this.peerId = evStr(params['peerId']);
    this.eventHandler = (event: RdeskEvent): void => {
      if (event.name === 'rustpalm_app_background') {
        this.suspendPresentation();
      } else if (event.name === 'rustpalm_app_foreground') {
        this.resumePresentation();
      } else if (event.name === 'rustpalm_app_destroy') {
        this.finish('应用已退出，会话已结束');
      } else if (!this.closed && event.get('session_id') === this.uuid) {
        this.onEvent(event);
      }
    };
    globalEvents.subscribe(this.eventHandler);
    this.backgroundSuspended = AppStorage.get<boolean>('rustpalmForeground') !== true;
    this.viewOnly = ffiGetToggleOption(this.uuid, 'view-only') === 1;
    if (this.uuid.length === 0 || ffiSessionStart(this.uuid) !== 0) {
      this.finish('连接启动失败，请返回重试');
      return;
    }
    this.keepScreenOn(true);
    AppStorage.SetOrCreate<boolean>('rustpalmSessionActive', true);
    this.armConnectionTimeout('连接等待超时，请检查网络和电脑是否在线');
  }

  aboutToDisappear(): void {
    this.pageActive = false;
    this.finish('会话已结束');
    if (this.eventHandler !== null) {
      globalEvents.unsubscribe(this.eventHandler);
      this.eventHandler = null;
    }
  }

  onBackPress(): boolean {
    if (this.showMore) { this.showMore = false; return true; }
    if (this.textInputVisible) { this.toggleTextInput(); return true; }
    this.disconnect();
    return true;
  }

  private keepScreenOn(enabled: boolean): void {
    window.getLastWindow(getContext(this)).then((win: window.Window) => {
      win.setWindowKeepScreenOn(enabled && !this.closed && !this.backgroundSuspended);
    }).catch(() => {});
  }

  private suspendPresentation(): void {
    if (this.closed) { return; }
    this.showMore = false;
    this.backgroundSuspended = true;
    this.cancelGesture();
    this.ctrl = false;
    this.alt = false;
    this.shift = false;
    this.inputText = '';
    this.authValue = '';
    this.protectInput = true;
    if (this.connectionTimer >= 0) {
      clearTimeout(this.connectionTimer);
      this.connectionTimer = -1;
      this.timeoutPaused = true;
    }
    this.keepScreenOn(false);
    if (this.videoBound) {
      ffiDeinitVideo(this.uuid);
      this.videoBound = false;
    }
    hilog.info(0x5253, 'RustPalmSession', 'background: preserving session, pausing presentation');
  }

  private resumePresentation(): void {
    if (this.closed || !this.backgroundSuspended) { return; }
    this.backgroundSuspended = false;
    this.keepScreenOn(true);
    this.bindVideo();
    if (this.ready) { ffiRefreshVideo(this.uuid); }
    if (this.timeoutPaused) { this.armConnectionTimeout(this.connectionTimeoutMessage); }
    hilog.info(0x5253, 'RustPalmSession', 'foreground: resuming existing session');
  }

  private clearPress(): void {
    if (this.pressTimer >= 0) {
      clearTimeout(this.pressTimer);
      this.pressTimer = -1;
    }
  }

  private clearConnectionTimeout(): void {
    if (this.connectionTimer >= 0) {
      clearTimeout(this.connectionTimer);
      this.connectionTimer = -1;
    }
    this.timeoutPaused = false;
    this.connectionTimeoutMessage = '';
  }

  private armConnectionTimeout(message: string): void {
    this.clearConnectionTimeout();
    this.connectionTimeoutMessage = message;
    if (this.backgroundSuspended) { this.timeoutPaused = true; return; }
    this.connectionTimer = setTimeout((): void => {
      this.connectionTimer = -1;
      if (!this.ready) { this.finish(message); }
    }, 90000) as number;
  }

  private releaseMouse(): void {
    if (this.leftHeld) {
      // Always release even after the peer revokes input permission.
      ffiSendMouse(this.uuid, LEFT_UP, 0, 0, false, false, false, false);
      this.leftHeld = false;
    }
  }

  private cancelGesture(): void {
    this.clearPress();
    this.releaseMouse();
    this.multiTouch = false;
    this.suppressTouch = true;
    this.scrollAnchorValid = false;
    this.wheel.reset();
  }

  private finish(message: string): void {
    if (this.closed) { return; }
    this.showMore = false;
    this.releaseMouse();
    this.closed = true;
    AppStorage.SetOrCreate<boolean>('rustpalmSessionActive', false);
    const ended = new RdeskEvent();
    ended.name = 'rustpalm_session_closed';
    globalEvents.dispatch(ended);
    this.ready = false;
    this.status = message;
    this.authValue = '';
    this.authPrompt = '';
    this.inputText = '';
    this.ctrl = false;
    this.alt = false;
    this.shift = false;
    this.clearPress();
    if (this.connectionTimer >= 0) {
      clearTimeout(this.connectionTimer);
      this.connectionTimer = -1;
    }
    if (this.videoBound) {
      ffiDeinitVideo(this.uuid);
      this.videoBound = false;
    }
    ffiSessionClose(this.uuid);
    this.keepScreenOn(false);
    this.cursor = new CursorShape();
    for (const shape of this.cursorCache.values()) { shape.pixels?.release(); }
    this.cursorCache.clear();
  }

  private async disconnect(): Promise<void> {
    if (this.disconnecting) { return; }
    const shouldLock = this.canControl();
    const cannotLock = this.ready && !this.closed && !shouldLock;
    this.disconnecting = true;
    this.cancelGesture();
    this.ctrl = false;
    this.alt = false;
    this.shift = false;
    this.inputText = '';
    this.authValue = '';
    if (shouldLock) {
      this.status = '正在请求锁屏并断开…';
      const key = lockScreenCommand();
      const result = ffiInputKey(this.uuid, key.name, key.down, key.press,
        key.alt, key.ctrl, key.shift, key.command);
      hilog.info(0x5253, 'RustPalmSession', 'lock before disconnect queued; result=%{public}d', result);
      if (result === 0) {
        // The core sends LOCK_SCREEN before Close on the same FIFO. Leave a
        // short grace period for remote input processing; there is no lock ACK.
        await new Promise<void>((resolve: () => void) => { setTimeout(resolve, 500); });
      } else {
        try { promptAction.showToast({ message: '锁屏指令发送失败，将断开连接，请在电脑端确认锁屏' }); } catch (e) {}
      }
    } else if (cannotLock) {
      try { promptAction.showToast({ message: '当前会话不允许控制，无法请求远程锁屏' }); } catch (e) {}
    }
    if (!this.pageActive) { return; }
    this.finish('会话已结束');
    router.back();
  }

  private bindVideo(): void {
    if (!this.surfaceReady || this.closed || this.backgroundSuspended) { return; }
    try {
      this.videoBound = ffiInitVideo(this.uuid, this.displayIndex,
        this.controller.getXComponentSurfaceId(),
        Math.max(128, this.remoteWidth), Math.max(128, this.remoteHeight)) === 0;
      if (!this.videoBound) { this.finish('显示初始化失败，请返回重试'); }
    } catch (error) {
      this.finish('显示组件不可用，请返回重试');
    }
  }

  private onEvent(event: RdeskEvent): void {
    switch (event.name) {
      case 'first_frame':
        this.status = '已连接';
        hilog.info(0x5253, 'RustPalmSession', 'first video frame presented');
        break;
      case 'connection_ready':
        hilog.info(0x5253, 'RustPalmSession', 'transport ready; secure=%{public}s direct=%{public}s',
          String(event.bool('secure')), String(event.bool('direct')));
        if (!event.bool('secure')) { this.finish('连接未通过加密校验'); return; }
        this.route = event.bool('direct') ? '加密直连' : '加密中继';
        this.status = '等待电脑端授权或密码验证…';
        break;
      case 'peer_info':
        hilog.info(0x5253, 'RustPalmSession', 'authentication accepted');
        this.ready = true;
        this.viewOnly = ffiGetToggleOption(this.uuid, 'view-only') === 1;
        this.status = '已连接';
        this.authPrompt = '';
        this.authValue = '';
        this.clearConnectionTimeout();
        this.displayIndex = event.num('current_display');
        this.updateDisplays(event.get('displays'));
        break;
      case 'sync_peer_info':
        this.updateDisplays(event.get('displays'));
        break;
      case 'switch_display':
        this.displayIndex = event.num('display');
        this.setDisplay(event.num('width'), event.num('height'), event.num('x'),
          event.num('y'), event.bool('cursor_embedded'));
        break;
      case 'permission':
        if (event.get('keyboard').length > 0) {
          if (!event.bool('keyboard')) { this.releaseMouse(); }
          this.keyboardAllowed = event.bool('keyboard');
        }
        break;
      case 'msgbox':
        const action = authenticationAction(event.get('type'));
        this.authMessage = sessionMessage(event.get('type'), event.get('title'), event.get('text'));
        hilog.info(0x5253, 'RustPalmSession', 'authentication action=%{public}s retry=%{public}s',
          action, String(event.get('type') === 're-input-password'));
        if (action === 'connected') {
          // The core emits success AFTER peer_info, before the first image.
          // This is a progress notification, never a request to close the session.
          this.authPrompt = '';
          this.authValue = '';
          this.status = '已连接，等待桌面画面…';
        } else if (action === 'password' || action === '2fa') {
          // User input time must not consume the network connection deadline.
          this.clearConnectionTimeout();
          this.authPrompt = action;
          this.authValue = '';
          this.status = action === 'password' ? '等待输入电脑访问密码' : '等待输入验证码';
        } else if (action === 'waiting') {
          this.clearConnectionTimeout();
          this.authPrompt = '';
          this.authValue = '';
          this.status = '等待电脑端允许访问…';
        } else if (action === 'notice') {
          this.status = '电脑正在显示系统授权窗口，请在电脑端处理';
        } else {
          this.finish(this.authMessage.length > 0 ? this.authMessage : '连接失败，请返回重试');
        }
        break;
      case 'cancel_msgbox':
        if (this.ready) {
          this.status = '已连接';
        }
        break;
      case 'connection_closed':
        this.finish('电脑已断开连接，请返回重试');
        break;
      case 'update_quality_status':
        if (event.get('codec_format').length > 0) { this.codec = event.get('codec_format'); }
        if (event.get('delay').length > 0) { this.delay = event.get('delay'); }
        break;
      case 'cursor_data': this.updateCursor(event); break;
      case 'cursor_id': this.selectCursor(event.get('id')); break;
      case 'cursor_position':
        this.cursorX = event.num('x');
        this.cursorY = event.num('y');
        break;
    }
  }

  private updateDisplays(json: string): void {
    const displays = parseJsonArray(json);
    if (this.displayIndex < 0 || this.displayIndex >= displays.length) { this.displayIndex = 0; }
    if (displays.length > 0) {
      const display = displays[this.displayIndex];
      this.setDisplay(evNum(display['width']), evNum(display['height']),
        evNum(display['x']), evNum(display['y']), evBool(display['cursor_embedded']));
    }
  }

  private setDisplay(width: number, height: number, x: number, y: number, embedded: boolean): void {
    if (width <= 0 || height <= 0) { return; }
    this.cancelGesture();
    this.remoteWidth = width;
    this.remoteHeight = height;
    this.originX = x;
    this.originY = y;
    this.cursorEmbedded = embedded;
    this.resetView();
    this.bindVideo();
  }

  private updateCursor(event: RdeskEvent): void {
    const id = event.get('id');
    const width = event.num('width');
    const height = event.num('height');
    if (width <= 0 || height <= 0 || width > 512 || height > 512 || id.length === 0) { return; }
    this.selectCursor(id);
    if (this.cursorCache.has(id)) { return; }
    if (this.cursorCache.size >= 16) {
      this.cursor = new CursorShape();
      for (const item of this.cursorCache.values()) { item.pixels?.release(); }
      this.cursorCache.clear();
    }
    const shape = new CursorShape();
    shape.width = width;
    shape.height = height;
    shape.hotX = event.num('hotx');
    shape.hotY = event.num('hoty');
    this.cursorCache.set(id, shape);
    try {
      const bytes = new util.Base64Helper().decodeSync(event.get('colors'));
      if (bytes.byteLength !== width * height * 4) { this.cursorCache.delete(id); return; }
      image.createPixelMap(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength),
        { size: { width: width, height: height }, pixelFormat: image.PixelMapFormat.RGBA_8888 })
        .then((pixels: image.PixelMap) => {
          if (this.closed || this.cursorCache.get(id) !== shape) { pixels.release(); return; }
          shape.pixels = pixels;
          if (this.cursorId === id) { this.cursor = shape; }
        }).catch(() => { this.cursorCache.delete(id); });
    } catch (error) {
      this.cursorCache.delete(id);
    }
  }

  private selectCursor(id: string): void {
    this.cursorId = id;
    const shape = this.cursorCache.get(id);
    if (shape !== undefined && shape.pixels !== undefined) { this.cursor = shape; }
  }

  private canControl(): boolean {
    return this.ready && !this.closed && !this.disconnecting && !this.backgroundSuspended && this.keyboardAllowed && !this.viewOnly;
  }

  private mouseAt(mask: number, x: number, y: number): void {
    if (!this.canControl()) { return; }
    const point = mapRemotePoint(x, y, this.containerWidth, this.containerHeight,
      this.remoteWidth, this.remoteHeight, this.zoom, this.offsetX, this.offsetY, this.originX, this.originY);
    if (!point.inside && !this.leftHeld) { return; }
    this.remoteMouseX = point.x;
    this.remoteMouseY = point.y;
    for (const command of pointerCommands(mask, point.x, point.y)) {
      ffiSendMouse(this.uuid, command.mask, command.x, command.y, this.alt, this.ctrl, this.shift, false);
    }
    if (mask === LEFT_DOWN) { this.leftHeld = true; }
    else if (mask === LEFT_UP) { this.leftHeld = false; }
  }

  private beginScroll(x: number, y: number): void {
    this.wheel.reset();
    const point = mapRemotePoint(x, y, this.containerWidth, this.containerHeight,
      this.remoteWidth, this.remoteHeight, this.zoom, this.offsetX, this.offsetY, this.originX, this.originY);
    this.scrollAnchorX = point.x;
    this.scrollAnchorY = point.y;
    this.scrollAnchorValid = point.inside;
  }

  private scrollBy(delta: number): void {
    if (!this.canControl() || !this.scrollAnchorValid) { return; }
    const steps = this.wheel.add(delta);
    if (steps === 0) { return; }
    for (const command of wheelCommands(this.scrollAnchorX, this.scrollAnchorY, steps)) {
      ffiSendMouse(this.uuid, command.mask, command.x, command.y, false, false, false, false);
    }
  }

  private selectInputMode(mode: string): void {
    this.cancelGesture();
    this.inputMode = this.inputMode === mode ? 'pointer' : mode;
  }

  private inputHint(): string {
    if (this.viewOnly || !this.keyboardAllowed) { return '只读模式'; }
    if (this.inputMode === 'drag') { return '拖动模式 · 单指按住拖动'; }
    if (this.inputMode === 'scroll') { return '滚动模式 · 在目标栏目上单指上下滑动'; }
    if (this.inputMode === 'pan') { return '平移模式 · 单指移动放大的画面'; }
    if (this.inputMode === 'right') { return '右键模式 · 点击目标执行一次右键'; }
    return '轻点左键 · 长按右键 · 双指滚动或捏合缩放';
  }

  private handleTouch(event: TouchEvent): void {
    if (this.closed || this.disconnecting || !this.ready) { return; }
    if (event.type === TouchType.Cancel) {
      this.cancelGesture();
      return;
    }
    const contacts = activeContacts(
      event.touches.map((touch: TouchObject) => new GestureContact(touch.id, touch.x, touch.y)),
      event.changedTouches.map((touch: TouchObject) => new GestureContact(touch.id, touch.x, touch.y)),
      event.type === TouchType.Up);
    // Consume both Up events from a multi-touch gesture, even when the
    // platform omits the lifted finger from touches. Never turn them into taps.
    if (event.type === TouchType.Up && this.multiTouch) {
      this.clearPress();
      this.releaseMouse();
      this.suppressTouch = contacts.length > 0;
      if (contacts.length === 0) { this.multiTouch = false; }
      return;
    }
    if (event.type === TouchType.Down && contacts.length === 1) {
      this.suppressTouch = false;
      this.multiTouch = false;
    }
    if (this.suppressTouch) {
      return;
    }
    if (contacts.length >= 2) {
      this.clearPress();
      this.releaseMouse();
      const a = contacts[0];
      const b = contacts[1];
      const centerX = (a.x + b.x) / 2;
      const centerY = (a.y + b.y) / 2;
      const distance = Math.hypot(a.x - b.x, a.y - b.y);
      if (!this.multiTouch) {
        this.multiTouch = true;
        this.pinchDistance = Math.max(1, distance);
        this.pinchZoom = this.zoom;
        this.pinchActive = false;
        this.midpointX = centerX;
        this.midpointY = centerY;
        this.beginScroll(centerX, centerY);
      } else if (event.type === TouchType.Move) {
        if (Math.abs(distance / this.pinchDistance - 1) > 0.06 &&
            Math.abs(distance - this.pinchDistance) >= 12) { this.pinchActive = true; }
        if (this.pinchActive) {
          const nextZoom = Math.max(1, Math.min(6, this.pinchZoom * distance / this.pinchDistance));
          const ratio = nextZoom / this.zoom;
          this.offsetX = centerX - this.containerWidth / 2 -
            (this.midpointX - this.containerWidth / 2 - this.offsetX) * ratio;
          this.offsetY = centerY - this.containerHeight / 2 -
            (this.midpointY - this.containerHeight / 2 - this.offsetY) * ratio;
          this.zoom = nextZoom;
          this.clampView();
        } else if (this.inputMode === 'pan') {
          this.offsetX += centerX - this.midpointX;
          this.offsetY += centerY - this.midpointY;
          this.clampView();
        } else {
          this.scrollBy(centerY - this.midpointY);
        }
        this.midpointX = centerX;
        this.midpointY = centerY;
      }
      return;
    }
    if (this.multiTouch) {
      return;
    }
    const touch = event.changedTouches[0];
    if (touch === undefined) { return; }
    const x = touch.x;
    const y = touch.y;
    if (event.type === TouchType.Down) {
      this.startX = x;
      this.startY = y;
      this.moved = false;
      this.longPressed = false;
      this.singleX = x;
      this.singleY = y;
      if (this.inputMode === 'scroll') { this.beginScroll(x, y); }
      else if (this.inputMode === 'drag') { this.mouseAt(LEFT_DOWN, x, y); }
      else if (this.inputMode === 'pointer') {
        this.pressTimer = setTimeout((): void => {
          this.pressTimer = -1;
          this.longPressed = true;
          this.mouseAt(RIGHT_DOWN, this.startX, this.startY);
          this.mouseAt(RIGHT_UP, this.startX, this.startY);
        }, 550) as number;
      }
    } else if (event.type === TouchType.Move) {
      if (this.inputMode === 'scroll') {
        this.scrollBy(y - this.singleY);
        this.singleY = y;
        return;
      }
      if (this.inputMode === 'pan') {
        this.offsetX += x - this.singleX;
        this.offsetY += y - this.singleY;
        this.singleX = x;
        this.singleY = y;
        this.clampView();
        return;
      }
      if (Math.hypot(x - this.startX, y - this.startY) > 8) {
        this.moved = true;
        this.clearPress();
        if (this.inputMode !== 'right') { this.mouseAt(MOUSE_MOVE, x, y); }
      }
    } else if (event.type === TouchType.Up) {
      this.clearPress();
      if (this.inputMode === 'scroll' || this.inputMode === 'pan') { return; }
      if (this.leftHeld) { this.mouseAt(LEFT_UP, x, y); this.releaseMouse(); }
      else if (!this.moved && !this.longPressed) {
        if (this.inputMode === 'right') {
          this.mouseAt(RIGHT_DOWN, x, y);
          this.mouseAt(RIGHT_UP, x, y);
          this.inputMode = 'pointer';
        } else {
          this.mouseAt(LEFT_DOWN, x, y);
          this.mouseAt(LEFT_UP, x, y);
        }
      }
    }
  }

  private fitScale(): number {
    if (this.remoteWidth <= 0 || this.remoteHeight <= 0) { return 1; }
    return Math.min(this.containerWidth / this.remoteWidth, this.containerHeight / this.remoteHeight);
  }

  private clampView(): void {
    this.offsetX = clampOffset(this.offsetX, this.remoteWidth * this.fitScale() * this.zoom, this.containerWidth);
    this.offsetY = clampOffset(this.offsetY, this.remoteHeight * this.fitScale() * this.zoom, this.containerHeight);
  }

  private resetView(): void { this.zoom = 1; this.offsetX = 0; this.offsetY = 0; }

  private sendKey(name: string): void {
    if (!this.canControl()) { return; }
    const key = toolbarKeyCommand(name, this.alt, this.ctrl, this.shift);
    if (key.name.length === 0) { return; }
    // Modifiers select one shortcut, rather than staying latched across keys.
    this.alt = false;
    this.ctrl = false;
    this.shift = false;
    ffiInputKey(this.uuid, key.name, key.down, key.press, key.alt, key.ctrl, key.shift, key.command);
  }

  private sendText(): void {
    if (this.canControl() && this.inputText.length > 0) {
      ffiInputString(this.uuid, this.inputText);
      this.inputText = '';
    }
  }

  private layoutModeChanged(): void { this.showMore = false; }

  private toggleTextInput(): void {
    this.showMore = false;
    if (this.textInputVisible) {
      try { this.textController.stopEditing(); } catch (e) {}
      this.inputText = '';
      this.protectInput = true;
    }
    this.textInputVisible = !this.textInputVisible;
  }

  private toggleViewOnly(): void {
    this.releaseMouse();
    if (ffiToggleOption(this.uuid, 'view-only') === 0) {
      this.viewOnly = ffiGetToggleOption(this.uuid, 'view-only') === 1;
    }
  }

  private submitAuth(): void {
    if (this.closed || this.authPrompt.length === 0) { return; }
    const value = this.authValue;
    this.authValue = '';
    if (value.length === 0) { return; }
    const result = this.authPrompt === '2fa'
      ? ffiSessionSend2fa(this.uuid, value, false) : ffiSessionLogin(this.uuid, value, false);
    this.authPrompt = '';
    hilog.info(0x5253, 'RustPalmSession', 'authentication submitted; result=%{public}d', result);
    if (result !== 0) { this.finish('认证提交失败，请返回重试'); return; }
    this.status = '正在验证，请等待电脑响应…';
    this.armConnectionTimeout('电脑认证响应超时，请检查电脑端 RustDesk 或返回重试');
  }

  @Builder
  private controlButton(label: string, selected: boolean, action: () => void) {
    Button(label, { type: ButtonType.Normal }).fontSize(13).height(36).borderRadius(8)
      .backgroundColor((label === 'Ctrl' ? this.ctrl : label === 'Alt' ? this.alt :
        label === 'Shift' ? this.shift : label === '键盘' ? this.textInputVisible :
        label === '右键' ? this.inputMode === 'right' : label === '滚动' ? this.inputMode === 'scroll' :
        label === '拖动' ? this.inputMode === 'drag' : label === '平移' ? this.inputMode === 'pan' :
        label === '只读' ? this.viewOnly : selected) ? '#246BFD' : '#263449')
      .fontColor('#FFFFFF').onClick(action)
  }

  @Builder
  private compactMore() {
    Scroll() {
      Column({ space: 6 }) {
        Row({ space: 6 }) {
          this.controlButton('Ctrl', this.ctrl, () => { this.ctrl = !this.ctrl; })
          this.controlButton('Alt', this.alt, () => { this.alt = !this.alt; })
          this.controlButton('Shift', this.shift, () => { this.shift = !this.shift; })
          this.controlButton('Tab', false, () => { this.sendKey('VK_TAB'); this.showMore = false; })
          Button('关闭').height(32).fontSize(12).onClick(() => { this.showMore = false; })
        }
        Row({ space: 6 }) {
          this.controlButton('Esc', false, () => { this.sendKey('VK_ESCAPE'); this.showMore = false; })
          this.controlButton('Enter', false, () => { this.sendKey('VK_RETURN'); this.showMore = false; })
          this.controlButton('⌫', false, () => { this.sendKey('VK_BACK'); this.showMore = false; })
        }
        Row({ space: 6 }) {
          this.controlButton('A', false, () => { this.sendKey('a'); this.showMore = false; })
          this.controlButton('C', false, () => { this.sendKey('c'); this.showMore = false; })
          this.controlButton('V', false, () => { this.sendKey('v'); this.showMore = false; })
          this.controlButton('Z', false, () => { this.sendKey('z'); this.showMore = false; })
        }
        Row({ space: 6 }) {
          this.controlButton('右键', this.inputMode === 'right', () => { this.selectInputMode('right'); this.showMore = false; })
          this.controlButton('滚动', this.inputMode === 'scroll', () => { this.selectInputMode('scroll'); this.showMore = false; })
          this.controlButton('拖动', this.inputMode === 'drag', () => { this.selectInputMode('drag'); this.showMore = false; })
          this.controlButton('平移', this.inputMode === 'pan', () => { this.selectInputMode('pan'); this.showMore = false; })
        }
        Row({ space: 6 }) {
          this.controlButton('只读', this.viewOnly, () => { this.toggleViewOnly(); this.showMore = false; })
          this.controlButton('适应屏幕', false, () => { this.resetView(); this.showMore = false; })
          this.controlButton('刷新', false, () => { ffiRefreshVideo(this.uuid); this.showMore = false; })
        }
        Text(this.inputHint()).fontSize(11).fontColor('#A9B9CC')
        Text(this.peerId + ' · ' + this.route + ' · ' + this.status +
          (this.codec.length > 0 ? ' · ' + this.codec : '') +
          (this.delay.length > 0 ? ' · ' + this.delay + ' ms' : ''))
          .fontSize(11).fontColor('#A9B9CC').width('100%')
        Button('锁屏并断开').height(36).fontSize(13).backgroundColor('#783C42').fontColor('#FFFFFF')
          .enabled(!this.disconnecting).onClick(() => { this.showMore = false; this.disconnect(); })
      }.padding(6).width('100%')
    }.width(Math.max(200, Math.min(380, this.availableWidth - 16)))
      // Leave room for the popup's screen-edge margins above the 44vp bar.
      .height(Math.max(48, Math.min(180, this.availableHeight - 64)))
      .scrollable(ScrollDirection.Vertical).scrollBar(BarState.Auto)
      .backgroundColor('#142033').borderRadius(12)
  }

  build() {
    Column() {
      if (!this.landscape) {
      Row({ space: 12 }) {
        Column({ space: 3 }) {
          Text(this.peerId).fontSize(17).fontWeight(FontWeight.Medium).fontColor('#F2F6FC')
          Text(this.closed ? this.status : this.route + ' · ' + this.status)
            .fontSize(12).fontColor('#A9B9CC').maxLines(2)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button(this.closed ? '返回' : (this.disconnecting ? '断开中…' : '断开')).fontSize(13)
          .enabled(!this.disconnecting)
          .backgroundColor('#783C42').onClick(() => this.disconnect())
      }.padding(14).width('100%')
      }
      Stack({ alignContent: Alignment.Center }) {
        Stack({ alignContent: Alignment.TopStart }) {
          XComponent({ id: 'rustpalm_video', type: XComponentType.SURFACE, controller: this.controller })
            .width('100%').height('100%').hitTestBehavior(HitTestMode.None)
            .onLoad(() => { this.surfaceReady = true; this.bindVideo(); })
            .onDestroy(() => {
              this.surfaceReady = false;
              if (this.videoBound) { ffiDeinitVideo(this.uuid); this.videoBound = false; }
            })
          if (!this.cursorEmbedded && this.cursor.pixels !== undefined) {
            Image(this.cursor.pixels)
              .width(this.cursor.width * this.fitScale()).height(this.cursor.height * this.fitScale())
              .position({ x: (this.cursorX - this.originX - this.cursor.hotX) * this.fitScale(),
                y: (this.cursorY - this.originY - this.cursor.hotY) * this.fitScale() })
              .hitTestBehavior(HitTestMode.None)
          }
        }.width(Math.max(1, this.remoteWidth * this.fitScale()))
          .height(Math.max(1, this.remoteHeight * this.fitScale()))
          .scale({ x: this.zoom, y: this.zoom }).translate({ x: this.offsetX, y: this.offsetY })
          .hitTestBehavior(HitTestMode.None)
        if (!this.ready) {
          Column({ space: 14 }) {
            if (!this.closed) { LoadingProgress().width(32).height(32).color('#91B4FF') }
            Text(this.status).fontColor('#CED9E8').fontSize(14).textAlign(TextAlign.Center)
          }.padding(24).hitTestBehavior(HitTestMode.None)
        }
      }.width('100%').layoutWeight(1).backgroundColor('#080E17').clip(true)
        .onAreaChange((_old: Area, area: Area) => {
          const width = Number(area.width);
          const height = Number(area.height);
          if (width !== this.containerWidth || height !== this.containerHeight) {
            this.cancelGesture();
            this.containerWidth = width;
            this.containerHeight = height;
            this.clampView();
          }
        }).onTouch((event: TouchEvent) => this.handleTouch(event))
      if (this.ready) {
        if (!this.landscape) {
        Text(this.inputHint())
          .fontSize(11).fontColor('#A9B9CC').padding(8)
        }
        if (!this.landscape || !this.textInputVisible) {
        Scroll() {
          Row({ space: 8 }) {
            this.controlButton('键盘', this.textInputVisible, () => this.toggleTextInput())
            this.controlButton('右键', this.inputMode === 'right', () => this.selectInputMode('right'))
            this.controlButton('滚动', this.inputMode === 'scroll', () => this.selectInputMode('scroll'))
            this.controlButton('拖动', this.inputMode === 'drag', () => this.selectInputMode('drag'))
            this.controlButton('平移', this.inputMode === 'pan', () => this.selectInputMode('pan'))
            this.controlButton('只读', this.viewOnly, () => this.toggleViewOnly())
            this.controlButton('适应屏幕', false, () => this.resetView())
            this.controlButton('刷新', false, () => { ffiRefreshVideo(this.uuid); })
            if (this.landscape) {
              Text(this.viewOnly || !this.keyboardAllowed ? '只读' : this.route)
                .fontSize(11).fontColor('#A9B9CC').maxLines(1)
              Button(this.disconnecting ? '断开中…' : '断开').height(36).fontSize(13)
                .backgroundColor('#783C42').fontColor('#FFFFFF').enabled(!this.disconnecting)
                .onClick(() => this.disconnect())
            }
          }.padding({ left: 8, right: 8, top: 4, bottom: 4 })
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%').height(44)
        }
        if (this.textInputVisible) {
          if (!this.landscape) {
          Row({ space: 8 }) {
            Text(this.protectInput ? '隐私输入 · 内容已隐藏' : '普通文本 · 内容可见')
              .fontSize(12).fontColor('#CED9E8').layoutWeight(1)
            Button(this.protectInput ? '显示文字' : '隐藏文字')
              .height(32).fontSize(12).backgroundColor('#263449').fontColor('#FFFFFF')
              .onClick(() => { this.protectInput = !this.protectInput; })
          }.width('100%').padding({ left: 12, right: 12, bottom: 6 })
          }
          Row({ space: 6 }) {
            if (this.landscape) {
              Button('收起').height(36).fontSize(12).padding({ left: 10, right: 10 })
                .backgroundColor('#263449').fontColor('#FFFFFF').onClick(() => this.toggleTextInput())
            }
            TextInput({ text: this.inputText, placeholder: this.protectInput ? '内容已隐藏' : '输入文字后发送', controller: this.textController })
              .type(this.protectInput ? InputType.Password : InputType.Normal)
              .showPasswordIcon(false).enableAutoFill(false)
              .layoutWeight(1).maxLength(4096).enabled(this.canControl())
              .height(this.landscape ? 36 : 48).fontSize(this.landscape ? 14 : 16)
              .backgroundColor('#F8FAFC').fontColor('#102035')
              .placeholderColor('#53657B').caretColor('#176B62').selectedBackgroundColor('#B9D7FF')
              .onChange((value: string) => { this.inputText = value; }).onSubmit(() => this.sendText())
            if (this.landscape) {
              Button(this.protectInput ? '显示' : '隐藏').height(36).fontSize(12).padding({ left: 10, right: 10 })
                .backgroundColor('#263449').fontColor('#FFFFFF').onClick(() => { this.protectInput = !this.protectInput; })
            }
            Button('发送').height(this.landscape ? 36 : 40).fontSize(this.landscape ? 13 : 16)
              .padding({ left: 12, right: 12 }).enabled(this.canControl()).onClick(() => this.sendText())
            if (this.landscape) {
              if (this.availableWidth >= 640) {
                this.controlButton('Ctrl', this.ctrl, () => { this.ctrl = !this.ctrl; })
                this.controlButton('Esc', false, () => this.sendKey('VK_ESCAPE'))
                this.controlButton('Enter', false, () => this.sendKey('VK_RETURN'))
              }
              Button('更多').height(36).fontSize(12).padding({ left: 10, right: 10 })
                .backgroundColor('#263449').fontColor('#FFFFFF')
                .onClick(() => { this.showMore = !this.showMore; })
                .bindPopup(this.showMore, {
                  builder: this.compactMore, placement: Placement.Top, enableArrow: false,
                  popupColor: '#142033', autoCancel: true, focusable: false,
                  onStateChange: (event: PopupStateChangeParam) => { this.showMore = event.isVisible; }
                })
            }
          }.padding({ left: 8, right: 8, top: this.landscape ? 4 : 0, bottom: this.landscape ? 4 : 8 })
            .height(this.landscape ? 44 : 56).width('100%')
          if (!this.landscape) {
          Scroll() {
            Row({ space: 6 }) {
              this.controlButton('Ctrl', this.ctrl, () => { this.ctrl = !this.ctrl; })
              this.controlButton('Alt', this.alt, () => { this.alt = !this.alt; })
              this.controlButton('Shift', this.shift, () => { this.shift = !this.shift; })
              this.controlButton('Tab', false, () => this.sendKey('VK_TAB'))
              this.controlButton('Esc', false, () => this.sendKey('VK_ESCAPE'))
              this.controlButton('Enter', false, () => this.sendKey('VK_RETURN'))
              this.controlButton('⌫', false, () => this.sendKey('VK_BACK'))
              this.controlButton('A', false, () => this.sendKey('a'))
              this.controlButton('C', false, () => this.sendKey('c'))
              this.controlButton('V', false, () => this.sendKey('v'))
              this.controlButton('Z', false, () => this.sendKey('z'))
            }.padding({ left: 12, right: 12, bottom: 8 })
          }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
          Text('Ctrl / Alt / Shift 仅用于下一次按键，可与 Esc 组合')
            .fontSize(10).fontColor('#A9B9CC').padding({ bottom: 4 })
          }
        }
        if (!this.landscape && this.codec.length > 0) {
          Text(this.codec + (this.delay.length > 0 ? ' · ' + this.delay + ' ms' : ''))
            .fontColor('#71849B').fontSize(10).padding({ bottom: 6 })
        }
      } else if (this.landscape) {
        Row({ space: 8 }) {
          Text(this.status).fontSize(12).fontColor('#CED9E8').layoutWeight(1).maxLines(1)
          Button(this.closed ? '返回' : '断开').height(36).fontSize(13)
            .enabled(!this.disconnecting).onClick(() => this.disconnect())
        }.padding({ left: 8, right: 8, top: 4, bottom: 4 }).height(44).width('100%')
      }
    }.width('100%').height('100%').backgroundColor('#142033')
      .onAreaChange((_old: Area, area: Area) => {
        this.availableWidth = Number(area.width);
        this.availableHeight = Number(area.height);
      })
      .bindContentCover(this.authPrompt.length > 0, this.authentication, {
        modalTransition: ModalTransition.NONE,
        onWillDismiss: (action: DismissContentCoverAction) => {
          const cancelled = this.authPrompt.length > 0;
          action.dismiss();
          if (cancelled) {
            this.disconnect();
          }
        }
      })
  }

  @Builder
  private authentication() {
    Column({ space: 18 }) {
      Text(this.authPrompt === '2fa' ? '输入验证码' : '输入电脑访问密码')
        .fontSize(22).fontWeight(FontWeight.Medium).fontColor('#102035')
      Text(this.authMessage).fontSize(14).fontColor('#526176')
      TextInput({ text: this.authValue, placeholder: this.authPrompt === '2fa' ? '验证码' : '访问密码' })
        .type(this.authPrompt === '2fa' ? InputType.Number : InputType.Password)
        .showPasswordIcon(false).enableAutoFill(false)
        .backgroundColor('#FFFFFF').fontColor('#102035').placeholderColor('#53657B').caretColor('#176B62')
        .maxLength(256).onChange((value: string) => { this.authValue = value; }).onSubmit(() => this.submitAuth())
      Row({ space: 16 }) {
        Button('取消').onClick(() => this.disconnect())
        Button('连接').enabled(this.authValue.length > 0).onClick(() => this.submitAuth())
      }
    }.padding(28).width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor('#F3F6FA')
  }
}
