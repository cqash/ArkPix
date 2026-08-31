import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { buffer } from '@kit.ArkTS';
import { promptAction } from '@kit.ArkUI';
import { preferenceService } from '../services/PreferenceService';
import { userSettingStore } from '../stores/UserSettingStore';
import { Constants } from '../utils/Constants';
import { getStr, getStrf } from '../utils/I18nUtils';
import {
  RelayRegisterResult,
  relayRegisterResultFromJson,
  parseRelayError
} from '../models/RelayModels';

/** 中继服务令牌失效：refreshToken 也被拒绝，需重新注册/导入账号（不清空 Pixiv 登录态） */
export class RelayAuthError extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'RelayAuthError'
  }
}

/** 中继请求入参（与 HttpClient.HttpRequestOptions 同构，独立定义避免循环依赖） */
export interface RelayRequestInput {
  url: string
  method?: http.RequestMethod
  header?: Record<string, string>
  body?: string | object
}

/** 包装时允许透传的请求头白名单（小写匹配） */
const RELAY_FORWARD_HEADERS: string[] = [
  'authorization', 'content-type', 'accept-language', 'user-agent', 'referer',
  'x-client-time', 'x-client-hash', 'host'
]

/** 解包时读取的响应头白名单（服务端约定小写键） */
const RELAY_RESPONSE_HEADERS: string[] = ['content-type', 'cache-control', 'retry-after']

/** 连续失败回落阈值 */
const RELAY_FAILURE_FALLBACK_THRESHOLD: number = 3

/** 过期前刷新余量（ms） */
const TOKEN_REFRESH_MARGIN_MS: number = 60000

// PreferenceService keys（令牌/accountKey/capabilities 直存，不进 AppSettings，防止随 settings 域上行泄漏）
const KEY_ACCESS_TOKEN: string = 'relay_access_token'
const KEY_REFRESH_TOKEN: string = 'relay_refresh_token'
const KEY_EXPIRES_AT: string = 'relay_expires_at'
const KEY_ACCOUNT_KEY: string = 'relay_account_key'
const KEY_SERVER_VERSION: string = 'relay_server_version'
const KEY_CAPABILITIES: string = 'relay_capabilities'

/** 纯函数：拼接图片中继 URL（供单元测试与实例方法共用） */
export function buildRelayImageUrl(serverUrl: string, pixivUrl: string): string {
  let base = serverUrl.trim()
  if (base.endsWith('/')) {
    base = base.substring(0, base.length - 1)
  }
  return base + '/img/v1/fetch?url=' + encodeURIComponent(pixivUrl)
}

