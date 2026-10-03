import { router } from '@kit.ArkUI';
import { Comment } from '../../models/Comment';
import { CommentStore } from '../../stores/CommentStore';
import { CachedImage } from '../../components/common/CachedImage';
import { EmptyView, ErrorView, LoadingView } from '../../components/common/CommonViews';
import { getStr, getStrf } from '../../utils/I18nUtils';
import { HapticUtils } from '../../utils/HapticUtils';

interface RouteParams {
  illustId: number
  illustTitle?: string
  parentCommentId?: number
  replyToName?: string
}

@Entry
@Component
struct CommentPage {
  private store: CommentStore = new CommentStore()
  @State comments: Comment[] = []
  @State isLoading: boolean = false
  @State isLoadingMore: boolean = false
  @State errorMessage: string = ''
  @State illustId: number = 0
  @State illustTitle: string = ''
  @State parentCommentId: number = 0
  @State replyToName: string = ''
  @State inputText: string = ''
  @State replyTarget: Comment | null = null
  @State sending: boolean = false

  private isReplyMode(): boolean {
    return this.parentCommentId > 0
  }

  aboutToAppear() {
    let params = router.getParams() as RouteParams
    if (!params || !params.illustId) {
      this.errorMessage = getStr($r('app.string.comment_param_error'))
      return
    }
    this.illustId = params.illustId
    this.illustTitle = params.illustTitle ?? ''
    this.parentCommentId = params.parentCommentId ?? 0
    this.replyToName = params.replyToName ?? ''
    this.loadInitial()
  }

  private async loadInitial(): Promise<void> {
    this.isLoading = true
    if (this.isReplyMode()) {
      await this.store.loadReplies(this.parentCommentId)
    } else {
      await this.store.loadFirst(this.illustId)
    }
    this.syncFromStore()
  }

  private syncFromStore(): void {
    this.comments = this.store.comments
    this.isLoading = this.store.isLoading
    this.isLoadingMore = this.store.isLoadingMore
    this.errorMessage = this.store.error
  }

  private async loadMore(): Promise<void> {
    await this.store.loadMore()
    this.syncFromStore()
  }

  private startReply(comment: Comment): void {
    this.replyTarget = comment
    this.store.replyTarget = comment
  }

  private cancelReply(): void {
    this.replyTarget = null
    this.store.replyTarget = null
  }

  private replyTargetName(): string {
    let target = this.replyTarget
    if (target !== null) {
      return target.user.name
    }
    return ''
  }

  private async sendComment(): Promise<void> {
    let text = this.inputText.trim()
    if (text.length === 0 || this.sending) {
      return
    }
    this.sending = true
    let ok: boolean = false
    let target = this.replyTarget
    if (target !== null) {
      ok = await this.store.postReply(this.illustId, target.id, text)
    } else {
      ok = await this.store.postComment(this.illustId, text)
    }
    // 失败时不清空输入框，保留用户输入
    if (ok) {
      HapticUtils.medium()
      this.inputText = ''
      this.cancelReply()
      this.syncFromStore()
    }
    this.sending = false
  }

  private openReplies(comment: Comment): void {
    router.pushUrl({
      url: 'pages/detail/CommentPage',
      params: {
        illustId: this.illustId,
        illustTitle: this.illustTitle,
        parentCommentId: comment.id,
        replyToName: comment.user.name
      }
    })
  }

  private formatDate(date: string): string {
    // "2026-07-01T10:00:00+09:00" → "2026-07-01 10:00"
    if (date.length >= 16) {
      return date.substring(0, 16).replace('T', ' ')
    }
    return date
  }

