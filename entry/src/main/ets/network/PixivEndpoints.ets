export class PixivEndpoints {
  static readonly OAUTH_AUTH_URL: string = 'https://app-api.pixiv.net/web/v1/login'
  static readonly OAUTH_TOKEN_URL: string = 'https://oauth.secure.pixiv.net/auth/token'
  static readonly API_BASE: string = 'https://app-api.pixiv.net'
  static readonly PUBLIC_BASE: string = 'https://public-api.secure.pixiv.net'

  static illustRecommended(): string { return PixivEndpoints.API_BASE + '/v1/illust/recommended?filter=for_android' }
  static illustRanking(mode: string, date?: string): string {
    let url = PixivEndpoints.API_BASE + '/v1/illust/ranking?mode=' + mode + '&filter=for_android'
    if (date) { url += '&date=' + date }
    return url
  }
  static illustNew(): string { return PixivEndpoints.API_BASE + '/v1/illust/new?filter=for_android' }
  static illustFollow(restrict: string): string { return PixivEndpoints.API_BASE + '/v2/illust/follow?restrict=' + restrict + '&filter=for_android' }
  static illustDetail(id: number): string { return PixivEndpoints.API_BASE + '/v1/illust/detail?illust_id=' + id + '&filter=for_android' }
  static illustRelated(id: number): string { return PixivEndpoints.API_BASE + '/v2/illust/related?illust_id=' + id + '&filter=for_android' }
  static illustComments(id: number): string { return PixivEndpoints.API_BASE + '/v3/illust/comments?illust_id=' + id }
  static illustCommentReplies(commentId: number): string { return PixivEndpoints.API_BASE + '/v2/illust/comment/replies?comment_id=' + commentId }
  static illustCommentAdd(): string { return PixivEndpoints.API_BASE + '/v1/illust/comment/add' }
  static illustBookmarkAdd(): string { return PixivEndpoints.API_BASE + '/v2/illust/bookmark/add' }
  static illustBookmarkDelete(): string { return PixivEndpoints.API_BASE + '/v1/illust/bookmark/delete' }
  static illustLike(): string { return PixivEndpoints.API_BASE + '/v2/illust/bookmark/add' }
  static illustUnlike(): string { return PixivEndpoints.API_BASE + '/v1/illust/bookmark/delete' }

  static userDetail(id: number): string { return PixivEndpoints.API_BASE + '/v1/user/detail?user_id=' + id }
  static userIllusts(id: number, type: string): string { return PixivEndpoints.API_BASE + '/v1/user/illusts?user_id=' + id + '&type=' + type + '&filter=for_android' }
  static userBookmarksIllust(id: number, restrict: string): string { return PixivEndpoints.API_BASE + '/v1/user/bookmarks/illust?user_id=' + id + '&restrict=' + restrict + '&filter=for_android' }
  static userBookmarkTagsIllust(restrict: string): string { return PixivEndpoints.API_BASE + '/v1/user/bookmark-tags/illust?restrict=' + restrict }
  static userFollowAdd(): string { return PixivEndpoints.API_BASE + '/v1/user/follow/add' }
  static userFollowDelete(): string { return PixivEndpoints.API_BASE + '/v1/user/follow/delete' }
  static userFollowDetail(id: number): string { return PixivEndpoints.API_BASE + '/v1/user/follow/detail?user_id=' + id }

  static searchIllust(word: string, sort?: string, searchTarget?: string): string {
    let url = PixivEndpoints.API_BASE + '/v1/search/illust?word=' + encodeURIComponent(word) + '&filter=for_android'
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
  static searchAutoComplete(word: string): string { return PixivEndpoints.API_BASE + '/v2/search/autocomplete?word=' + encodeURIComponent(word) + '&merge_plain_keyword_results=true' }
  static trendingTagsIllust(): string { return PixivEndpoints.API_BASE + '/v1/trending-tags/illust?filter=for_android' }

  static novelRecommended(): string { return PixivEndpoints.API_BASE + '/v1/novel/recommended?filter=for_android' }
  static novelDetail(id: number): string { return PixivEndpoints.API_BASE + '/v1/novel/detail?novel_id=' + id }
  static novelText(id: number): string { return PixivEndpoints.API_BASE + '/v1/novel/text?novel_id=' + id }
  static novelComments(id: number): string { return PixivEndpoints.API_BASE + '/v3/novel/comments?novel_id=' + id }

  static spotlightArticles(category: string): string { return PixivEndpoints.API_BASE + '/v1/spotlight/articles?category=' + category }

  static ugoiraMetadata(id: number): string { return PixivEndpoints.API_BASE + '/v1/ugoira/metadata?illust_id=' + id }
  static walkthroughIllusts(): string { return PixivEndpoints.API_BASE + '/v1/walkthrough/illusts' }
}
