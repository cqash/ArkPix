import { router } from '@kit.ArkUI';
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
