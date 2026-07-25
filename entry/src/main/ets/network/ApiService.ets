import { http } from '@kit.NetworkKit';
import { HttpClient } from './HttpClient';
import { PixivEndpoints } from './PixivEndpoints';
import { authInterceptor } from './AuthInterceptor';
import { retryInterceptor } from './RetryInterceptor';
import { logInterceptor } from './LogInterceptor';

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
      throw new Error('HTTP ' + response.responseCode + ': ' + url)
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

  async addBookmark(illustId: number, restrict: string = 'public', tags: string[] = []): Promise<Object> {
    let fields: Record<string, string | number | boolean> = { 'illust_id': illustId, 'restrict': restrict }
    let arrayFields: Record<string, string[]> = { 'tags': tags }
    return this.post(PixivEndpoints.illustBookmarkAdd(), fields, arrayFields)
  }

  async deleteBookmark(illustId: number): Promise<Object> {
    let fields: Record<string, string | number | boolean> = { 'illust_id': illustId }
    return this.post(PixivEndpoints.illustBookmarkDelete(), fields)
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

  async getUgoiraMetadata(id: number): Promise<Object> {
    return this.get(PixivEndpoints.ugoiraMetadata(id))
  }
}

export const apiService = ApiService.getInstance()
