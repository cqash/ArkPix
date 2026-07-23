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
          SettingItem({
            title: '预览图质量',
            value: this.settings.previewQuality === 0 ? '缩略图' : this.settings.previewQuality === 1 ? '中图' : '大图',
            onItemClick: () => {
              let next = (this.settings.previewQuality + 1) % 3
              userSettingStore.setPreviewQuality(next)
              this.settings = userSettingStore.getSettings()
            }
          })
          SettingItem({
            title: '详情页质量',
            value: this.settings.detailQuality === 0 ? '大图' : '原图',
            onItemClick: () => {
              let next = this.settings.detailQuality === 0 ? 1 : 0
              userSettingStore.setDetailQuality(next)
              this.settings = userSettingStore.getSettings()
            }
          })
          SettingItem({
            title: '全屏查看质量',
            value: this.settings.fullScreenQuality === 0 ? '大图' : '原图',
            onItemClick: () => {
              let next = this.settings.fullScreenQuality === 0 ? 1 : 0
              userSettingStore.setFullScreenQuality(next)
              this.settings = userSettingStore.getSettings()
            }
          })
          SettingItem({
            title: '下载图片质量',
            value: this.settings.downloadQuality === 0 ? '大图' : '原图',
            onItemClick: () => {
              let next = this.settings.downloadQuality === 0 ? 1 : 0
              userSettingStore.setDownloadQuality(next)
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
            value: this.settings.networkMode === 'direct' ? '直连' : this.settings.networkMode === 'bypass' ? '绕过' : '代理',
            onItemClick: () => {
              let modes: string[] = ['direct', 'bypass', 'proxy']
              let currentIndex: number = modes.indexOf(this.settings.networkMode)
              if (currentIndex < 0) {
                currentIndex = 0
              }
              let nextIndex: number = (currentIndex + 1) % modes.length
              let next: string = modes[nextIndex]
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
          Text('收藏')
            .fontSize(12)
            .fontColor('#999999')
            .width('100%')
            .padding({ left: 16, bottom: 4 })
          SettingItem({
            title: '我的收藏',
            value: '',
            onItemClick: () => {
              router.pushUrl({ url: 'pages/bookmark/BookmarkPage' })
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
          SettingItem({
            title: '文件名模板',
            value: this.settings.filenameTemplate,
            onItemClick: () => {
              router.pushUrl({ url: 'pages/settings/FilenameTemplatePage' })
            }
          })
          SettingItem({
            title: '写入图片元数据',
            value: this.settings.embedExifMetadata ? '开启' : '关闭',
            onItemClick: () => {
              userSettingStore.setEmbedExifMetadata(!this.settings.embedExifMetadata)
              this.settings = userSettingStore.getSettings()
            }
          })
          SettingItem({
            title: '备注模板',
            value: this.settings.exifCommentTemplate,
            onItemClick: () => {
              router.pushUrl({ url: 'pages/settings/ExifTemplatePage' })
            }
          })
          SettingItem({
            title: '显示翻译标签',
            value: this.settings.showTranslatedTags ? '开启' : '关闭',
            onItemClick: () => {
              userSettingStore.setShowTranslatedTags(!this.settings.showTranslatedTags)
              this.settings = userSettingStore.getSettings()
            }
          })
          SettingItem({
            title: '下载时自动收藏',
            value: this.settings.autoBookmarkOnDownload ? '开启' : '关闭',
            onItemClick: () => {
              userSettingStore.setAutoBookmarkOnDownload(!this.settings.autoBookmarkOnDownload)
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
