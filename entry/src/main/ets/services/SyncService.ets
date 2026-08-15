import { http } from '@kit.NetworkKit';
import { preferenceService } from './PreferenceService';
import { getDbService, DatabaseService, setSyncWriteHook } from './DatabaseService';
import { userSettingStore, setSettingsWriteHook } from '../stores/UserSettingStore';
import { ExifTagMergeRule } from '../models/AppSettings';
import { Illust } from '../models/Illust';
import { bookmarkStateStore } from '../stores/BookmarkStateStore';
import { relayClient } from '../network/RelayClient';
import {
  SyncItem,
  syncPushResultFromJson,
  syncPullResultFromJson,
  bookmarkSnapshotFromIllust,
  parseRelayError,
  BookmarkSnapshot
} from '../models/RelayModels';

// ---------------- 同步域 ----------------

export const SYNC_DOMAIN_HISTORY: string = 'history'
export const SYNC_DOMAIN_SEARCH_HISTORY: string = 'search_history'
export const SYNC_DOMAIN_BOOKMARK_SNAPSHOT: string = 'bookmark_snapshot'
export const SYNC_DOMAIN_MUTE: string = 'mute'
export const SYNC_DOMAIN_EXIF_CONFIG: string = 'exif_config'
export const SYNC_DOMAIN_SETTINGS: string = 'settings'

export const SYNC_DOMAINS: string[] = [
  SYNC_DOMAIN_HISTORY,
  SYNC_DOMAIN_SEARCH_HISTORY,
  SYNC_DOMAIN_BOOKMARK_SNAPSHOT,
  SYNC_DOMAIN_MUTE,
  SYNC_DOMAIN_EXIF_CONFIG,
  SYNC_DOMAIN_SETTINGS
]

const PUSH_BATCH_SIZE: number = 500
const PUSH_DEBOUNCE_MS: number = 10000
/** 前台补偿 pull 最小间隔（避免频繁进出前台反复全域拉取） */
const FOREGROUND_PULL_MIN_INTERVAL_MS: number = 5 * 60 * 1000

// ---------------- 纯函数（供单元测试） ----------------

/** LWW 判定：远端 updatedAt 严格大于本地才应用 */
export function shouldApplyRemote(localUpdatedAt: number, remoteUpdatedAt: number): boolean {
  return remoteUpdatedAt > localUpdatedAt
}

/** 递归剔除字段名含 token（不区分大小写）的键，避免服务端 400 SENSITIVE_FIELD_REJECTED */
function stripSensitiveValue(value: Object): Object {
  if (value === null) {
    return value
  }
  if (Array.isArray(value)) {
    let arr = value as Object[]
    let out: Object[] = []
    for (let i = 0; i < arr.length; i++) {
      out.push(stripSensitiveValue(arr[i]))
    }
    return out
  }
  if (typeof value === 'object') {
    let rec = value as Record<string, Object>
    let out: Record<string, Object> = {}
    let keys = Object.keys(rec)
    for (let i = 0; i < keys.length; i++) {
      let key = keys[i]
      if (key.toLowerCase().indexOf('token') >= 0) {
        continue
      }
      out[key] = stripSensitiveValue(rec[key])
    }
    return out
  }
  return value
}

/** 上行前序列化净化：剔除任何层级字段名含 token 的键；解析失败原样返回 */
export function stripSensitiveJson(json: string): string {
  try {
    return JSON.stringify(stripSensitiveValue(JSON.parse(json)))
  } catch (e) {
    console.error('stripSensitiveJson failed: ' + e)
    return json
  }
}

// ---------------- 内部结构 ----------------

interface TombstoneRecord {
  key: string
  updatedAt: number
}

interface RawHistorySyncData {
  title?: string
  imageUrl?: string
  userName?: string
  viewedAt?: number
}

interface RawMuteValueData {
  value?: string
  enabled?: boolean
}

interface RawExifMergeRuleData {
  mainTag?: string
  fromTags?: string[]
}

interface RawExifConfigSyncData {
  exifMutedTags?: string[]
  exifMergedTags?: RawExifMergeRuleData[]
  exifTagPriority?: string[]
  exifCommentTemplate?: string
}

/** settings 域上行子集（非敏感字段；token 类凭据本就不在 AppSettings 内，此处再兜底剔除） */
interface RawSettingsSyncData {
  pictureQuality?: number
  mangaQuality?: number
  previewQuality?: number
  detailQuality?: number
  fullScreenQuality?: number
  downloadQuality?: number
  theme?: string
  language?: string
  crossCount?: number
  isTopMode?: boolean
  saveFormat?: string
  autoBookmarkOnDownload?: boolean
  filenameTemplate?: string
  showTranslatedTags?: boolean
  showR18Rank?: boolean
  antiSocialDeath?: boolean
  downloadConcurrency?: number
  imageHostType?: string
  imageHostCustom?: string
  relayServerUrl?: string
  syncEnabled?: boolean
}

