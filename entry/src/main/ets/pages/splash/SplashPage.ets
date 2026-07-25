import { router, promptAction } from '@kit.ArkUI';
import { accountStore } from '../../stores/AccountStore';

@Entry
@Component
struct SplashPage {
  @State isReady: boolean = false

  aboutToAppear() {
    setTimeout(() => {
      this.isReady = true
      if (accountStore.getIsLoggedIn()) {
        router.replaceUrl({ url: 'pages/home/HomePage' })
      } else {
        // 凭证被服务端明确判定失效后引导重新登录（临时网络故障不会走到这里）
        let needsRelogin = AppStorage.get<boolean>('needsRelogin') ?? false
        if (needsRelogin || accountStore.getNeedsRelogin()) {
          promptAction.showToast({ message: '登录已过期，请重新登录' })
          accountStore.clearNeedsRelogin()
        }
        router.replaceUrl({ url: 'pages/login/LoginPage' })
      }
    }, 1500)
  }

  build() {
    Column() {
      Text('PixEz')
        .fontSize(48)
        .fontWeight(FontWeight.Bold)
        .fontColor('#0096FA')
      Text('HarmonyOS')
        .fontSize(16)
        .fontColor('#999999')
        .margin({ top: 8 })
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
