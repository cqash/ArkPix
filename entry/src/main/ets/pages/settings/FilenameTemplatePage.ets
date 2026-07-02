import { router } from '@kit.ArkUI';
import { userSettingStore } from '../../stores/UserSettingStore';

const SAMPLE_ILLUST_ID = 12345678
const SAMPLE_USER_ID = 87654321
const SAMPLE_USER_NAME = 'サンプルユーザー'
const SAMPLE_TITLE = 'サンプルイラスト'
const FILENAME_ILLEGAL_CHARS = /[\\/:*?"<>|]/g

function buildPreviewFilename(template: string): string {
  let result = template
    .replaceAll('{illust_id}', SAMPLE_ILLUST_ID.toString())
    .replaceAll('{user_id}', SAMPLE_USER_ID.toString())
    .replaceAll('{part}', '0')
    .replaceAll('{user_name}', SAMPLE_USER_NAME)
    .replaceAll('{title}', SAMPLE_TITLE)
  let safe = result.replace(FILENAME_ILLEGAL_CHARS, '_')
  return safe + '.jpg'
}

@Entry
@Component
struct FilenameTemplatePage {
  @State template: string = userSettingStore.getSettings().filenameTemplate

  private insertToken(token: string): void {
    this.template = this.template + token
  }

  private saveAndBack(): void {
    let value = this.template.trim()
    if (value.length === 0) {
      value = '{illust_id}_p{part}'
    }
    userSettingStore.setFilenameTemplate(value)
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
        Text('文件名模板')
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
        Text(buildPreviewFilename(this.template))
          .fontSize(14)
          .fontColor('#333333')
          .width('100%')
          .margin({ top: 4 })
          .maxLines(2)
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
        TextInput({ placeholder: '例如: {illust_id}_p{part}', text: this.template })
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
          this.TokenButton('{part}')
          this.TokenButton('{user_name}')
          this.TokenButton('{title}')
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
        Text('{part}  页码（从0开始）')
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
        Text('扩展名会自动添加；\\ / : * ? " < > | 等字符会被替换为下划线。')
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
