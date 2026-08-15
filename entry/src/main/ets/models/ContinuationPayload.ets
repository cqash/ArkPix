/**
 * 多端流转（应用接续）载荷 + 设备间同步载荷的模型与序列化/解析纯函数。
 * 解析函数全部失败返回 null，不抛异常（对端版本不一致/字段缺失时静默降级）。
 */

import { ExifTagMergeRule } from './AppSettings';

// ---------------- 流转载荷 ----------------

export const CONTINUATION_PAYLOAD_VERSION: number = 1

export const CONTINUATION_PAGE_HOME: string = 'home'
export const CONTINUATION_PAGE_ILLUST_DETAIL: string = 'illust_detail'
export const CONTINUATION_PAGE_USER_PROFILE: string = 'user_profile'

/** 接续载荷序列化后写入 wantParam / AppStorage 的键（避开系统占用键 version/targetDevice/sessionId） */
export const CONTINUATION_PAYLOAD_KEY: string = 'continuationPayload'

export interface ContinuationPayloadOptions {
  version?: number
  page?: string
  illustId?: number
  userId?: number
  tabIndex?: number
}

/**
 * 流转载荷：页面类型 + 上下文参数（illustId / userId / tabIndex）+ 版本号。
 * 设计约束：序列化后 << 100KB（实际 <200 字节），详情数据由对端重新拉取。
 * id 字段以 0 表示缺失；page 决定哪个 id 字段有效。
 */
export class ContinuationPayload {
  version: number = CONTINUATION_PAYLOAD_VERSION
  page: string = ''
  illustId: number = 0
  userId: number = 0
  tabIndex: number = 0

  constructor(options?: ContinuationPayloadOptions) {
    if (options) {
      this.version = options.version ?? CONTINUATION_PAYLOAD_VERSION
      this.page = options.page ?? ''
      this.illustId = options.illustId ?? 0
      this.userId = options.userId ?? 0
      this.tabIndex = options.tabIndex ?? 0
    }
  }
}

// ---------------- 分布式同步元信息 ----------------

export const DISTRIBUTED_SYNC_SCHEMA_VERSION: number = 1

/** metaJson 载荷：settingsJson 的 LWW 时间戳载体 + 来源设备标识 */
export interface DistributedSyncMeta {
  deviceId: string
  updatedAt: number
  schemaVersion: number
}

// ---------------- 同步历史条目（与 DatabaseService 的 HistoryItem/SearchHistoryItem 字段对齐） ----------------

export interface SyncedHistoryItem {
  illustId: number
  title: string
  imageUrl: string
  userName: string
  timestamp: number
}

export interface SyncedSearchHistoryItem {
  keyword: string
  searchType: string
  timestamp: number
}

// ---------------- 解析用 Raw 接口（as 断言仅限本文件解析内部层） ----------------

interface RawContinuationPayload {
  version?: number
  page?: string
  illustId?: number
  userId?: number
  tabIndex?: number
}

interface RawDistributedSyncMeta {
  deviceId?: string
  updatedAt?: number
  schemaVersion?: number
}

interface RawSyncedHistoryItem {
  illustId?: number
  title?: string
  imageUrl?: string
  userName?: string
  timestamp?: number
}

interface RawSyncedSearchHistoryItem {
  keyword?: string
  searchType?: string
  timestamp?: number
}

// ---------------- 流转载荷序列化/解析 ----------------

/** 序列化接续载荷为 JSON 字符串（实际 <200 字节，远低于 100KB 上限） */
export function buildContinuationPayloadJson(payload: ContinuationPayload): string {
  let raw: RawContinuationPayload = { version: payload.version, page: payload.page }
  if (payload.illustId > 0) {
    raw.illustId = payload.illustId
  }
  if (payload.userId > 0) {
    raw.userId = payload.userId
  }
  if (payload.tabIndex > 0) {
    raw.tabIndex = payload.tabIndex
  }
  return JSON.stringify(raw)
}

/**
 * 解析接续载荷 JSON；非法（非对象/缺 page/上下文 id 缺失）返回 null。
 * page 值本身不做白名单校验——未知 page 由路由层回退主页。
 */