/** 纯函数：构造一个空的 http.PerformanceTiming（解包响应时需要） */
export function emptyPerformanceTiming(): http.PerformanceTiming {
  let timing: http.PerformanceTiming = {
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
  return timing
}

interface RawRelayEnvelope {
  status?: number
  headers?: Record<string, string>
  bodyBase64?: string
}

export class RelayClient {
  private static instance: RelayClient
  /** 502/超时连续失败计数（成功清零） */
  private consecutiveFailures: number = 0
  private isRefreshing: boolean = false

  private constructor() {
  }

  static getInstance(): RelayClient {
    if (!RelayClient.instance) {
      RelayClient.instance = new RelayClient()
    }
    return RelayClient.instance
  }

  // ---------------- 配置与状态 ----------------

  /** 中继服务器地址（来自 AppSettings.relayServerUrl，归一化去掉尾部斜杠） */
  getServerUrl(): string {
    let url = userSettingStore.getSettings().relayServerUrl.trim()
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1)
    }
    return url
  }

  isRegistered(): boolean {
    return preferenceService.getString(KEY_REFRESH_TOKEN, '').length > 0
  }

  getAccountKey(): string {
    return preferenceService.getString(KEY_ACCOUNT_KEY, '')
  }

  getServerVersion(): string {
    return preferenceService.getString(KEY_SERVER_VERSION, '')
  }

  getCapabilities(): string[] {
    try {
      let raw = preferenceService.getString(KEY_CAPABILITIES, '[]')
      return JSON.parse(raw) as string[]
    } catch (e) {
      console.error('getCapabilities parse failed: ' + e)
      return []
    }
  }

  hasCapability(name: string): boolean {
    return this.getCapabilities().includes(name)
  }

  /** 注销：清空 relay_* 凭据（保留 relayServerUrl 配置） */
  logout(): void {
    preferenceService.delete(KEY_ACCESS_TOKEN)
    preferenceService.delete(KEY_REFRESH_TOKEN)
    preferenceService.delete(KEY_EXPIRES_AT)
    preferenceService.delete(KEY_ACCOUNT_KEY)
    preferenceService.delete(KEY_SERVER_VERSION)
    preferenceService.delete(KEY_CAPABILITIES)
    this.consecutiveFailures = 0
  }

  // ---------------- 服务认证 ----------------

  /**
   * 设备注册（可选 inviteCode / accountKey 导入已有账号）。
   * 失败抛 Error，消息含服务端 error.message（供设置页展示）。
   */
  async register(serverUrl: string, deviceName: string, inviteCode?: string, accountKey?: string): Promise<RelayRegisterResult> {
    let base = serverUrl.trim()
    if (base.endsWith('/')) {
      base = base.substring(0, base.length - 1)
    }
    if (base.length === 0) {
      throw new Error(getStr($r('app.string.net_relay_no_server')))
    }
    let fields: Record<string, string> = { 'deviceName': deviceName }
    if (inviteCode !== undefined && inviteCode.length > 0) {
      fields['inviteCode'] = inviteCode
    }
    if (accountKey !== undefined && accountKey.length > 0) {
      fields['accountKey'] = accountKey
    }
    let header: Record<string, string> = { 'Content-Type': 'application/json' }
    let response = await this.rawRequest(base + '/auth/v1/register', http.RequestMethod.POST, header, JSON.stringify(fields))
    let body = String(response.result)
    if (response.responseCode !== 200) {
      let errInfo = parseRelayError(body)
      throw new Error(errInfo.message.length > 0 ? errInfo.message :
        getStrf($r('app.string.net_relay_register_failed'), response.responseCode))
    }
    let result = relayRegisterResultFromJson(JSON.parse(body))
    if (result.accessToken.length === 0 || result.refreshToken.length === 0) {
      throw new Error(getStr($r('app.string.net_relay_register_invalid')))
    }
    // 注册成功后持久化服务器地址 + 令牌对 + accountKey + capabilities
    userSettingStore.setRelayServerUrl(base)
    preferenceService.setString(KEY_ACCESS_TOKEN, result.accessToken)
    preferenceService.setString(KEY_REFRESH_TOKEN, result.refreshToken)
    preferenceService.setNumber(KEY_EXPIRES_AT, Date.now() + result.expiresIn * 1000)
    preferenceService.setString(KEY_ACCOUNT_KEY, result.accountKey)
    preferenceService.setString(KEY_SERVER_VERSION, result.serverVersion)
    preferenceService.setString(KEY_CAPABILITIES, JSON.stringify(result.capabilities))
    this.consecutiveFailures = 0
    return result
  }

  /**
   * 轮换制刷新服务令牌对并写回。
   * 注意：refresh 响应不含 accountKey（注册时已持有），不覆盖本地值。
   * 401/400（INVALID_TOKEN）清空凭据并返回 false；其余错误抛 NetworkError 语义异常。
   */
  async refreshAccessToken(): Promise<boolean> {
    if (this.isRefreshing) {
      return false
    }
    let refreshToken = preferenceService.getString(KEY_REFRESH_TOKEN, '')
    if (refreshToken.length === 0) {
      return false
    }
    let base = this.getServerUrl()
    if (base.length === 0) {
      return false
    }
    this.isRefreshing = true
    try {
      let fields: Record<string, string> = { 'refreshToken': refreshToken }
      let header: Record<string, string> = { 'Content-Type': 'application/json' }
      let response = await this.rawRequest(base + '/auth/v1/refresh', http.RequestMethod.POST, header, JSON.stringify(fields))
      let body = String(response.result)
      if (response.responseCode !== 200) {
        // api.md：refreshToken 无效/过期 → 401 INVALID_TOKEN；400 为参数错误（VALIDATION_FAILED），按异常上抛
        if (response.responseCode === 401) {
          // 服务令牌彻底失效：清空凭据，停留设置页引导重新注册/导入
          this.logout()
          return false
        }
        throw new Error(getStrf($r('app.string.net_relay_token_refresh_failed'), response.responseCode))
      }
      let result = relayRegisterResultFromJson(JSON.parse(body))
      if (result.accessToken.length === 0 || result.refreshToken.length === 0) {
        throw new Error(getStr($r('app.string.net_relay_token_refresh_invalid')))
      }
      preferenceService.setString(KEY_ACCESS_TOKEN, result.accessToken)
      preferenceService.setString(KEY_REFRESH_TOKEN, result.refreshToken)
      if (result.expiresIn > 0) {
        preferenceService.setNumber(KEY_EXPIRES_AT, Date.now() + result.expiresIn * 1000)
      }
      return true
    } finally {
      this.isRefreshing = false
    }
  }

  /** 获取有效服务令牌（过期前自动刷新）；不可用返回空串 */
  async getValidToken(): Promise<string> {
    let token = preferenceService.getString(KEY_ACCESS_TOKEN, '')
    let expiresAt = preferenceService.getNumber(KEY_EXPIRES_AT, 0)
    if (token.length === 0) {
      return ''
    }
    if (Date.now() >= expiresAt - TOKEN_REFRESH_MARGIN_MS) {
      let ok = await this.refreshAccessToken()
      if (!ok) {
        return ''
      }
      token = preferenceService.getString(KEY_ACCESS_TOKEN, '')
    }
    return token
  }

  // ---------------- Relay 请求 ----------------

  /**
   * 包装/解包中继请求（供 HttpClient.doRequest relay 分支调用）。
   * - 包装 method/url/白名单头/bodyBase64 → POST {relay}/relay/v1/request
   * - 注入服务级 Authorization: Bearer <relayAccessToken>
   * - 外层 401：自动刷新一次并重放；仍失败抛 RelayAuthError
   * - 外层 502/网络异常：连续计数 ≥3 toast + 回落上一可用模式；成功清零
   */
  async relayRequest(input: RelayRequestInput): Promise<http.HttpResponse> {
    let base = this.getServerUrl()
    if (base.length === 0) {
      throw new Error(getStr($r('app.string.net_relay_not_configured')))
    }
    if (!input.url.startsWith('https://')) {
      // 服务端强制 https URL，否则 400；客户端提前拦截
      throw new Error(getStrf($r('app.string.net_relay_https_only'), input.url))
    }
    let token = await this.getValidToken()
    if (token.length === 0) {
      throw new RelayAuthError(getStr($r('app.string.net_relay_auth_required')))
    }
    let response = await this.doRelayPost(base, input, token)
    if (response.responseCode === 401) {
      // 服务令牌 401：刷新一次并重放
      let refreshed = await this.refreshAccessToken()
      if (refreshed) {
        let newToken = preferenceService.getString(KEY_ACCESS_TOKEN, '')
        response = await this.doRelayPost(base, input, newToken)
      }
      if (response.responseCode === 401) {
        throw new RelayAuthError(getStr($r('app.string.net_relay_auth_expired')))
      }
    }
    if (response.responseCode === 502) {
      this.recordFailure()
      throw new Error(getStr($r('app.string.net_relay_server_502')))
    }
    if (response.responseCode !== 200) {
      let errInfo = parseRelayError(String(response.result))
      let msg = errInfo.message.length > 0 ? errInfo.message :
        getStrf($r('app.string.net_relay_request_failed'), response.responseCode)
      throw new Error(msg)
    }
    this.resetFailures()
    return this.unwrapEnvelope(String(response.result))
  }

  /** 图片中继 URL 包装（/img/v1/fetch?url=）；已是本中继 URL 的不重复包装（recover 返回的 pages[].url 即为此形式） */
  buildImageUrl(pixivUrl: string): string {
    let base = this.getServerUrl()
    if (base.length > 0 && pixivUrl.startsWith(base + '/img/v1/fetch')) {
      return pixivUrl
    }
    return buildRelayImageUrl(base, pixivUrl)
  }

  /**
   * 中继已认证请求（同步/恢复等非包装端点共用）：
   * 注入服务级 Bearer；外层 401 自动刷新一次重放，仍失败抛 RelayAuthError；
   * 其余状态码（含 409 SYNC_FULL_REQUIRED / 429 RATE_LIMITED）原样返回给调用方处理。
   */
  async authorizedRequest(path: string, method: http.RequestMethod, body?: string): Promise<http.HttpResponse> {
    let base = this.getServerUrl()
    if (base.length === 0) {
      throw new Error(getStr($r('app.string.net_relay_not_configured')))
    }
    let token = await this.getValidToken()
    if (token.length === 0) {
      throw new RelayAuthError(getStr($r('app.string.net_relay_auth_required')))
    }
    let header: Record<string, string> = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ' + token
    }
    let response = await this.rawRequest(base + path, method, header, body)
    if (response.responseCode === 401) {
      let refreshed = await this.refreshAccessToken()
      if (refreshed) {
        let newToken = preferenceService.getString(KEY_ACCESS_TOKEN, '')
        header['Authorization'] = 'Bearer ' + newToken
        response = await this.rawRequest(base + path, method, header, body)
      }
      if (response.responseCode === 401) {
        throw new RelayAuthError(getStr($r('app.string.net_relay_auth_expired')))
      }
    }
    return response
  }

  /** relay 模式图片请求头（仅注入服务级 Bearer，不注入 Referer/User-Agent） */
  async buildImageAuthHeader(): Promise<Record<string, string>> {
    let header: Record<string, string> = {}
    let token = await this.getValidToken()
    if (token.length > 0) {
      header['Authorization'] = 'Bearer ' + token
    }
    return header
  }

  // ---------------- 内部实现 ----------------

  private async doRelayPost(base: string, input: RelayRequestInput, token: string): Promise<http.HttpResponse> {
    let method: string = input.method ?? 'GET'
    let forwardHeaders = this.filterForwardHeaders(input.header)
    let bodyBase64 = ''
    if (input.body !== undefined) {
      let bodyStr = typeof input.body === 'string' ? input.body : JSON.stringify(input.body)
      bodyBase64 = buffer.from(bodyStr, 'utf-8').toString('base64')
    }
    let envelope: Record<string, Object> = {
      'method': method,
      'url': input.url,
      'headers': forwardHeaders,
      'bodyBase64': bodyBase64,
      'timeoutMs': 30000
    }
    let header: Record<string, string> = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ' + token
    }
    try {
      return await this.rawRequest(base + '/relay/v1/request', http.RequestMethod.POST, header, JSON.stringify(envelope))
    } catch (e) {
      // 网络异常（超时/断网）计入连续失败
      this.recordFailure()
      if (e instanceof Error) {
        throw e
      }
      throw new Error(String(e))
    }
  }

  private filterForwardHeaders(header: Record<string, string> | undefined): Record<string, string> {
    let out: Record<string, string> = {}
    if (!header) {
      return out
    }
    let keys = Object.keys(header)
    for (let i = 0; i < keys.length; i++) {
      let key = keys[i]
      if (RELAY_FORWARD_HEADERS.includes(key.toLowerCase())) {
        out[key] = header[key]
      }
    }
    return out
  }

  /** 解包中继信封：{status, headers(小写键白名单), bodyBase64} → 还原原始 http.HttpResponse */
  private unwrapEnvelope(body: string): http.HttpResponse {
    let raw = JSON.parse(body) as RawRelayEnvelope
    let status = raw?.status ?? 0
    let bodyText = ''
    if (raw?.bodyBase64 && raw.bodyBase64.length > 0) {
      bodyText = buffer.from(raw.bodyBase64, 'base64').toString('utf-8')
    }
    let headers: Record<string, string> = {}
    if (raw?.headers) {
      for (let i = 0; i < RELAY_RESPONSE_HEADERS.length; i++) {
        let name = RELAY_RESPONSE_HEADERS[i]
        let value = raw.headers[name]
        if (value !== undefined) {
          headers[name] = value
        }
      }
    }
    let resp: http.HttpResponse = {
      result: bodyText,
      resultType: http.HttpDataType.STRING,
      responseCode: status,
      header: headers,
      cookies: '',
      performanceTiming: emptyPerformanceTiming()
    }
    return resp
  }

  private recordFailure(): void {
    this.consecutiveFailures++
    if (this.consecutiveFailures >= RELAY_FAILURE_FALLBACK_THRESHOLD) {
      this.consecutiveFailures = 0
      this.fallbackToPreviousMode()
    }
  }

  private resetFailures(): void {
    this.consecutiveFailures = 0
  }

  /** FR-008：连续失败后回落到上一可用模式（仅对当前为 relay 的开关生效，保留 relayServerUrl 配置） */
  private fallbackToPreviousMode(): void {
    try {
      let settings = userSettingStore.getSettings()
      if (Constants.isRelayMode(settings.authMode)) {
        userSettingStore.setAuthMode(settings.prevAuthMode)
      }
      if (Constants.isRelayMode(settings.apiMode)) {
        userSettingStore.setApiMode(settings.prevApiMode)
      }
      promptAction.showToast({ message: getStr($r('app.string.net_relay_fallback_toast')) })
    } catch (e) {
      console.error('Relay fallback failed: ' + e)
    }
  }

  /** 裸 HTTP 请求（不经 HttpClient，避免拦截器链注入 Pixiv 头 / 递归分流） */
  private rawRequest(url: string, method: http.RequestMethod, header: Record<string, string>, body?: string): Promise<http.HttpResponse> {
    let client = http.createHttp()
    let reqOptions: http.HttpRequestOptions = {
      method: method,
      header: header,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 30000,
      readTimeout: 30000
    }
    if (body !== undefined) {
      reqOptions.extraData = body
    }
    return new Promise((resolve, reject) => {
      client.request(url, reqOptions, (err: BusinessError, data: http.HttpResponse) => {
        client.destroy()
        if (!err) {
          resolve(data)
        } else {
          reject(err)
        }
      })
    })
  }
}

export const relayClient = RelayClient.getInstance()
