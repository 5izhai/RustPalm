import { UIAbility } from '@kit.AbilityKit';
import { window, KeyboardAvoidMode } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { ffiInit, ffiSetCallbacks } from '../ohos_ffi';
import { globalEvents, parseEvent, RdeskEvent, EventHandler } from '../model/RdeskEvents';

const LOG_DOMAIN = 0x5253;
const TAG = 'RustPalmAbility';

export default class EntryAbility extends UIAbility {
  private systemBarsHidden: boolean = false;
  private mainWindow: window.Window | undefined = undefined;
  private suspendDelayId: number = -1;
  private sessionHandler: EventHandler = (event: RdeskEvent): void => {
    if (event.name === 'rustpalm_session_closed') { this.cancelSuspendDelay(); }
  };

  private dispatchLifecycle(name: string): void {
    const event = new RdeskEvent();
    event.name = name;
    globalEvents.dispatch(event);
  }

  private cancelSuspendDelay(): void {
    if (this.suspendDelayId < 0) { return; }
    try { backgroundTaskManager.cancelSuspendDelay(this.suspendDelayId); } catch (e) {}
    this.suspendDelayId = -1;
  }

  onForeground(): void {
    this.cancelSuspendDelay();
    AppStorage.SetOrCreate<boolean>('rustpalmForeground', true);
    this.dispatchLifecycle('rustpalm_app_foreground');
  }

  onBackground(): void {
    AppStorage.SetOrCreate<boolean>('rustpalmForeground', false);
    this.dispatchLifecycle('rustpalm_app_background');
    // Request a bounded background grace period during calls or app switches.
    if (AppStorage.get<boolean>('rustpalmSessionActive') === true && this.suspendDelayId < 0) {
      try {
        const delay = backgroundTaskManager.requestSuspendDelay('保持远程桌面连接', () => {
          this.cancelSuspendDelay();
        });
        this.suspendDelayId = delay.requestId;
        hilog.info(LOG_DOMAIN, TAG, 'background grace period granted: %{public}d ms', delay.actualDelayTime);
      } catch (e) {
        hilog.warn(LOG_DOMAIN, TAG, 'background grace period unavailable');
      }
    }
  }

  onDestroy(): void {
    this.cancelSuspendDelay();
    AppStorage.SetOrCreate<boolean>('rustpalmForeground', false);
    this.dispatchLifecycle('rustpalm_app_destroy');
    AppStorage.SetOrCreate<boolean>('rustpalmCoreReady', false);
  }

  private updateSystemBars(win: window.Window, width: number, height: number): void {
    const landscape = width > height;
    AppStorage.SetOrCreate<boolean>('rustpalmLandscape', landscape);
    if (landscape === this.systemBarsHidden) {
      return;
    }
    this.systemBarsHidden = landscape;
    win.setWindowSystemBarEnable(landscape ? [] : ['status', 'navigation'])
      .catch((e: BusinessError) => {
        hilog.warn(LOG_DOMAIN, TAG, 'system bars update failed: %{public}d', e.code);
      });
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    globalEvents.subscribe(this.sessionHandler);
    AppStorage.SetOrCreate<boolean>('rustpalmCoreReady', false);
    AppStorage.SetOrCreate<boolean>('rustpalmForeground', true);
    const filesDir = this.context.filesDir;
    const homeDir = `${filesDir}/home`;
    try {
      if (!fs.accessSync(homeDir)) {
        fs.mkdirSync(homeDir, true);
      }
      const initialized = ffiInit(homeDir, filesDir, '') === 0;
      if (initialized) {
        const callbacksReady = ffiSetCallbacks((json: string) => {
          globalEvents.dispatch(parseEvent(json));
        }, (_text: string) => {}) === 0;
        AppStorage.SetOrCreate<boolean>('rustpalmCoreReady', callbacksReady);
      }
    } catch (e) {
      hilog.error(LOG_DOMAIN, TAG, 'core initialization failed');
    }

    windowStage.loadContent('pages/Index', (err: BusinessError) => {
      if (err.code !== 0) {
        hilog.error(LOG_DOMAIN, TAG, 'loadContent failed: %{public}d', err.code);
        return;
      }
      const win = windowStage.getMainWindowSync();
      this.mainWindow = win;
      win.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
      win.on('windowSizeChange', (size: window.Size) => {
        this.updateSystemBars(win, size.width, size.height);
      });
      const rect = win.getWindowProperties().windowRect;
      this.updateSystemBars(win, rect.width, rect.height);
    });
  }

  onWindowStageDestroy(): void {
    this.cancelSuspendDelay();
    this.dispatchLifecycle('rustpalm_app_destroy');
    globalEvents.unsubscribe(this.sessionHandler);
    if (this.mainWindow !== undefined) {
      this.mainWindow.off('windowSizeChange');
      this.mainWindow = undefined;
    }
  }
}