export function parseContinuationPayloadJson(json: string): ContinuationPayload | null {
  if (json.length === 0) {
    return null
  }
  try {
    let raw = JSON.parse(json) as RawContinuationPayload
    if (raw === null || typeof raw !== 'object') {
      return null
    }
    let page = raw.page ?? ''
    if (page.length === 0) {
      return null
    }
    let illustId = raw.illustId ?? 0
    let userId = raw.userId ?? 0
    let tabIndex = raw.tabIndex ?? 0
    // 上下文参数完整性校验：详情页必须带 illustId，用户主页必须带 userId
    if (page === CONTINUATION_PAGE_ILLUST_DETAIL && illustId <= 0) {
      return null
    }
    if (page === CONTINUATION_PAGE_USER_PROFILE && userId <= 0) {
      return null
    }
    if (page === CONTINUATION_PAGE_HOME && (tabIndex < 0 || tabIndex > 4)) {
      tabIndex = 0
    }
    return new ContinuationPayload({
      version: raw.version ?? CONTINUATION_PAYLOAD_VERSION,
      page: page,
      illustId: illustId,
      userId: userId,
      tabIndex: tabIndex
    })
  } catch (e) {
    console.error('Parse continuation payload failed: ' + e)
    return null
  }
}

// ---------------- 分布式同步载荷解析 ----------------

/** 解析 metaJson；失败返回 null */
export function parseSyncMetaJson(json: string): DistributedSyncMeta | null {
  if (json.length === 0) {
    return null
  }
  try {
    let raw = JSON.parse(json) as RawDistributedSyncMeta
    if (raw === null || typeof raw !== 'object') {
      return null
    }
    let meta: DistributedSyncMeta = {
      deviceId: raw.deviceId ?? '',
      updatedAt: raw.updatedAt ?? 0,
      schemaVersion: raw.schemaVersion ?? DISTRIBUTED_SYNC_SCHEMA_VERSION
    }
    return meta
  } catch (e) {
    console.error('Parse sync meta json failed: ' + e)
    return null
  }
}

export function buildSyncMetaJson(meta: DistributedSyncMeta): string {
  let raw: RawDistributedSyncMeta = {
    deviceId: meta.deviceId,
    updatedAt: meta.updatedAt,
    schemaVersion: meta.schemaVersion
  }
  return JSON.stringify(raw)
}

/**
 * 解析 settingsJson 为字段键值对（逐字段应用时按 key 读取，未知字段自然跳过）。
 * 非对象/解析失败返回 null。
 */
export function parseSettingsSyncJson(json: string): Record<string, Object> | null {
  if (json.length === 0) {
    return null
  }
  try {
    let raw = JSON.parse(json) as Record<string, Object>
    if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
      return null
    }
    return raw
  } catch (e) {
    console.error('Parse settings sync json failed: ' + e)
    return null
  }
}

/** 解析 historyJson 为条目数组；单条非法字段按默认值兜底，整体失败返回 null */
export function parseHistorySyncJson(json: string): SyncedHistoryItem[] | null {
  if (json.length === 0) {
    return null
  }
  try {
    let raw = JSON.parse(json) as RawSyncedHistoryItem[]
    if (!Array.isArray(raw)) {
      return null
    }
    let items: SyncedHistoryItem[] = []
    for (let i = 0; i < raw.length; i++) {
      let entry = raw[i]
      if (entry === null || typeof entry !== 'object') {
        continue
      }
      let illustId = entry.illustId ?? 0
      if (illustId <= 0) {
        continue
      }
      let item: SyncedHistoryItem = {
        illustId: illustId,
        title: entry.title ?? '',
        imageUrl: entry.imageUrl ?? '',
        userName: entry.userName ?? '',
        timestamp: entry.timestamp ?? 0
      }
      items.push(item)
    }
    return items
  } catch (e) {
    console.error('Parse history sync json failed: ' + e)
    return null
  }
}

export function buildHistorySyncJson(items: SyncedHistoryItem[]): string {
  let raw: RawSyncedHistoryItem[] = []
  for (let i = 0; i < items.length; i++) {
    let entry: RawSyncedHistoryItem = {
      illustId: items[i].illustId,
      title: items[i].title,
      imageUrl: items[i].imageUrl,
      userName: items[i].userName,
      timestamp: items[i].timestamp
    }
    raw.push(entry)
  }
  return JSON.stringify(raw)
}

