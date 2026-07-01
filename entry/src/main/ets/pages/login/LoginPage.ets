import { router } from '@kit.ArkUI';
import { Constants } from '../../utils/Constants';

@Entry
@Component
struct LoginPage {
  @State useBypass: boolean = false

  aboutToAppear() {
    // 加载之前保存的网络模式设置
    this.useBypass = false
  }

  toggleBypass() {
    this.useBypass = !this.useBypass
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
          })
        Text('使用内置绕过方式')
          .fontSize(14)
          .fontColor('#666666')
          .margin({ left: 8 })
      }
      .width('85%')
      .margin({ top: 16 })

      if (this.useBypass) {
        Text('内置绕过将使用代理服务器访问 Pixiv，适合网络受限环境')
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
