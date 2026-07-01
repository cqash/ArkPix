export interface ImageUrlsOptions {
  squareMedium?: string
  medium?: string
  large?: string
  original?: string
}

interface RawImageUrls {
  square_medium: string
  medium: string
  large: string
  original: string
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

  static fromJson(json: RawImageUrls): ImageUrlsOptions {
    let p = json
    let opts: ImageUrlsOptions = {
      squareMedium: p.square_medium,
      medium: p.medium,
      large: p.large,
      original: p.original
    }
    return opts
  }
}

export interface MetaPageOptions {
  imageUrls?: ImageUrlsOptions
}

interface RawMetaPage {
  image_urls: RawImageUrls
}

export class MetaPage {
  imageUrls: ImageUrls = new ImageUrls()

  constructor(options?: MetaPageOptions) {
    if (options) {
      this.imageUrls = new ImageUrls(options.imageUrls)
    }
  }

  static fromJson(json: RawMetaPage): MetaPageOptions {
    let p = json
    let opts: MetaPageOptions = {
      imageUrls: ImageUrls.fromJson(p.image_urls)
    }
    return opts
  }
}

export interface TagOptions {
  name?: string
  translatedName?: string
}

interface RawTag {
  name: string
  translated_name: string
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

  static fromJson(json: RawTag): TagOptions {
    let p = json
    let opts: TagOptions = {
      name: p.name,
      translatedName: p.translated_name
    }
    return opts
  }
}

export interface UserPreviewOptions {
  id?: number
  name?: string
  account?: string
  profileImageUrls?: ImageUrlsOptions
}

interface RawUserPreview {
  id: number
  name: string
  account: string
  profile_image_urls: RawImageUrls
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

  static fromJson(json: RawUserPreview): UserPreviewOptions {
    let p = json
    let opts: UserPreviewOptions = {
      id: p.id,
      name: p.name,
      account: p.account,
      profileImageUrls: ImageUrls.fromJson(p.profile_image_urls)
    }
    return opts
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

interface RawIllust {
  id: number
  title: string
  type: string
  image_urls: RawImageUrls
  meta_pages: RawMetaPage[]
  user: RawUserPreview
  tags: RawTag[]
  tools: string[]
  create_date: string
  page_count: number
  width: number
  height: number
  total_view: number
  total_bookmarks: number
  is_bookmarked: boolean
  is_muted: boolean
  restrict: string
  x_restrict: number
  illust_ai_type: number
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

  static fromJson(json: Object): Illust {
    let p = json as RawIllust
    let opts: IllustOptions = {
      id: p.id,
      title: p.title,
      type: p.type,
      imageUrls: ImageUrls.fromJson(p.image_urls),
      metaPages: p.meta_pages ? p.meta_pages.map((mp: RawMetaPage) => MetaPage.fromJson(mp)) : [],
      user: UserPreview.fromJson(p.user),
      tags: p.tags ? p.tags.map((t: RawTag) => Tag.fromJson(t)) : [],
      tools: p.tools ? p.tools : [],
      createDate: p.create_date,
      pageCount: p.page_count,
      width: p.width,
      height: p.height,
      totalView: p.total_view,
      totalBookmarks: p.total_bookmarks,
      isBookmarked: p.is_bookmarked,
      isMuted: p.is_muted,
      restrict: p.restrict,
      xRestrict: p.x_restrict,
      illustAIType: p.illust_ai_type
    }
    return new Illust(opts)
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
