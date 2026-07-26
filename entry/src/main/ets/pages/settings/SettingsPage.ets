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
        if (this.onItemClick) {
          Text(' >')
            .fontSize(16)
            .fontColor('#999999')
        }
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
struct SwitchItem {
  @Prop title: string = ''
  @Prop isOn: boolean = false
  onToggle: (() => void) | null = null

  build() {
    Row() {
      Text(this.title)
        .fontSize(14)
        .fontColor('#333333')
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .selectedColor('#0096FA')
        .onChange((isOn: boolean) => {
          if (this.onToggle) {
            this.onToggle()
          }
        })
    }
    .width('100%')
    .height(48)
    .justifyContent(FlexAlign.SpaceBetween)
    .padding({ left: 16, right: 16 })
    .backgroundColor('#FFFFFF')
  }
}

@Component
struct SectionHeader {
  @Prop title: string = ''

  build() {
    Text(this.title)
      .fontSize(12)
      .fontColor('#999999')
      .width('100%')
      .padding({ left: 16, bottom: 4 })
  }
}

interface QualityOption {
  label: string
  value: number
}

@Component
export struct SettingsPage {
  @State settings: AppSettings = userSettingStore.getSettings()

  // 多值选项：用 TextPickerDialog 选择，防止误触直接切换
  private showQualityPicker(title: string, options: QualityOption[], currentValue: number, onSelect: (value: number) => void): void {
    let labels: string[] = []
    let selectedIndex: number = 0
    for (let i = 0; i < options.length; i++) {
      labels.push(options[i].label)
      if (options[i].value === currentValue) {
        selectedIndex = i
      }
    }
    TextPickerDialog.show({
      range: labels,
      selected: selectedIndex,
      onAccept: (result: TextPickerResult) => {
        let idx: number | number[] = result.index
        let index: number = 0
        if (typeof idx === 'number') {
          index = idx
        }
        if (index >= 0 && index < options.length && options[index].value !== currentValue) {
          onSelect(options[index].value)
        }
      }
    })
  }

  private previewQualityOptions: QualityOption[] = [
    { label: '缩略图', value: 0 },
    { label: '中图', value: 1 },
    { label: '大图', value: 2 }
  ]

  private detailQualityOptions: QualityOption[] = [
    { label: '大图', value: 0 },
    { label: '原图', value: 1 }
  ]

  private illustMangaQualityOptions: QualityOption[] = [
    { label: '中', value: 0 },
    { label: '大', value: 1 },
    { label: '原图', value: 2 }
  ]

  private networkModeOptions: QualityOption[] = [
    { label: '直连', value: 0 },
    { label: '绕过', value: 1 },
    { label: '代理', value: 2 }
  ]

  private refresh(): void {
    this.settings = userSettingStore.getSettings()
  }

