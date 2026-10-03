import { router } from '@kit.ArkUI';
import { accountStore, Account } from '../../stores/AccountStore';
import { AppSettings } from '../../models/AppSettings';
import { userSettingStore } from '../../stores/UserSettingStore';
import { relayClient } from '../../network/RelayClient';
import {
  SettingItem,
  labelOf,
  PREVIEW_QUALITY_OPTIONS,
  DETAIL_QUALITY_OPTIONS,
  networkModeLabel,
  languageLabel
} from './SettingWidgets';
import { getStr, getStrf } from '../../utils/I18nUtils';

/**
 * 设置首页：仅呈现 7 个分类入口，点击进入独立路由二级子页。
 * 全部设置项已平移至 BrowseSettingsPage/DownloadSettingsPage/FilterSettingsPage/
 * NetworkSettingsPage/RelaySettingsPage/GeneralSettingsPage/AccountSettingsPage。
 * @Entry：同时作为 HomePage 的 Tab 子组件与独立路由页（登录页"设置"入口 pushUrl 进入）。
 */
@Entry
@Component
export struct SettingsPage {
  @State settings: AppSettings = userSettingStore.getSettings()

  // 中继状态摘要用（子页返回后 aboutToAppear 重读刷新）
  @State relayRegistered: boolean = false
  @State relayServerVersion: string = ''
  @State accountName: string = ''

  aboutToAppear(): void {
    this.settings = userSettingStore.getSettings()
    this.relayRegistered = relayClient.isRegistered()
    this.relayServerVersion = relayClient.getServerVersion()
    let account: Account | null = accountStore.getCurrentAccount()
    this.accountName = account ? account.name : ''
  }

  private browseSummary(): string {
    return getStrf($r('app.string.settings_summary_browse'),
      labelOf(PREVIEW_QUALITY_OPTIONS, this.settings.previewQuality), this.settings.crossCount)
  }

  private downloadSummary(): string {
    return labelOf(DETAIL_QUALITY_OPTIONS, this.settings.downloadQuality) +
      getStrf($r('app.string.settings_summary_threads_suffix'), this.settings.downloadConcurrency)
  }

  private filterSummary(): string {
    let onOff = this.settings.aiFilter ? getStr($r('app.string.common_switch_on')) : getStr($r('app.string.common_switch_off'))
    return getStrf($r('app.string.settings_summary_ai_filter'), onOff)
  }

  private networkSummary(): string {
    return getStrf($r('app.string.settings_summary_network'),
      networkModeLabel(this.settings.authMode), networkModeLabel(this.settings.apiMode))
  }

  private relaySummary(): string {
    let status: string
    if (this.settings.relayServerUrl.trim().length === 0) {
      status = getStr($r('app.string.settings_relay_not_configured'))
    } else if (!this.relayRegistered) {
      status = getStr($r('app.string.settings_relay_not_registered'))
    } else {
      status = getStr($r('app.string.settings_relay_connected')) +
        (this.relayServerVersion.length > 0 ? ' v' + this.relayServerVersion : '')
    }
    let onOff = this.settings.syncEnabled ? getStr($r('app.string.common_switch_on')) : getStr($r('app.string.common_switch_off'))
    return status + getStrf($r('app.string.settings_summary_sync'), onOff)
  }

  private accountSummary(): string {
    return this.accountName
  }

  build() {
    Column() {
      // 标题
      Row() {
        Text($r('app.string.settings_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor('#FFFFFF')

      Scroll() {
        Column() {
          SettingItem({
            title: getStr($r('app.string.settings_cat_browse')),
            value: this.browseSummary(),
            onItemClick: () => {
              router.pushUrl({ url: 'pages/settings/BrowseSettingsPage' })
            }
          })
          SettingItem({
            title: getStr($r('app.string.settings_cat_download')),
            value: this.downloadSummary(),
            onItemClick: () => {
              router.pushUrl({ url: 'pages/settings/DownloadSettingsPage' })
            }
          })
          SettingItem({
            title: getStr($r('app.string.settings_cat_filter')),
            value: this.filterSummary(),
            onItemClick: () => {
              router.pushUrl({ url: 'pages/settings/FilterSettingsPage' })
            }
          })
          SettingItem({
            title: getStr($r('app.string.settings_cat_network')),
            value: this.networkSummary(),
            onItemClick: () => {
              router.pushUrl({ url: 'pages/settings/NetworkSettingsPage' })
            }
          })
          SettingItem({
            title: getStr($r('app.string.settings_cat_relay')),
            value: this.relaySummary(),
            onItemClick: () => {
              router.pushUrl({ url: 'pages/settings/RelaySettingsPage' })
            }
          })
          SettingItem({
            title: getStr($r('app.string.settings_cat_general')),
            value: languageLabel(this.settings.language),
            onItemClick: () => {
              router.pushUrl({ url: 'pages/settings/GeneralSettingsPage' })
            }
          })
          SettingItem({
            title: getStr($r('app.string.settings_cat_account')),
            value: this.accountSummary(),
            onItemClick: () => {
              router.pushUrl({ url: 'pages/settings/AccountSettingsPage' })
            }
          })
        }
        .width('100%')
        .padding({ top: 8, bottom: 80 })
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