export class SyncService {
  private static instance: SyncService
  private initialized: boolean = false
  /** 下行应用期间抑制本地写入回传（防回声循环） */
  private applyingRemote: boolean = false
  private pendingDomains: string[] = []
  private pushTimer: number = -1

  private constructor() {
  }

  static getInstance(): SyncService {
    if (!SyncService.instance) {
      SyncService.instance = new SyncService()
    }
    return SyncService.instance
  }

  /** 幂等初始化：注册收藏变更回调与各写入点 hook（避免反向 import 成环） */
  init(): void {
    if (this.initialized) {
      return
    }
    this.initialized = true
    bookmarkStateStore.registerBookmarkChangeListener((illust: Illust, bookmarked: boolean) => {
      this.onBookmarkChanged(illust, bookmarked)
    })
    setSyncWriteHook((domain: string, tombstoneKeys: string[]) => {
      if (this.applyingRemote) {
        // 下行应用/全量重建期间的本地写入不回传（防回声；清库不产生墓碑）
        return
      }
      if (tombstoneKeys.length > 0) {
        this.addTombstones(domain, tombstoneKeys)
      }
      this.schedulePush(domain)
    })
    setSettingsWriteHook((domain: string, tombstoneKeys: string[]) => {
      if (this.applyingRemote) {
        return
      }
      if (tombstoneKeys.length > 0) {
        this.addTombstones(domain, tombstoneKeys)
      }
      this.schedulePush(domain)
    })
  }

  private canSync(): boolean {
    let settings = userSettingStore.getSettings()
    return settings.syncEnabled && relayClient.isRegistered() && settings.relayServerUrl.trim().length > 0
  }

  /** 当前是否具备同步条件（供设置页"立即同步"置灰判断） */
  isSyncReady(): boolean {
    return this.canSync()
  }

  // ---------------- 游标与时间持久化（syncToken 按不透明串处理） ----------------

  private getCursor(domain: string): string {
    return preferenceService.getString('sync_token_' + domain, '')
  }

  private setCursor(domain: string, token: string): void {
    preferenceService.setString('sync_token_' + domain, token)
  }

  private setLastSync(domain: string, ts: number): void {
    preferenceService.setNumber('sync_last_' + domain, ts)
  }

  private getLocalWrite(domain: string): number {
    return preferenceService.getNumber('sync_local_' + domain, 0)
  }

  private recordLocalWrite(domain: string): void {
    preferenceService.setNumber('sync_local_' + domain, Date.now())
  }

  private pad2(n: number): string {
    return n < 10 ? '0' + n.toString() : n.toString()
  }

  getLastSyncText(domain: string): string {
    let ts = preferenceService.getNumber('sync_last_' + domain, 0)
    if (ts <= 0) {
      return '从未同步'
    }
    let d = new Date(ts)
    return d.getFullYear().toString() + '-' + this.pad2(d.getMonth() + 1) + '-' + this.pad2(d.getDate()) +
      ' ' + this.pad2(d.getHours()) + ':' + this.pad2(d.getMinutes())
  }

  // ---------------- 墓碑暂存（history/search_history/mute 删除传播） ----------------

  private getTombstones(domain: string): TombstoneRecord[] {
    try {
      let raw = preferenceService.getString('sync_tombstones_' + domain, '[]')
      return JSON.parse(raw) as TombstoneRecord[]
    } catch (e) {
      console.error('getTombstones failed: ' + e)
      return []
    }
  }

  addTombstones(domain: string, keys: string[]): void {
    if (keys.length === 0) {
      return
    }
    let list = this.getTombstones(domain)
    let now = Date.now()
    for (let i = 0; i < keys.length; i++) {
      let exists = false
      for (let j = 0; j < list.length; j++) {
        if (list[j].key === keys[i]) {
          list[j].updatedAt = now
          exists = true
          break
        }
      }
      if (!exists) {
        let rec: TombstoneRecord = { key: keys[i], updatedAt: now }
        list.push(rec)
      }
    }
    preferenceService.setString('sync_tombstones_' + domain, JSON.stringify(list))
  }

  private clearTombstones(domain: string): void {
    preferenceService.delete('sync_tombstones_' + domain)
  }

