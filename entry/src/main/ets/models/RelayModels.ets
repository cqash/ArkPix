import { Illust, Tag } from './Illust'
import { pickDetailUrl } from '../utils/ImageUrlUtils'

/**
 * Relay Server 客户端模型集。
 * 协议契约以 docs/backend-design.md v1.0 为准（pix_backend）。
 * 遵循项目 fromJson → Options → new Model 模式；data 字段一律用 JSON string，避免动态对象。
 */

// ---------------- RelayAccount（内存模型，持久化走 PreferenceService 分立 key） ----------------

export interface RelayAccountOptions {
  accessToken?: string
  refreshToken?: string
  expiresAt?: number
  accountKey?: string
  serverVersion?: string
  capabilities?: string[]
}

export class RelayAccount {
  accessToken: string = ''
  refreshToken: string = ''
  /** 过期时间（Unix ms） */
  expiresAt: number = 0
  accountKey: string = ''
  serverVersion: string = ''
  capabilities: string[] = []

  constructor(options?: RelayAccountOptions) {
    if (options) {
      this.accessToken = options.accessToken ?? ''
      this.refreshToken = options.refreshToken ?? ''
      this.expiresAt = options.expiresAt ?? 0
      this.accountKey = options.accountKey ?? ''
      this.serverVersion = options.serverVersion ?? ''
      this.capabilities = options.capabilities ?? []
    }
  }
}

// ---------------- RelayRegisterResult（POST /auth/v1/register 响应） ----------------

export interface RelayRegisterResultOptions {
  accessToken?: string
  refreshToken?: string
  expiresIn?: number
  accountKey?: string
  serverVersion?: string
  capabilities?: string[]
}

interface RawRelayRegisterResult {
  accessToken?: string
  refreshToken?: string
  expiresIn?: number
  accountKey?: string
  serverVersion?: string
  capabilities?: string[]
}

export class RelayRegisterResult {
  accessToken: string = ''
  refreshToken: string = ''
  expiresIn: number = 0
  accountKey: string = ''
  serverVersion: string = ''
  capabilities: string[] = []

  constructor(options?: RelayRegisterResultOptions) {
    if (options) {
      this.accessToken = options.accessToken ?? ''
      this.refreshToken = options.refreshToken ?? ''
      this.expiresIn = options.expiresIn ?? 0
      this.accountKey = options.accountKey ?? ''
      this.serverVersion = options.serverVersion ?? ''
      this.capabilities = options.capabilities ?? []
    }
  }
}

export function relayRegisterResultFromJson(raw: Object): RelayRegisterResult {
  let p = raw as RawRelayRegisterResult
  let opts: RelayRegisterResultOptions = {
    accessToken: p?.accessToken ?? '',
    refreshToken: p?.refreshToken ?? '',
    expiresIn: p?.expiresIn ?? 0,
    accountKey: p?.accountKey ?? '',
    serverVersion: p?.serverVersion ?? '',
    capabilities: p?.capabilities ?? []
  }
  return new RelayRegisterResult(opts)
}

// ---------------- Relay 统一错误体 {error:{code,message,requestId}} ----------------

interface RawRelayError {
  code?: string
  message?: string
  requestId?: string
}

interface RawRelayErrorBody {
  error?: RawRelayError
}

export interface RelayErrorInfo {
  code: string
  message: string
}

/** 解析统一错误体，返回 code+message；解析失败返回空串字段 */
export function parseRelayError(body: string): RelayErrorInfo {
  let info: RelayErrorInfo = { code: '', message: '' }
  if (body.length === 0) {
    return info
  }
  try {
    let raw = JSON.parse(body) as RawRelayErrorBody
    if (raw?.error) {
      info.code = raw.error.code ?? ''
      info.message = raw.error.message ?? ''
    }
  } catch (e) {
    console.error('parseRelayError failed: ' + e)
  }
  return info
}

// ---------------- SyncItem / SyncPushResult / SyncPullResult ----------------

export interface SyncItemOptions {
  key?: string
  data?: string
  updatedAt?: number
  deleted?: boolean
}

interface RawSyncItem {
  key?: string
  /** 线上格式为 JSON 对象（api.md）；容错字符串形式 */
  data?: Object
  updatedAt?: number
  deleted?: boolean
}

export class SyncItem {
  key: string = ''
  /** 条目数据（JSON 串，避免 ArkTS 动态对象） */
  data: string = ''
  updatedAt: number = 0
  /** 墓碑标记 */
  deleted: boolean = false

  constructor(options?: SyncItemOptions) {
    if (options) {
      this.key = options.key ?? ''
      this.data = options.data ?? ''
      this.updatedAt = options.updatedAt ?? 0
      this.deleted = options.deleted ?? false
    }
  }
}

