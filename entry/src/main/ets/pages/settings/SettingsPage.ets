import { AppSettings } from '../../models/AppSettings'
import { imageCacheService } from '../../services/ImageCacheService';
import { userSettingStore } from '../../stores/UserSettingStore';

@Component
export struct SettingsPage {
  @State settings: AppSettings = userSettingStore.getSettings()

  @Builder
  SettingItem(title: string, value: string, onClick: () => void) {
    Row() {
      Text(title)
        .fontSize(14)
        .fontColor('#333333')
      Text(value)
        .fontSize(14)
        .fontColor('#999999')
    }
    .width('100%')
    .height(48)
    .justifyContent(FlexAlign.SpaceBetween)
    .padding({ left: 16, right: 16 })
    .backgroundColor('#FFFFFF')
    .onClick(onClick)
  }

  build() {
    List() {
      ListItem() {
        Column() {
          Text('图片质量')
            .fontSize(12)
            .fontColor('#999999')
            .width('100%')
            .padding({ left: 16, bottom: 4 })
          this.SettingItem('插画质量', this.settings.pictureQuality === 0 ? '中' : this.settings.pictureQuality === 1 ? '大' : '原图', () => {
            let next = (this.settings.pictureQuality + 1) % 3
            userSettingStore.setPictureQuality(next)
            this.settings = userSettingStore.getSettings()
          })
          this.SettingItem('漫画质量', this.settings.mangaQuality === 0 ? '中' : this.settings.mangaQuality === 1 ? '大' : '原图', () => {
            let next = (this.settings.mangaQuality + 1) % 3
            userSettingStore.setMangaQuality(next)
            this.settings = userSettingStore.getSettings()
          })
        }
        .padding({ top: 8, bottom: 8 })
      }

      ListItem() {
        Column() {
          Text('显示设置')
            .fontSize(12)
            .fontColor('#999999')
            .width('100%')
            .padding({ left: 16, bottom: 4 })
          this.SettingItem('主题', this.settings.theme === 'light' ? '浅色' : this.settings.theme === 'dark' ? '深色' : '跟随系统', () => {
            let modes = ['light', 'dark', 'system']
            let next = modes[(modes.indexOf(this.settings.theme) + 1) % modes.length]
            userSettingStore.setTheme(next)
            this.settings = userSettingStore.getSettings()
          })
          this.SettingItem('网格列数', this.settings.crossCount.toString(), () => {
            let next = this.settings.crossCount === 2 ? 3 : 2
            userSettingStore.setCrossCount(next)
            this.settings = userSettingStore.getSettings()
          })
        }
        .padding({ top: 8, bottom: 8 })
      }

      ListItem() {
        Column() {
          Text('网络')
            .fontSize(12)
            .fontColor('#999999')
            .width('100%')
            .padding({ left: 16, bottom: 4 })
          this.SettingItem('网络模式', this.settings.networkMode === 'direct' ? '直连' : '代理', () => {
            let next = this.settings.networkMode === 'direct' ? 'proxy' : 'direct'
            userSettingStore.setNetworkMode(next)
            this.settings = userSettingStore.getSettings()
          })
        }
        .padding({ top: 8, bottom: 8 })
      }

      ListItem() {
        Column() {
          Text('缓存')
            .fontSize(12)
            .fontColor('#999999')
            .width('100%')
            .padding({ left: 16, bottom: 4 })
          this.SettingItem('清理图片缓存', '', () => {
            imageCacheService.clearCache()
          })
        }
        .padding({ top: 8, bottom: 8 })
      }

      ListItem() {
        Column() {
          Text('账户')
            .fontSize(12)
            .fontColor('#999999')
            .width('100%')
            .padding({ left: 16, bottom: 4 })
          Row() {
            Text('退出登录')
              .fontSize(14)
              .fontColor('#FF4444')
          }
          .width('100%')
          .height(48)
          .padding({ left: 16, right: 16 })
          .backgroundColor('#FFFFFF')
          .onClick(() => {
            // TODO: logout
          })
        }
        .padding({ top: 8, bottom: 8 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