  private appendTombstones(domain: string, items: SyncItem[]): SyncItem[] {
    let tombstones = this.getTombstones(domain)
    for (let i = 0; i < tombstones.length; i++) {
      items.push(new SyncItem({
        key: tombstones[i].key,
        data: '',
        updatedAt: tombstones[i].updatedAt,
        deleted: true
      }))
    }
    return items
  }

  // ---------------- 调度 ----------------

  /** 本地写入后 10s 防抖批量 push 对应域 */
  schedulePush(domain: string): void {
    this.init()
    if (this.applyingRemote) {
      return
    }
    if (!this.canSync()) {
      return
    }
    this.recordLocalWrite(domain)
    if (!this.pendingDomains.includes(domain)) {
      this.pendingDomains.push(domain)
    }
    if (this.pushTimer >= 0) {
      clearTimeout(this.pushTimer)
    }
    this.pushTimer = setTimeout(() => {
      this.pushTimer = -1
      this.flushPendingPush()
    }, PUSH_DEBOUNCE_MS)
  }

  private flushPendingPush(): void {
    let domains = this.pendingDomains.slice()
    this.pendingDomains = []
    for (let i = 0; i < domains.length; i++) {
      this.pushDomain(domains[i])
        .catch((e: Object) => {
          // 离线/失败静默：游标与墓碑保留，下轮重试
          console.error('Sync push failed (' + domains[i] + '): ' + e)
        })
    }
  }

  /** 启动后空闲全域 pull（syncEnabled + 已注册才执行） */
  async startupPull(): Promise<void> {
    this.init()
    if (!this.canSync()) {
      return
    }
    for (let i = 0; i < SYNC_DOMAINS.length; i++) {
      try {
        await this.pullDomain(SYNC_DOMAINS[i])
      } catch (e) {
        console.error('Startup pull failed (' + SYNC_DOMAINS[i] + '): ' + e)
      }
    }
  }

  private lastForegroundPullMs: number = 0

  /**
   * 回前台补偿同步（EntryAbility.onForeground 经 lazy import 调用）：
   * 受 autoSyncForeground 开关门控 + 5 分钟节流；静默执行，失败下轮重试。
   */
  onAppForeground(): void {
    this.init()
    if (!this.canSync()) {
      return
    }
    if (!userSettingStore.getSettings().autoSyncForeground) {
      return
    }
    let now = Date.now()
    if (now - this.lastForegroundPullMs < FOREGROUND_PULL_MIN_INTERVAL_MS) {
      return
    }
    this.lastForegroundPullMs = now
    this.startupPull()
      .then(() => {
        // 有本地防抖期内未推的变更时顺带 flush
        this.flushPendingPush()
      })
      .catch((e: Object) => {
        console.error('Foreground pull failed: ' + e)
      })
  }

  /** 设置页"立即同步"：全域 push 后 pull；返回是否全部成功 */
  async syncNow(): Promise<boolean> {
    this.init()
    if (!this.canSync()) {
      return false
    }
    let allOk = true
    for (let i = 0; i < SYNC_DOMAINS.length; i++) {
      try {
        await this.pushDomain(SYNC_DOMAINS[i])
      } catch (e) {
        allOk = false
        console.error('Sync now push failed (' + SYNC_DOMAINS[i] + '): ' + e)
      }
    }
    for (let i = 0; i < SYNC_DOMAINS.length; i++) {
      try {
        await this.pullDomain(SYNC_DOMAINS[i])
      } catch (e) {
        allOk = false
        console.error('Sync now pull failed (' + SYNC_DOMAINS[i] + '): ' + e)
      }
    }
    return allOk
  }

  // ---------------- push ----------------

  private async pushDomain(domain: string): Promise<void> {
    if (!this.canSync()) {
      return
    }
    let items = await this.collectDomain(domain)
    if (items.length === 0) {
      return
    }
    let offset = 0
    while (offset < items.length) {
      let batch = items.slice(offset, offset + PUSH_BATCH_SIZE)
      let body = this.buildPushBody(domain, batch)
      let resp = await relayClient.authorizedRequest('/sync/v1/push', http.RequestMethod.POST, body)
      if (resp.responseCode === 409) {
        // SYNC_FULL_REQUIRED：清空本地域后全量 pull 重建（applyingRemote 抑制清库产生的墓碑/回传）
        this.applyingRemote = true
        try {
          await this.fullRebuild(domain)
        } finally {
          this.applyingRemote = false
        }
        return
      }
      if (resp.responseCode !== 200) {
        let errInfo = parseRelayError(String(resp.result))
        throw new Error(errInfo.message.length > 0 ? errInfo.message : '同步上行失败 (HTTP ' + resp.responseCode + ')')
      }
      let result = syncPushResultFromJson(JSON.parse(String(resp.result)))
      if (result.syncToken.length > 0) {
        this.setCursor(domain, result.syncToken)
      }
      offset += PUSH_BATCH_SIZE
    }
    this.clearTombstones(domain)
    this.setLastSync(domain, Date.now())
  }

