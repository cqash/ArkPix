export interface ImageUrlsOptions {
  squareMedium?: string
  medium?: string
  large?: string
  original?: string
}

export class ImageUrls {
  squareMedium: string = ''
  medium: string = ''
  large: string = ''
  original: string = ''

  constructor(options?: ImageUrlsOptions) {
    if (options) {
      this.squareMedium = options.squareMedium ?? ''
      this.medium = options.medium ?? ''
      this.large = options.large ?? ''
      this.original = options.original ?? ''
    }
  }
}

export interface MetaPageOptions {
  imageUrls?: ImageUrlsOptions
}

export class MetaPage {
  imageUrls: ImageUrls = new ImageUrls()

  constructor(options?: MetaPageOptions) {
    if (options) {
      this.imageUrls = new ImageUrls(options.imageUrls)
    }
  }
}

export interface TagOptions {
  name?: string
  translatedName?: string
}

export class Tag {
  name: string = ''
  translatedName: string = ''

  constructor(options?: TagOptions) {
    if (options) {
      this.name = options.name ?? ''
      this.translatedName = options.translatedName ?? ''
    }
  }
}

export interface UserPreviewOptions {
  id?: number
  name?: string
  account?: string
  profileImageUrls?: ImageUrlsOptions
}

export class UserPreview {
  id: number = 0
  name: string = ''
  account: string = ''
  profileImageUrls: ImageUrls = new ImageUrls()

  constructor(options?: UserPreviewOptions) {
    if (options) {
      this.id = options.id ?? 0
      this.name = options.name ?? ''
      this.account = options.account ?? ''
      this.profileImageUrls = new ImageUrls(options.profileImageUrls)
    }
  }
}

export interface IllustOptions {
  id?: number
  title?: string
  type?: string
  imageUrls?: ImageUrlsOptions
  metaPages?: MetaPageOptions[]
  user?: UserPreviewOptions
  tags?: TagOptions[]
  tools?: string[]
  createDate?: string
  pageCount?: number
  width?: number
  height?: number
  totalView?: number
  totalBookmarks?: number
  isBookmarked?: boolean
  isMuted?: boolean
  restrict?: string
  xRestrict?: number
  illustAIType?: number
}

export class Illust {
  id: number = 0
  title: string = ''
  type: string = ''
  imageUrls: ImageUrls = new ImageUrls()
  metaPages: MetaPage[] = []
  user: UserPreview = new UserPreview()
  tags: Tag[] = []
  tools: string[] = []
  createDate: string = ''
  pageCount: number = 1
  width: number = 0
  height: number = 0
  totalView: number = 0
  totalBookmarks: number = 0
  isBookmarked: boolean = false
  isMuted: boolean = false
  restrict: string = ''
  xRestrict: number = 0
  illustAIType: number = 0

  constructor(options?: IllustOptions) {
    if (options) {
      this.id = options.id ?? 0
      this.title = options.title ?? ''
      this.type = options.type ?? ''
      this.imageUrls = new ImageUrls(options.imageUrls)
      this.metaPages = (options.metaPages ?? []).map((p: MetaPageOptions) => new MetaPage(p))
      this.user = new UserPreview(options.user)
      this.tags = (options.tags ?? []).map((t: TagOptions) => new Tag(t))
      this.tools = options.tools ?? []
      this.createDate = options.createDate ?? ''
      this.pageCount = options.pageCount ?? 1
      this.width = options.width ?? 0
      this.height = options.height ?? 0
      this.totalView = options.totalView ?? 0
      this.totalBookmarks = options.totalBookmarks ?? 0
      this.isBookmarked = options.isBookmarked ?? false
      this.isMuted = options.isMuted ?? false
      this.restrict = options.restrict ?? ''
      this.xRestrict = options.xRestrict ?? 0
      this.illustAIType = options.illustAIType ?? 0
    }
  }

  get detailUrl(): string {
    return this.imageUrls.large
  }

  get metaPageUrl(): string {
    if (this.metaPages.length > 0) {
      return this.metaPages[0].imageUrls.large
    }
    return this.imageUrls.large
  }
}
