import { router } from '@kit.ArkUI';
import { userSettingStore } from '../../stores/UserSettingStore';
import { ExifTag } from '../../services/ImageExifService';

const DEFAULT_TEMPLATE = 'PID:{illust_id} | {tags}'
const SAMPLE_ILLUST_ID = 12345678
const SAMPLE_USER_ID = 87654321
const SAMPLE_USER_NAME = 'サンプルユーザー'
const SAMPLE_TITLE = 'サンプルイラスト'
const SAMPLE_TAGS: ExifTag[] = [
  { name: 'オリジナル', translatedName: '原创' },
  { name: '女の子', translatedName: '女孩子' },
  { name: 'clipstudiopaint', translatedName: '' }
]

function buildPreviewComment(template: string): string {
  let tagsOriginal = SAMPLE_TAGS.map((t: ExifTag) => t.name).join(', ')
  let tagsTranslated = SAMPLE_TAGS.map((t: ExifTag) => {
    if (t.translatedName && t.translatedName !== t.name) {
      return `${t.name} (${t.translatedName})`
    }
    return t.name
  }).join(', ')
  // {tags_translated} 必须先于 {tags} 替换（前缀包含关系）
  return template
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
        Button('返回')
          .fontSize(12)
          .height(32)
          .backgroundColor('#0096FA')
          .onClick(() => { router.back() })
        Text('备注模板')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Button('保存')
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
        Text('预览')
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
        Text('模板')
          .fontSize(12)
          .fontColor('#999999')
          .width('100%')
          .margin({ bottom: 8 })
        TextInput({ placeholder: '例如: PID:{illust_id} | {tags}', text: this.template })
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
        Text('插入变量')
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
        }
        .width('100%')
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .margin({ top: 8 })

      Column() {
        Text('可用变量')
          .fontSize(12)
          .fontColor('#999999')
          .width('100%')
          .margin({ bottom: 8 })
        Text('{illust_id}  作品ID')
          .fontSize(12)
          .fontColor('#666666')
          .width('100%')
          .margin({ bottom: 4 })
        Text('{user_id}  作者用户ID')
          .fontSize(12)
          .fontColor('#666666')
          .width('100%')
          .margin({ bottom: 4 })
        Text('{user_name}  作者名')
          .fontSize(12)
          .fontColor('#666666')
          .width('100%')
          .margin({ bottom: 4 })
        Text('{title}  作品标题')
          .fontSize(12)
          .fontColor('#666666')
          .width('100%')
          .margin({ bottom: 4 })
        Text('{part}  页码（从0开始）')
          .fontSize(12)
          .fontColor('#666666')
          .width('100%')
          .margin({ bottom: 4 })
        Text('{tags}  标签（仅原文，如: オリジナル, 女の子）')
          .fontSize(12)
          .fontColor('#666666')
          .width('100%')
          .margin({ bottom: 4 })
        Text('{tags_translated}  标签（带翻译，如: オリジナル (原创), 女の子 (女孩子)；无翻译时仅显示原文）')
          .fontSize(12)
          .fontColor('#666666')
          .width('100%')
          .margin({ bottom: 4 })
        Text('备注内容过长时会按容量自动截断；未定义的 {变量} 会原样保留。')
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
