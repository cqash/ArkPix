import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { hoster } from '../network/Hoster';
import { localProxyServer } from '../network/LocalProxyServer';
// ContinuationService 纯内存 + AppStorage（不依赖 PreferenceService），可安全静态 import
import { continuationService } from '../services/ContinuationService';
import { CONTINUATION_PAYLOAD_KEY } from '../models/ContinuationPayload';
// lazy import：SyncService 依赖链含模块级 Store 单例（UserSettingStore），
// 静态 import 会在 onCreate 前求值导致冷启动闪退（历史事故）。
// lazy 语义=首次访问变量时才同步加载模块，onForeground 首次访问时 context 已注入，安全。
import lazy { syncService } from '../services/SyncService';
// lazy import：DistributedSyncService 同样依赖 UserSettingStore/PreferenceService 模块级单例，遵循同一约束
import lazy { distributedSyncService } from '../services/DistributedSyncService';

const DOMAIN = 0x0000;

/** 接续对端最低 versionCode（低于此版本的旧版不认识接续载荷，显式拒绝） */
const MIN_CONTINUATION_PEER_VERSION_CODE: number = 1000000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      AppStorage.setOrCreate('context', this.context);
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');

    // 注册 pixiv 自定义协议到 Web 内核（必须在 Web 组件初始化之前），
    // 否则 OAuth 完成后跳转 pixiv:// 会被系统 AppLinking 接管，登录页拿不到 code
    try {
      let pixivScheme: webview.WebCustomScheme = { schemeName: 'pixiv', isSupportCORS: true, isSupportFetch: true }
      webview.WebviewController.customizeSchemes([pixivScheme])
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'customizeSchemes failed: %{public}s', JSON.stringify(e));
    }

    // 接续冷启动对端：收载荷入 AppStorage，SplashPage 路由决策时一次性消费
    this.consumeContinuationWant(want, launchParam);

    hoster.init();
    hoster.refreshAll();
    localProxyServer.start();

    // 注意：同步启动 pull 挂载在 SplashPage（页面模块在 context 入 AppStorage 之后才加载）。
    // 此处不得静态 import SyncService——其依赖链上的模块级单例（UserSettingStore）会在
    // 模块求值时访问 PreferenceService，早于 onCreate 的 context 注入，导致冷启动闪退。

    // 设备间同步（分布式数据对象）：lazy import，首次访问时 context 已注入，安全；
    // 内部读 deviceSyncEnabled，失败静默降级纯本地
    try {
      distributedSyncService.init();
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'distributedSyncService.init failed: %{public}s', JSON.stringify(e));
    }
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 单实例应用接续热启动对端：收载荷入 AppStorage，由 SplashPage 消费
    this.consumeContinuationWant(want, launchParam);
  }

  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    try {
      // 版本协商：对端版本低于本特性引入版本时拒绝接续（wantParam.version 为系统预置的对端 versionCode）
      let peerVersion = Number(wantParam['version'] ?? 0);
      if (peerVersion < MIN_CONTINUATION_PEER_VERSION_CODE) {
        hilog.warn(DOMAIN, 'testTag', 'onContinue rejected: peer version %{public}d too low', peerVersion);
        return AbilityConstant.OnContinueResult.MISMATCH;
      }
      // 写入当前页面状态载荷（页面主动登记模式，未覆盖页面仅传版本号回退主页）
      let param = continuationService.buildWantParam();
      let keys = Object.keys(param);
      for (let i = 0; i < keys.length; i++) {
        wantParam[keys[i]] = param[keys[i]];
      }
      return AbilityConstant.OnContinueResult.AGREE;
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'onContinue failed: %{public}s', JSON.stringify(e));
      return AbilityConstant.OnContinueResult.REJECT;
    }
  }

  /** 接续场景收载荷：LaunchReason.CONTINUATION 时解析 want 并落 AppStorage（一次性消费键） */
  private consumeContinuationWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (launchParam.launchReason !== AbilityConstant.LaunchReason.CONTINUATION) {
      return;
    }
    try {
      let payload = continuationService.parseWant(want);
      if (payload !== null) {
        AppStorage.setOrCreate(CONTINUATION_PAYLOAD_KEY, payload);
        hilog.info(DOMAIN, 'testTag', 'continuation payload received: page=%{public}s', payload.page);
      }
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'parse continuation want failed: %{public}s', JSON.stringify(e));
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
    localProxyServer.stop();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');
    this.loadSplashPage(windowStage);
  }

  onWindowStageRestore(windowStage: window.WindowStage): void {
    // 接续对端拉起时不走 onWindowStageCreate 而走本回调（不使用系统页面栈恢复）：
    // 自行加载 SplashPage，由其消费 AppStorage 中的接续载荷跳转到目标页
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageRestore');
    this.loadSplashPage(windowStage);
  }

  private loadSplashPage(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/splash/SplashPage', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    // 回前台补偿同步（autoSyncForeground 开关 + SyncService 内部 5 分钟节流）
    try {
      syncService.onAppForeground();
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'onAppForeground failed: %{public}s', JSON.stringify(e));
    }
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
