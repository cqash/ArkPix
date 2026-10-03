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
import { getStr } from '../../utils/I18nUtils';

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
        Text($r('app.string.common_back_arrow'))
          .fontSize(16)
          .fontColor('#0096FA')
          .onClick(() => {
            router.back()
          })
        Text($r('app.string.settings_cat_download'))
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
            title: getStr($r('app.string.settings_download_manager')),
            value: '',
            onItemClick: () => {
              router.pushUrl({ url: 'pages/settings/DownloadPage' })
            }
          })
          SettingItem({
            title: getStr($r('app.string.settings_download_quality')),
            value: labelOf(DETAIL_QUALITY_OPTIONS, this.settings.downloadQuality),
            onItemClick: () => {
              showQualityPicker(getStr($r('app.string.settings_download_quality')), DETAIL_QUALITY_OPTIONS, this.settings.downloadQuality,
                (v: number) => { userSettingStore.setDownloadQuality(v); this.refresh() })
            }
          })
          SettingItem({
            title: getStr($r('app.string.settings_download_concurrency')),
            value: labelOf(DOWNLOAD_CONCURRENCY_OPTIONS, this.settings.downloadConcurrency),
            onItemClick: () => {
              showQualityPicker(getStr($r('app.string.settings_download_concurrency')), DOWNLOAD_CONCURRENCY_OPTIONS, this.settings.downloadConcurrency,
                (v: number) => { userSettingStore.setDownloadConcurrency(v); this.refresh() })
            }
          })
          SettingItem({
            title: getStr($r('app.string.settings_filename_template')),
            value: this.settings.filenameTemplate,
            onItemClick: () => {
              router.pushUrl({ url: 'pages/settings/FilenameTemplatePage' })
            }
          })
          SwitchItem({
            title: getStr($r('app.string.settings_embed_exif')),
            isOn: this.settings.embedExifMetadata,
            onToggle: () => {
              userSettingStore.setEmbedExifMetadata(!this.settings.embedExifMetadata)
              this.refresh()
            }
          })
          SettingItem({
            title: getStr($r('app.string.settings_exif_template')),
            value: this.settings.exifCommentTemplate,
            onItemClick: () => {
              router.pushUrl({ url: 'pages/settings/ExifTemplatePage' })
            }
          })
          SettingItem({
            title: getStr($r('app.string.settings_exif_tag_config')),
            value: '',
            onItemClick: () => {
              router.pushUrl({ url: 'pages/settings/ExifTagConfigPage' })
            }
          })
          SwitchItem({
            title: getStr($r('app.string.settings_long_press_save_confirm')),
            isOn: this.settings.longPressSaveConfirm,
            onToggle: () => {
              userSettingStore.setLongPressSaveConfirm(!this.settings.longPressSaveConfirm)
              this.refresh()
            }
          })
          SwitchItem({
            title: getStr($r('app.string.settings_auto_bookmark')),
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
