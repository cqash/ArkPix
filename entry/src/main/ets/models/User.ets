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
      squareMedium: p?.square_medium ?? '',
      medium: p?.medium ?? '',
      large: p?.large ?? '',
      original: p?.original ?? ''
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
      id: p?.id ?? 0,
      name: p?.name ?? '',
      account: p?.account ?? '',
      profileImageUrls: p?.profile_image_urls ? ImageUrls.fromJson(p.profile_image_urls) : undefined,
      comment: p?.comment ?? '',
      isFollowed: p?.is_followed ?? false,
      isFriend: p?.is_friend ?? false,
      totalFollowUsers: p?.total_follow_users ?? 0,
      totalIllusts: p?.total_illusts ?? 0,
      totalManga: p?.total_manga ?? 0,
      totalNovels: p?.total_novels ?? 0
    }
    return new User(opts)
  }
}

export interface ProfileStatsOptions {
  totalFollowUsers?: number
  totalIllusts?: number
  totalManga?: number
  totalIllustBookmarksPublic?: number
}

interface RawProfileStats {
  total_follow_users: number
  total_illusts: number
  total_manga: number
  total_illust_bookmarks_public: number
}

/** 用户统计（/v1/user/detail 响应的 profile 对象，独立于 user 对象） */
export class ProfileStats {
  totalFollowUsers: number = 0
  totalIllusts: number = 0
  totalManga: number = 0
  totalIllustBookmarksPublic: number = 0

  constructor(options?: ProfileStatsOptions) {
    if (options) {
      this.totalFollowUsers = options.totalFollowUsers ?? 0
      this.totalIllusts = options.totalIllusts ?? 0
      this.totalManga = options.totalManga ?? 0
      this.totalIllustBookmarksPublic = options.totalIllustBookmarksPublic ?? 0
    }
  }

  static fromJson(json: Object): ProfileStats {
    let p = json as RawProfileStats
    let opts: ProfileStatsOptions = {
      totalFollowUsers: p?.total_follow_users ?? 0,
      totalIllusts: p?.total_illusts ?? 0,
      totalManga: p?.total_manga ?? 0,
      totalIllustBookmarksPublic: p?.total_illust_bookmarks_public ?? 0
    }
    return new ProfileStats(opts)
  }
}

/** 解析 user/detail 响应中的 profile 统计对象 */
export function profileStatsFromJson(json: Object): ProfileStats {
  return ProfileStats.fromJson(json)
}
