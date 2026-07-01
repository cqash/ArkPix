import { http } from '@kit.NetworkKit';
import { HttpClient } from './HttpClient';
import { PixivEndpoints } from './PixivEndpoints';
import { authInterceptor } from './AuthInterceptor';
import { retryInterceptor } from './RetryInterceptor';
import { logInterceptor } from './LogInterceptor';

interface BookmarkBody {
  illust_id: number
  restrict: string
  tags: string[]
}

interface UserIdBody {
  illust_id: number
}

interface FollowBody {
  user_id: number
  restrict: string
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

  private async get(url: string): Promise<Object> {
    let response = await this.httpClient.get(url)
    let body = String(response.result)
    return JSON.parse(body)
  }

  private async post(url: string, body: Object): Promise<Object> {
    let response = await this.httpClient.post(url, body)
    let resBody = String(response.result)
    return JSON.parse(resBody)
  }

  async getRecommendedIllusts(): Promise<Object> {
    return this.get(PixivEndpoints.illustRecommended())
  }

  async getRankingIllusts(mode: string, date?: string): Promise<Object> {
    return this.get(PixivEndpoints.illustRanking(mode, date))
  }

  async getNewIllusts(): Promise<Object> {
    return this.get(PixivEndpoints.illustNew())
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
    let body: BookmarkBody = { illust_id: illustId, restrict: restrict, tags: tags }
    return this.post(PixivEndpoints.illustBookmarkAdd(), body)
  }

  async deleteBookmark(illustId: number): Promise<Object> {
    let body: UserIdBody = { illust_id: illustId }
    return this.post(PixivEndpoints.illustBookmarkDelete(), body)
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
    let body: FollowBody = { user_id: userId, restrict: restrict }
    return this.post(PixivEndpoints.userFollowAdd(), body)
  }

  async unfollowUser(userId: number): Promise<Object> {
    let body: UserIdBody = { illust_id: userId }
    return this.post(PixivEndpoints.userFollowDelete(), body)
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
