import { IllustListPage } from '../components/illust/IllustWaterfall';

/**
 * 详情页作品间滑动的列表上下文注册表（纯内存，模块级 Map）。
 * 列表页（IllustWaterfall）默认 onCardClick 时先注册当前列表上下文，
 * 再向详情页传递轻量标量参数 { illustId, contextToken, contextIndex }；
 * 详情页凭 token 取回 ids 序列与续页闭包，驱动 Swiper 作品间滑动与末尾预取。
 */
export interface DetailListContext {
  ids: number[]
  nextUrl: string
  fetchNext: (nextUrl: string) => Promise<IllustListPage>
}

let contexts: Map<string, DetailListContext> = new Map<string, DetailListContext>()
let tokenCounter: number = 0

/** 上限保护：防止无限注册导致内存膨胀（同 session 内保留最近若干上下文） */
const MAX_CONTEXTS: number = 8

export class DetailListContextRegistry {
  static register(ctx: DetailListContext): string {
    tokenCounter += 1
    let token = 'ctx_' + tokenCounter.toString() + '_' + Date.now().toString()
    if (contexts.size >= MAX_CONTEXTS) {
      let firstKey = contexts.keys().next().value as string
      contexts.delete(firstKey)
    }
    contexts.set(token, ctx)
    return token
  }

  static get(token: string): DetailListContext | null {
    let ctx = contexts.get(token)
    if (ctx === undefined) {
      return null
    }
    return ctx
  }

  /** 末尾预取成功后追加续页数据到既有上下文 */
  static append(token: string, page: IllustListPage): void {
    let ctx = contexts.get(token)
    if (ctx === undefined) {
      return
    }
    for (let i = 0; i < page.illusts.length; i++) {
      ctx.ids.push(page.illusts[i].id)
    }
    ctx.nextUrl = page.nextUrl
  }

  static remove(token: string): void {
    contexts.delete(token)
  }
}