  build() {
    List() {
      // ===== 浏览 =====
      ListItem() {
        Column() {
          SectionHeader({ title: '浏览' })
          SettingItem({
            title: '预览图质量',
            value: this.qualityLabel(this.previewQualityOptions, this.settings.previewQuality),
            onItemClick: () => {
              this.showQualityPicker('预览图质量', this.previewQualityOptions, this.settings.previewQuality,
                (v: number) => { userSettingStore.setPreviewQuality(v); this.refresh() })
            }
          })
          SettingItem({
            title: '详情页质量',
            value: this.qualityLabel(this.detailQualityOptions, this.settings.detailQuality),
            onItemClick: () => {
              this.showQualityPicker('详情页质量', this.detailQualityOptions, this.settings.detailQuality,
                (v: number) => { userSettingStore.setDetailQuality(v); this.refresh() })
            }
          })
          SettingItem({
            title: '全屏查看质量',
            value: this.qualityLabel(this.detailQualityOptions, this.settings.fullScreenQuality),
            onItemClick: () => {
              this.showQualityPicker('全屏查看质量', this.detailQualityOptions, this.settings.fullScreenQuality,
                (v: number) => { userSettingStore.setFullScreenQuality(v); this.refresh() })
            }
          })
          SettingItem({
            title: '插画质量',
            value: this.qualityLabel(this.illustMangaQualityOptions, this.settings.pictureQuality),
            onItemClick: () => {
              this.showQualityPicker('插画质量', this.illustMangaQualityOptions, this.settings.pictureQuality,
                (v: number) => { userSettingStore.setPictureQuality(v); this.refresh() })
            }
          })
          SettingItem({
            title: '漫画质量',
            value: this.qualityLabel(this.illustMangaQualityOptions, this.settings.mangaQuality),
            onItemClick: () => {
              this.showQualityPicker('漫画质量', this.illustMangaQualityOptions, this.settings.mangaQuality,
                (v: number) => { userSettingStore.setMangaQuality(v); this.refresh() })
            }
          })
          SettingItem({
            title: '网格列数',
            value: this.settings.crossCount.toString(),
            onItemClick: () => {
              this.showQualityPicker('网格列数',
                [{ label: '2 列', value: 2 }, { label: '3 列', value: 3 }],
                this.settings.crossCount,
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

      // ===== 下载 =====
      ListItem() {
        Column() {
          SectionHeader({ title: '下载' })
          SettingItem({
            title: '下载管理',
            value: '',
            onItemClick: () => {
              router.pushUrl({ url: 'pages/settings/DownloadPage' })
            }
          })
          SettingItem({
            title: '下载图片质量',
            value: this.qualityLabel(this.detailQualityOptions, this.settings.downloadQuality),
            onItemClick: () => {
              this.showQualityPicker('下载图片质量', this.detailQualityOptions, this.settings.downloadQuality,
                (v: number) => { userSettingStore.setDownloadQuality(v); this.refresh() })
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

      // ===== 屏蔽与过滤 =====
      ListItem() {
        Column() {
          SectionHeader({ title: '屏蔽与过滤' })
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

      // ===== 网络 =====
      ListItem() {
        Column() {
          SectionHeader({ title: '网络' })
          SettingItem({
            title: '网络模式',
            value: this.settings.networkMode === 'direct' ? '直连' : this.settings.networkMode === 'bypass' ? '绕过' : '代理',
            onItemClick: () => {
              let currentIdx: number = this.settings.networkMode === 'direct' ? 0 :
                this.settings.networkMode === 'bypass' ? 1 : 2
              this.showQualityPicker('网络模式', this.networkModeOptions, currentIdx,
                (v: number) => {
                  let modes: string[] = ['direct', 'bypass', 'proxy']
                  userSettingStore.setNetworkMode(modes[v])
                  this.refresh()
                })
            }
          })
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })
      }
      .width('100%')

      // ===== 其他 =====
      ListItem() {
        Column() {
          SectionHeader({ title: '其他' })
          SettingItem({
            title: '我的收藏',
            value: '',
            onItemClick: () => {
              router.pushUrl({ url: 'pages/bookmark/BookmarkPage' })
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
                  action: () => { imageCacheService.clearCache() }
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

      // ===== 账户 =====
      ListItem() {
        Column() {
          SectionHeader({ title: '账户' })
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
            this.getUIContext().showAlertDialog({
              title: '退出登录',
              message: '确定要退出当前账号吗？',
              autoCancel: true,
              primaryButton: {
                value: '取消',
                action: () => {}
              },
              secondaryButton: {
                value: '退出',
                action: () => {
                  accountStore.logout()
                  router.replaceUrl({ url: 'pages/login/LoginPage' })
                }
              }
            })
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

  private qualityLabel(options: QualityOption[], currentValue: number): string {
    for (let i = 0; i < options.length; i++) {
      if (options[i].value === currentValue) {
        return options[i].label
      }
    }
    return ''
  }
}
