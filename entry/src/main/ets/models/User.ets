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

interface RawUser {
  id: number
  name: string
  account: string
  profile_image_urls: RawImageUrls
  comment: string
  is_followed: boolean
  is_friend: boolean
  total_follow_users: number
  total_illusts: number
  total_manga: number
  total_novels: number
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

  static fromJson(json: Object): User {
    let p = json as RawUser
    let opts: UserOptions = {
      id: p.id,
      name: p.name,
      account: p.account,
      profileImageUrls: ImageUrls.fromJson(p.profile_image_urls),
      comment: p.comment,
      isFollowed: p.is_followed,
      isFriend: p.is_friend,
      totalFollowUsers: p.total_follow_users,
      totalIllusts: p.total_illusts,
      totalManga: p.total_manga,
      totalNovels: p.total_novels
    }
    return new User(opts)
  }
}
