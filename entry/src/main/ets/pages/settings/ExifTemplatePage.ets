import { router } from '@kit.ArkUI';
import { userSettingStore } from '../../stores/UserSettingStore';
import { ExifTag } from '../../services/ImageExifService';
import { Constants } from '../../utils/Constants';
import { getStr } from '../../utils/I18nUtils';

const DEFAULT_TEMPLATE = 'PID:{illust_id} | {tags}'
const SAMPLE_ILLUST_ID = 12345678
const SAMPLE_USER_ID = 87654321
const SAMPLE_USER_NAME = 'サンプルユーザー'
const SAMPLE_TITLE = 'サンプルイラスト'

function buildSampleTags(): ExifTag[] {
  let t1: ExifTag = { name: 'オリジナル', translatedName: getStr($r('app.string.exif_sample_tag_original')) }
  let t2: ExifTag = { name: '女の子', translatedName: getStr($r('app.string.exif_sample_tag_girl')) }
  let t3: ExifTag = { name: 'clipstudiopaint', translatedName: '' }
  return [t1, t2, t3]
}

function buildPreviewComment(template: string): string {
  let sampleTags = buildSampleTags()
  let tagsOriginal = sampleTags.map((t: ExifTag) => t.name).join(', ')
  let tagsLocalized = sampleTags.map((t: ExifTag) => {
    let displayTranslation = Constants.filterTranslatedName(t.name, t.translatedName)
    if (displayTranslation.length > 0) {
      return displayTranslation
    }
    return t.name
  }).join(', ')
  let tagsTranslated = sampleTags.map((t: ExifTag) => {
    let displayTranslation = Constants.filterTranslatedName(t.name, t.translatedName)
    if (displayTranslation.length > 0) {
      return `${t.name} (${displayTranslation})`
    }
    return t.name
  }).join(', ')
  // {tags_localized} → {tags_translated} → {tags} 替换（前缀包含关系，最长先替换）
  return template
    .replaceAll('{tags_localized}', tagsLocalized)
    .replaceAll('{tags_translated}', tagsTranslated)
    .replaceAll('{tags}', tagsOriginal)
    .replaceAll('{illust_id}', SAMPLE_ILLUST_ID.toString())
    .replaceAll('{user_id}', SAMPLE_USER_ID.toString())
    .replaceAll('{user_name}', SAMPLE_USER_NAME)
    .replaceAll('{title}', SAMPLE_TITLE)
    .replaceAll('{part}', '0')
}

@Entry
@Component
struct ExifTemplatePage {
  @State template: string = userSettingStore.getSettings().exifCommentTemplate

  private insertToken(token: string): void {
    this.template = this.template + token
  }

  private saveAndBack(): void {
    let value = this.template.trim()
    if (value.length === 0) {
      value = DEFAULT_TEMPLATE
    }
    userSettingStore.setExifCommentTemplate(value)
    router.back()
  }

  @Builder
  TokenButton(token: string) {
    Button(token)
      .fontSize(12)
      .height(32)
      .margin({ right: 8, bottom: 8 })
      .backgroundColor('#E6F4FF')
      .fontColor('#0096FA')
      .onClick(() => { this.insertToken(token) })
  }

  build() {
    Column() {
      Row() {
        Button($r('app.string.common_back'))
          .fontSize(12)
          .height(32)
          .backgroundColor('#0096FA')
          .onClick(() => { router.back() })
        Text($r('app.string.exif_template_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Button($r('app.string.common_save'))
          .fontSize(12)
          .height(32)
          .backgroundColor('#0096FA')
          .onClick(() => { this.saveAndBack() })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .justifyContent(FlexAlign.SpaceBetween)
      .backgroundColor('#FFFFFF')

      Column() {
        Text($r('app.string.exif_preview'))
          .fontSize(12)
          .fontColor('#999999')
          .width('100%')
        Text(buildPreviewComment(this.template))
          .fontSize(14)
          .fontColor('#333333')
          .width('100%')
          .margin({ top: 4 })
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .margin({ top: 8 })

      Column() {
        Text($r('app.string.exif_template_label'))
          .fontSize(12)
          .fontColor('#999999')
          .width('100%')
          .margin({ bottom: 8 })
        TextInput({ placeholder: $r('app.string.exif_template_placeholder'), text: this.template })
          .width('100%')
          .height(48)
          .backgroundColor('#F5F5F5')
          .onChange((value: string) => {
            this.template = value
          })
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .margin({ top: 8 })

      Column() {
        Text($r('app.string.exif_insert_var'))
          .fontSize(12)
          .fontColor('#999999')
          .width('100%')
          .margin({ bottom: 8 })
        Flex({ wrap: FlexWrap.Wrap }) {
          this.TokenButton('{illust_id}')
          this.TokenButton('{user_id}')
          this.TokenButton('{user_name}')
          this.TokenButton('{title}')
          this.TokenButton('{part}')
          this.TokenButton('{tags}')
          this.TokenButton('{tags_translated}')
          this.TokenButton('{tags_localized}')
        }
        .width('100%')
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .margin({ top: 8 })

      Column() {
        Text($r('app.string.exif_available_vars'))
          .fontSize(12)
          .fontColor('#999999')
          .width('100%')
          .margin({ bottom: 8 })
        Text($r('app.string.exif_var_illust_id'))
          .fontSize(12)
          .fontColor('#666666')
          .width('100%')
          .margin({ bottom: 4 })
        Text($r('app.string.exif_var_user_id'))
          .fontSize(12)
          .fontColor('#666666')
          .width('100%')
          .margin({ bottom: 4 })
        Text($r('app.string.exif_var_user_name'))
          .fontSize(12)
          .fontColor('#666666')
          .width('100%')
          .margin({ bottom: 4 })
        Text($r('app.string.exif_var_title'))
          .fontSize(12)
          .fontColor('#666666')
          .width('100%')
          .margin({ bottom: 4 })
        Text($r('app.string.exif_var_part'))
          .fontSize(12)
          .fontColor('#666666')
          .width('100%')
          .margin({ bottom: 4 })
        Text($r('app.string.exif_var_tags'))
          .fontSize(12)
          .fontColor('#666666')
          .width('100%')
          .margin({ bottom: 4 })
        Text($r('app.string.exif_var_tags_translated'))
          .fontSize(12)
          .fontColor('#666666')
          .width('100%')
          .margin({ bottom: 4 })
        Text($r('app.string.exif_var_tags_localized'))
          .fontSize(12)
          .fontColor('#666666')
          .width('100%')
          .margin({ bottom: 4 })
        Text($r('app.string.exif_var_note'))
          .fontSize(11)
          .fontColor('#999999')
          .width('100%')
          .margin({ top: 8 })
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
    .alignItems(HorizontalAlign.Start)
  }
}
