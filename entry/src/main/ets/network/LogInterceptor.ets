import { http } from '@kit.NetworkKit';
import { HttpInterceptor, HttpRequestOptions } from './HttpClient';

interface TagRaw {
  name: string
  translated_name: string
}

interface IllustRaw {
  tags?: TagRaw[]
}

interface DetailResponse {
  illust?: IllustRaw
}

interface ListResponse {
  illusts?: IllustRaw[]
}

export class LogInterceptor implements HttpInterceptor {
  async intercept(options: HttpRequestOptions, next: (opts: HttpRequestOptions) => Promise<http.HttpResponse>): Promise<http.HttpResponse> {
    let acceptLang = options.header ? options.header['Accept-Language'] : 'NOT_SET'
    console.info('[HTTP] Request: ' + (options.method ?? 'GET') + ' ' + options.url + ' | Accept-Language: ' + (acceptLang ?? 'NOT_SET'))
    let response = await next(options)
    console.info('[HTTP] Response: ' + response.responseCode + ' ' + options.url)

    // Debug: log tag translated_name for illust detail / list responses
    if (response.responseCode === 200) {
      try {
        let body = String(response.result)
        let parsed: Object = JSON.parse(body)

        // Single illust detail
        let detail = parsed as DetailResponse
        if (detail.illust && detail.illust.tags) {
          let tags = detail.illust.tags
          let tagLog = tags.map((t: TagRaw) => t.name + '→' + (t.translated_name ?? 'null')).join(', ')
          console.info('[HTTP-TAGS] Detail: ' + tagLog)
        }

        // Illust list (recommended/follow/ranking/search)
        let list = parsed as ListResponse
        if (list.illusts && Array.isArray(list.illusts) && list.illusts.length > 0) {
          let first = list.illusts[0]
          if (first.tags) {
            let tags = first.tags
            let tagLog = tags.map((t: TagRaw) => t.name + '→' + (t.translated_name ?? 'null')).join(', ')
            console.info('[HTTP-TAGS] List(first): ' + tagLog)
          }
        }
      } catch (e) {
        // Not JSON or no tags — ignore
      }
    }

    return response
  }
}

export const logInterceptor = new LogInterceptor()
