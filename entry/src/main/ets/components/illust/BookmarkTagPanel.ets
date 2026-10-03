import { apiService } from '../../network/ApiService';
import { BookmarkTag } from '../../models/Bookmark';
import { getStr } from '../../utils/I18nUtils';

/**
 * 带标签收藏内联底部弹层（对齐 pixez 星标长按面板）。
 * 半透明遮罩 + 底部弹层（内层 .onClick(()=>{}) 消费点击防冒泡，不用 hitTestBehavior Block）。
 * 打开时加载用户历史收藏标签（多选 chip 流式排布）+ 公开/私密切换；
 * 加载失败显错误态并允许无标签确认兜底；空标签确认等价普通收藏。
 */
@Component
export struct BookmarkTagPanel {
  @Link @Watch('onVisibleChange') visible: boolean
  onConfirm: (tags: string[], restrict: string) => void = (tags: string[], restrict: string) => {}
  onCancel: () => void = () => {}
  @State tags: BookmarkTag[] = []
  @State selectedTags: string[] = []
  @State restrict: string = 'public'
  @State loading: boolean = false
  @State loadFailed: boolean = false
  @State loadedOnce: boolean = false

  onVisibleChange() {
    if (this.visible) {
      // 每次打开重置选择态并重新加载标签
      this.selectedTags = []
      this.restrict = 'public'
      this.loadTags()
    }
  }

  private async loadTags(): Promise<void> {
    this.loading = true
    this.loadFailed = false
    try {
      let list = await apiService.getBookmarkTags('public')
      let sorted = list.slice()
      sorted.sort((a: BookmarkTag, b: BookmarkTag) => b.count - a.count)
      this.tags = sorted
      this.loadedOnce = true
    } catch (e) {
      console.error('Load bookmark tags failed: ' + e)
      this.loadFailed = true
      this.loadedOnce = true
    } finally {
      this.loading = false
    }
  }

  private toggleTag(name: string): void {
    let idx = this.selectedTags.indexOf(name)
    let next = this.selectedTags.slice()
    if (idx >= 0) {
      next.splice(idx, 1)
    } else {
      next.push(name)
    }
    this.selectedTags = next
  }

  private confirm(): void {
    this.visible = false
    this.onConfirm(this.selectedTags.slice(), this.restrict)
  }

  private cancel(): void {
    this.visible = false
    this.onCancel()
  }

  @Builder
  TagChip(name: string) {
    Text(name)
      .fontSize(13)
      .fontColor(this.selectedTags.indexOf(name) >= 0 ? '#FFFFFF' : '#333333')
      .backgroundColor(this.selectedTags.indexOf(name) >= 0 ? '#0096FA' : '#F0F0F0')
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(16)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => { this.toggleTag(name) })
  }

  build() {
    if (this.visible) {
      Stack({ alignContent: Alignment.Bottom }) {
        // 半透明遮罩：点击关闭
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0, 0, 0, 0.5)')
          .onClick(() => { this.cancel() })

        // 底部弹层：内层消费点击防冒泡关闭
        Column() {
          Text($r('app.string.bookmark_tag_title'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
            .width('100%')
            .padding({ top: 16, bottom: 12 })

          if (this.loading) {
            Row() {
              LoadingProgress()
                .width(20)
                .height(20)
                .color('#0096FA')
              Text($r('app.string.common_loading'))
                .fontSize(12)
                .fontColor('#999999')
                .margin({ left: 8 })
            }
            .width('100%')
            .height(64)
            .justifyContent(FlexAlign.Center)
          } else if (this.loadFailed) {
            Text($r('app.string.bookmark_tag_failed'))
              .fontSize(12)
              .fontColor('#FF4444')
              .width('100%')
              .padding({ top: 8, bottom: 8 })
              .onClick(() => { this.loadTags() })
          } else if (this.tags.length === 0) {
            Text($r('app.string.bookmark_tag_empty'))
              .fontSize(12)
              .fontColor('#999999')
              .width('100%')
              .padding({ top: 8, bottom: 8 })
          } else {
            Scroll() {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.tags, (tag: BookmarkTag) => {
                  this.TagChip(tag.name)
                }, (tag: BookmarkTag) => tag.name)
              }
              .width('100%')
            }
            .width('100%')
            .constraintSize({ maxHeight: 200 })
            .align(Alignment.TopStart)
          }

          // 公开/私密切换
          Row({ space: 12 }) {
            Text($r('app.string.bookmark_tag_public'))
              .fontSize(14)
              .fontColor(this.restrict === 'public' ? '#FFFFFF' : '#333333')
              .backgroundColor(this.restrict === 'public' ? '#0096FA' : '#F0F0F0')
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .borderRadius(18)
              .onClick(() => { this.restrict = 'public' })
            Text($r('app.string.bookmark_tag_private'))
              .fontSize(14)
              .fontColor(this.restrict === 'private' ? '#FFFFFF' : '#333333')
              .backgroundColor(this.restrict === 'private' ? '#0096FA' : '#F0F0F0')
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .borderRadius(18)
              .onClick(() => { this.restrict = 'private' })
          }
          .width('100%')
          .justifyContent(FlexAlign.Start)
          .padding({ top: 12 })

          Row({ space: 16 }) {
            Text($r('app.string.common_cancel'))
              .fontSize(15)
              .fontColor('#999999')
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .padding({ top: 12, bottom: 12 })
              .onClick(() => { this.cancel() })
            Text($r('app.string.common_confirm'))
              .fontSize(15)
              .fontColor('#FFFFFF')
              .backgroundColor('#0096FA')
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .padding({ top: 12, bottom: 12 })
              .borderRadius(22)
              .onClick(() => { this.confirm() })
          }
          .width('100%')
          .padding({ top: 16, bottom: 8 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 16 })
        .backgroundColor('#FFFFFF')
        .borderRadius({ topLeft: 16, topRight: 16 })
        .onClick(() => {})
      }
      .width('100%')
      .height('100%')
    } else {
      Column() {}
      .width(0)
      .height(0)
    }
  }
}
