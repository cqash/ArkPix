import { router } from '@kit.ArkUI';
import { accountStore } from '../../stores/AccountStore';
import { AppSettings } from '../../models/AppSettings'
import { imageCacheService } from '../../services/ImageCacheService';
import { userSettingStore } from '../../stores/UserSettingStore';

@Component
struct SettingItem {
  @Prop title: string = ''
  @Prop value: string = ''
  onItemClick: (() => void) | null = null

  build() {
    Row() {
      Text(this.title)
        .fontSize(14)
        .fontColor('#333333')
      Row() {
        Text(this.value)
          .fontSize(14)
          .fontColor('#0096FA')
        Text(' >')
          .fontSize(16)
          .fontColor('#999999')
      }
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .height(48)
    .justifyContent(FlexAlign.SpaceBetween)
    .padding({ left: 16, right: 16 })
    .backgroundColor('#FFFFFF')
    .stateStyles({
      pressed: {
        .backgroundColor('#F0F0F0')
      }
    })
    .onClick(() => {
      if (this.onItemClick) {
        this.onItemClick()
      }
    })
  }
}

@Component
export struct SettingsPage {
  @State settings: AppSettings = userSettingStore.getSettings()

  build() {
    List() {
      ListItem() {
        Column() {
          Text('图片质量')
            .fontSize(12)
            .fontColor('#999999')
            .width('100%')
            .padding({ left: 16, bottom: 4 })
          SettingItem({
            title: '插画质量',
            value: this.settings.pictureQuality === 0 ? '中' : this.settings.pictureQuality === 1 ? '大' : '原图',
            onItemClick: () => {
              let next = (this.settings.pictureQuality + 1) % 3
              userSettingStore.setPictureQuality(next)
              this.settings = userSettingStore.getSettings()
            }
          })
          SettingItem({
            title: '漫画质量',
            value: this.settings.mangaQuality === 0 ? '中' : this.settings.mangaQuality === 1 ? '大' : '原图',
            onItemClick: () => {
              let next = (this.settings.mangaQuality + 1) % 3
              userSettingStore.setMangaQuality(next)
              this.settings = userSettingStore.getSettings()
            }
          })
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })
      }
      .width('100%')

      ListItem() {
        Column() {
          Text('显示设置')
            .fontSize(12)
            .fontColor('#999999')
            .width('100%')
            .padding({ left: 16, bottom: 4 })
          SettingItem({
            title: '主题',
            value: this.settings.theme === 'light' ? '浅色' : this.settings.theme === 'dark' ? '深色' : '跟随系统',
            onItemClick: () => {
              let modes = ['light', 'dark', 'system']
              let next = modes[(modes.indexOf(this.settings.theme) + 1) % modes.length]
              userSettingStore.setTheme(next)
              this.settings = userSettingStore.getSettings()
            }
          })
          SettingItem({
            title: '网格列数',
            value: this.settings.crossCount.toString(),
            onItemClick: () => {
              let next = this.settings.crossCount === 2 ? 3 : 2
              userSettingStore.setCrossCount(next)
              this.settings = userSettingStore.getSettings()
            }
          })
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })
      }
      .width('100%')

      ListItem() {
        Column() {
          Text('网络')
            .fontSize(12)
            .fontColor('#999999')
            .width('100%')
            .padding({ left: 16, bottom: 4 })
          SettingItem({
            title: '网络模式',
            value: this.settings.networkMode === 'direct' ? '直连' : '代理',
            onItemClick: () => {
              let next = this.settings.networkMode === 'direct' ? 'proxy' : 'direct'
              userSettingStore.setNetworkMode(next)
              this.settings = userSettingStore.getSettings()
            }
          })
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })
      }
      .width('100%')

      ListItem() {
        Column() {
          Text('缓存')
            .fontSize(12)
            .fontColor('#999999')
            .width('100%')
            .padding({ left: 16, bottom: 4 })
          SettingItem({
            title: '清理图片缓存',
            value: '',
            onItemClick: () => {
              imageCacheService.clearCache()
            }
          })
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })
      }
      .width('100%')

      ListItem() {
        Column() {
          Text('下载')
            .fontSize(12)
            .fontColor('#999999')
            .width('100%')
            .padding({ left: 16, bottom: 4 })
          SettingItem({
            title: '下载管理',
            value: '',
            onItemClick: () => {
              router.pushUrl({ url: 'pages/settings/DownloadPage' })
            }
          })
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })
      }
      .width('100%')

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
            Text(' >')
              .fontSize(16)
              .fontColor('#999999')
          }
          .width('100%')
          .height(48)
          .justifyContent(FlexAlign.SpaceBetween)
          .padding({ left: 16, right: 16 })
          .backgroundColor('#FFFFFF')
          .stateStyles({
            pressed: {
              .backgroundColor('#F0F0F0')
            }
          })
          .onClick(() => {
            accountStore.logout()
            router.replaceUrl({ url: 'pages/login/LoginPage' })
          })
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
