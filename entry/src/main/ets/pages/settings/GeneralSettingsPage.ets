import { router, promptAction } from '@kit.ArkUI';
import { imageCacheService } from '../../services/ImageCacheService';
import { SettingItem } from './SettingWidgets';

@Entry
@Component
export struct GeneralSettingsPage {
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