/** 解析 searchHistoryJson 为条目数组；单条非法跳过，整体失败返回 null */
export function parseSearchHistorySyncJson(json: string): SyncedSearchHistoryItem[] | null {
  if (json.length === 0) {
    return null
  }
  try {
    let raw = JSON.parse(json) as RawSyncedSearchHistoryItem[]
    if (!Array.isArray(raw)) {
      return null
    }
    let items: SyncedSearchHistoryItem[] = []
    for (let i = 0; i < raw.length; i++) {
      let entry = raw[i]
      if (entry === null || typeof entry !== 'object') {
        continue
      }
      let keyword = entry.keyword ?? ''
      if (keyword.length === 0) {
        continue
      }
      let item: SyncedSearchHistoryItem = {
        keyword: keyword,
        searchType: entry.searchType ?? 'illust',
        timestamp: entry.timestamp ?? 0
      }
      items.push(item)
    }
    return items
  } catch (e) {
    console.error('Parse search history sync json failed: ' + e)
    return null
  }
}

export function buildSearchHistorySyncJson(items: SyncedSearchHistoryItem[]): string {
  let raw: RawSyncedSearchHistoryItem[] = []
  for (let i = 0; i < items.length; i++) {
    let entry: RawSyncedSearchHistoryItem = {
      keyword: items[i].keyword,
      searchType: items[i].searchType,
      timestamp: items[i].timestamp
    }
    raw.push(entry)
  }
  return JSON.stringify(raw)
}

// ---------------- settingsJson 字段提取助手（解析内部层，as 断言仅限此处） ----------------

/** 从设置载荷取 number 字段；缺失/类型不符返回 null（调用方跳过该字段，未知字段不崩溃） */
export function pickSyncNumber(fields: Record<string, Object>, key: string): number | null {
  let value = fields[key]
  if (value === undefined || value === null || typeof value !== 'number') {
    return null
  }
  return value as number
}

export function pickSyncBoolean(fields: Record<string, Object>, key: string): boolean | null {
  let value = fields[key]
  if (value === undefined || value === null || typeof value !== 'boolean') {
    return null
  }
  return value as boolean
}

export function pickSyncString(fields: Record<string, Object>, key: string): string | null {
  let value = fields[key]
  if (value === undefined || value === null || typeof value !== 'string') {
    return null
  }
  return value as string
}

export function pickSyncStringArray(fields: Record<string, Object>, key: string): string[] | null {
  let value = fields[key]
  if (value === undefined || value === null || !Array.isArray(value)) {
    return null
  }
  let rawArr = value as Object[]
  let result: string[] = []
  for (let i = 0; i < rawArr.length; i++) {
    if (typeof rawArr[i] === 'string') {
      result.push(rawArr[i] as string)
    }
  }
  return result
}

export function pickSyncNumberArray(fields: Record<string, Object>, key: string): number[] | null {
  let value = fields[key]
  if (value === undefined || value === null || !Array.isArray(value)) {
    return null
  }
  let rawArr = value as Object[]
  let result: number[] = []
  for (let i = 0; i < rawArr.length; i++) {
    if (typeof rawArr[i] === 'number') {
      result.push(rawArr[i] as number)
    }
  }
  return result
}

/** 从设置载荷取 EXIF 合并规则数组；非法元素跳过，字段缺失返回 null */
export function pickSyncExifMergeRules(fields: Record<string, Object>, key: string): ExifTagMergeRule[] | null {
  let value = fields[key]
  if (value === undefined || value === null || !Array.isArray(value)) {
    return null
  }
  let rawArr = value as RawExifMergeRuleData[]
  let result: ExifTagMergeRule[] = []
  for (let i = 0; i < rawArr.length; i++) {
    let entry = rawArr[i]
    if (entry === null || typeof entry !== 'object') {
      continue
    }
    let mainTag = entry.mainTag ?? ''
    if (mainTag.length === 0) {
      continue
    }
    let fromTags: string[] = []
    let rawFrom = entry.fromTags ?? []
    for (let j = 0; j < rawFrom.length; j++) {
      if (typeof rawFrom[j] === 'string') {
        fromTags.push(rawFrom[j])
      }
    }
    result.push(new ExifTagMergeRule({ mainTag: mainTag, fromTags: fromTags }))
  }
  return result
}

interface RawExifMergeRuleData {
  mainTag?: string
  fromTags?: string[]
}
