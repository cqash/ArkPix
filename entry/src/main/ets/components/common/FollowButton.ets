import { promptAction } from '@kit.ArkUI';
import { apiService } from '../../network/ApiService';
import { HapticUtils } from '../../utils/HapticUtils';

/**
 * 三态关注按钮（对齐 pixez）：
 *  - 未关注=实心主题色胶囊（#0096FA）
 *  - 已关注=描边胶囊（白底 + 主题色描边/文字）
 *  - 请求中=按钮原地 12px 小菊花（容器尺寸不变，不引发布局跳动）
 * 单击=快速公开关注/取关；长按=heavy 震动 + bindContextMenu 精细关注（公开关注/悄悄关注/取消关注，按当前态显隐）。
 * 组件无状态：关注态由宿主注入（isFollowed）并经 onChanged 回调回报。
 */
@Component
export struct FollowButton {
  @Prop userId: number = 0
  @Prop isFollowed: boolean = false
  onChanged: (newState: boolean) => void = (newState: boolean) => {}
  @State requesting: boolean = false
  @State menuShown: boolean = false

  private showToast(message: Resource): void {
    try {
      promptAction.showToast({ message: message })
    } catch (e) {
      console.error('Toast failed: ' + e)
    }
  }

  private async doFollow(restrict: string): Promise<void> {
    if (this.requesting || this.userId <= 0) {
      return
    }
    this.requesting = true
    try {
      await apiService.followUser(this.userId, restrict)
      HapticUtils.medium()
      this.onChanged(true)
      this.showToast($r('app.string.user_followed'))
    } catch (e) {
      console.error('Follow failed: ' + e)
      this.showToast($r('app.string.user_follow_failed'))
    } finally {
      this.requesting = false
    }
  }

  private async doUnfollow(): Promise<void> {
    if (this.requesting || this.userId <= 0) {
      return
    }
    this.requesting = true
    try {
      await apiService.unfollowUser(this.userId)
      HapticUtils.light()
      this.onChanged(false)
      this.showToast($r('app.string.user_unfollowed'))
    } catch (e) {
      console.error('Unfollow failed: ' + e)
      this.showToast($r('app.string.user_unfollow_failed'))
    } finally {
      this.requesting = false
    }
  }

  private handleClick(): void {
    if (this.requesting) {
      return
    }
    if (this.isFollowed) {
      this.doUnfollow()
    } else {
      this.doFollow('public')
    }
  }

  @Builder
  MenuBuilder() {
    Column() {
      if (!this.isFollowed) {
        Text($r('app.string.user_follow_public'))
          .fontSize(14)
          .fontColor('#333333')
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .onClick(() => {
            this.menuShown = false
            setTimeout(() => { this.doFollow('public') }, 300)
          })
        Text($r('app.string.user_follow_private'))
          .fontSize(14)
          .fontColor('#333333')
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .onClick(() => {
            this.menuShown = false
            setTimeout(() => { this.doFollow('private') }, 300)
          })
      } else {
        Text($r('app.string.user_unfollow_action'))
          .fontSize(14)
          .fontColor('#333333')
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .onClick(() => {
            this.menuShown = false
            setTimeout(() => { this.doUnfollow() }, 300)
          })
      }
    }
    .width(140)
    .padding({ top: 4, bottom: 4 })
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.requesting) {
        // 请求中：原地小菊花，容器尺寸不变防布局跳动
        LoadingProgress()
          .width(12)
          .height(12)
          .color(this.isFollowed ? '#0096FA' : '#FFFFFF')
      } else {
        Text(this.isFollowed ? $r('app.string.user_followed_btn') : $r('app.string.user_follow'))
          .fontSize(13)
          .fontColor(this.isFollowed ? '#0096FA' : '#FFFFFF')
          .maxLines(1)
      }
    }
    .width(96)
    .height(32)
    .borderRadius(16)
    .backgroundColor(this.isFollowed ? '#FFFFFF' : '#0096FA')
    .border({ width: this.isFollowed ? 1 : 0, color: '#0096FA' })
    .onClick(() => { this.handleClick() })
    .gesture(
      LongPressGesture({ fingers: 1, duration: 500 })
        .onAction(() => {
          if (!this.requesting) {
            HapticUtils.heavy()
            this.menuShown = true
          }
        })
    )
    .bindContextMenu(this.menuShown, this.MenuBuilder, {
      onDisappear: () => { this.menuShown = false }
    })
  }
}
