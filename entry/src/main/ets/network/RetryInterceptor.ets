import { http } from '@kit.NetworkKit';
import { HttpInterceptor, HttpRequestOptions } from './HttpClient';

export class RetryInterceptor implements HttpInterceptor {
  private maxRetries: number = 3
  private delayMs: number = 1000

  async intercept(options: HttpRequestOptions, next: (opts: HttpRequestOptions) => Promise<http.HttpResponse>): Promise<http.HttpResponse> {
    let lastError: Error | undefined = undefined
    for (let i = 0; i <= this.maxRetries; i++) {
      try {
        let response = await next(options)
        if (response.responseCode !== 500 && response.responseCode !== 502 && response.responseCode !== 503) {
          return response
        }
        if (i === this.maxRetries) {
          return response
        }
      } catch (err) {
        lastError = err as Error
        if (i === this.maxRetries) {
          throw new Error(String(err))
        }
      }
      await this.sleep(this.delayMs * Math.pow(2, i))
    }
    if (lastError) {
      throw new Error(String(lastError))
    }
    return await next(options)
  }

  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms))
  }
}

export const retryInterceptor = new RetryInterceptor()
