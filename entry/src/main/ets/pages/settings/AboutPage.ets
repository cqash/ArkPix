import { router } from '@kit.ArkUI';

@Entry
@Component
struct AboutPage {
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
        Text('关于')
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
            Text('Pixiv 第三方客户端 · HarmonyOS 版')
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
            Text('项目信息')
              .fontSize(12)
              .fontColor('#999999')
              .width('100%')
              .padding({ left: 16, bottom: 4 })

            this.InfoItem('应用名称', 'ArkPix')
            this.InfoItem('版本号', '1.0.0 (1000000)')
            this.InfoItem('基于', 'PixEz 开源项目')
            this.InfoItem('框架', 'HarmonyOS ArkTS')
            this.InfoItem('SDK', 'API 12+ / SDK 6.1.0')
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })

          // 开源与致谢
          Column() {
            Text('致谢')
              .fontSize(12)
              .fontColor('#999999')
              .width('100%')
              .padding({ left: 16, bottom: 4 })

            this.InfoItem('PixEz', 'Flutter 版 Pixiv 客户端')
            this.InfoItem('Pixiv', '插画交流平台')
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })

          // 免责声明
          Column() {
            Text('声明')
              .fontSize(12)
              .fontColor('#999999')
              .width('100%')
              .padding({ left: 16, bottom: 4 })

            Column() {
              Text('ArkPix 为 Pixiv 第三方客户端，与 Pixiv Inc. 无任何关联。所有插画版权归原创作者所有，仅供个人学习交流使用。')
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
