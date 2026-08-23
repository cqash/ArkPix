import { router } from '@kit.ArkUI';
import { userSettingStore } from '../../stores/UserSettingStore';
import { hoster } from '../../network/Hoster';
import { localProxyServer } from '../../network/LocalProxyServer';

@Entry
@Component
struct LoginPage {
  @State useBypass: boolean = false

  aboutToAppear() {
    this.useBypass = userSettingStore.getSettings().authMode !== 'standard'
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column({ space: 20 }) {
      Column({ space: 8 }) {
        Text('ArkPix')
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
            let mode = isOn ? 'compatible' : 'standard'
            userSettingStore.setAuthMode(mode)
            userSettingStore.setApiMode(mode)
            if (isOn) {
              hoster.init()
              hoster.refreshAll()
              localProxyServer.start()
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
        Text('内置绕过通过 DoH 解析真实 IP 直连 Pixiv，WebView 登录同样经过内置代理')
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

      // 右上角设置入口：登录前可配置网络/中继（如先开中继再登录）
      Text('设置')
        .fontSize(15)
        .fontColor('#0096FA')
        .padding({ left: 24, right: 20, top: 16, bottom: 16 })
        .onClick(() => {
          router.pushUrl({ url: 'pages/settings/SettingsPage' })
        })
    }
    .width('100%')
    .height('100%')
  }
}