  private buildPushBody(domain: string, items: SyncItem[]): string {
    let arr: Object[] = []
    for (let i = 0; i < items.length; i++) {
      // 上行前统一敏感字段剔除（双保险：collector 构建 data 时已剔除一次）
      let sanitized = stripSensitiveJson(items[i].data)
      let obj: Record<string, Object> = {
        'key': items[i].key,
        // api.md wire 格式：data 为 JSON 对象（本地模型内以 JSON 串存储，此处还原）
        'data': sanitized.length > 0 ? JSON.parse(sanitized) : JSON.parse('{}'),
        'updatedAt': items[i].updatedAt,
        'deleted': items[i].deleted
      }
      arr.push(obj)
    }
    let body: Record<string, Object> = {
      'domain': domain,
      'baseToken': this.getCursor(domain),
      'items': arr
    }
    return JSON.stringify(body)
  }

  // ---------------- pull ----------------

  private async pullDomain(domain: string): Promise<void> {
    if (!this.canSync()) {
      return
    }
    let since = this.getCursor(domain)
    this.applyingRemote = true
    try {
      while (true) {
        let path = '/sync/v1/pull?domain=' + encodeURIComponent(domain) + '&since=' + encodeURIComponent(since) +
          '&limit=100'
        let resp = await relayClient.authorizedRequest(path, http.RequestMethod.GET)
        if (resp.responseCode === 409) {
          // SYNC_FULL_REQUIRED：游标无效/过旧 → 清空本地域后全量重建
          await this.clearLocalDomain(domain)
          this.setCursor(domain, '')
          since = ''
          continue
        }
        if (resp.responseCode !== 200) {
          let errInfo = parseRelayError(String(resp.result))
          throw new Error(errInfo.message.length > 0 ? errInfo.message : '同步下行失败 (HTTP ' + resp.responseCode + ')')
        }
        let result = syncPullResultFromJson(JSON.parse(String(resp.result)))
        await this.applyItems(domain, result.items)
        if (result.syncToken.length > 0) {
          this.setCursor(domain, result.syncToken)
          since = result.syncToken
        }
        this.setLastSync(domain, Date.now())
        if (!result.hasMore) {
          break
        }
      }
    } finally {
      this.applyingRemote = false
    }
  }

  private async fullRebuild(domain: string): Promise<void> {
    await this.clearLocalDomain(domain)
    this.setCursor(domain, '')
    await this.pullDomain(domain)
  }

  // ---------------- 本地域清空（全量重建用） ----------------

  private async clearLocalDomain(domain: string): Promise<void> {
    if (domain === SYNC_DOMAIN_HISTORY) {
      let db = await getDbService()
      await db.clearHistory()
    } else if (domain === SYNC_DOMAIN_SEARCH_HISTORY) {
      let db = await getDbService()
      await db.clearSearchHistory()
    } else if (domain === SYNC_DOMAIN_BOOKMARK_SNAPSHOT) {
      let db = await getDbService()
      await db.replaceBookmarkSnapshots([])
    } else if (domain === SYNC_DOMAIN_MUTE) {
      userSettingStore.setMuteTags([])
      userSettingStore.setMuteUsers([])
      userSettingStore.setAiFilter(false)
    } else if (domain === SYNC_DOMAIN_EXIF_CONFIG) {
      userSettingStore.setExifMutedTags([])
      userSettingStore.setExifMergedTags([])
      userSettingStore.setExifTagPriority([])
      userSettingStore.setExifCommentTemplate('PID:{illust_id} | {tags}')
    } else if (domain === SYNC_DOMAIN_SETTINGS) {
      // settings 域无墓碑语义，全量重建由后续 pull 的整条 LWW 覆盖，无需清空
    }
  }

  // ---------------- collectors（六域上行数据） ----------------

  private async collectDomain(domain: string): Promise<SyncItem[]> {
    if (domain === SYNC_DOMAIN_HISTORY) {
      return this.collectHistory()
    }
    if (domain === SYNC_DOMAIN_SEARCH_HISTORY) {
      return this.collectSearchHistory()
    }
    if (domain === SYNC_DOMAIN_BOOKMARK_SNAPSHOT) {
      return this.collectBookmarkSnapshots()
    }
    if (domain === SYNC_DOMAIN_MUTE) {
      return this.collectMute()
    }
    if (domain === SYNC_DOMAIN_EXIF_CONFIG) {
      return this.collectExifConfig()
    }
    if (domain === SYNC_DOMAIN_SETTINGS) {
      return this.collectSettings()
    }
    return []
  }

