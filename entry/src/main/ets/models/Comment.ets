import { UserPreview, UserPreviewOptions } from './Illust'

export interface CommentOptions {
  id?: number
  parentCommentId?: number
  user?: UserPreviewOptions
  comment?: string
  date?: string
  replyToUserName?: string
  hasReplies?: boolean
  hasStamp?: boolean
}

interface RawCommentUser {
  id: number
  name: string
}

interface RawParentComment {
  id: number
  user: RawCommentUser
}

interface RawComment {
  id: number
  comment: string
  date: string
  user: Object
  parent_comment: RawParentComment
  has_replies: boolean
  stamp: Object
}

export class Comment {
  id: number = 0
  parentCommentId: number = 0
  user: UserPreview = new UserPreview()
  comment: string = ''
  date: string = ''
  /** 回复目标用户名（回复楼条目"回复 @某人"前缀来源），顶层评论为空串 */
  replyToUserName: string = ''
  /** 该评论是否有回复（/v3 响应 has_replies） */
  hasReplies: boolean = false
  /** 是否为贴图评论（comment 为空且含 stamp 字段，界面显示"[贴图]"） */
  hasStamp: boolean = false

  constructor(options?: CommentOptions) {
    if (options) {
      this.id = options.id ?? 0
      this.parentCommentId = options.parentCommentId ?? 0
      this.user = new UserPreview(options.user)
      this.comment = options.comment ?? ''
      this.date = options.date ?? ''
      this.replyToUserName = options.replyToUserName ?? ''
      this.hasReplies = options.hasReplies ?? false
      this.hasStamp = options.hasStamp ?? false
    }
  }
}

/** 解析单条评论（顶层与回复楼同构）；parent_comment.user.name → replyToUserName */
export function commentFromJson(raw: Object): Comment {
  let p = raw as RawComment
  let parentId = 0
  let replyTo = ''
  if (p?.parent_comment && p.parent_comment.id) {
    parentId = p.parent_comment.id
    if (p.parent_comment.user) {
      replyTo = p.parent_comment.user.name ?? ''
    }
  }
  let opts: CommentOptions = {
    id: p?.id ?? 0,
    parentCommentId: parentId,
    user: p?.user ? UserPreview.fromJson(p.user) : undefined,
    comment: p?.comment ?? '',
    date: p?.date ?? '',
    replyToUserName: replyTo,
    hasReplies: p?.has_replies ?? false,
    hasStamp: p?.stamp !== undefined && p?.stamp !== null
  }
  return new Comment(opts)
}

interface RawCommentListResponse {
  comments?: Object[]
  next_url?: string
}

export interface CommentListPage {
  comments: Comment[]
  nextUrl: string
}

/** 解析评论列表接口统一结构（comments + next_url），顶层与回复楼同构 */
export function parseCommentListPage(response: Object): CommentListPage {
  let raw = response as RawCommentListResponse
  let comments = (raw.comments ?? []).map((item: Object) => commentFromJson(item))
  let page: CommentListPage = { comments: comments, nextUrl: raw.next_url ?? '' }
  return page
}
