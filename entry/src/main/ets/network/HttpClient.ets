import { http } from '@kit.NetworkKit';
import { rcp } from '@kit.RemoteCommunicationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Constants } from '../utils/Constants';
import { preferenceService } from '../services/PreferenceService';
import { hoster } from './Hoster';

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
  private bypassSession: rcp.Session | null = null

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

  isBypassEnabled(): boolean {
    return preferenceService.getString('network_mode', 'direct') === 'bypass'
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

  private getBypassSession(): rcp.Session {
    if (this.bypassSession === null) {
      this.bypassSession = rcp.createSession({
        requestConfiguration: {
          dns: {
            dnsRules: (host: string, port: number): string[] => {
              return hoster.resolveIps(host)
            }
          },
          transfer: {
            timeout: { connectMs: 30000, transferMs: 30000 }
          }
        }
      })
    }
    return this.bypassSession
  }

  private async doRequest(options: HttpRequestOptions): Promise<http.HttpResponse> {
    if (this.isBypassEnabled()) {
      return this.doBypassRequest(options)
    }

    let httpClient = http.createHttp()
    let emptyHeader: Record<string, string> = {}
    let reqOptions: http.HttpRequestOptions = {
      method: options.method ?? http.RequestMethod.GET,
      header: options.header ?? emptyHeader,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 30000,
      readTimeout: 30000
    }

    if (options.body) {
      if (typeof options.body === 'string') {
        reqOptions.extraData = options.body
      } else {
        reqOptions.extraData = JSON.stringify(options.body)
      }
    }

    return new Promise((resolve, reject) => {
      httpClient.request(options.url, reqOptions, (err: BusinessError, data: http.HttpResponse) => {
        httpClient.destroy()
        if (!err) {
          resolve(data)
        } else {
          reject(err)
        }
      })
    })
  }

  private async doBypassRequest(options: HttpRequestOptions): Promise<http.HttpResponse> {
    let session: rcp.Session = this.getBypassSession()
    let methodStr: string = 'GET'
    if (options.method === http.RequestMethod.POST) {
      methodStr = 'POST'
    } else if (options.method === http.RequestMethod.PUT) {
      methodStr = 'PUT'
    } else if (options.method === http.RequestMethod.DELETE) {
      methodStr = 'DELETE'
    } else if (options.method === http.RequestMethod.HEAD) {
      methodStr = 'HEAD'
    } else if (options.method === http.RequestMethod.OPTIONS) {
      methodStr = 'OPTIONS'
    }

    let request: rcp.Request = new rcp.Request(options.url, methodStr)
    if (options.header) {
      request.headers = options.header
    }
    if (options.body) {
      if (typeof options.body === 'string') {
        request.content = options.body
      } else {
        request.content = JSON.stringify(options.body)
      }
    }

    let response: rcp.Response = await session.fetch(request)
    let result: string = ''
    if (response.body) {
      result = this.arrayBufferToString(response.body)
    }

    let httpResponse: http.HttpResponse = {
      responseCode: response.statusCode,
      result: result,
      header: response.headers,
      cookies: '',
      resultType: http.HttpDataType.STRING,
      performanceTiming: {
        dnsTiming: 0,
        tcpTiming: 0,
        tlsTiming: 0,
        firstSendTiming: 0,
        firstReceiveTiming: 0,
        totalFinishTiming: 0,
        redirectTiming: 0,
        responseHeaderTiming: 0,
        responseBodyTiming: 0,
        totalTiming: 0
      }
    }
    return httpResponse
  }

  private arrayBufferToString(buffer: ArrayBuffer): string {
    let bytes = new Uint8Array(buffer)
    let chars: string[] = []
    for (let i = 0; i < bytes.length; i++) {
      chars.push(String.fromCharCode(bytes[i]))
    }
    return chars.join('')
  }

  async get(url: string, header?: Record<string, string>): Promise<http.HttpResponse> {
    return this.request({ url: url, method: http.RequestMethod.GET, header: header })
  }

  async post(url: string, body?: string | object, header?: Record<string, string>): Promise<http.HttpResponse> {
    return this.request({ url: url, method: http.RequestMethod.POST, body: body, header: header })
  }
}
