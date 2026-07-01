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

export interface UserOptions {
  id?: number
  name?: string
  account?: string
  profileImageUrls?: ImageUrlsOptions
  comment?: string
  isFollowed?: boolean
  isFriend?: boolean
  totalFollowUsers?: number
  totalIllusts?: number
  totalManga?: number
  totalNovels?: number
}

export class User {
  id: number = 0
  name: string = ''
  account: string = ''
  profileImageUrls: ImageUrls = new ImageUrls()
  comment: string = ''
  isFollowed: boolean = false
  isFriend: boolean = false
  totalFollowUsers: number = 0
  totalIllusts: number = 0
  totalManga: number = 0
  totalNovels: number = 0

  constructor(options?: UserOptions) {
    if (options) {
      this.id = options.id ?? 0
      this.name = options.name ?? ''
      this.account = options.account ?? ''
      this.profileImageUrls = new ImageUrls(options.profileImageUrls)
      this.comment = options.comment ?? ''
      this.isFollowed = options.isFollowed ?? false
      this.isFriend = options.isFriend ?? false
      this.totalFollowUsers = options.totalFollowUsers ?? 0
      this.totalIllusts = options.totalIllusts ?? 0
      this.totalManga = options.totalManga ?? 0
      this.totalNovels = options.totalNovels ?? 0
    }
  }
}
