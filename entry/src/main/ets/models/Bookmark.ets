export interface RawBookmarkTag {
  name?: string
  count?: number
}

export interface RawBookmarkTagListResponse {
  bookmark_tags?: RawBookmarkTag[]
}

export interface BookmarkTagOptions {
  name?: string
  count?: number
}

/** 收藏标签（/v1/user/bookmark-tags/illust 返回元素）：name 原样回传，count 用于排序展示 */
export class BookmarkTag {
  name: string = ''
  count: number = 0

  constructor(options: BookmarkTagOptions = {}) {
    this.name = options.name ?? ''
    this.count = options.count ?? 0
  }
}

export function bookmarkTagFromJson(raw: RawBookmarkTag): BookmarkTag {
  let opts: BookmarkTagOptions = {
    name: raw.name ?? '',
    count: raw.count ?? 0
  }
  return new BookmarkTag(opts)
}

export interface BookmarkOptions {
  id?: number
  workId?: number
  workType?: string
  tags?: string[]
  restrict?: string
  createDate?: string
}

export class Bookmark {
  id: number = 0
  workId: number = 0
  workType: string = ''
  tags: string[] = []
  restrict: string = 'public'
  createDate: string = ''

  constructor(options: BookmarkOptions = {}) {
    this.id = options.id ?? 0
    this.workId = options.workId ?? 0
    this.workType = options.workType ?? ''
    this.tags = options.tags ?? []
    this.restrict = options.restrict ?? 'public'
    this.createDate = options.createDate ?? ''
  }
}