export function syncItemFromJson(raw: Object): SyncItem {
  let p = raw as RawSyncItem
  let dataStr = ''
  if (p?.data !== undefined && p.data !== null) {
    // 对象形式统一落为 JSON 串存入本地模型；字符串形式原样保留
    dataStr = typeof p.data === 'string' ? String(p.data) : JSON.stringify(p.data)
  }
  let opts: SyncItemOptions = {
    key: p?.key ?? '',
    data: dataStr,
    updatedAt: p?.updatedAt ?? 0,
    deleted: p?.deleted ?? false
  }
  return new SyncItem(opts)
}

export interface SyncPushResultOptions {
  accepted?: number
  syncToken?: string
  fullRequired?: boolean
}

interface RawSyncPushResult {
  accepted?: number
  syncToken?: string
}

export class SyncPushResult {
  accepted: number = 0
  /** 服务端游标，不透明串（st_<seq>_<hex>），客户端只持久化/透传 */
  syncToken: string = ''
  /** 409 SYNC_FULL_REQUIRED 映射而来，需清空本地域后全量重建 */
  fullRequired: boolean = false

  constructor(options?: SyncPushResultOptions) {
    if (options) {
      this.accepted = options.accepted ?? 0
      this.syncToken = options.syncToken ?? ''
      this.fullRequired = options.fullRequired ?? false
    }
  }
}

export function syncPushResultFromJson(raw: Object): SyncPushResult {
  let p = raw as RawSyncPushResult
  let opts: SyncPushResultOptions = {
    accepted: p?.accepted ?? 0,
    syncToken: p?.syncToken ?? '',
    fullRequired: false
  }
  return new SyncPushResult(opts)
}

export interface SyncPullResultOptions {
  items?: SyncItem[]
  syncToken?: string
  hasMore?: boolean
}

interface RawSyncPullResult {
  items?: Object[]
  syncToken?: string
  hasMore?: boolean
}

export class SyncPullResult {
  items: SyncItem[] = []
  syncToken: string = ''
  hasMore: boolean = false

  constructor(options?: SyncPullResultOptions) {
    if (options) {
      this.items = options.items ?? []
      this.syncToken = options.syncToken ?? ''
      this.hasMore = options.hasMore ?? false
    }
  }
}

export function syncPullResultFromJson(raw: Object): SyncPullResult {
  let p = raw as RawSyncPullResult
  let opts: SyncPullResultOptions = {
    items: (p?.items ?? []).map((item: Object) => syncItemFromJson(item)),
    syncToken: p?.syncToken ?? '',
    hasMore: p?.hasMore ?? false
  }
  return new SyncPullResult(opts)
}

// ---------------- BookmarkSnapshot（收藏快照） ----------------

export interface BookmarkSnapshotOptions {
  illustId?: number
  title?: string
  userId?: number
  userName?: string
  restrict?: string
  pageCount?: number
  width?: number
  height?: number
  tags?: string[]
  createDate?: string
  imageUrls?: string[]
  bookmarkedAt?: number
}

interface RawBookmarkSnapshot {
  illustId?: number
  title?: string
  userId?: number
  userName?: string
  restrict?: string
  pageCount?: number
  width?: number
  height?: number
  tags?: string[]
  createDate?: string
  imageUrls?: string[]
  bookmarkedAt?: number
}

export class BookmarkSnapshot {
  illustId: number = 0
  title: string = ''
  userId: number = 0
  userName: string = ''
  restrict: string = ''
  pageCount: number = 1
  width: number = 0
  height: number = 0
  tags: string[] = []
  createDate: string = ''
  /** 原图 URL 列表（每页一条，元素全 string） */
  imageUrls: string[] = []
  bookmarkedAt: number = 0

  constructor(options?: BookmarkSnapshotOptions) {
    if (options) {
      this.illustId = options.illustId ?? 0
      this.title = options.title ?? ''
      this.userId = options.userId ?? 0
      this.userName = options.userName ?? ''
      this.restrict = options.restrict ?? ''
      this.pageCount = options.pageCount ?? 1
      this.width = options.width ?? 0
      this.height = options.height ?? 0
      this.tags = options.tags ?? []
      this.createDate = options.createDate ?? ''
      this.imageUrls = options.imageUrls ?? []
      this.bookmarkedAt = options.bookmarkedAt ?? 0
    }
  }

  /** 序列化为上行/存储用 JSON 串（illustId 为数字、imageUrls 元素全 string，满足服务端校验） */
  toJsonString(): string {
    let obj: Record<string, Object> = {
      'illustId': this.illustId,
      'title': this.title,
      'userId': this.userId,
      'userName': this.userName,
      'restrict': this.restrict,
      'pageCount': this.pageCount,
      'width': this.width,
      'height': this.height,
      'tags': this.tags,
      'createDate': this.createDate,
      'imageUrls': this.imageUrls,
      'bookmarkedAt': this.bookmarkedAt
    }
    return JSON.stringify(obj)
  }
}

