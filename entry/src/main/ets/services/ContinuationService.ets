import { Want } from '@kit.AbilityKit';
import {
  ContinuationPayload,
  CONTINUATION_PAYLOAD_KEY,
  CONTINUATION_PAYLOAD_VERSION,
  buildContinuationPayloadJson,
  parseContinuationPayloadJson
} from '../models/ContinuationPayload';

/**
 * 多端流转（应用接续）页面状态登记与载荷编排骨架。
 * 页面主动登记模式：aboutToAppear 登记 / aboutToDisappear 清除（router 无 API 查询栈顶业务参数）。
 * 纯内存 + AppStorage，不依赖 PreferenceService，可无 lazy 直接 import（EntryAbility 安全）。
 */
export class ContinuationService {
  private static instance: ContinuationService
  /** 当前页面登记的接续状态（null = 未覆盖页面，接续时仅传版本号回退主页） */
  private currentState: ContinuationPayload | null = null

  private constructor() {
  }

  static getInstance(): ContinuationService {
    if (!ContinuationService.instance) {
      ContinuationService.instance = new ContinuationService()
    }
    return ContinuationService.instance
  }

  /** 页面登记/清除当前接续状态 */
  setCurrentPageState(state: ContinuationPayload | null): void {
    this.currentState = state
  }

  /**
   * onContinue 调用：构建 wantParam 写入内容。
   * 无登记状态时返回仅含载荷版本的最小载荷（对端回退主页）。
   */
  buildWantParam(): Record<string, Object> {
    let state = this.currentState
    if (state === null) {
      state = new ContinuationPayload({ version: CONTINUATION_PAYLOAD_VERSION, page: '' })
    }
    let json = buildContinuationPayloadJson(state)
    // 编码断言：接续 wantParam 硬限制 100KB（本载荷设计 <200 字节，超限即实现偏离）
    if (json.length > 100 * 1024) {
      console.error('Continuation payload exceeds 100KB limit: ' + json.length)
    }
    let param: Record<string, Object> = {}
    param[CONTINUATION_PAYLOAD_KEY] = json
    return param
  }

  /** 对端解析 want 中的接续载荷；缺失/非法返回 null */
  parseWant(want: Want): ContinuationPayload | null {
    let params = want.parameters
    if (params === undefined) {
      return null
    }
    let raw = params[CONTINUATION_PAYLOAD_KEY]
    if (typeof raw !== 'string') {
      return null
    }
    return parseContinuationPayloadJson(raw)
  }

  /** SplashPage 一次性消费 AppStorage 中的接续载荷并清除（消费后不再影响后续路由） */
  consumePendingPayload(): ContinuationPayload | null {
    let payload = AppStorage.get<ContinuationPayload>(CONTINUATION_PAYLOAD_KEY)
    if (payload === undefined) {
      return null
    }
    AppStorage.delete(CONTINUATION_PAYLOAD_KEY)
    return payload
  }
}

export const continuationService = ContinuationService.getInstance()