  private async collectHistory(): Promise<SyncItem[]> {
    let items: SyncItem[] = []
    let db = await getDbService()
    let rows = await db.getHistory(500)
    for (let i = 0; i < rows.length; i++) {
      let data: Record<string, Object> = {
        'title': rows[i].title,
        'imageUrl': rows[i].image_url,
        'userName': rows[i].user_name,
        'viewedAt': rows[i].timestamp
      }
      items.push(new SyncItem({
        key: rows[i].illust_id.toString(),
        data: stripSensitiveJson(JSON.stringify(data)),
        updatedAt: rows[i].timestamp,
        deleted: false
      }))
    }
    return this.appendTombstones(SYNC_DOMAIN_HISTORY, items)
  }

  private async collectSearchHistory(): Promise<SyncItem[]> {
    let items: SyncItem[] = []
    let db = await getDbService()
    let rows = await db.getSearchHistory(500)
    for (let i = 0; i < rows.length; i++) {
      let data: Record<string, Object> = {
        'keyword': rows[i].keyword,
        'searchType': rows[i].search_type
      }
      items.push(new SyncItem({
        key: this.searchKey(rows[i].keyword, rows[i].search_type),
        data: stripSensitiveJson(JSON.stringify(data)),
        updatedAt: rows[i].timestamp,
        deleted: false
      }))
    }
    return this.appendTombstones(SYNC_DOMAIN_SEARCH_HISTORY, items)
  }

  private searchKey(keyword: string, searchType: string): string {
    return searchType + ':' + keyword
  }

  private async collectBookmarkSnapshots(): Promise<SyncItem[]> {
    let items: SyncItem[] = []
    let db = await getDbService()
    let rows = await db.getAllBookmarkSnapshotRows()
    for (let i = 0; i < rows.length; i++) {
      items.push(new SyncItem({
        key: rows[i].illust_id.toString(),
        data: stripSensitiveJson(rows[i].data),
        updatedAt: rows[i].updated_at,
        deleted: rows[i].deleted !== 0
      }))
    }
    return items
  }

  private collectMute(): SyncItem[] {
    let items: SyncItem[] = []
    let settings = userSettingStore.getSettings()
    let updatedAt = this.getLocalWrite(SYNC_DOMAIN_MUTE)
    if (updatedAt <= 0) {
      updatedAt = Date.now()
    }
    for (let i = 0; i < settings.muteTags.length; i++) {
      let data: Record<string, Object> = { 'value': settings.muteTags[i] }
      items.push(new SyncItem({
        key: 'tag:' + settings.muteTags[i],
        data: stripSensitiveJson(JSON.stringify(data)),
        updatedAt: updatedAt,
        deleted: false
      }))
    }
    for (let i = 0; i < settings.muteUsers.length; i++) {
      let data: Record<string, Object> = { 'value': settings.muteUsers[i].toString() }
      items.push(new SyncItem({
        key: 'user:' + settings.muteUsers[i].toString(),
        data: stripSensitiveJson(JSON.stringify(data)),
        updatedAt: updatedAt,
        deleted: false
      }))
    }
    let aiData: Record<string, Object> = { 'enabled': settings.aiFilter }
    items.push(new SyncItem({
      key: 'ai',
      data: stripSensitiveJson(JSON.stringify(aiData)),
      updatedAt: updatedAt,
      deleted: false
    }))
    return this.appendTombstones(SYNC_DOMAIN_MUTE, items)
  }

  private collectExifConfig(): SyncItem[] {
    let updatedAt = this.getLocalWrite(SYNC_DOMAIN_EXIF_CONFIG)
    if (updatedAt <= 0) {
      // 本地从未修改过 EXIF 配置，不上行（等待远端覆盖）
      return []
    }
    let settings = userSettingStore.getSettings()
    let rules: Object[] = settings.exifMergedTags.map((rule: ExifTagMergeRule): Object => {
      let obj: Record<string, Object> = { 'mainTag': rule.mainTag, 'fromTags': rule.fromTags }
      return obj
    })
    let data: Record<string, Object> = {
      'exifMutedTags': settings.exifMutedTags,
      'exifMergedTags': rules,
      'exifTagPriority': settings.exifTagPriority,
      'exifCommentTemplate': settings.exifCommentTemplate
    }
    let item = new SyncItem({
      key: 'config',
      data: stripSensitiveJson(JSON.stringify(data)),
      updatedAt: updatedAt,
      deleted: false
    })
    return [item]
  }

