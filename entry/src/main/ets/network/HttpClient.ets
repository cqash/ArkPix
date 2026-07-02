import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Constants } from '../utils/Constants';

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

  private async doRequest(options: HttpRequestOptions): Promise<http.HttpResponse> {
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

  async get(url: string, header?: Record<string, string>): Promise<http.HttpResponse> {
    return this.request({ url: url, method: http.RequestMethod.GET, header: header })
  }

  async post(url: string, body?: string | object, header?: Record<string, string>): Promise<http.HttpResponse> {
    return this.request({ url: url, method: http.RequestMethod.POST, body: body, header: header })
  }
}
