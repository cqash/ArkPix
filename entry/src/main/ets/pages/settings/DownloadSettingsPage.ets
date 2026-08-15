import { router } from '@kit.ArkUI';
import { AppSettings } from '../../models/AppSettings';
import { userSettingStore } from '../../stores/UserSettingStore';
import {
  SettingItem,
  SwitchItem,
  showQualityPicker,
  labelOf,
  DETAIL_QUALITY_OPTIONS,
  DOWNLOAD_CONCURRENCY_OPTIONS
} from './SettingWidgets';

@Entry
@Component
export struct DownloadSettingsPage {
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
        Text('下载与元数据')
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
            title: '下载管理',
            value: '',
            onItemClick: () => {
              router.pushUrl({ url: 'pages/settings/DownloadPage' })
            }
          })
          SettingItem({
            title: '下载图片质量',
            value: labelOf(DETAIL_QUALITY_OPTIONS, this.settings.downloadQuality),
            onItemClick: () => {
              showQualityPicker('下载图片质量', DETAIL_QUALITY_OPTIONS, this.settings.downloadQuality,
                (v: number) => { userSettingStore.setDownloadQuality(v); this.refresh() })
            }
          })
          SettingItem({
            title: '下载线程数',
            value: labelOf(DOWNLOAD_CONCURRENCY_OPTIONS, this.settings.downloadConcurrency),
            onItemClick: () => {
              showQualityPicker('下载线程数', DOWNLOAD_CONCURRENCY_OPTIONS, this.settings.downloadConcurrency,
                (v: number) => { userSettingStore.setDownloadConcurrency(v); this.refresh() })
            }
          })
          SettingItem({
            title: '文件名模板',
            value: this.settings.filenameTemplate,
            onItemClick: () => {
              router.pushUrl({ url: 'pages/settings/FilenameTemplatePage' })
            }
          })
          SwitchItem({
            title: '写入图片元数据',
            isOn: this.settings.embedExifMetadata,
            onToggle: () => {
              userSettingStore.setEmbedExifMetadata(!this.settings.embedExifMetadata)
              this.refresh()
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
            title: 'EXIF 标签管理',
            value: '',
            onItemClick: () => {
              router.pushUrl({ url: 'pages/settings/ExifTagConfigPage' })
            }
          })
          SwitchItem({
            title: '自动合并同义标签',
            isOn: this.settings.autoMergeTranslatedTags,
            onToggle: () => {
              userSettingStore.setAutoMergeTranslatedTags(!this.settings.autoMergeTranslatedTags)
              this.refresh()
            }
          })
          SwitchItem({
            title: '下载时自动收藏',
            isOn: this.settings.autoBookmarkOnDownload,
            onToggle: () => {
              userSettingStore.setAutoBookmarkOnDownload(!this.settings.autoBookmarkOnDownload)
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
