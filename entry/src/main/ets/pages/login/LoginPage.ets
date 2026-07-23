import { router } from '@kit.ArkUI';
import { userSettingStore } from '../../stores/UserSettingStore';
import { hoster } from '../../network/Hoster';

@Entry
@Component
struct LoginPage {
  @State useBypass: boolean = false

  aboutToAppear() {
    this.useBypass = userSettingStore.getSettings().networkMode === 'bypass'
  }

  build() {
    Column({ space: 20 }) {
      Column({ space: 8 }) {
        Text('PixEz')
          .fontSize(48)
          .fontWeight(FontWeight.Bold)
          .fontColor('#0096FA')
        Text('HarmonyOS')
          .fontSize(16)
          .fontColor('#999999')
      }
      .margin({ bottom: 40 })

      Button('使用 WebView 登录')
        .width('85%')
        .height(50)
        .backgroundColor('#0096FA')
        .fontColor('#FFFFFF')
        .fontSize(16)
        .onClick(() => {
          router.pushUrl({ url: 'pages/login/WebViewLoginPage' })
        })

      Button('使用 Token 登录')
        .width('85%')
        .height(50)
        .backgroundColor('#FFFFFF')
        .fontColor('#0096FA')
        .border({ width: 1, color: '#0096FA' })
        .fontSize(16)
        .onClick(() => {
          router.pushUrl({ url: 'pages/login/TokenLoginPage' })
        })

      Row() {
        Toggle({ type: ToggleType.Switch, isOn: $$this.useBypass })
          .selectedColor('#0096FA')
          .onChange((isOn: boolean) => {
            this.useBypass = isOn
            userSettingStore.setNetworkMode(isOn ? 'bypass' : 'direct')
            if (isOn) {
              hoster.init()
              hoster.refreshAll()
            }
          })
        Text('使用内置绕过方式')
          .fontSize(14)
          .fontColor('#666666')
          .margin({ left: 8 })
      }
      .width('85%')
      .margin({ top: 16 })

      if (this.useBypass) {
        Text('内置绕过通过自定义 DNS 解析直连 Pixiv；WebView 登录不经过绕过，网络受限时建议使用 Token 登录')
          .fontSize(12)
          .fontColor('#FF8800')
          .width('85%')
          .textAlign(TextAlign.Center)
      }

      Text('使用条款')
        .fontSize(12)
        .fontColor('#999999')
        .margin({ top: 24 })
        .decoration({ type: TextDecorationType.Underline })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#FFFFFF')
  }
}
