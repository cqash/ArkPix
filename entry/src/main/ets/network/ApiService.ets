import { http } from '@kit.NetworkKit';
import { HttpClient } from './HttpClient';
import { PixivEndpoints } from './PixivEndpoints';
import { authInterceptor } from './AuthInterceptor';
import { retryInterceptor } from './RetryInterceptor';
import { logInterceptor } from './LogInterceptor';
import { BookmarkTag, bookmarkTagFromJson, RawBookmarkTag, RawBookmarkTagListResponse } from '../models/Bookmark';
import { UgoiraMetadata, ugoiraMetadataFromJson, RawUgoiraMetadataResponse } from '../models/UgoiraMetadata';

/** 携带 HTTP 状态码的错误（ensureSuccess 抛出），供调用方按状态码分流（如详情页识别 404） */
export class HttpStatusError extends Error {
  readonly statusCode: number

  constructor(statusCode: number, message: string) {
    super(message)
    this.name = 'HttpStatusError'
    this.statusCode = statusCode
  }
}

export class ApiService {
  private static instance: ApiService
  private httpClient: HttpClient

  private constructor() {
    this.httpClient = HttpClient.getInstance()
    this.httpClient.addInterceptor(authInterceptor)
    this.httpClient.addInterceptor(retryInterceptor)
    this.httpClient.addInterceptor(logInterceptor)
  }

  static getInstance(): ApiService {
    if (!ApiService.instance) {
      ApiService.instance = new ApiService()
    }
    return ApiService.instance
  }

  private ensureSuccess(response: http.HttpResponse, url: string): void {
    if (response.responseCode < 200 || response.responseCode >= 300) {
      // 附加截断后的响应体（约 200 字符），便于定位服务端 4xx/5xx 原因
      let bodySnippet = ''
      try {
        let raw = String(response.result)
        bodySnippet = raw.length > 200 ? raw.substring(0, 200) + '...' : raw
      } catch (e) {
        bodySnippet = ''
      }
      let message = 'HTTP ' + response.responseCode + ': ' + url
      if (bodySnippet.length > 0) {
        message += ' | body: ' + bodySnippet
      }
      throw new HttpStatusError(response.responseCode, message)
    }
  }

  private async get(url: string): Promise<Object> {
    let response = await this.httpClient.get(url)
    this.ensureSuccess(response, url)
    let body = String(response.result)
    return JSON.parse(body)
  }