  private collectSettings(): SyncItem[] {
    let updatedAt = this.getLocalWrite(SYNC_DOMAIN_SETTINGS)
    if (updatedAt <= 0) {
      return []
    }
    let s = userSettingStore.getSettings()
    let data: Record<string, Object> = {
      'pictureQuality': s.pictureQuality,
      'mangaQuality': s.mangaQuality,
      'previewQuality': s.previewQuality,
      'detailQuality': s.detailQuality,
      'fullScreenQuality': s.fullScreenQuality,
      'downloadQuality': s.downloadQuality,
      'theme': s.theme,
      'language': s.language,
      'crossCount': s.crossCount,
      'isTopMode': s.isTopMode,
      'saveFormat': s.saveFormat,
      'autoBookmarkOnDownload': s.autoBookmarkOnDownload,
      'filenameTemplate': s.filenameTemplate,
      'showTranslatedTags': s.showTranslatedTags,
      'showR18Rank': s.showR18Rank,
      'antiSocialDeath': s.antiSocialDeath,
      'downloadConcurrency': s.downloadConcurrency,
      'imageHostType': s.imageHostType,
      'imageHostCustom': s.imageHostCustom,
      'relayServerUrl': s.relayServerUrl,
      'syncEnabled': s.syncEnabled
    }
    let item = new SyncItem({
      key: 'settings',
      data: stripSensitiveJson(JSON.stringify(data)),
      updatedAt: updatedAt,
      deleted: false
    })
    return [item]
  }

  // ---------------- appliers（六域下行合并：LWW + 墓碑） ----------------

  private async applyItems(domain: string, items: SyncItem[]): Promise<void> {
    if (items.length === 0) {
      return
    }
    if (domain === SYNC_DOMAIN_MUTE) {
      await this.applyMuteItems(items)
      return
    }
    for (let i = 0; i < items.length; i++) {
      try {
        await this.applyItem(domain, items[i])
      } catch (e) {
        console.error('Apply sync item failed (' + domain + '/' + items[i].key + '): ' + e)
      }
    }
  }

  private async applyItem(domain: string, item: SyncItem): Promise<void> {
    if (domain === SYNC_DOMAIN_HISTORY) {
      await this.applyHistoryItem(item)
    } else if (domain === SYNC_DOMAIN_SEARCH_HISTORY) {
      await this.applySearchHistoryItem(item)
    } else if (domain === SYNC_DOMAIN_BOOKMARK_SNAPSHOT) {
      await this.applyBookmarkSnapshotItem(item)
    } else if (domain === SYNC_DOMAIN_EXIF_CONFIG) {
      this.applyExifConfigItem(item)
    } else if (domain === SYNC_DOMAIN_SETTINGS) {
      this.applySettingsItem(item)
    }
  }

  private async applyHistoryItem(item: SyncItem): Promise<void> {
    let illustId = Number(item.key)
    if (Number.isNaN(illustId)) {
      return
    }
    let db = await getDbService()
    if (item.deleted) {
      await db.deleteHistory(illustId)
      return
    }
    let localTs = await db.getHistoryTimestamp(illustId)
    if (!shouldApplyRemote(localTs, item.updatedAt)) {
      return
    }
    let raw = JSON.parse(item.data) as RawHistorySyncData
    await db.upsertHistory(illustId, raw?.title ?? '', raw?.imageUrl ?? '', raw?.userName ?? '', raw?.viewedAt ?? item.updatedAt)
  }

  private async applySearchHistoryItem(item: SyncItem): Promise<void> {
    // key 格式 search_type:keyword（按首个冒号拆分）
    let sep = item.key.indexOf(':')
    if (sep < 0) {
      return
    }
    let searchType = item.key.substring(0, sep)
    let keyword = item.key.substring(sep + 1)
    let db = await getDbService()
    if (item.deleted) {
      await db.deleteSearchHistory(keyword, searchType)
      return
    }
    let localTs = await db.getSearchHistoryTimestamp(keyword, searchType)
    if (!shouldApplyRemote(localTs, item.updatedAt)) {
      return
    }
    await db.upsertSearchHistory(keyword, searchType, item.updatedAt)
  }

