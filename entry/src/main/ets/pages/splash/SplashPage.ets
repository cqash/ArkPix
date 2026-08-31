import { router, promptAction } from '@kit.ArkUI';
import { accountStore } from '../../stores/AccountStore';
import { syncService } from '../../services/SyncService';
import { continuationService } from '../../services/ContinuationService';
import {
  ContinuationPayload,
  CONTINUATION_PAGE_HOME,
  CONTINUATION_PAGE_ILLUST_DETAIL,
  CONTINUATION_PAGE_USER_PROFILE
} from '../../models/ContinuationPayload';

@Entry
@Component
struct SplashPage {
  @State isReady: boolean = false

  /**
   * 接续路由：消费一次性载荷并跳转目标页，返回 true 表示已处理。
   * 载荷非法/未登录/未知 page 一律返回 false，回退既有路由逻辑（主页或登录页）。
   */
  private routeByContinuation(payload: ContinuationPayload | null): boolean {
    if (payload === null || !accountStore.getIsLoggedIn()) {
      return false
    }
    // FR-014：detail/user_profile 先落地主页再压入目标页，保持可返回的页面栈（返回键回主页而非退出应用）
    if (payload.page === CONTINUATION_PAGE_ILLUST_DETAIL) {
      router.replaceUrl({ url: 'pages/home/HomePage' })
      router.pushUrl({ url: 'pages/detail/IllustDetailPage', params: { illustId: payload.illustId } })
      return true
    }
    if (payload.page === CONTINUATION_PAGE_HOME) {
      router.replaceUrl({ url: 'pages/home/HomePage', params: { tabIndex: payload.tabIndex } })
      return true
    }
    if (payload.page === CONTINUATION_PAGE_USER_PROFILE) {
      router.replaceUrl({ url: 'pages/home/HomePage' })
      router.pushUrl({ url: 'pages/user/UserProfilePage', params: { userId: payload.userId } })
      return true
    }
    // 未知/空 page（未覆盖页面接续）：回退主页默认 Tab
    router.replaceUrl({ url: 'pages/home/HomePage' })
    return true
  }

  aboutToAppear() {
    // 启动后约 5 秒空闲触发一次全域同步 pull（内部判 syncEnabled + 已注册中继账号）；
    // 挂载在此而非 EntryAbility：页面模块在 context 入 AppStorage 之后才加载，
    // 模块级 Store 单例可安全访问 PreferenceService
    setTimeout(() => {
      syncService.startupPull()
        .catch((e: Object) => {
          console.error('Startup sync pull failed: ' + JSON.stringify(e))
        });
    }, 5000)

    setTimeout(() => {
      this.isReady = true
      // 接续分支优先：对端流转拉起时直接进入目标页面
      if (this.routeByContinuation(continuationService.consumePendingPayload())) {
        return
      }
      if (accountStore.getIsLoggedIn()) {
        router.replaceUrl({ url: 'pages/home/HomePage' })
      } else {
        // 凭证被服务端明确判定失效后引导重新登录（临时网络故障不会走到这里）
        let needsRelogin = AppStorage.get<boolean>('needsRelogin') ?? false
        if (needsRelogin || accountStore.getNeedsRelogin()) {
          promptAction.showToast({ message: $r('app.string.splash_session_expired') })
          accountStore.clearNeedsRelogin()
        }
        router.replaceUrl({ url: 'pages/login/LoginPage' })
      }
    }, 1500)
  }

  build() {
    Column() {
      Text('ArkPix')
        .fontSize(48)
        .fontWeight(FontWeight.Bold)
        .fontColor('#0096FA')
      LoadingProgress()
        .width(40)
        .height(40)
        .color('#0096FA')
        .margin({ top: 32 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#FFFFFF')
  }
}
