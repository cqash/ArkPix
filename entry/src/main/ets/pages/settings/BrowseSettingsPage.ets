import { router } from '@kit.ArkUI';
import { AppSettings } from '../../models/AppSettings';
import { userSettingStore } from '../../stores/UserSettingStore';
import {
  SettingItem,
  SwitchItem,
  showQualityPicker,
  labelOf,
  PREVIEW_QUALITY_OPTIONS,
  DETAIL_QUALITY_OPTIONS,
  ILLUST_MANGA_QUALITY_OPTIONS,
  CROSS_COUNT_OPTIONS
} from './SettingWidgets';
import { getStr } from '../../utils/I18nUtils';

@Entry
@Component
export struct BrowseSettingsPage {
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
        Text($r('app.string.settings_cat_browse'))
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
            title: getStr($r('app.string.settings_preview_quality')),
            value: labelOf(PREVIEW_QUALITY_OPTIONS, this.settings.previewQuality),
            onItemClick: () => {
              showQualityPicker(getStr($r('app.string.settings_preview_quality')), PREVIEW_QUALITY_OPTIONS, this.settings.previewQuality,
                (v: number) => { userSettingStore.setPreviewQuality(v); this.refresh() })
            }
          })
          SettingItem({
            title: getStr($r('app.string.settings_detail_quality')),
            value: labelOf(DETAIL_QUALITY_OPTIONS, this.settings.detailQuality),
            onItemClick: () => {
              showQualityPicker(getStr($r('app.string.settings_detail_quality')), DETAIL_QUALITY_OPTIONS, this.settings.detailQuality,
                (v: number) => { userSettingStore.setDetailQuality(v); this.refresh() })
            }
          })
          SettingItem({
            title: getStr($r('app.string.settings_fullscreen_quality')),
            value: labelOf(DETAIL_QUALITY_OPTIONS, this.settings.fullScreenQuality),
            onItemClick: () => {
              showQualityPicker(getStr($r('app.string.settings_fullscreen_quality')), DETAIL_QUALITY_OPTIONS, this.settings.fullScreenQuality,
                (v: number) => { userSettingStore.setFullScreenQuality(v); this.refresh() })
            }
          })
          SettingItem({
            title: getStr($r('app.string.settings_illust_quality')),
            value: labelOf(ILLUST_MANGA_QUALITY_OPTIONS, this.settings.pictureQuality),
            onItemClick: () => {
              showQualityPicker(getStr($r('app.string.settings_illust_quality')), ILLUST_MANGA_QUALITY_OPTIONS, this.settings.pictureQuality,
                (v: number) => { userSettingStore.setPictureQuality(v); this.refresh() })
            }
          })
          SettingItem({
            title: getStr($r('app.string.settings_manga_quality')),
            value: labelOf(ILLUST_MANGA_QUALITY_OPTIONS, this.settings.mangaQuality),
            onItemClick: () => {
              showQualityPicker(getStr($r('app.string.settings_manga_quality')), ILLUST_MANGA_QUALITY_OPTIONS, this.settings.mangaQuality,
                (v: number) => { userSettingStore.setMangaQuality(v); this.refresh() })
            }
          })
          SettingItem({
            title: getStr($r('app.string.settings_cross_count')),
            value: this.settings.crossCount.toString(),
            onItemClick: () => {
              showQualityPicker(getStr($r('app.string.settings_cross_count')), CROSS_COUNT_OPTIONS, this.settings.crossCount,
                (v: number) => { userSettingStore.setCrossCount(v); this.refresh() })
            }
          })
          SwitchItem({
            title: getStr($r('app.string.settings_show_translated')),
            isOn: this.settings.showTranslatedTags,
            onToggle: () => {
              userSettingStore.setShowTranslatedTags(!this.settings.showTranslatedTags)
              this.refresh()
            }
          })
          SwitchItem({
            title: getStr($r('app.string.settings_show_r18_rank')),
            isOn: this.settings.showR18Rank,
            onToggle: () => {
              userSettingStore.setShowR18Rank(!this.settings.showR18Rank)
              this.refresh()
            }
          })
          SwitchItem({
            title: getStr($r('app.string.settings_anti_social')),
            isOn: this.settings.antiSocialDeath,
            onToggle: () => {
              userSettingStore.setAntiSocialDeath(!this.settings.antiSocialDeath)
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
