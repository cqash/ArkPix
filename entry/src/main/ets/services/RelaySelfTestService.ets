import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { relayClient, RelayAuthError, RelayRequestInput } from '../network/RelayClient';
import { parseRelayError } from '../models/RelayModels';
import { getStr, getStrf } from '../utils/I18nUtils';

/** 自检项状态 */
export const SELF_TEST_PENDING: string = 'pending'
export const SELF_TEST_RUNNING: string = 'running'
export const SELF_TEST_PASSED: string = 'passed'
export const SELF_TEST_FAILED: string = 'failed'
export const SELF_TEST_SKIPPED: string = 'skipped'

export interface SelfTestItemResult {
  name: string
  status: string
  durationMs: number
  /** 失败时的 HTTP 状态码（无则 0） */
  httpStatus: number
  /** 服务端 error.code（无则空串） */
  errorCode: string
  /** 服务端 error.message 或本地错误描述 */
  errorMessage: string
  /** 通过时的补充说明（如 recover 实际命中的状态） */
  detail: string
}

// 自检固定小图：Pixiv 默认头像（长期稳定存在；原 novel_bg.png 上游已 404）
const SELF_TEST_IMAGE_URL: string = 'https://s.pximg.net/common/images/no_profile.png'

function makeItem(name: string): SelfTestItemResult {
  let item: SelfTestItemResult = {
    name: name,
    status: SELF_TEST_PENDING,
    durationMs: 0,
    httpStatus: 0,
    errorCode: '',
    errorMessage: '',
    detail: ''
  }
  return item
}

/**
 * 后端自检：逐项探测六个端点是否全部实现并可用。
 * 前项失败则后续依赖项标记跳过（healthz 失败跳过全部；令牌失败跳过 3–6）。
 */
export class RelaySelfTestService {
  private static instance: RelaySelfTestService

  private constructor() {
  }

  static getInstance(): RelaySelfTestService {
    if (!RelaySelfTestService.instance) {
      RelaySelfTestService.instance = new RelaySelfTestService()
    }
    return RelaySelfTestService.instance
  }

  /** 初始 6 项（pending），供 UI 先渲染占位 */
  initialResults(): SelfTestItemResult[] {
    return [
      makeItem(getStr($r('app.string.svc_selftest_health'))),
      makeItem(getStr($r('app.string.svc_selftest_token'))),
      makeItem(getStr($r('app.string.svc_selftest_relay'))),
      makeItem(getStr($r('app.string.svc_selftest_image'))),
      makeItem(getStr($r('app.string.svc_selftest_sync'))),
      makeItem(getStr($r('app.string.svc_selftest_recover')))
    ]
  }

  /** 逐项执行，每项结束后经 onUpdate 回调最新结果数组（实时刷新 UI） */
  async runAll(onUpdate: (results: SelfTestItemResult[]) => void): Promise<void> {
    let results = this.initialResults()
    onUpdate(results.slice())

    // 1. 存活探针
    let healthOk = await this.runItem(results, 0, onUpdate, (item: SelfTestItemResult) => this.checkHealth(item))
    if (!healthOk) {
      this.skipRange(results, 1, 5, getStr($r('app.string.svc_selftest_health_unreachable')))
      onUpdate(results.slice())
      return
    }

    // 2. 服务令牌（401 自动刷新链路走 RelayClient.authorizedRequest 既有实现）
    let tokenOk = await this.runItem(results, 1, onUpdate, (item: SelfTestItemResult) => this.checkToken(item))
    if (!tokenOk) {
      this.skipRange(results, 2, 5, getStr($r('app.string.svc_selftest_token_unusable')))
      onUpdate(results.slice())
      return
    }

    // 3–6 顺序执行（相互独立）
    await this.runItem(results, 2, onUpdate, (item: SelfTestItemResult) => this.checkRelay(item))
    await this.runItem(results, 3, onUpdate, (item: SelfTestItemResult) => this.checkImage(item))
    await this.runItem(results, 4, onUpdate, (item: SelfTestItemResult) => this.checkSyncLoop(item))
    await this.runItem(results, 5, onUpdate, (item: SelfTestItemResult) => this.checkRecover(item))
  }

  /** 统计通过数（UI 总结论用） */
  countPassed(results: SelfTestItemResult[]): number {
    let n = 0
    for (let i = 0; i < results.length; i++) {
      if (results[i].status === SELF_TEST_PASSED) {
        n++
      }
    }
    return n
  }

  // ---------------- 内部框架 ----------------

  private skipRange(results: SelfTestItemResult[], from: number, to: number, reason: string): void {
    for (let i = from; i <= to; i++) {
      results[i].status = SELF_TEST_SKIPPED
      results[i].errorMessage = reason
      results[i] = this.copyItem(results[i])
    }
  }

