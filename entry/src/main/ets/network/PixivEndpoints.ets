export class PixivEndpoints {
  static readonly OAUTH_AUTH_URL: string = 'https://app-api.pixiv.net/web/v1/login'
  static readonly OAUTH_TOKEN_URL: string = 'https://oauth.secure.pixiv.net/auth/token'
  static readonly API_BASE: string = 'https://app-api.pixiv.net'
  static readonly PUBLIC_BASE: string = 'https://public-api.secure.pixiv.net'

  static illustRecommended(): string { return PixivEndpoints.API_BASE + '/v1/illust/recommended' }
  static illustRanking(mode: string, date?: string): string {
    let url = PixivEndpoints.API_BASE + '/v1/illust/ranking?mode=' + mode
    if (date) { url += '&date=' + date }
    return url
  }
  static illustNew(): string { return PixivEndpoints.API_BASE + '/v1/illust/new' }
  static illustFollow(restrict: string): string { return PixivEndpoints.API_BASE + '/v2/illust/follow?restrict=' + restrict }
  static illustDetail(id: number): string { return PixivEndpoints.API_BASE + '/v1/illust/detail?illust_id=' + id }
  static illustRelated(id: number): string { return PixivEndpoints.API_BASE + '/v2/illust/related?illust_id=' + id }
  static illustComments(id: number): string { return PixivEndpoints.API_BASE + '/v3/illust/comments?illust_id=' + id }
  static illustBookmarkAdd(): string { return PixivEndpoints.API_BASE + '/v2/illust/bookmark/add' }
  static illustBookmarkDelete(): string { return PixivEndpoints.API_BASE + '/v1/illust/bookmark/delete' }
  static illustLike(): string { return PixivEndpoints.API_BASE + '/v2/illust/bookmark/add' }
  static illustUnlike(): string { return PixivEndpoints.API_BASE + '/v1/illust/bookmark/delete' }

  static userDetail(id: number): string { return PixivEndpoints.API_BASE + '/v1/user/detail?user_id=' + id }
  static userIllusts(id: number, type: string): string { return PixivEndpoints.API_BASE + '/v1/user/illusts?user_id=' + id + '&type=' + type }
  static userBookmarksIllust(id: number, restrict: string): string { return PixivEndpoints.API_BASE + '/v1/user/bookmarks/illust?user_id=' + id + '&restrict=' + restrict }
  static userFollowAdd(): string { return PixivEndpoints.API_BASE + '/v1/user/follow/add' }
  static userFollowDelete(): string { return PixivEndpoints.API_BASE + '/v1/user/follow/delete' }
  static userFollowDetail(id: number): string { return PixivEndpoints.API_BASE + '/v1/user/follow/detail?user_id=' + id }

  static searchIllust(word: string, sort?: string, searchTarget?: string): string {
    let url = PixivEndpoints.API_BASE + '/v1/search/illust?word=' + encodeURIComponent(word)
    if (sort) { url += '&sort=' + sort }
    if (searchTarget) { url += '&search_target=' + searchTarget }
    return url
  }
  static searchNovel(word: string, sort?: string): string {
    let url = PixivEndpoints.API_BASE + '/v1/search/novel?word=' + encodeURIComponent(word)
    if (sort) { url += '&sort=' + sort }
    return url
  }
  static searchUser(word: string): string { return PixivEndpoints.API_BASE + '/v1/search/user?word=' + encodeURIComponent(word) }
  static searchAutoComplete(word: string): string { return PixivEndpoints.API_BASE + '/v2/search/autocomplete?word=' + encodeURIComponent(word) }
  static trendingTagsIllust(): string { return PixivEndpoints.API_BASE + '/v1/trending-tags/illust' }

  static novelRecommended(): string { return PixivEndpoints.API_BASE + '/v1/novel/recommended' }
  static novelDetail(id: number): string { return PixivEndpoints.API_BASE + '/v1/novel/detail?novel_id=' + id }
  static novelText(id: number): string { return PixivEndpoints.API_BASE + '/v1/novel/text?novel_id=' + id }
  static novelComments(id: number): string { return PixivEndpoints.API_BASE + '/v3/novel/comments?novel_id=' + id }

  static spotlightArticles(category: string): string { return PixivEndpoints.API_BASE + '/v1/spotlight/articles?category=' + category }

  static ugoiraMetadata(id: number): string { return PixivEndpoints.API_BASE + '/v1/ugoira/metadata?illust_id=' + id }
  static walkthroughIllusts(): string { return PixivEndpoints.API_BASE + '/v1/walkthrough/illusts' }
}
