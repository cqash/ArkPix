import { router } from '@kit.ArkUI';
import { userSettingStore } from '../../stores/UserSettingStore';
import { AppSettings } from '../../models/AppSettings';
import { getStrf } from '../../utils/I18nUtils';

@Entry
@Component
struct MutePage {
  @State settings: AppSettings = userSettingStore.getSettings()
  @State newMuteTag: string = ''

  addMuteTag(): void {
    let tag = this.newMuteTag.trim()
    if (!tag) {
      return
    }
    userSettingStore.addMuteTag(tag)
    this.newMuteTag = ''
    this.settings = userSettingStore.getSettings()
  }

  removeMuteTag(tag: string): void {
    userSettingStore.removeMuteTag(tag)
    this.settings = userSettingStore.getSettings()
  }

  removeMuteUser(userId: number): void {
    userSettingStore.removeMuteUser(userId)
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
        Text($r('app.string.settings_mute_manager'))
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

      List() {
        // 屏蔽词
        ListItem() {
          Column() {
            Text($r('app.string.mute_tags_section'))
              .fontSize(12)
              .fontColor('#999999')
              .width('100%')
              .padding({ left: 16, bottom: 4 })

            Row() {
              TextInput({ placeholder: $r('app.string.mute_tag_placeholder'), text: $$this.newMuteTag })
                .height(40)
                .layoutWeight(1)
                .backgroundColor('#FFFFFF')
                .onSubmit(() => { this.addMuteTag() })
              Button($r('app.string.common_add'))
                .height(40)
                .backgroundColor('#0096FA')
                .margin({ left: 8 })
                .onClick(() => { this.addMuteTag() })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .backgroundColor('#FFFFFF')

            if (this.settings.muteTags.length === 0) {
              Text($r('app.string.mute_no_tags'))
                .fontSize(13)
                .fontColor('#CCCCCC')
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: 16, bottom: 16 })
            }

            ForEach(this.settings.muteTags, (tag: string) => {
              Row() {
                Text(tag)
                  .fontSize(14)
                  .fontColor('#333333')
                  .layoutWeight(1)
                Text($r('app.string.common_delete'))
                  .fontSize(12)
                  .fontColor('#FF4444')
                  .onClick(() => { this.removeMuteTag(tag) })
              }
              .width('100%')
              .height(44)
              .padding({ left: 16, right: 16 })
              .backgroundColor('#FFFFFF')
            }, (tag: string) => tag)
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
        }

        // 屏蔽作者
        ListItem() {
          Column() {
            Text($r('app.string.mute_users_section'))
              .fontSize(12)
              .fontColor('#999999')
              .width('100%')
              .padding({ left: 16, bottom: 4 })

            if (this.settings.muteUsers.length === 0) {
              Text($r('app.string.mute_no_users'))
                .fontSize(13)
                .fontColor('#CCCCCC')
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: 16, bottom: 16 })
                .backgroundColor('#FFFFFF')
            }

            ForEach(this.settings.muteUsers, (userId: number) => {
              Row() {
                Text(getStrf($r('app.string.mute_user_id'), userId))
                  .fontSize(14)
                  .fontColor('#333333')
                  .layoutWeight(1)
                Text($r('app.string.common_delete'))
                  .fontSize(12)
                  .fontColor('#FF4444')
                  .onClick(() => { this.removeMuteUser(userId) })
              }
              .width('100%')
              .height(44)
              .padding({ left: 16, right: 16 })
              .backgroundColor('#FFFFFF')
            }, (userId: number) => userId.toString())
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
        }
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