  /**
   * 复制 item 为新对象引用。
   * UI 侧 ForEach 以 key 复用子组件、且 item 为普通对象（非 @Observed），
   * 原地改属性不会触发行刷新，必须替换元素引用（配合 UI keyGenerator 含 status）。
   */
  private copyItem(item: SelfTestItemResult): SelfTestItemResult {
    let copy: SelfTestItemResult = {
      name: item.name,
      status: item.status,
      durationMs: item.durationMs,
      httpStatus: item.httpStatus,
      errorCode: item.errorCode,
      errorMessage: item.errorMessage,
      detail: item.detail
    }
    return copy
  }

  private async runItem(results: SelfTestItemResult[], index: number,
    onUpdate: (results: SelfTestItemResult[]) => void,
    check: (item: SelfTestItemResult) => Promise<boolean>): Promise<boolean> {
    let item = this.copyItem(results[index])
    item.status = SELF_TEST_RUNNING
    results[index] = this.copyItem(item)
    onUpdate(results.slice())
    let start = Date.now()
    let ok = false
    try {
      ok = await check(item)
    } catch (e) {
      ok = false
      if (e instanceof RelayAuthError) {
        item.errorCode = 'INVALID_TOKEN'
        item.errorMessage = e.message
      } else {
        item.errorMessage = e instanceof Error ? e.message : String(e)
        // 从 "HTTP xxx" 文案中提取状态码
        let m = item.errorMessage.indexOf('HTTP ')
        if (m >= 0) {
          let code = Number(item.errorMessage.substring(m + 5, m + 8))
          if (!Number.isNaN(code)) {
            item.httpStatus = Math.floor(code)
          }
        }
      }
    }
    item.durationMs = Date.now() - start
    item.status = ok ? SELF_TEST_PASSED : SELF_TEST_FAILED
    results[index] = this.copyItem(item)
    onUpdate(results.slice())
    return ok
  }

  // ---------------- 检查项 ----------------

  /** 1. GET /healthz（无鉴权，期望 200 {status:"ok"}） */
  private async checkHealth(item: SelfTestItemResult): Promise<boolean> {
    let base = relayClient.getServerUrl()
    if (base.length === 0) {
      item.errorMessage = getStr($r('app.string.svc_selftest_no_server'))
      return false
    }
    let header: Record<string, string> = {}
    let resp = await this.rawGet(base + '/healthz', header)
    item.httpStatus = resp.responseCode
    if (resp.responseCode !== 200) {
      this.fillServerError(item, String(resp.result))
      return false
    }
    let body = String(resp.result)
    if (body.indexOf('"ok"') < 0) {
      item.errorMessage = getStr($r('app.string.svc_selftest_missing_ok'))
      return false
    }
    item.detail = getStr($r('app.string.svc_selftest_alive'))
    return true
  }

  /** 2. 服务令牌有效性（轻量鉴权端点；401 自动刷新链路即 RelayClient 既有实现） */
  private async checkToken(item: SelfTestItemResult): Promise<boolean> {
    let resp = await relayClient.authorizedRequest('/sync/v1/pull?domain=settings&limit=1', http.RequestMethod.GET)
    item.httpStatus = resp.responseCode
    if (resp.responseCode !== 200) {
      this.fillServerError(item, String(resp.result))
      return false
    }
    item.detail = getStr($r('app.string.svc_selftest_token_valid'))
    return true
  }

  /** 3. POST /relay/v1/request：包装无害上游请求（GET app-api walkthrough，不带 Pixiv token） */
  private async checkRelay(item: SelfTestItemResult): Promise<boolean> {
    // 探针目标用 app-api 而非 www.pixiv.net：www 根路径经部分代理出口会被 Cloudflare 拦出 500，
    // 而 walkthrough 免鉴权稳定 200；200/401/403 任一明确响应都证明中继链路通
    let input: RelayRequestInput = {
      url: 'https://app-api.pixiv.net/v1/walkthrough/illusts',
      method: http.RequestMethod.GET,
      header: {}
    }
    let resp = await relayClient.relayRequest(input)
    let upstream = resp.responseCode
    item.httpStatus = upstream
    if (upstream === 200 || upstream === 401 || upstream === 403) {
      item.detail = getStrf($r('app.string.svc_selftest_upstream_detail'), upstream)
      return true
    }
    item.errorMessage = getStrf($r('app.string.svc_selftest_upstream_unexpected'), upstream)
    return false
  }

  /** 4. GET /img/v1/fetch：固定小图，期望 200 且 Content-Type 为图片 */
  private async checkImage(item: SelfTestItemResult): Promise<boolean> {
    let url = relayClient.buildImageUrl(SELF_TEST_IMAGE_URL)
    let header = await relayClient.buildImageAuthHeader()
    let resp = await this.rawGet(url, header)
    item.httpStatus = resp.responseCode
    if (resp.responseCode !== 200) {
      this.fillServerError(item, String(resp.result))
      return false
    }
    let contentType = this.headerValue(resp.header, 'content-type')
    if (contentType.indexOf('image') < 0) {
      item.errorMessage = getStrf($r('app.string.svc_selftest_content_type_not_image'), contentType)
      return false
    }
    item.detail = 'Content-Type: ' + contentType
    return true
  }

