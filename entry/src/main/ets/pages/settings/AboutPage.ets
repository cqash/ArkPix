import { router } from '@kit.ArkUI';
import { getStr } from '../../utils/I18nUtils';

@Entry
@Component
struct AboutPage {
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
        Text($r('app.string.about_title'))
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
          // 应用图标与名称
          Column() {
            Text('ArkPix')
              .fontSize(36)
              .fontWeight(FontWeight.Bold)
              .fontColor('#0096FA')
            Text($r('app.string.about_tagline'))
              .fontSize(14)
              .fontColor('#999999')
              .margin({ top: 8 })
            Text('v1.0.0')
              .fontSize(12)
              .fontColor('#CCCCCC')
              .margin({ top: 4 })
          }
          .width('100%')
          .padding({ top: 40, bottom: 32 })
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)

          // 项目信息
          Column() {
            Text($r('app.string.about_section_project'))
              .fontSize(12)
              .fontColor('#999999')
              .width('100%')
              .padding({ left: 16, bottom: 4 })

            this.InfoItem(getStr($r('app.string.about_app_name')), 'ArkPix')
            this.InfoItem(getStr($r('app.string.about_version_label')), '1.0.0 (1000000)')
            this.InfoItem(getStr($r('app.string.about_based_on')), getStr($r('app.string.about_based_on_value')))
            this.InfoItem(getStr($r('app.string.about_framework')), 'HarmonyOS ArkTS')
            this.InfoItem('SDK', 'API 12+ / SDK 6.1.0')
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })

          // 开源与致谢
          Column() {
            Text($r('app.string.about_section_thanks'))
              .fontSize(12)
              .fontColor('#999999')
              .width('100%')
              .padding({ left: 16, bottom: 4 })

            this.InfoItem('PixEz', getStr($r('app.string.about_pixez_value')))
            this.InfoItem('Pixiv', getStr($r('app.string.about_pixiv_value')))
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })

          // 免责声明
          Column() {
            Text($r('app.string.about_section_disclaimer'))
              .fontSize(12)
              .fontColor('#999999')
              .width('100%')
              .padding({ left: 16, bottom: 4 })

            Column() {
              Text($r('app.string.about_disclaimer_text'))
                .fontSize(13)
                .fontColor('#666666')
                .lineHeight(20)
            }
            .width('100%')
            .padding(16)
            .backgroundColor('#FFFFFF')
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })

          // 底部版权
          Column() {
            Text('© 2025 ArkPix')
              .fontSize(12)
              .fontColor('#CCCCCC')
            Text('Made with ArkTS')
              .fontSize(11)
              .fontColor('#DDDDDD')
              .margin({ top: 4 })
          }
          .width('100%')
          .padding({ top: 32, bottom: 32 })
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
      }
      .layoutWeight(1)
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }

  @Builder
  InfoItem(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor('#333333')
      Text(value)
        .fontSize(14)
        .fontColor('#999999')
    }
    .width('100%')
    .height(48)
    .justifyContent(FlexAlign.SpaceBetween)
    .padding({ left: 16, right: 16 })
    .backgroundColor('#FFFFFF')
  }
}
