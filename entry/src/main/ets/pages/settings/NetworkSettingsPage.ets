import { router } from '@kit.ArkUI';
import { AppSettings } from '../../models/AppSettings';
import { userSettingStore } from '../../stores/UserSettingStore';
import { hoster } from '../../network/Hoster';
import { localProxyServer } from '../../network/LocalProxyServer';
import { Constants } from '../../utils/Constants';
import {
  SettingItem,
  TextInputItem,
  showQualityPicker,
  NETWORK_MODE_OPTIONS,
  NETWORK_MODE_VALUES,
  IMAGE_HOST_OPTIONS,
  IMAGE_HOST_VALUES,
  networkModeLabel,
  networkModeIndex,
  imageHostLabel,
  imageHostIndex
} from './SettingWidgets';
import { getStr } from '../../utils/I18nUtils';

@Entry
@Component
export struct NetworkSettingsPage {
  @State settings: AppSettings = userSettingStore.getSettings()

  private refresh(): void {
    this.settings = userSettingStore.getSettings()
  }

  /** 选中 relay 但 relayServerUrl 为空时引导配置且不生效（不落 setter） */
  private ensureRelayReady(mode: string): boolean {
    if (!Constants.isRelayMode(mode)) {
      return true
    }
    if (userSettingStore.getSettings().relayServerUrl.trim().length === 0) {
      this.getUIContext().showAlertDialog({
        title: $r('app.string.settings_relay_missing_title'),
        message: $r('app.string.settings_relay_missing_msg'),
        autoCancel: true,
        primaryButton: {
          value: $r('app.string.settings_got_it'),
          action: () => {}
        }
      })
      return false
    }
    return true
  }

  private applyAuthMode(mode: string): void {
    if (!this.ensureRelayReady(mode)) {
      return
    }
    // 从非 relay 切到 relay 前记录上一可用模式（失败回落用）
    if (Constants.isRelayMode(mode) && !Constants.isRelayMode(this.settings.authMode)) {
      userSettingStore.setPrevAuthMode(this.settings.authMode)
    }
    userSettingStore.setAuthMode(mode)
    hoster.init()
    hoster.refreshAll()
    localProxyServer.start()
    this.refresh()
  }

  private applyApiMode(mode: string): void {
    if (!this.ensureRelayReady(mode)) {
      return
    }
    if (Constants.isRelayMode(mode) && !Constants.isRelayMode(this.settings.apiMode)) {
      userSettingStore.setPrevApiMode(this.settings.apiMode)
    }
    userSettingStore.setApiMode(mode)
    hoster.init()
    hoster.refreshAll()
    localProxyServer.start()
    this.refresh()
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Text($r('app.string.common_back_arrow'))
          .fontSize(16)
          .fontColor('#0096FA')
          .onClick(() => {
            router.back()
          })
        Text($r('app.string.settings_cat_network'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text('    ')
          .fontSize(16)
          .width(48)
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor('#FFFFFF')

      Scroll() {
        Column() {
          SettingItem({
            title: getStr($r('app.string.settings_auth_mode')),
            value: networkModeLabel(this.settings.authMode),
            onItemClick: () => {
              showQualityPicker(getStr($r('app.string.settings_auth_mode')), NETWORK_MODE_OPTIONS, networkModeIndex(this.settings.authMode),
                (v: number) => {
                  this.applyAuthMode(NETWORK_MODE_VALUES[v])
                })
            }
          })
          SettingItem({
            title: getStr($r('app.string.settings_api_mode')),
            value: networkModeLabel(this.settings.apiMode),
            onItemClick: () => {
              showQualityPicker(getStr($r('app.string.settings_api_mode')), NETWORK_MODE_OPTIONS, networkModeIndex(this.settings.apiMode),
                (v: number) => {
                  this.applyApiMode(NETWORK_MODE_VALUES[v])
                })
            }
          })

          Text($r('app.string.settings_net_mode_desc'))
            .fontSize(12)
            .fontColor('#999999')
            .width('100%')
            .padding({ left: 16, right: 16, top: 4, bottom: 8 })

          SettingItem({
            title: getStr($r('app.string.settings_image_host')),
            value: imageHostLabel(this.settings.imageHostType),
            onItemClick: () => {
              showQualityPicker(getStr($r('app.string.settings_image_host')), IMAGE_HOST_OPTIONS, imageHostIndex(this.settings.imageHostType),
                (v: number) => {
                  userSettingStore.setImageHostType(IMAGE_HOST_VALUES[v])
                  this.refresh()
                })
            }
          })
          if (this.settings.imageHostType === 'custom') {
            TextInputItem({
              title: getStr($r('app.string.settings_image_host_custom_title')),
              placeholder: getStr($r('app.string.settings_image_host_custom_placeholder')),
              value: this.settings.imageHostCustom,
              onTextChange: (text: string) => {
                userSettingStore.setImageHostCustom(text)
              }
            })
          }
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })
      }
      .width('100%')
      .layoutWeight(1)
      // Scroll 限高后内容不足一屏时默认居中，须显式顶部对齐
      .align(Alignment.TopStart)
      .backgroundColor('#F5F5F5')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
