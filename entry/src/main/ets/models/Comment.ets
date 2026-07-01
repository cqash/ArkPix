import { UserPreview } from './User'

export class Comment {
  id: number = 0
  parentCommentId: number = 0
  user: UserPreview = new UserPreview()
  comment: string = ''
  date: string = ''

  constructor(options: Partial<Comment> = {}) {
    this.id = options.id ?? 0
    this.parentCommentId = options.parentCommentId ?? 0
    this.user = new UserPreview(options.user)
    this.comment = options.comment ?? ''
    this.date = options.date ?? ''
  }
}