  /** 5. sync 回环：push __selftest__ 条目 → pull 回读 → push 墓碑清理 */
  private async checkSyncLoop(item: SelfTestItemResult): Promise<boolean> {
    let key = '__selftest__' + Date.now().toString()
    let now = Date.now()
    let itemData: Record<string, Object> = { 'keyword': '__selftest__', 'searchType': 'illust' }
    let syncItem: Record<string, Object> = { 'key': key, 'data': itemData, 'updatedAt': now, 'deleted': false }
    let pushBody: Record<string, Object> = {
      'domain': 'search_history',
      'baseToken': '',
      'items': [syncItem]
    }
    let pushResp = await relayClient.authorizedRequest('/sync/v1/push', http.RequestMethod.POST, JSON.stringify(pushBody))
    item.httpStatus = pushResp.responseCode
    if (pushResp.responseCode !== 200) {
      // 400/404/409 分别报告（错误体含 code）
      this.fillServerError(item, String(pushResp.result))
      if (item.errorMessage.length === 0) {
        item.errorMessage = getStrf($r('app.string.svc_selftest_push_failed'), pushResp.responseCode)
      }
      return false
    }
    // pull 回读（全量 since=''，最多翻 10 页）
    let found = false
    let since = ''
    for (let page = 0; page < 10 && !found; page++) {
      let pullPath = '/sync/v1/pull?domain=search_history&since=' + encodeURIComponent(since) + '&limit=100'
      let pullResp = await relayClient.authorizedRequest(pullPath, http.RequestMethod.GET)
      if (pullResp.responseCode !== 200) {
        item.httpStatus = pullResp.responseCode
        this.fillServerError(item, String(pullResp.result))
        await this.cleanupSyncItem(key)
        return false
      }
      let raw = JSON.parse(String(pullResp.result)) as RawSelfTestPull
      let items = raw?.items ?? []
      for (let i = 0; i < items.length; i++) {
        if (items[i].key === key) {
          found = true
          break
        }
      }
      let nextToken = raw?.syncToken ?? ''
      if ((raw?.hasMore ?? false) && nextToken.length > 0) {
        since = nextToken
      } else {
        break
      }
    }
    // 无论是否回读到，都推墓碑清理
    await this.cleanupSyncItem(key)
    if (!found) {
      item.errorMessage = getStr($r('app.string.svc_selftest_pull_missed'))
      return false
    }
    item.detail = getStr($r('app.string.svc_selftest_loop_ok'))
    return true
  }

  private async cleanupSyncItem(key: string): Promise<void> {
    try {
      let tombstone: Record<string, Object> = { 'key': key, 'data': JSON.parse('{}'), 'updatedAt': Date.now(), 'deleted': true }
      let body: Record<string, Object> = { 'domain': 'search_history', 'baseToken': '', 'items': [tombstone] }
      await relayClient.authorizedRequest('/sync/v1/push', http.RequestMethod.POST, JSON.stringify(body))
    } catch (e) {
      console.error('Self-test cleanup failed: ' + e)
    }
  }

  /** 6. GET /recover/v1/illust/1：200/202/404 且 JSON 结构合法即端点可用，展示实际命中状态 */
  private async checkRecover(item: SelfTestItemResult): Promise<boolean> {
    let resp = await relayClient.authorizedRequest('/recover/v1/illust/1', http.RequestMethod.GET)
    item.httpStatus = resp.responseCode
    if (resp.responseCode === 200 || resp.responseCode === 202 || resp.responseCode === 404) {
      try {
        let raw = JSON.parse(String(resp.result)) as RawSelfTestRecover
        let status = raw?.status ?? ''
        if (status === 'ready' || status === 'fetching' || status === 'not_found') {
          item.detail = getStrf($r('app.string.svc_selftest_endpoint_hit'), status, resp.responseCode)
          return true
        }
        item.errorMessage = getStrf($r('app.string.svc_selftest_bad_status'), status)
        return false
      } catch (e) {
        item.errorMessage = getStr($r('app.string.svc_selftest_json_parse'))
        return false
      }
    }
    this.fillServerError(item, String(resp.result))
    return false
  }

  // ---------------- 工具 ----------------

  private fillServerError(item: SelfTestItemResult, body: string): void {
    let info = parseRelayError(body)
    item.errorCode = info.code
    item.errorMessage = info.message
  }

  private headerValue(header: Object, name: string): string {
    try {
      let rec = header as Record<string, Object>
      let keys = Object.keys(rec)
      for (let i = 0; i < keys.length; i++) {
        if (keys[i].toLowerCase() === name) {
          return String(rec[keys[i]])
        }
      }
    } catch (e) {
      console.error('headerValue failed: ' + e)
    }
    return ''
  }

  private rawGet(url: string, header: Record<string, string>): Promise<http.HttpResponse> {
    let client = http.createHttp()
    let reqOptions: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: header,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 30000
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

interface RawSelfTestPullItem {
  key?: string
}

interface RawSelfTestPull {
  items?: RawSelfTestPullItem[]
  syncToken?: string
  hasMore?: boolean
}

interface RawSelfTestRecover {
  status?: string
}

export const relaySelfTestService = RelaySelfTestService.getInstance()
