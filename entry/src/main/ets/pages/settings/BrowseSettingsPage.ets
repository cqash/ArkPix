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
        Text('< 返回')
          .fontSize(16)
          .fontColor('#0096FA')
          .onClick(() => {
            router.back()
          })
        Text('浏览与显示')
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
            title: '预览图质量',
            value: labelOf(PREVIEW_QUALITY_OPTIONS, this.settings.previewQuality),
            onItemClick: () => {
              showQualityPicker('预览图质量', PREVIEW_QUALITY_OPTIONS, this.settings.previewQuality,
                (v: number) => { userSettingStore.setPreviewQuality(v); this.refresh() })
            }
          })
          SettingItem({
            title: '详情页质量',
            value: labelOf(DETAIL_QUALITY_OPTIONS, this.settings.detailQuality),
            onItemClick: () => {
              showQualityPicker('详情页质量', DETAIL_QUALITY_OPTIONS, this.settings.detailQuality,
                (v: number) => { userSettingStore.setDetailQuality(v); this.refresh() })
            }
          })
          SettingItem({
            title: '全屏查看质量',
            value: labelOf(DETAIL_QUALITY_OPTIONS, this.settings.fullScreenQuality),
            onItemClick: () => {
              showQualityPicker('全屏查看质量', DETAIL_QUALITY_OPTIONS, this.settings.fullScreenQuality,
                (v: number) => { userSettingStore.setFullScreenQuality(v); this.refresh() })
            }
          })
          SettingItem({
            title: '插画质量',
            value: labelOf(ILLUST_MANGA_QUALITY_OPTIONS, this.settings.pictureQuality),
            onItemClick: () => {
              showQualityPicker('插画质量', ILLUST_MANGA_QUALITY_OPTIONS, this.settings.pictureQuality,
                (v: number) => { userSettingStore.setPictureQuality(v); this.refresh() })
            }
          })
          SettingItem({
            title: '漫画质量',
            value: labelOf(ILLUST_MANGA_QUALITY_OPTIONS, this.settings.mangaQuality),
            onItemClick: () => {
              showQualityPicker('漫画质量', ILLUST_MANGA_QUALITY_OPTIONS, this.settings.mangaQuality,
                (v: number) => { userSettingStore.setMangaQuality(v); this.refresh() })
            }
          })
          SettingItem({
            title: '网格列数',
            value: this.settings.crossCount.toString(),
            onItemClick: () => {
              showQualityPicker('网格列数', CROSS_COUNT_OPTIONS, this.settings.crossCount,
                (v: number) => { userSettingStore.setCrossCount(v); this.refresh() })
            }
          })
          SwitchItem({
            title: '显示翻译标签',
            isOn: this.settings.showTranslatedTags,
            onToggle: () => {
              userSettingStore.setShowTranslatedTags(!this.settings.showTranslatedTags)
              this.refresh()
            }
          })
          SwitchItem({
            title: '显示 R18 榜单',
            isOn: this.settings.showR18Rank,
            onToggle: () => {
              userSettingStore.setShowR18Rank(!this.settings.showR18Rank)
              this.refresh()
            }
          })
          SwitchItem({
            title: '防社死模式',
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
