import { http } from '@kit.NetworkKit';
import { HttpInterceptor, HttpRequestOptions } from './HttpClient';

export class AuthInterceptor implements HttpInterceptor {
  private static readonly REFRESH_THROTTLE_MS: number = 120000
  private accessToken: string = ''
  private refreshToken: string = ''
  private isRefreshing: boolean = false
  private lastRefreshTime: number = 0
  private pendingRequests: Array<(token: string) => void> = []
  private refreshHandler: () => Promise<string> = async () => { return '' }
  private onRefreshFailed: (() => void) | null = null

  setTokens(accessToken: string, refreshToken: string): void {
    this.accessToken = accessToken
    this.refreshToken = refreshToken
  }

  getAccessToken(): string {
    return this.accessToken
  }

  getRefreshToken(): string {
    return this.refreshToken
  }

  clearTokens(): void {
    this.accessToken = ''
    this.refreshToken = ''
  }

  setRefreshHandler(handler: () => Promise<string>): void {
    this.refreshHandler = handler
  }

  setOnRefreshFailed(callback: () => void): void {
    this.onRefreshFailed = callback
  }

  async intercept(options: HttpRequestOptions, next: (opts: HttpRequestOptions) => Promise<http.HttpResponse>): Promise<http.HttpResponse> {
    if (!options.header) {
      options.header = {}
    }
    if (this.accessToken) {
      options.header['Authorization'] = 'Bearer ' + this.accessToken
    }
    // Accept-Language: 让 Pixiv API 返回 tag 的 translated_name 翻译
    options.header['Accept-Language'] = 'zh-CN'
    try {
      let response = await next(options)
      if (AuthInterceptor.isAuthErrorResponse(response)) {
        let newToken = await this.refreshAccessToken()
        if (newToken) {
          options.header['Authorization'] = 'Bearer ' + newToken
          let replayed = await next(options)
          if (AuthInterceptor.isAuthErrorResponse(replayed)) {
            // 重放最终校验：仍为鉴权错误说明新 token 未被接受，
            // 不再循环重试，错误交由上层按凭证/网络分类处理
            console.error('Replay after token refresh still auth-error (HTTP ' + replayed.responseCode + ')')
          }
          return replayed
        }
        // 刷新返回空 token（失败）时不重放原请求
      }
      return response
    } catch (err) {
      throw new Error(String(err))
    }
  }

  /**
   * 鉴权错误判定：401 直接命中；Pixiv 对无效/过期 access token 多数接口返回
   * 400 + 错误体（对标 PixEz Flutter RefreshTokenInterceptor 的 "400 + OAuth 错误信息" 策略），
   * 需触发刷新重放而非直接把 400 冒泡到页面（含历史 bug 写坏 token 后的自愈场景）
   */
  private static isAuthErrorResponse(response: http.HttpResponse): boolean {
    if (response.responseCode === 401) {
      return true
    }
    if (response.responseCode !== 400) {
      return false
    }
    let body = String(response.result).toLowerCase()
    return body.includes('invalid access token') ||
      body.includes('invalid_access_token') ||
      body.includes('invalid_grant') ||
      body.includes('access token') ||
      body.includes('oauth')
  }

  private async refreshAccessToken(): Promise<string> {
    if (this.isRefreshing) {
      return new Promise((resolve) => {
        this.pendingRequests.push((token: string) => resolve(token))
      })
    }
    // 刷新节流：距上次成功刷新 <120s 直接复用当前 token，避免每次 401 都重复刷新
    if (this.accessToken && Date.now() - this.lastRefreshTime < AuthInterceptor.REFRESH_THROTTLE_MS) {
      return this.accessToken
    }
    this.isRefreshing = true
    try {
      if (!this.refreshToken) {
        // 无 refresh token 时也必须唤醒排队请求，避免挂起
        this.pendingRequests.forEach(cb => cb(''))
        this.pendingRequests = []
        return ''
      }
      let newToken = await this.refreshHandler()
      if (newToken) {
        this.lastRefreshTime = Date.now()
      }
      this.pendingRequests.forEach(cb => cb(newToken))
      this.pendingRequests = []
      return newToken
    } catch (err) {
      this.pendingRequests = []
      if (this.onRefreshFailed) {
        this.onRefreshFailed()
      }
      return ''
    } finally {
      this.isRefreshing = false
    }
  }
}

export const authInterceptor = new AuthInterceptor()
