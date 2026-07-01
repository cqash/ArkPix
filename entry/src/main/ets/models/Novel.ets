export class ImageUrls {
  squareMedium: string = ''
  medium: string = ''
  large: string = ''
  original: string = ''

  constructor(options?: Partial<ImageUrls>) {
    if (options) {
      this.squareMedium = options.squareMedium ?? ''
      this.medium = options.medium ?? ''
      this.large = options.large ?? ''
      this.original = options.original ?? ''
    }
  }
}

export class Tag {
  name: string = ''
  translatedName: string = ''

  constructor(options?: Partial<Tag>) {
    if (options) {
      this.name = options.name ?? ''
      this.translatedName = options.translatedName ?? ''
    }
  }
}

export class UserPreview {
  id: number = 0
  name: string = ''
  account: string = ''
  profileImageUrls: ImageUrls = new ImageUrls()

  constructor(options?: Partial<UserPreview>) {
    if (options) {
      this.id = options.id ?? 0
      this.name = options.name ?? ''
      this.account = options.account ?? ''
      this.profileImageUrls = new ImageUrls(options.profileImageUrls)
    }
  }
}

export class Novel {
  id: number = 0
  title: string = ''
  type: string = ''
  imageUrls: ImageUrls = new ImageUrls()
  tags: Tag[] = []
  user: UserPreview = new UserPreview()
  textLength: number = 0
  totalView: number = 0
  totalBookmarks: number = 0
  isBookmarked: boolean = false
  restrict: string = ''
  seriesId: number = 0
  content: string = ''

  constructor(options?: Partial<Novel>) {
    if (options) {
      this.id = options.id ?? 0
      this.title = options.title ?? ''
      this.type = options.type ?? ''
      this.imageUrls = new ImageUrls(options.imageUrls)
      this.tags = (options.tags ?? []).map((t: Tag) => new Tag(t))
      this.user = new UserPreview(options.user)
      this.textLength = options.textLength ?? 0
      this.totalView = options.totalView ?? 0
      this.totalBookmarks = options.totalBookmarks ?? 0
      this.isBookmarked = options.isBookmarked ?? false
      this.restrict = options.restrict ?? ''
      this.seriesId = options.seriesId ?? 0
      this.content = options.content ?? ''
    }
  }
}