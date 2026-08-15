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
  networkModeLabel
} from './SettingWidgets';

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
    return '预览:' + labelOf(PREVIEW_QUALITY_OPTIONS, this.settings.previewQuality) +
      ' · 网格:' + this.settings.crossCount + '列'
  }

  private downloadSummary(): string {
    return labelOf(DETAIL_QUALITY_OPTIONS, this.settings.downloadQuality) +
      ' · ' + this.settings.downloadConcurrency + '线程'
  }

  private filterSummary(): string {
    return 'AI过滤:' + (this.settings.aiFilter ? '开' : '关')
  }

  private networkSummary(): string {
    return '认证:' + networkModeLabel(this.settings.authMode) +
      ' · API:' + networkModeLabel(this.settings.apiMode)
  }

  private relaySummary(): string {
    let status: string
    if (this.settings.relayServerUrl.trim().length === 0) {
      status = '未配置'
    } else if (!this.relayRegistered) {
      status = '未注册'
    } else {
      status = '已连接' + (this.relayServerVersion.length > 0 ? ' v' + this.relayServerVersion : '')
    }
    return status + ' · 同步:' + (this.settings.syncEnabled ? '开' : '关')
  }

  private accountSummary(): string {
    return this.accountName
  }

  build() {
    Column() {
      // 标题
      Row() {
        Text('设置')
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
            title: '浏览与显示',
            value: this.browseSummary(),
            onItemClick: () => {
              router.pushUrl({ url: 'pages/settings/BrowseSettingsPage' })
            }
          })
          SettingItem({
            title: '下载与元数据',
            value: this.downloadSummary(),
            onItemClick: () => {
              router.pushUrl({ url: 'pages/settings/DownloadSettingsPage' })
            }
          })
          SettingItem({
            title: '屏蔽与过滤',
            value: this.filterSummary(),
            onItemClick: () => {
              router.pushUrl({ url: 'pages/settings/FilterSettingsPage' })
            }
          })
          SettingItem({
            title: '网络',
            value: this.networkSummary(),
            onItemClick: () => {
              router.pushUrl({ url: 'pages/settings/NetworkSettingsPage' })
            }
          })
          SettingItem({
            title: '中继服务器与同步',
            value: this.relaySummary(),
            onItemClick: () => {
              router.pushUrl({ url: 'pages/settings/RelaySettingsPage' })
            }
          })
          SettingItem({
            title: '通用',
            value: '',
            onItemClick: () => {
              router.pushUrl({ url: 'pages/settings/GeneralSettingsPage' })
            }
          })
          SettingItem({
            title: '账户',
            value: this.accountSummary(),
            onItemClick: () => {
              router.pushUrl({ url: 'pages/settings/AccountSettingsPage' })
            }
          })
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
