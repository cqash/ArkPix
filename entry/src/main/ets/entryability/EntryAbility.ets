import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { hoster } from '../network/Hoster';
import { localProxyServer } from '../network/LocalProxyServer';
// lazy import：SyncService 依赖链含模块级 Store 单例（UserSettingStore），
// 静态 import 会在 onCreate 前求值导致冷启动闪退（历史事故）。
// lazy 语义=首次访问变量时才同步加载模块，onForeground 首次访问时 context 已注入，安全。
import lazy { syncService } from '../services/SyncService';

const DOMAIN = 0x0000;

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

    hoster.init();
    hoster.refreshAll();
    localProxyServer.start();

    // 注意：同步启动 pull 挂载在 SplashPage（页面模块在 context 入 AppStorage 之后才加载）。
    // 此处不得静态 import SyncService——其依赖链上的模块级单例（UserSettingStore）会在
    // 模块求值时访问 PreferenceService，早于 onCreate 的 context 注入，导致冷启动闪退。
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
    localProxyServer.stop();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

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
