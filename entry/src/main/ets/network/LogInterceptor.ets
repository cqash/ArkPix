import { http } from '@kit.NetworkKit';
import { HttpInterceptor, HttpRequestOptions } from './HttpClient';

export class LogInterceptor implements HttpInterceptor {
  async intercept(options: HttpRequestOptions, next: (opts: HttpRequestOptions) => Promise<http.HttpResponse>): Promise<http.HttpResponse> {
    console.info('HTTP Request: ' + options.method + ' ' + options.url)
    let response = await next(options)
    console.info('HTTP Response: ' + response.responseCode + ' ' + options.url)
    return response
  }
}

export const logInterceptor = new LogInterceptor()
