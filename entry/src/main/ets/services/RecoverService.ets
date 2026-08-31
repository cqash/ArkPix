import { http } from '@kit.NetworkKit';
import { relayClient } from '../network/RelayClient';
import { getStrf } from '../utils/I18nUtils';
import {
  RecoverResult,
  recoverResultFromJson,
  parseRelayError,
  RECOVER_STATUS_READY,
  RECOVER_STATUS_FETCHING,
  RECOVER_STATUS_NOT_FOUND
} from '../models/RelayModels';

/** 轮询被取消时的结果状态（非服务端状态，客户端本地语义） */
export const RECOVER_STATUS_CANCELLED: string = 'cancelled'

/** 恢复轮询取消令牌：cancel() 立即中断等待中的 sleep */
export class RecoverPollToken {
  cancelled: boolean = false
  timerId: number = -1
  onWake: (() => void) | null = null

  cancel(): void {
    this.cancelled = true
    if (this.timerId >= 0) {
      clearTimeout(this.timerId)
      this.timerId = -1
    }
    if (this.onWake !== null) {
      let wake = this.onWake
      this.onWake = null
      wake()
    }
  }
}

export class RecoverService {
  private static instance: RecoverService

  private constructor() {
  }

  static getInstance(): RecoverService {
    if (!RecoverService.instance) {
      RecoverService.instance = new RecoverService()
    }
    return RecoverService.instance
  }

  /**
   * 恢复查询：GET {relay}/recover/v1/illust/{pid}（relay Bearer 鉴权）。
   * 200 ready / 202 fetching(retryAfterSec) / 404 not_found 三态映射 RecoverResult；
   * 其余状态码抛 Error（含服务端 error.message）。
   */
  async query(pid: number): Promise<RecoverResult> {
    let resp = await relayClient.authorizedRequest('/recover/v1/illust/' + pid, http.RequestMethod.GET)
    if (resp.responseCode === 200 || resp.responseCode === 202 || resp.responseCode === 404) {
      let body = String(resp.result)
      let parsed: Object = body.length > 0 ? JSON.parse(body) : JSON.parse('{}')
      return recoverResultFromJson(parsed, resp.responseCode)
    }
    let errInfo = parseRelayError(String(resp.result))
    throw new Error(errInfo.message.length > 0 ? errInfo.message :
      getStrf($r('app.string.svc_recover_query_failed'), resp.responseCode))
  }

  /**
   * 按 retryAfterSec 间隔轮询直至 ready / not_found / 达到 maxAttempts / 被取消。
   * onProgress(attempt, retryAfterSec) 在每次进入等待前回调。
   */
  async pollUntilReady(pid: number, onProgress?: (attempt: number, retryAfterSec: number) => void,
    maxAttempts: number = 30, token?: RecoverPollToken): Promise<RecoverResult> {
    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      if (token !== undefined && token.cancelled) {
        return new RecoverResult({ status: RECOVER_STATUS_CANCELLED })
      }
      let result = await this.query(pid)
      if (result.status === RECOVER_STATUS_READY || result.status === RECOVER_STATUS_NOT_FOUND) {
        return result
      }
      // fetching：等待 retryAfterSec 后下一轮
      if (onProgress !== undefined) {
        onProgress(attempt, result.retryAfterSec)
      }
      await this.sleep(result.retryAfterSec * 1000, token)
      if (token !== undefined && token.cancelled) {
        return new RecoverResult({ status: RECOVER_STATUS_CANCELLED })
      }
    }
    // 超过最大轮询次数仍未就绪，按 not_found 语义交由上层提示
    return new RecoverResult({ status: RECOVER_STATUS_NOT_FOUND })
  }

  private sleep(ms: number, token?: RecoverPollToken): Promise<void> {
    return new Promise<void>((resolve) => {
      if (token !== undefined) {
        token.onWake = () => {
          resolve()
        }
        token.timerId = setTimeout(() => {
          token.timerId = -1
          token.onWake = null
          resolve()
        }, ms)
      } else {
        setTimeout(() => {
          resolve()
        }, ms)
      }
    })
  }
}

export const recoverService = RecoverService.getInstance()
