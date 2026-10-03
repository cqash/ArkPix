import { router, promptAction } from '@kit.ArkUI';
import { imageCacheService } from '../../services/ImageCacheService';
import { distributedSyncService } from '../../services/DistributedSyncService';
import { userSettingStore } from '../../stores/UserSettingStore';
import { AppSettings } from '../../models/AppSettings';
import { SettingItem, SwitchItem, SectionHeader, showQualityPicker, LANGUAGE_OPTIONS, LANGUAGE_VALUES, languageIndex, languageLabel } from './SettingWidgets';
import { getStr } from '../../utils/I18nUtils';
import { HapticUtils } from '../../utils/HapticUtils';

@Entry
@Component
export struct GeneralSettingsPage {
  @State settings: AppSettings = userSettingStore.getSettings()
  // FR-013：会话状态事件化——DistributedSyncService 在 sessionActive 每次变更时写 AppStorage，
  // @StorageLink 订阅后入会话成功瞬间 UI 自动更新，无需手动轮询/延时刷新
  @StorageLink('deviceSyncActive') deviceSyncActive: boolean = false

  aboutToAppear() {
    // 首开时申请 DISTRIBUTED_DATASYNC 权限并加入同步会话（deviceSyncEnabled 默认开）；
    // 权限拒绝则 setEnabled 内部回退开关持久化，此处 toast 引导
    if (this.settings.deviceSyncEnabled && !this.deviceSyncActive) {
      this.enableDeviceSync()
    }
  }

  private enableDeviceSync() {
    distributedSyncService.setEnabled(true, (success: boolean) => {
      if (!success) {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.settings_device_sync_denied_toast') })
      }
      this.refreshSyncState()
    })
  }

  private refreshSyncState() {
    this.settings = userSettingStore.getSettings()
  }

  private deviceSyncStatusText(): string {
    if (!this.settings.deviceSyncEnabled) {
      return getStr($r('app.string.settings_sync_off'))
    }
    return this.deviceSyncActive ? getStr($r('app.string.settings_sync_joined')) :
      getStr($r('app.string.settings_sync_unauthorized'))
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
        Text($r('app.string.settings_cat_general'))
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
          SectionHeader({ title: getStr($r('app.string.settings_section_device_sync')) })
          SwitchItem({
            title: getStr($r('app.string.settings_device_sync_item')),
            isOn: this.settings.deviceSyncEnabled,
            onToggle: () => {
              let next = !this.settings.deviceSyncEnabled
              if (next) {
                // 开启：触发权限申请 + 入会话（拒绝时内部回退持久化并回调 toast）
                this.enableDeviceSync()
              } else {
                distributedSyncService.setEnabled(false)
                this.refreshSyncState()
              }
            }
          })
          SettingItem({
            title: getStr($r('app.string.settings_sync_status')),
            value: this.deviceSyncStatusText()
          })
          SectionHeader({ title: getStr($r('app.string.settings_cat_general')) })
          SettingItem({
            title: getStr($r('app.string.settings_language')),
            value: languageLabel(this.settings.language),
            onItemClick: () => {
              showQualityPicker(getStr($r('app.string.settings_language')), LANGUAGE_OPTIONS,
                languageIndex(this.settings.language), (v: number) => {
                  // showQualityPicker 回调的是 value 字段，这里直接用索引语义（value===index）
                  userSettingStore.setLanguage(LANGUAGE_VALUES[v])
                  this.settings = userSettingStore.getSettings()
                })
            }
          })
          SwitchItem({
            title: getStr($r('app.string.settings_haptic_feedback')),
            isOn: this.settings.hapticFeedback,
            onToggle: () => {
              userSettingStore.setHapticFeedback(!this.settings.hapticFeedback)
              this.settings = userSettingStore.getSettings()
            }
          })
          SettingItem({
            title: getStr($r('app.string.settings_my_bookmarks')),
            value: '',
            onItemClick: () => {
              router.pushUrl({ url: 'pages/bookmark/BookmarkPage' })
            }
          })
          SettingItem({
            title: getStr($r('app.string.settings_history')),
            value: '',
            onItemClick: () => {
              router.pushUrl({ url: 'pages/settings/HistoryPage' })
            }
          })
          SettingItem({
            title: getStr($r('app.string.settings_clear_cache')),
            value: '',
            onItemClick: () => {
              this.getUIContext().showAlertDialog({
                title: $r('app.string.settings_clear_cache_title'),
                message: $r('app.string.settings_clear_cache_msg'),
                autoCancel: true,
                primaryButton: {
                  value: $r('app.string.common_cancel'),
                  action: () => {}
                },
                secondaryButton: {
                  value: $r('app.string.common_confirm'),
                  action: () => {
                    HapticUtils.heavy()
                    imageCacheService.clearCache()
                    promptAction.showToast({ message: $r('app.string.settings_cache_cleared') })
                  }
                }
              })
            }
          })
          SettingItem({
            title: getStr($r('app.string.settings_about')),
            value: 'v1.0.0',
            onItemClick: () => {
              router.pushUrl({ url: 'pages/settings/AboutPage' })
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