export function bookmarkSnapshotFromJson(raw: Object): BookmarkSnapshot {
  let p = raw as RawBookmarkSnapshot
  let opts: BookmarkSnapshotOptions = {
    illustId: p?.illustId ?? 0,
    title: p?.title ?? '',
    userId: p?.userId ?? 0,
    userName: p?.userName ?? '',
    restrict: p?.restrict ?? '',
    pageCount: p?.pageCount ?? 1,
    width: p?.width ?? 0,
    height: p?.height ?? 0,
    tags: p?.tags ?? [],
    createDate: p?.createDate ?? '',
    imageUrls: p?.imageUrls ?? [],
    bookmarkedAt: p?.bookmarkedAt ?? 0
  }
  return new BookmarkSnapshot(opts)
}

/** 从 JSON 串反序列化（DB data 列 / 同步 data 字段），失败返回 null */
export function bookmarkSnapshotFromJsonString(json: string): BookmarkSnapshot | null {
  if (json.length === 0) {
    return null
  }
  try {
    return bookmarkSnapshotFromJson(JSON.parse(json))
  } catch (e) {
    console.error('bookmarkSnapshotFromJsonString failed: ' + e)
    return null
  }
}

/** 由收藏成功的 Illust 生成快照（imageUrls 取每页原图档） */
export function bookmarkSnapshotFromIllust(illust: Illust, bookmarkedAt: number): BookmarkSnapshot {
  let imageUrls: string[] = []
  for (let i = 0; i < illust.pageCount; i++) {
    imageUrls.push(pickDetailUrl(illust, i, 1))
  }
  let tags: string[] = illust.tags.map((t: Tag) => t.name)
  let opts: BookmarkSnapshotOptions = {
    illustId: illust.id,
    title: illust.title,
    userId: illust.user.id,
    userName: illust.user.name,
    restrict: illust.restrict,
    pageCount: illust.pageCount,
    width: illust.width,
    height: illust.height,
    tags: tags,
    createDate: illust.createDate,
    imageUrls: imageUrls,
    bookmarkedAt: bookmarkedAt
  }
  return new BookmarkSnapshot(opts)
}

// ---------------- RecoverPage / RecoverResult（GET /recover/v1/illust/{pid}） ----------------

export interface RecoverPageOptions {
  page?: number
  url?: string
  width?: number
  height?: number
}

interface RawRecoverPage {
  page?: number
  url?: string
  width?: number
  height?: number
}

export class RecoverPage {
  page: number = 0
  url: string = ''
  width: number = 0
  height: number = 0

  constructor(options?: RecoverPageOptions) {
    if (options) {
      this.page = options.page ?? 0
      this.url = options.url ?? ''
      this.width = options.width ?? 0
      this.height = options.height ?? 0
    }
  }
}

export function recoverPageFromJson(raw: Object): RecoverPage {
  let p = raw as RawRecoverPage
  let opts: RecoverPageOptions = {
    page: p?.page ?? 0,
    url: p?.url ?? '',
    width: p?.width ?? 0,
    height: p?.height ?? 0
  }
  return new RecoverPage(opts)
}

/** 恢复三态 */
export const RECOVER_STATUS_READY: string = 'ready'
export const RECOVER_STATUS_FETCHING: string = 'fetching'
export const RECOVER_STATUS_NOT_FOUND: string = 'not_found'

export interface RecoverResultOptions {
  status?: string
  pages?: RecoverPage[]
  source?: string
  title?: string
  userName?: string
  retryAfterSec?: number
}

interface RawRecoverMeta {
  title?: string
  userName?: string
}

interface RawRecoverResult {
  status?: string
  pages?: Object[]
  source?: string
  meta?: RawRecoverMeta
  retryAfterSec?: number
}

export class RecoverResult {
  /** ready / fetching / not_found */
  status: string = RECOVER_STATUS_NOT_FOUND
  pages: RecoverPage[] = []
  source: string = ''
  title: string = ''
  userName: string = ''
  retryAfterSec: number = 5

  constructor(options?: RecoverResultOptions) {
    if (options) {
      this.status = options.status ?? RECOVER_STATUS_NOT_FOUND
      this.pages = options.pages ?? []
      this.source = options.source ?? ''
      this.title = options.title ?? ''
      this.userName = options.userName ?? ''
      this.retryAfterSec = options.retryAfterSec ?? 5
    }
  }
}

/**
 * 解析恢复查询响应体。httpStatus 三态映射：200→ready、202→fetching、404→not_found；
 * 其余状态码由调用方按错误处理。api.md：ready 响应的元数据在 meta 对象内（无顶层 title/userName）。
 */
export function recoverResultFromJson(raw: Object, httpStatus: number): RecoverResult {
  let p = raw as RawRecoverResult
  let status = RECOVER_STATUS_NOT_FOUND
  if (httpStatus === 200) {
    status = RECOVER_STATUS_READY
  } else if (httpStatus === 202) {
    status = RECOVER_STATUS_FETCHING
  }
  let opts: RecoverResultOptions = {
    status: status,
    pages: (p?.pages ?? []).map((item: Object) => recoverPageFromJson(item)),
    source: p?.source ?? '',
    title: p?.meta?.title ?? '',
    userName: p?.meta?.userName ?? '',
    retryAfterSec: p?.retryAfterSec ?? 5
  }
  return new RecoverResult(opts)
}
