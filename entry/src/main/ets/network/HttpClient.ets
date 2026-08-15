import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Constants } from '../utils/Constants';
import { preferenceService } from '../services/PreferenceService';
import { relayClient, RelayRequestInput } from './RelayClient';

export interface HttpRequestOptions {
  url: string
  method?: http.RequestMethod
  header?: Record<string, string>
  body?: string | object
  extraData?: object
}

export interface HttpInterceptor {
  intercept(options: HttpRequestOptions, next: (opts: HttpRequestOptions) => Promise<http.HttpResponse>): Promise<http.HttpResponse>
}

export class HttpClient {
  private static instance: HttpClient
  private interceptors: HttpInterceptor[] = []

  private constructor() {
  }

  static getInstance(): HttpClient {
    if (!HttpClient.instance) {
      HttpClient.instance = new HttpClient()
    }
    return HttpClient.instance
  }

  addInterceptor(interceptor: HttpInterceptor): void {
    this.interceptors.push(interceptor)
  }

  async request(options: HttpRequestOptions): Promise<http.HttpResponse> {
    options.url = Constants.applyProxy(options.url)
    return this.executeChain(options, 0)
  }

  private async executeChain(options: HttpRequestOptions, index: number): Promise<http.HttpResponse> {
    if (index < this.interceptors.length) {
      return this.interceptors[index].intercept(options, (opts) => this.executeChain(opts, index + 1))
    }
    return this.doRequest(options)
  }

  /** 按 URL 归属解析网络模式：认证主机→authMode，API 主机→apiMode，其余直连 */
  private resolveMode(url: string): string {
    let mode = Constants.MODE_STANDARD
    if (Constants.isOauthUrl(url)) {
      mode = preferenceService.getString('auth_mode', Constants.MODE_STANDARD)
    } else if (Constants.isApiUrl(url)) {
      mode = preferenceService.getString('api_mode', Constants.MODE_STANDARD)
    }
    return Constants.normalizeMode(mode)
  }

  private async doRequest(options: HttpRequestOptions): Promise<http.HttpResponse> {
    let mode = this.resolveMode(options.url)

    // relay 分流：跳过 applyDirectIp/remoteValidation:'skip'，委派 RelayClient 包装/解包。
    // Pixiv Authorization 头已由 AuthInterceptor 注入 options.header，进入包装体 headers 白名单；
    // 解包后还原原始 status/body，Pixiv 401 语义仍由 AuthInterceptor 处理。
    if (Constants.isRelayMode(mode)) {
      let relayInput: RelayRequestInput = {
        url: options.url,
        method: options.method,
        header: options.header,
        body: options.body
      }
      return relayClient.relayRequest(relayInput)
    }

    let httpClient = http.createHttp()
    let isCompatible = (mode === Constants.MODE_COMPATIBLE || mode === Constants.MODE_ECH)

    let requestUrl = options.url
    if (isCompatible) {
      let originalHost = Constants.extractHost(options.url)
      requestUrl = Constants.applyDirectIp(options.url)
      if (originalHost.length > 0) {
        if (!options.header) {
          options.header = {}
        }
        options.header['Host'] = originalHost
      }
    }

    let emptyHeader: Record<string, string> = {}
    let reqOptions: http.HttpRequestOptions = {
      method: options.method ?? http.RequestMethod.GET,
      header: options.header ?? emptyHeader,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 30000,
      readTimeout: 30000
    }

    if (isCompatible) {
      reqOptions.remoteValidation = 'skip'
      reqOptions.sniHostName = ''
    }

    if (options.body) {
      if (typeof options.body === 'string') {
        reqOptions.extraData = options.body
      } else {
        reqOptions.extraData = JSON.stringify(options.body)
      }
    }

    return new Promise((resolve, reject) => {
      httpClient.request(requestUrl, reqOptions, (err: BusinessError, data: http.HttpResponse) => {
        httpClient.destroy()
        if (!err) {
          resolve(data)
        } else {
          reject(err)
        }
      })
    })
  }

  async get(url: string, header?: Record<string, string>): Promise<http.HttpResponse> {
    return this.request({ url: url, method: http.RequestMethod.GET, header: header })
  }

  async post(url: string, body?: string | object, header?: Record<string, string>): Promise<http.HttpResponse> {
    return this.request({ url: url, method: http.RequestMethod.POST, body: body, header: header })
  }
}
