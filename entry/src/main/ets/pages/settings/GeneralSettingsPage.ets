import { router, promptAction } from '@kit.ArkUI';
import { imageCacheService } from '../../services/ImageCacheService';
import { distributedSyncService } from '../../services/DistributedSyncService';
import { userSettingStore } from '../../stores/UserSettingStore';
import { AppSettings } from '../../models/AppSettings';
import { SettingItem, SwitchItem, SectionHeader } from './SettingWidgets';

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
        this.getUIContext().getPromptAction().showToast({ message: '未授权跨设备数据同步，可在系统设置中开启后重试' })
      }
      this.refreshSyncState()
    })
  }

  private refreshSyncState() {
    this.settings = userSettingStore.getSettings()
  }

  private deviceSyncStatusText(): string {
    if (!this.settings.deviceSyncEnabled) {
      return '未开启'
    }
    return this.deviceSyncActive ? '已加入会话' : '未授权'
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Text('< 返回')
          .fontSize(16)
          .fontColor('#0096FA')
          .onClick(() => {
            router.back()
          })
        Text('通用')
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
          SectionHeader({ title: '设备间同步' })
          SwitchItem({
            title: '设备间同步（设置/屏蔽/历史）',
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
            title: '同步状态',
            value: this.deviceSyncStatusText()
          })
          SectionHeader({ title: '通用' })
          SettingItem({
            title: '我的收藏',
            value: '',
            onItemClick: () => {
              router.pushUrl({ url: 'pages/bookmark/BookmarkPage' })
            }
          })
          SettingItem({
            title: '历史记录',
            value: '',
            onItemClick: () => {
              router.pushUrl({ url: 'pages/settings/HistoryPage' })
            }
          })
          SettingItem({
            title: '清理图片缓存',
            value: '',
            onItemClick: () => {
              this.getUIContext().showAlertDialog({
                title: '清理缓存',
                message: '确定要清理所有图片缓存吗？',
                autoCancel: true,
                primaryButton: {
                  value: '取消',
                  action: () => {}
                },
                secondaryButton: {
                  value: '确定',
                  action: () => {
                    imageCacheService.clearCache()
                    promptAction.showToast({ message: '图片缓存已清理' })
                  }
                }
              })
            }
          })
          SettingItem({
            title: '关于 ArkPix',
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
