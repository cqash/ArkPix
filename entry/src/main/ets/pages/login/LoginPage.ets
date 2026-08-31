import { router } from '@kit.ArkUI';
import { userSettingStore } from '../../stores/UserSettingStore';
import { hoster } from '../../network/Hoster';
import { localProxyServer } from '../../network/LocalProxyServer';
import {
  showQualityPicker,
  LANGUAGE_OPTIONS,
  LANGUAGE_VALUES,
  languageIndex
} from '../settings/SettingWidgets';
import { getStr } from '../../utils/I18nUtils';

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

      Button($r('app.string.login_webview'))
        .width('85%')
        .height(50)
        .backgroundColor('#0096FA')
        .fontColor('#FFFFFF')
        .fontSize(16)
        .onClick(() => {
          router.pushUrl({ url: 'pages/login/WebViewLoginPage' })
        })

      Button($r('app.string.login_token'))
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
        Text($r('app.string.login_bypass'))
          .fontSize(14)
          .fontColor('#666666')
          .margin({ left: 8 })
      }
      .width('85%')
      .margin({ top: 16 })

      if (this.useBypass) {
        Text($r('app.string.login_bypass_hint'))
          .fontSize(12)
          .fontColor('#FF8800')
          .width('85%')
          .textAlign(TextAlign.Center)
      }

      Text($r('app.string.login_terms'))
        .fontSize(12)
        .fontColor('#999999')
        .margin({ top: 24 })
        .decoration({ type: TextDecorationType.Underline })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#FFFFFF')

      // 右上角语言/设置入口：登录前可切换界面语言、配置网络/中继（如先开中继再登录）
      Row() {
        Text($r('app.string.settings_language'))
          .fontSize(15)
          .fontColor('#0096FA')
          .padding({ left: 24, right: 20, top: 16, bottom: 16 })
          .onClick(() => {
            showQualityPicker(getStr($r('app.string.settings_language')), LANGUAGE_OPTIONS,
              languageIndex(userSettingStore.getSettings().language), (v: number) => {
                userSettingStore.setLanguage(LANGUAGE_VALUES[v])
              })
          })
        Text($r('app.string.settings_title'))
          .fontSize(15)
          .fontColor('#0096FA')
          .padding({ left: 24, right: 20, top: 16, bottom: 16 })
          .onClick(() => {
            router.pushUrl({ url: 'pages/settings/SettingsPage' })
          })
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height('100%')
  }
}