  /**
   * Pixiv 写接口（收藏/关注等）要求 application/x-www-form-urlencoded 表单编码，
   * 发送 JSON 会被服务端拒绝（HTTP 400）。字符串数组按 Pixiv 约定编码为 key[]=v1&key[]=v2。
   */
  private toFormBody(fields: Record<string, string | number | boolean>, arrayFields?: Record<string, string[]>): string {
    let parts: string[] = []
    let keys = Object.keys(fields)
    for (let i = 0; i < keys.length; i++) {
      let key = keys[i]
      parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(String(fields[key])))
    }
    if (arrayFields) {
      let arrKeys = Object.keys(arrayFields)
      for (let i = 0; i < arrKeys.length; i++) {
        let key = arrKeys[i]
        let arr = arrayFields[key]
        for (let j = 0; j < arr.length; j++) {
          parts.push(encodeURIComponent(key + '[]') + '=' + encodeURIComponent(arr[j]))
        }
      }
    }
    return parts.join('&')
  }

  private async post(url: string, fields: Record<string, string | number | boolean>,
    arrayFields?: Record<string, string[]>): Promise<Object> {
    let header: Record<string, string> = { 'Content-Type': 'application/x-www-form-urlencoded' }
    let response = await this.httpClient.post(url, this.toFormBody(fields, arrayFields), header)
    this.ensureSuccess(response, url)
    let resBody = String(response.result)
    if (resBody.length === 0) {
      // 部分写接口（如取消收藏）成功时返回空响应体
      let empty: Record<string, string> = {}
      return empty
    }
    return JSON.parse(resBody)
  }

  async fetchNext(nextUrl: string): Promise<Object> {
    return this.get(nextUrl)
  }

  async getRecommendedIllusts(): Promise<Object> {
    return this.get(PixivEndpoints.illustRecommended())
  }

  async getRankingIllusts(mode: string, date?: string): Promise<Object> {
    return this.get(PixivEndpoints.illustRanking(mode, date))
  }

  async getFollowIllusts(restrict: string = 'public'): Promise<Object> {
    return this.get(PixivEndpoints.illustFollow(restrict))
  }

  async getIllustDetail(id: number): Promise<Object> {
    return this.get(PixivEndpoints.illustDetail(id))
  }

  async getRelatedIllusts(id: number): Promise<Object> {
    return this.get(PixivEndpoints.illustRelated(id))
  }

  async getIllustComments(id: number): Promise<Object> {
    return this.get(PixivEndpoints.illustComments(id))
  }

  async getIllustCommentReplies(commentId: number): Promise<Object> {
    return this.get(PixivEndpoints.illustCommentReplies(commentId))
  }

  async addIllustComment(illustId: number, text: string, parentCommentId?: number): Promise<Object> {
    // Pixiv /v1/illust/comment/add 的 form 字段名为 comment（误用 text 会触发服务端 500）
    let fields: Record<string, string | number | boolean> = { 'illust_id': illustId, 'comment': text }
    if (parentCommentId !== undefined && parentCommentId > 0) {
      fields['parent_comment_id'] = parentCommentId
    }
    return this.post(PixivEndpoints.illustCommentAdd(), fields)
  }

  async addBookmark(illustId: number, restrict: string = 'public', tags: string[] = []): Promise<Object> {
    let fields: Record<string, string | number | boolean> = { 'illust_id': illustId, 'restrict': restrict }
    let arrayFields: Record<string, string[]> = { 'tags': tags }
    return this.post(PixivEndpoints.illustBookmarkAdd(), fields, arrayFields)
  }

  async deleteBookmark(illustId: number): Promise<Object> {
    let fields: Record<string, string | number | boolean> = { 'illust_id': illustId }
    return this.post(PixivEndpoints.illustBookmarkDelete(), fields)
  }

  /** 用户历史收藏标签列表（带标签收藏面板用），失败抛既有类型化错误由面板层捕获显错误态 */
  async getBookmarkTags(restrict: string = 'public'): Promise<BookmarkTag[]> {
    let response = await this.get(PixivEndpoints.userBookmarkTagsIllust(restrict))
    let raw = response as RawBookmarkTagListResponse
    let tags: BookmarkTag[] = []
    let arr: RawBookmarkTag[] = raw.bookmark_tags ?? []
    for (let i = 0; i < arr.length; i++) {
      let tag = bookmarkTagFromJson(arr[i])
      if (tag.name.length > 0) {
        tags.push(tag)
      }
    }
    return tags
  }

  async getUserDetail(userId: number): Promise<Object> {
    return this.get(PixivEndpoints.userDetail(userId))
  }

  async getUserIllusts(userId: number, type: string = 'illust'): Promise<Object> {
    return this.get(PixivEndpoints.userIllusts(userId, type))
  }

  async getUserBookmarks(userId: number, restrict: string = 'public'): Promise<Object> {
    return this.get(PixivEndpoints.userBookmarksIllust(userId, restrict))
  }

  async followUser(userId: number, restrict: string = 'public'): Promise<Object> {
    let fields: Record<string, string | number | boolean> = { 'user_id': userId, 'restrict': restrict }
    return this.post(PixivEndpoints.userFollowAdd(), fields)
  }

  async unfollowUser(userId: number): Promise<Object> {
    // Pixiv follow/delete 接口参数为 user_id（此前误写 illust_id 会 400）
    let fields: Record<string, string | number | boolean> = { 'user_id': userId }
    return this.post(PixivEndpoints.userFollowDelete(), fields)
  }

  async searchIllusts(word: string, sort?: string, target?: string): Promise<Object> {
    return this.get(PixivEndpoints.searchIllust(word, sort, target))
  }

  async searchNovels(word: string, sort?: string): Promise<Object> {
    return this.get(PixivEndpoints.searchNovel(word, sort))
  }

  async searchUsers(word: string): Promise<Object> {
    return this.get(PixivEndpoints.searchUser(word))
  }

  async getAutoComplete(word: string): Promise<Object> {
    return this.get(PixivEndpoints.searchAutoComplete(word))
  }

  async getTrendingTags(): Promise<Object> {
    return this.get(PixivEndpoints.trendingTagsIllust())
  }

  async getNovelRecommended(): Promise<Object> {
    return this.get(PixivEndpoints.novelRecommended())
  }

  async getNovelDetail(id: number): Promise<Object> {
    return this.get(PixivEndpoints.novelDetail(id))
  }

  async getNovelText(id: number): Promise<Object> {
    return this.get(PixivEndpoints.novelText(id))
  }

  async getSpotlightArticles(category: string): Promise<Object> {
    return this.get(PixivEndpoints.spotlightArticles(category))
  }

  async getUgoiraMetadata(id: number): Promise<UgoiraMetadata> {
    let raw = await this.get(PixivEndpoints.ugoiraMetadata(id))
    return ugoiraMetadataFromJson(raw as RawUgoiraMetadataResponse)
  }
}

export const apiService = ApiService.getInstance()