  @Builder
  CommentRow(comment: Comment) {
    Row() {
      if (comment.user.profileImageUrls.medium.length > 0) {
        Stack() {
          CachedImage({ url: comment.user.profileImageUrls.medium, ratio: 1, fit: ImageFit.Cover })
        }
        .width(40)
        .height(40)
        .clip(true)
        .borderRadius(20)
      } else {
        Column()
          .width(40)
          .height(40)
          .borderRadius(20)
          .backgroundColor('#F0F0F0')
      }
      Column() {
        Row() {
          Text(comment.user.name)
            .fontSize(13)
            .fontColor('#0096FA')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(this.formatDate(comment.date))
            .fontSize(11)
            .fontColor('#BBBBBB')
        }
        .width('100%')

        if (comment.replyToUserName.length > 0) {
          Text(getStrf($r('app.string.comment_reply_prefix'), comment.replyToUserName))
            .fontSize(12)
            .fontColor('#999999')
            .margin({ top: 4 })
        }

        Text(comment.comment.length > 0 ? comment.comment :
          (comment.hasStamp ? getStr($r('app.string.comment_stamp')) : ''))
          .fontSize(14)
          .fontColor('#333333')
          .margin({ top: 4 })
          .width('100%')

        Row() {
          Text($r('app.string.comment_reply'))
            .fontSize(12)
            .fontColor('#0096FA')
            .onClick(() => { this.startReply(comment) })
          if (!this.isReplyMode() && comment.hasReplies) {
            Text($r('app.string.comment_view_replies'))
              .fontSize(12)
              .fontColor('#0096FA')
              .margin({ left: 16 })
              .onClick(() => { this.openReplies(comment) })
          }
        }
        .width('100%')
        .margin({ top: 6 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 10 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Top)
    .backgroundColor('#FFFFFF')
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text($r('app.string.common_back_arrow'))
          .fontSize(16)
          .fontColor('#0096FA')
          .onClick(() => {
            router.back()
          })
        Text(this.isReplyMode() ? $r('app.string.comment_reply_list') : $r('app.string.comment_title'))
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

      if (this.isReplyMode() && this.replyToName.length > 0) {
        Text(getStrf($r('app.string.comment_reply_to_comment'), this.replyToName))
          .fontSize(12)
          .fontColor('#999999')
          .width('100%')
          .padding({ left: 16, top: 6, bottom: 6 })
          .backgroundColor('#F5F5F5')
      }

      // 评论列表区
      if (this.errorMessage && this.comments.length === 0) {
        ErrorView({ message: this.errorMessage, onRetry: () => { this.loadInitial() } })
          .layoutWeight(1)
      } else if (this.isLoading && this.comments.length === 0) {
        LoadingView()
          .layoutWeight(1)
      } else if (this.comments.length === 0) {
        EmptyView({ message: getStr($r('app.string.comment_empty')) })
          .layoutWeight(1)
      } else {
        List() {
          ForEach(this.comments, (comment: Comment) => {
            ListItem() {
              this.CommentRow(comment)
            }
          }, (comment: Comment) => comment.id.toString())
          if (this.isLoadingMore) {
            ListItem() {
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
              .height(44)
              .justifyContent(FlexAlign.Center)
            }
          }
        }
        .width('100%')
        .layoutWeight(1)
        .onReachEnd(() => { this.loadMore() })
      }

      // 底部输入栏
      if (this.replyTarget !== null) {
        Row() {
          Text(getStrf($r('app.string.comment_reply_prefix'), this.replyTargetName()))
            .fontSize(12)
            .fontColor('#0096FA')
            .layoutWeight(1)
          Text($r('app.string.comment_cancel_reply'))
            .fontSize(12)
            .fontColor('#999999')
            .onClick(() => { this.cancelReply() })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 6, bottom: 6 })
        .backgroundColor('#F5F5F5')
      }
      Row() {
        TextInput({
          placeholder: this.replyTarget !== null ? $r('app.string.comment_placeholder_reply') :
            $r('app.string.comment_placeholder'),
          text: $$this.inputText
        })
          .layoutWeight(1)
          .height(40)
          .maxLength(140)
          .backgroundColor('#F5F5F5')
          .borderRadius(20)
          .padding({ left: 16, right: 16 })
          .onSubmit(() => { this.sendComment() })
        Button(this.sending ? $r('app.string.comment_sending') : $r('app.string.comment_send'))
          .height(40)
          .fontSize(14)
          .backgroundColor('#0096FA')
          .margin({ left: 8 })
          .enabled(!this.sending && this.inputText.trim().length > 0)
          .onClick(() => { this.sendComment() })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor('#FFFFFF')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
