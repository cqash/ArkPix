import { promptAction } from '@kit.ArkUI';
import { apiService } from '../network/ApiService';
import { Comment, commentFromJson, parseCommentListPage } from '../models/Comment';
import { getStr, getStrf } from '../utils/I18nUtils';

interface RawCommentAddResponse {
  comment?: Object
}

/**
 * 评论页数据编排（非单例，页面持有，同 IllustDetailStore 模式）：
 * 主楼列表（/v3）与回复楼（/v2 replies）双模式，游标分页，发表/回复。
 */
export class CommentStore {
  comments: Comment[] = []
  isLoading: boolean = false
  isLoadingMore: boolean = false
  nextUrl: string = ''
  error: string = ''
  /** 回复楼模式（loadReplies 后 true） */
  isReplyMode: boolean = false
  /** 回复目标（输入框指向的评论），null 表示发表顶层评论 */
  replyTarget: Comment | null = null
  private parentCommentId: number = 0

  private async loadPage(loader: () => Promise<Object>): Promise<void> {
    this.isLoading = true
    this.error = ''
    try {
      let response = await loader()
      let page = parseCommentListPage(response)
      this.comments = page.comments
      this.nextUrl = page.nextUrl
    } catch (e) {
      this.error = getStrf($r('app.string.common_load_failed_detail'), String(e))
      console.error('Load comments failed: ' + e)
    } finally {
      this.isLoading = false
    }
  }

  /** 主楼模式：加载作品评论首屏（/v3/illust/comments） */
  async loadFirst(illustId: number): Promise<void> {
    this.isReplyMode = false
    await this.loadPage((): Promise<Object> => apiService.getIllustComments(illustId))
  }

  /** 回复楼模式：加载某评论的回复首屏（/v2/illust/comment/replies） */
  async loadReplies(commentId: number): Promise<void> {
    this.isReplyMode = true
    this.parentCommentId = commentId
    await this.loadPage((): Promise<Object> => apiService.getIllustCommentReplies(commentId))
  }

  /** 游标分页加载下一页（主楼与回复楼同构） */
  async loadMore(): Promise<void> {
    if (this.isLoading || this.isLoadingMore || this.nextUrl.length === 0) {
      return
    }
    this.isLoadingMore = true
    try {
      let response = await apiService.fetchNext(this.nextUrl)
      let page = parseCommentListPage(response)
      let fresh: Comment[] = []
      for (let i = 0; i < page.comments.length; i++) {
        let exists = false
        for (let j = 0; j < this.comments.length; j++) {
          if (this.comments[j].id === page.comments[i].id) {
            exists = true
            break
          }
        }
        if (!exists) {
          fresh.push(page.comments[i])
        }
      }
      this.comments = this.comments.concat(fresh)
      this.nextUrl = page.nextUrl
    } catch (e) {
      console.error('Load more comments failed: ' + e)
    } finally {
      this.isLoadingMore = false
    }
  }

  /** 发表顶层评论；成功后插入列表头部，失败 toast 且返回 false（输入内容由页面保留） */
  async postComment(illustId: number, text: string): Promise<boolean> {
    try {
      let response = await apiService.addIllustComment(illustId, text)
      let raw = response as RawCommentAddResponse
      if (raw.comment) {
        let added = commentFromJson(raw.comment)
        this.comments = [added].concat(this.comments)
      }
      promptAction.showToast({ message: getStr($r('app.string.store_comment_posted')) })
      return true
    } catch (e) {
      console.error('Post comment failed: ' + e)
      // 透传含响应体的错误信息（ApiService.ensureSuccess 已附加截断响应体）
      let detail = e instanceof Error ? e.message : String(e)
      promptAction.showToast({ message: getStrf($r('app.string.store_comment_post_failed'), detail) })
      return false
    }
  }

  /** 回复指定评论；回复楼模式下成功追加到列表尾部，主楼模式仅提示 */
  async postReply(illustId: number, parentCommentId: number, text: string): Promise<boolean> {
    try {
      let response = await apiService.addIllustComment(illustId, text, parentCommentId)
      let raw = response as RawCommentAddResponse
      if (raw.comment) {
        let added = commentFromJson(raw.comment)
        if (this.isReplyMode) {
          this.comments = this.comments.concat([added])
        }
      }
      promptAction.showToast({ message: getStr($r('app.string.store_reply_posted')) })
      return true
    } catch (e) {
      console.error('Post reply failed: ' + e)
      let detail = e instanceof Error ? e.message : String(e)
      promptAction.showToast({ message: getStrf($r('app.string.store_reply_failed'), detail) })
      return false
    }
  }
}
