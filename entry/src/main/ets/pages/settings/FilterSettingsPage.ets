import { router } from '@kit.ArkUI';
import { AppSettings } from '../../models/AppSettings';
import { userSettingStore } from '../../stores/UserSettingStore';
import { SettingItem, SwitchItem } from './SettingWidgets';

@Entry
@Component
export struct FilterSettingsPage {
  @State settings: AppSettings = userSettingStore.getSettings()

  private refresh(): void {
    this.settings = userSettingStore.getSettings()
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
        Text('屏蔽与过滤')
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
            title: '屏蔽管理',
            value: this.settings.muteTags.length + this.settings.muteUsers.length > 0 ?
              (this.settings.muteTags.length + this.settings.muteUsers.length) + ' 条规则' : '',
            onItemClick: () => {
              router.pushUrl({ url: 'pages/settings/MutePage' })
            }
          })
          SwitchItem({
            title: '过滤 AI 作品',
            isOn: this.settings.aiFilter,
            onToggle: () => {
              userSettingStore.setAiFilter(!this.settings.aiFilter)
              this.refresh()
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
