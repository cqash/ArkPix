import { http } from '@kit.NetworkKit';
import { HttpInterceptor, HttpRequestOptions } from './HttpClient';

export class AuthInterceptor implements HttpInterceptor {
  private accessToken: string = ''
  private refreshToken: string = ''
  private isRefreshing: boolean = false
  private pendingRequests: Array<(token: string) => void> = []

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

  async intercept(options: HttpRequestOptions, next: (opts: HttpRequestOptions) => Promise<http.HttpResponse>): Promise<http.HttpResponse> {
    if (!options.header) {
      options.header = {}
    }
    if (this.accessToken) {
      options.header['Authorization'] = 'Bearer ' + this.accessToken
    }
    try {
      let response = await next(options)
      if (response.responseCode === 401) {
        if (this.refreshToken) {
          let newToken = await this.refreshAccessToken()
          if (newToken) {
            options.header['Authorization'] = 'Bearer ' + newToken
            return next(options)
          }
        }
      }
      return response
    } catch (err) {
      throw new Error(String(err))
    }
  }

  private async refreshAccessToken(): Promise<string> {
    if (this.isRefreshing) {
      return new Promise((resolve) => {
        this.pendingRequests.push((token: string) => resolve(token))
      })
    }
    this.isRefreshing = true
    try {
      // TODO: call OAuth refresh endpoint
      let newToken = ''
      this.accessToken = newToken
      this.pendingRequests.forEach(cb => cb(newToken))
      this.pendingRequests = []
      return newToken
    } catch (err) {
      this.pendingRequests = []
      return ''
    } finally {
      this.isRefreshing = false
    }
  }
}

export const authInterceptor = new AuthInterceptor()