  private async applyBookmarkSnapshotItem(item: SyncItem): Promise<void> {
    let illustId = Number(item.key)
    if (Number.isNaN(illustId)) {
      return
    }
    let db = await getDbService()
    let local = await db.getBookmarkSnapshot(illustId)
    let localTs = local !== null ? local.updated_at : 0
    if (!shouldApplyRemote(localTs, item.updatedAt)) {
      return
    }
    if (item.deleted) {
      await db.markBookmarkSnapshotDeleted(illustId)
      return
    }
    await db.upsertBookmarkSnapshot(illustId, item.data, item.updatedAt, false)
  }

  /** mute 域：按 key 集合并集 + 墓碑移除，批量写回 */
  private async applyMuteItems(items: SyncItem[]): Promise<void> {
    let settings = userSettingStore.getSettings()
    let muteTags = settings.muteTags.slice()
    let muteUsers = settings.muteUsers.slice()
    let aiFilter = settings.aiFilter
    let localWrite = this.getLocalWrite(SYNC_DOMAIN_MUTE)
    let dirty = false
    for (let i = 0; i < items.length; i++) {
      let item = items[i]
      if (!shouldApplyRemote(localWrite, item.updatedAt)) {
        continue
      }
      if (item.key.startsWith('tag:')) {
        let tag = item.key.substring(4)
        let idx = muteTags.indexOf(tag)
        if (item.deleted) {
          if (idx >= 0) {
            muteTags.splice(idx, 1)
            dirty = true
          }
        } else if (idx < 0) {
          muteTags.push(tag)
          dirty = true
        }
      } else if (item.key.startsWith('user:')) {
        let userId = Number(item.key.substring(5))
        if (Number.isNaN(userId)) {
          continue
        }
        let idx = muteUsers.indexOf(userId)
        if (item.deleted) {
          if (idx >= 0) {
            muteUsers.splice(idx, 1)
            dirty = true
          }
        } else if (idx < 0) {
          muteUsers.push(userId)
          dirty = true
        }
      } else if (item.key === 'ai') {
        try {
          let raw = JSON.parse(item.data) as RawMuteValueData
          let enabled = raw?.enabled ?? false
          if (aiFilter !== enabled) {
            aiFilter = enabled
            dirty = true
          }
        } catch (e) {
          console.error('Parse mute ai item failed: ' + e)
        }
      }
    }
    if (dirty) {
      userSettingStore.setMuteTags(muteTags)
      userSettingStore.setMuteUsers(muteUsers)
      userSettingStore.setAiFilter(aiFilter)
    }
  }

  /** exif_config 域：整条 LWW（key 固定 'config'） */
  private applyExifConfigItem(item: SyncItem): void {
    if (item.deleted) {
      if (!shouldApplyRemote(this.getLocalWrite(SYNC_DOMAIN_EXIF_CONFIG), item.updatedAt)) {
        return
      }
      userSettingStore.setExifMutedTags([])
      userSettingStore.setExifMergedTags([])
      userSettingStore.setExifTagPriority([])
      userSettingStore.setExifCommentTemplate('PID:{illust_id} | {tags}')
      return
    }
    if (!shouldApplyRemote(this.getLocalWrite(SYNC_DOMAIN_EXIF_CONFIG), item.updatedAt)) {
      return
    }
    try {
      let raw = JSON.parse(item.data) as RawExifConfigSyncData
      userSettingStore.setExifMutedTags(raw?.exifMutedTags ?? [])
      let rules = (raw?.exifMergedTags ?? []).map((r: RawExifMergeRuleData) =>
        new ExifTagMergeRule({ mainTag: r.mainTag ?? '', fromTags: r.fromTags ?? [] }))
      userSettingStore.setExifMergedTags(rules)
      userSettingStore.setExifTagPriority(raw?.exifTagPriority ?? [])
      userSettingStore.setExifCommentTemplate(raw?.exifCommentTemplate ?? 'PID:{illust_id} | {tags}')
    } catch (e) {
      console.error('Apply exif_config failed: ' + e)
    }
  }

  /** settings 域：非敏感字段整条 LWW（key 固定 'settings'） */
  private applySettingsItem(item: SyncItem): void {
    if (item.deleted) {
      return
    }
    if (!shouldApplyRemote(this.getLocalWrite(SYNC_DOMAIN_SETTINGS), item.updatedAt)) {
      return
    }
    try {
      let raw = JSON.parse(item.data) as RawSettingsSyncData
      if (raw?.pictureQuality !== undefined) {
        userSettingStore.setPictureQuality(raw.pictureQuality)
      }
      if (raw?.mangaQuality !== undefined) {
        userSettingStore.setMangaQuality(raw.mangaQuality)
      }
      if (raw?.previewQuality !== undefined) {
        userSettingStore.setPreviewQuality(raw.previewQuality)
      }
      if (raw?.detailQuality !== undefined) {
        userSettingStore.setDetailQuality(raw.detailQuality)
      }
      if (raw?.fullScreenQuality !== undefined) {
        userSettingStore.setFullScreenQuality(raw.fullScreenQuality)
      }
      if (raw?.downloadQuality !== undefined) {
        userSettingStore.setDownloadQuality(raw.downloadQuality)
      }
      if (raw?.theme !== undefined) {
        userSettingStore.setTheme(raw.theme)
      }
      if (raw?.language !== undefined) {
        userSettingStore.setLanguage(raw.language)
      }
      if (raw?.crossCount !== undefined) {
        userSettingStore.setCrossCount(raw.crossCount)
      }
      if (raw?.isTopMode !== undefined) {
        userSettingStore.setIsTopMode(raw.isTopMode)
      }
      if (raw?.saveFormat !== undefined) {
        userSettingStore.setSaveFormat(raw.saveFormat)
      }
      if (raw?.autoBookmarkOnDownload !== undefined) {
        userSettingStore.setAutoBookmarkOnDownload(raw.autoBookmarkOnDownload)
      }
      if (raw?.filenameTemplate !== undefined) {
        userSettingStore.setFilenameTemplate(raw.filenameTemplate)
      }
      if (raw?.showTranslatedTags !== undefined) {
        userSettingStore.setShowTranslatedTags(raw.showTranslatedTags)
      }
      if (raw?.showR18Rank !== undefined) {
        userSettingStore.setShowR18Rank(raw.showR18Rank)
      }
      if (raw?.antiSocialDeath !== undefined) {
        userSettingStore.setAntiSocialDeath(raw.antiSocialDeath)
      }
      if (raw?.downloadConcurrency !== undefined) {
        userSettingStore.setDownloadConcurrency(raw.downloadConcurrency)
      }
      if (raw?.imageHostType !== undefined) {
        userSettingStore.setImageHostType(raw.imageHostType)
      }
      if (raw?.imageHostCustom !== undefined) {
        userSettingStore.setImageHostCustom(raw.imageHostCustom)
      }
      if (raw?.relayServerUrl !== undefined) {
        userSettingStore.setRelayServerUrl(raw.relayServerUrl)
      }
      // syncEnabled 不随远端覆盖本机开关（避免用户在 B 设备关闭同步后被 A 设备重新打开）
    } catch (e) {
      console.error('Apply settings failed: ' + e)
    }
  }

  // ---------------- 收藏快照（BookmarkStateStore 回调，fire-and-forget） ----------------

  onBookmarkChanged(illust: Illust, bookmarked: boolean): void {
    if (bookmarked) {
      this.pushBookmarkSnapshot(illust)
    } else {
      this.pushBookmarkTombstone(illust.id)
    }
  }

  /** star 成功：生成快照写本地表暂存 + 防抖 push；失败下轮重试，不阻塞收藏主流程 */
  pushBookmarkSnapshot(illust: Illust): void {
    if (!this.canSync()) {
      return
    }
    let now = Date.now()
    let snapshot = bookmarkSnapshotFromIllust(illust, now)
    let json = snapshot.toJsonString()
    getDbService()
      .then(async (db: DatabaseService): Promise<void> => {
        await db.upsertBookmarkSnapshot(illust.id, json, now, false)
        this.schedulePush(SYNC_DOMAIN_BOOKMARK_SNAPSHOT)
      })
      .catch((e: Object) => {
        console.error('Save bookmark snapshot failed: ' + e)
      })
  }

  /** unstar 成功：推墓碑（无本地快照行时插入最小墓碑行） */
  pushBookmarkTombstone(illustId: number): void {
    if (!this.canSync()) {
      return
    }
    let now = Date.now()
    getDbService()
      .then(async (db: DatabaseService): Promise<void> => {
        let local = await db.getBookmarkSnapshot(illustId)
        if (local !== null && local.data.length > 0) {
          await db.upsertBookmarkSnapshot(illustId, local.data, now, true)
        } else {
          let minimal = new BookmarkSnapshot({ illustId: illustId, bookmarkedAt: now })
          await db.upsertBookmarkSnapshot(illustId, minimal.toJsonString(), now, true)
        }
        this.schedulePush(SYNC_DOMAIN_BOOKMARK_SNAPSHOT)
      })
      .catch((e: Object) => {
        console.error('Save bookmark tombstone failed: ' + e)
      })
  }
}

export const syncService = SyncService.getInstance()
