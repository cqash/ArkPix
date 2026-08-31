import { distributedDataObject } from '@kit.ArkData';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { preferenceService } from './PreferenceService';
import { addSyncWriteHook, getDbService, HistoryItem, SearchHistoryItem } from './DatabaseService';
import { userSettingStore, addSettingsWriteHook } from '../stores/UserSettingStore';
import { AppSettings } from '../models/AppSettings';
import {
  DistributedSyncMeta,
  SyncedHistoryItem,
  SyncedSearchHistoryItem,
  DISTRIBUTED_SYNC_SCHEMA_VERSION,
  buildSyncMetaJson,
  buildHistorySyncJson,
  buildSearchHistorySyncJson,
  parseSyncMetaJson,
  parseSettingsSyncJson,
  parseHistorySyncJson,
  parseSearchHistorySyncJson,
  pickSyncNumber,
  pickSyncBoolean,
  pickSyncString,
  pickSyncStringArray,
  pickSyncNumberArray,
  pickSyncExifMergeRules
} from '../models/ContinuationPayload';

const DOMAIN = 0x0000;
const TAG = 'DistributedSyncService';

/** 固定同步会话 ID（仅字母数字下划线，≤128 字符） */
export const DISTRIBUTED_SYNC_SESSION_ID: string = 'arkpix_device_sync'

const PREF_KEY_DEVICE_ID: string = 'distributed_sync_device_id'
/** 设置域下行 LWW：本地已应用的远端 metaJson.updatedAt */
const PREF_KEY_LAST_APPLIED_SETTINGS_AT: string = 'distributed_sync_applied_settings_at'

/** 写钩子触发上行前的防抖窗口 */
const PUSH_DEBOUNCE_MS: number = 2000

/** 历史同步裁剪窗口（单对象 ≤500KB 预算：100 条浏览 ≈30-50KB，50 条搜索 ≈5KB） */
const HISTORY_SYNC_LIMIT: number = 100
const SEARCH_HISTORY_SYNC_LIMIT: number = 50

/** 分布式对象根属性：复杂类型仅根属性变更触发同步，故全部域载荷保持 JSON 字符串根属性设计 */
class SyncRootObject {
  settingsJson: string = ''
  historyJson: string = ''
  searchHistoryJson: string = ''
  metaJson: string = ''
  updatedAt: number = 0
}

/**
 * 设备间同步服务（分布式数据对象通道）。
 * 与既有 Relay SyncService 双通道共存、互不耦合：仅共享写钩子 fan-out 与 hook-free applier。
 * 全部系统调用 try-catch + hilog，任何失败静默降级为纯本地运行。
 * 注意：本服务依赖 UserSettingStore/PreferenceService 模块级单例，EntryAbility 必须 lazy import。
 */
export class DistributedSyncService {
  private static instance: DistributedSyncService
  private initialized: boolean = false
  private dataObject: distributedDataObject.DataObject | null = null
  /** 是否已加入同步会话（setSessionId 成功） */
  private sessionActive: boolean = false
  /** 下行应用期间抑制本地写入回传（防回声循环） */
  private applyingRemote: boolean = false
  private deviceId: string = ''
  private settingsPushTimer: number = -1
  private historyPushTimer: number = -1

  private constructor() {
  }

  static getInstance(): DistributedSyncService {
    if (!DistributedSyncService.instance) {
      DistributedSyncService.instance = new DistributedSyncService()
    }
    return DistributedSyncService.instance
  }

  /** 下行应用期间标志（写钩子侧防回声判定用） */
  isApplyingRemote(): boolean {
    return this.applyingRemote
  }

  /** 会话状态（设置页"已加入会话"显示用） */
  isActive(): boolean {
    return this.sessionActive
  }

  /**
   * sessionActive 唯一写入点（FR-013）：每次变更同步 AppStorage 键 deviceSyncActive，
   * 设置页经 @StorageLink 订阅，入会话成功瞬间 UI 自动更新，无需轮询。
   */
  private setSessionActive(active: boolean): void {
    this.sessionActive = active
    AppStorage.setOrCreate('deviceSyncActive', active)
  }

  /**
   * 幂等初始化：读 deviceSyncEnabled → 创建 DataObject → 注册 change/status 监听 + 写钩子。
   * 开关关闭时仍完成对象创建与监听注册（保持幂等可重开），但不加入会话。
   */
  init(): void {
    if (this.initialized) {
      return
    }
    this.initialized = true
    // 写入 AppStorage 初值，保证 @StorageLink('deviceSyncActive') 订阅的键始终存在
    AppStorage.setOrCreate('deviceSyncActive', false)
    try {
      let ctx = AppStorage.get<common.UIAbilityContext>('context')
      if (!ctx) {
        hilog.error(DOMAIN, TAG, 'init aborted: UIAbilityContext not found in AppStorage')
        return
      }
      this.deviceId = this.loadOrCreateDeviceId()
      let source = new SyncRootObject()
      this.dataObject = distributedDataObject.create(ctx.getApplicationContext(), source)
      this.registerListeners()
      this.registerWriteHooks()
      if (userSettingStore.getSettings().deviceSyncEnabled) {
        this.joinSession()
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'init failed: %{public}s', JSON.stringify(e))
      this.dataObject = null
    }
  }

  /**
   * 设置页开关：开启=运行时申请 DISTRIBUTED_DATASYNC → 授权后加入会话；
   * 关闭=退出会话（本地数据保留）。结果经 onResult 回调（授权拒绝时设置页回退开关 + toast）。
   */
  setEnabled(enabled: boolean, onResult?: (success: boolean) => void): void {
    if (!enabled) {
      userSettingStore.setDeviceSyncEnabled(false)
      this.leaveSession()
      if (onResult) {
        onResult(true)
      }
      return
    }
    this.requestDataSyncPermission()
      .then((granted: boolean) => {
        if (granted) {
          userSettingStore.setDeviceSyncEnabled(true)
          // FR-013：授权后首次入会话可能因组网未就绪失败，允许延迟 2s 重试一次
          this.joinSession(true)
          if (onResult) {
            onResult(true)
          }
        } else {
          // 拒绝：开关回退（保持关闭），由设置页 toast 引导
          userSettingStore.setDeviceSyncEnabled(false)
          if (onResult) {
            onResult(false)
          }
        }
      })
      .catch((e: Object) => {
        hilog.error(DOMAIN, TAG, 'setEnabled request failed: %{public}s', JSON.stringify(e))
        userSettingStore.setDeviceSyncEnabled(false)
        if (onResult) {
          onResult(false)
        }
      })
  }

  // ---------------- 内部：会话生命周期 ----------------

  /**
   * 加入同步会话。allowRetry=true（授权后首次开启）时失败延迟 2s 重试一次，仍失败保持降级。
   */
  private joinSession(allowRetry: boolean = false): void {
    let obj = this.dataObject
    if (obj === null) {
      return
    }
    obj.setSessionId(DISTRIBUTED_SYNC_SESSION_ID)
      .then(() => {
        this.setSessionActive(true)
        hilog.info(DOMAIN, TAG, 'joined sync session')
        // 入会话后先 reconciliate（远端较新则先应用），避免用本地旧快照覆盖远端
        this.reconcileAll()
      })
      .catch((e: Object) => {
        // 常见失败：201 未授权 / 未组网——静默降级纯本地
        this.setSessionActive(false)
        hilog.warn(DOMAIN, TAG, 'join session failed (degrade to local): %{public}s', JSON.stringify(e))
        if (allowRetry) {
          setTimeout(() => {
            // 重试前确认仍未入会话且开关未被中途关闭
            if (!this.sessionActive && userSettingStore.getSettings().deviceSyncEnabled) {
              hilog.info(DOMAIN, TAG, 'retry join session once after authorization')
              this.joinSession(false)
            }
          }, 2000)
        }
      })
  }

  private leaveSession(): void {
    let obj = this.dataObject
    if (obj === null || !this.sessionActive) {
      this.setSessionActive(false)
      return
    }
    obj.setSessionId('')
      .then(() => {
        hilog.info(DOMAIN, TAG, 'left sync session')
      })
      .catch((e: Object) => {
        hilog.warn(DOMAIN, TAG, 'leave session failed: %{public}s', JSON.stringify(e))
      })
    this.setSessionActive(false)
  }

  private async requestDataSyncPermission(): Promise<boolean> {
    try {
      let ctx = AppStorage.get<common.UIAbilityContext>('context')
      if (!ctx) {
        return false
      }
      let atManager = abilityAccessCtrl.createAtManager()
      let permissions: Permissions[] = ['ohos.permission.DISTRIBUTED_DATASYNC']
      let result = await atManager.requestPermissionsFromUser(ctx, permissions)
      for (let i = 0; i < result.authResults.length; i++) {
        if (result.authResults[i] !== 0) {
          return false
        }
      }
      return result.authResults.length > 0
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'requestPermissionsFromUser failed: %{public}s', JSON.stringify(e))
      return false
    }
  }

  // ---------------- 内部：监听注册 ----------------

  private registerListeners(): void {
    let obj = this.dataObject
    if (obj === null) {
      return
    }
    try {
      obj.on('change', (sessionId: string, fields: string[]) => {
        this.onRemoteChange(fields)
      })
      obj.on('status', (sessionId: string, networkId: string, status: 'online' | 'offline') => {
        hilog.info(DOMAIN, TAG, 'sync peer %{public}s %{public}s', networkId, status)
        if (status === 'online') {
          // 对端上线：先应用远端较新数据再推本地，避免旧数据覆盖新数据
          this.reconcileAll()
        }
      })
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'registerListeners failed: %{public}s', JSON.stringify(e))
    }
  }

  private registerWriteHooks(): void {
    addSettingsWriteHook((domain: string, tombstoneKeys: string[]) => {
      if (this.applyingRemote) {
        return
      }
      this.scheduleSettingsPush()
    })
    addSyncWriteHook((domain: string, tombstoneKeys: string[]) => {
      if (this.applyingRemote) {
        return
      }
      if (domain === 'history' || domain === 'search_history') {
        this.scheduleHistoryPush()
      }
    })
  }

  // ---------------- 内部：根属性读写（DataObject 无字段声明，经 Reflect 读写规避动态索引） ----------------

  private readRootString(field: string): string {
    let obj = this.dataObject
    if (obj === null) {
      return ''
    }
    try {
      let value: Object = Reflect.get(obj, field)
      if (typeof value === 'string') {
        return value
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'readRootString %{public}s failed: %{public}s', field, JSON.stringify(e))
    }
    return ''
  }

  private writeRoot(field: string, value: string): void {
    let obj = this.dataObject
    if (obj === null) {
      return
    }
    // 编码断言：单分布式对象 ≤500KB（各域裁剪后预算 ≈100KB，超限即实现偏离，告警但仍写入本地不受影响）
    if (value.length > 500 * 1024) {
      hilog.warn(DOMAIN, TAG, 'sync payload %{public}s exceeds 500KB budget: %{public}d', field, value.length)
    }
    try {
      Reflect.set(obj, field, value)
      Reflect.set(obj, 'updatedAt', Date.now())
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'writeRoot %{public}s failed: %{public}s', field, JSON.stringify(e))
    }
  }

  // ---------------- 上行/下行编排 ----------------

  /** 入会话/对端上线时全量 reconciliate：远端较新先应用，否则推本地 */
  private reconcileAll(): void {
    if (!this.sessionActive) {
      return
    }
    // 设置：远端 meta 较新且来自其他设备 → 应用远端；否则推本地（含远端为空时的播种）
    let meta = parseSyncMetaJson(this.readRootString('metaJson'))
    if (meta !== null && meta.deviceId !== this.deviceId &&
      meta.updatedAt > this.getLastAppliedSettingsAt()) {
      this.handleRemoteSettings()
    } else {
      this.pushSettingsNow()
    }
    // 历史：条目级 LWW 应用远端（幂等），再推本地合并后快照
    this.applyRemoteHistory()
    this.applyRemoteSearchHistory()
    this.pushHistoryNow()
  }

  private scheduleSettingsPush(): void {
    if (!this.sessionActive) {
      return
    }
    if (this.settingsPushTimer >= 0) {
      clearTimeout(this.settingsPushTimer)
    }
    this.settingsPushTimer = setTimeout(() => {
      this.settingsPushTimer = -1
      this.pushSettingsNow()
    }, PUSH_DEBOUNCE_MS)
  }

  private scheduleHistoryPush(): void {
    if (!this.sessionActive) {
      return
    }
    if (this.historyPushTimer >= 0) {
      clearTimeout(this.historyPushTimer)
    }
    this.historyPushTimer = setTimeout(() => {
      this.historyPushTimer = -1
      this.pushHistoryNow()
    }, PUSH_DEBOUNCE_MS)
  }

  // ---------------- 设置域上行（US3/US4：mute/exif_config 域共用 settingsJson 载荷） ----------------

  /**
   * 可同步字段全集序列化。
   * 排除设备本地字段：deviceSyncEnabled / autoSyncForeground / syncEnabled（Relay 账号绑定）
   * / relayServerUrl / prevAuthMode / prevApiMode / language（界面语言偏好，设备本地）。
   * 另排除浏览相关字段（FR-012，不同设备屏幕尺寸/形态不同，保持设备本地）：
   * pictureQuality / mangaQuality / previewQuality / detailQuality / fullScreenQuality
   * / crossCount / isTopMode；downloadQuality 等非浏览字段仍同步。
   */
  private buildSettingsPayload(settings: AppSettings): Record<string, Object> {
    let payload: Record<string, Object> = {}
    payload['downloadQuality'] = settings.downloadQuality
    payload['theme'] = settings.theme
    payload['authMode'] = settings.authMode
    payload['apiMode'] = settings.apiMode
    payload['muteTags'] = settings.muteTags
    payload['muteUsers'] = settings.muteUsers
    payload['aiFilter'] = settings.aiFilter
    payload['saveFormat'] = settings.saveFormat
    payload['autoBookmarkOnDownload'] = settings.autoBookmarkOnDownload
    payload['filenameTemplate'] = settings.filenameTemplate
    payload['embedExifMetadata'] = settings.embedExifMetadata
    payload['exifCommentTemplate'] = settings.exifCommentTemplate
    payload['showTranslatedTags'] = settings.showTranslatedTags
    payload['showR18Rank'] = settings.showR18Rank
    payload['antiSocialDeath'] = settings.antiSocialDeath
    payload['exifMutedTags'] = settings.exifMutedTags
    payload['exifMergedTags'] = settings.exifMergedTags
    payload['exifTagPriority'] = settings.exifTagPriority
    payload['downloadConcurrency'] = settings.downloadConcurrency
    payload['proxyType'] = settings.proxyType
    payload['proxyHost'] = settings.proxyHost
    payload['proxyPort'] = settings.proxyPort
    payload['proxyUsername'] = settings.proxyUsername
    payload['proxyPassword'] = settings.proxyPassword
    payload['imageHostType'] = settings.imageHostType
    payload['imageHostCustom'] = settings.imageHostCustom
    payload['sniHost'] = settings.sniHost
    return payload
  }

  /** 设置上行：重建 settingsJson + metaJson 根属性（写钩子 → 防抖 2s → 此处） */
  private pushSettingsNow(): void {
    if (!this.sessionActive) {
      return
    }
    try {
      let settings = userSettingStore.getSettings()
      let now = Date.now()
      let meta: DistributedSyncMeta = {
        deviceId: this.deviceId,
        updatedAt: now,
        schemaVersion: DISTRIBUTED_SYNC_SCHEMA_VERSION
      }
      this.writeRoot('settingsJson', JSON.stringify(this.buildSettingsPayload(settings)))
      this.writeRoot('metaJson', buildSyncMetaJson(meta))
      // 本地写入视为已应用到本端时间线，防止自己的回声被当作远端新数据
      this.recordAppliedSettingsAt(now)
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'pushSettingsNow failed: %{public}s', JSON.stringify(e))
    }
  }

  // ---------------- 设置域下行（LWW：metaJson.updatedAt 严格大于本地已应用时间才应用） ----------------

  private handleRemoteSettings(): void {
    let meta = parseSyncMetaJson(this.readRootString('metaJson'))
    if (meta === null) {
      return
    }
    if (meta.deviceId === this.deviceId) {
      return // 本设备写入的回声
    }
    if (meta.updatedAt <= this.getLastAppliedSettingsAt()) {
      return // LWW：非严格更新不应用
    }
    let fields = parseSettingsSyncJson(this.readRootString('settingsJson'))
    if (fields === null) {
      return
    }
    this.applyingRemote = true
    try {
      this.applySettingsFields(fields)
      this.recordAppliedSettingsAt(meta.updatedAt)
      hilog.info(DOMAIN, TAG, 'remote settings applied, updatedAt=%{public}d', meta.updatedAt)
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'apply remote settings failed: %{public}s', JSON.stringify(e))
    } finally {
      this.applyingRemote = false
    }
  }

  /** 逐字段经 UserSettingStore 既有 setter 落偏好（suppress 期间防回声）；未知字段缺失即跳过 */
  private applySettingsFields(fields: Record<string, Object>): void {
    let current = userSettingStore.getSettings()
    // FR-012：浏览相关字段（pictureQuality/mangaQuality/previewQuality/detailQuality/
    // fullScreenQuality/crossCount/isTopMode）为设备本地，对端旧载荷残留这些字段时跳过不应用
    this.applyNumberField(fields, 'downloadQuality', current.downloadQuality,
      (v: number) => userSettingStore.setDownloadQuality(v))
    this.applyStringField(fields, 'theme', current.theme, (v: string) => userSettingStore.setTheme(v))
    this.applyStringField(fields, 'authMode', current.authMode, (v: string) => userSettingStore.setAuthMode(v))
    this.applyStringField(fields, 'apiMode', current.apiMode, (v: string) => userSettingStore.setApiMode(v))
    this.applyBooleanField(fields, 'aiFilter', current.aiFilter, (v: boolean) => userSettingStore.setAiFilter(v))
    this.applyStringField(fields, 'saveFormat', current.saveFormat,
      (v: string) => userSettingStore.setSaveFormat(v))
    this.applyBooleanField(fields, 'autoBookmarkOnDownload', current.autoBookmarkOnDownload,
      (v: boolean) => userSettingStore.setAutoBookmarkOnDownload(v))
    this.applyStringField(fields, 'filenameTemplate', current.filenameTemplate,
      (v: string) => userSettingStore.setFilenameTemplate(v))
    this.applyBooleanField(fields, 'embedExifMetadata', current.embedExifMetadata,
      (v: boolean) => userSettingStore.setEmbedExifMetadata(v))
    this.applyStringField(fields, 'exifCommentTemplate', current.exifCommentTemplate,
      (v: string) => userSettingStore.setExifCommentTemplate(v))
    this.applyBooleanField(fields, 'showTranslatedTags', current.showTranslatedTags,
      (v: boolean) => userSettingStore.setShowTranslatedTags(v))
    this.applyBooleanField(fields, 'showR18Rank', current.showR18Rank,
      (v: boolean) => userSettingStore.setShowR18Rank(v))
    this.applyBooleanField(fields, 'antiSocialDeath', current.antiSocialDeath,
      (v: boolean) => userSettingStore.setAntiSocialDeath(v))
    this.applyNumberField(fields, 'downloadConcurrency', current.downloadConcurrency,
      (v: number) => userSettingStore.setDownloadConcurrency(v))
    this.applyStringField(fields, 'proxyType', current.proxyType,
      (v: string) => userSettingStore.setProxyType(v))
    this.applyStringField(fields, 'proxyHost', current.proxyHost,
      (v: string) => userSettingStore.setProxyHost(v))
    this.applyNumberField(fields, 'proxyPort', current.proxyPort,
      (v: number) => userSettingStore.setProxyPort(v))
    this.applyStringField(fields, 'proxyUsername', current.proxyUsername,
      (v: string) => userSettingStore.setProxyUsername(v))
    this.applyStringField(fields, 'proxyPassword', current.proxyPassword,
      (v: string) => userSettingStore.setProxyPassword(v))
    this.applyStringField(fields, 'imageHostType', current.imageHostType,
      (v: string) => userSettingStore.setImageHostType(v))
    this.applyStringField(fields, 'imageHostCustom', current.imageHostCustom,
      (v: string) => userSettingStore.setImageHostCustom(v))
    this.applyStringField(fields, 'sniHost', current.sniHost, (v: string) => userSettingStore.setSniHost(v))
    // US4：屏蔽列表与 EXIF 配置随设置通道下行（整体替换语义，setter 均为 suppress 保护路径）
    this.applyStringArrayField(fields, 'muteTags', current.muteTags,
      (v: string[]) => userSettingStore.setMuteTags(v))
    this.applyNumberArrayField(fields, 'muteUsers', current.muteUsers,
      (v: number[]) => userSettingStore.setMuteUsers(v))
    this.applyStringArrayField(fields, 'exifMutedTags', current.exifMutedTags,
      (v: string[]) => userSettingStore.setExifMutedTags(v))
    this.applyStringArrayField(fields, 'exifTagPriority', current.exifTagPriority,
      (v: string[]) => userSettingStore.setExifTagPriority(v))
    let rules = pickSyncExifMergeRules(fields, 'exifMergedTags')
    if (rules !== null && JSON.stringify(rules) !== JSON.stringify(current.exifMergedTags)) {
      userSettingStore.setExifMergedTags(rules)
    }
  }

  private applyNumberField(fields: Record<string, Object>, key: string, current: number,
    setter: (v: number) => void): void {
    let value = pickSyncNumber(fields, key)
    if (value !== null && value !== current) {
      setter(value)
    }
  }

  private applyBooleanField(fields: Record<string, Object>, key: string, current: boolean,
    setter: (v: boolean) => void): void {
    let value = pickSyncBoolean(fields, key)
    if (value !== null && value !== current) {
      setter(value)
    }
  }

  private applyStringField(fields: Record<string, Object>, key: string, current: string,
    setter: (v: string) => void): void {
    let value = pickSyncString(fields, key)
    if (value !== null && value !== current) {
      setter(value)
    }
  }

  private applyStringArrayField(fields: Record<string, Object>, key: string, current: string[],
    setter: (v: string[]) => void): void {
    let value = pickSyncStringArray(fields, key)
    if (value !== null && JSON.stringify(value) !== JSON.stringify(current)) {
      setter(value)
    }
  }

  private applyNumberArrayField(fields: Record<string, Object>, key: string, current: number[],
    setter: (v: number[]) => void): void {
    let value = pickSyncNumberArray(fields, key)
    if (value !== null && JSON.stringify(value) !== JSON.stringify(current)) {
      setter(value)
    }
  }

  // ---------------- 历史域上行/下行（US5） ----------------

  /** 历史上行：裁剪最近 100 条浏览 + 50 条搜索，序列化赋值对应根属性（防抖 2s 后触发） */
  private pushHistoryNow(): void {
    if (!this.sessionActive) {
      return
    }
    getDbService()
      .then(async (db) => {
        let history = await db.getHistory(HISTORY_SYNC_LIMIT)
        let historyItems: SyncedHistoryItem[] = []
        for (let i = 0; i < history.length; i++) {
          let entry: HistoryItem = history[i]
          let item: SyncedHistoryItem = {
            illustId: entry.illust_id,
            title: entry.title,
            imageUrl: entry.image_url,
            userName: entry.user_name,
            timestamp: entry.timestamp
          }
          historyItems.push(item)
        }
        let search = await db.getSearchHistory(SEARCH_HISTORY_SYNC_LIMIT)
        let searchItems: SyncedSearchHistoryItem[] = []
        for (let i = 0; i < search.length; i++) {
          let entry: SearchHistoryItem = search[i]
          let item: SyncedSearchHistoryItem = {
            keyword: entry.keyword,
            searchType: entry.search_type,
            timestamp: entry.timestamp
          }
          searchItems.push(item)
        }
        if (!this.sessionActive) {
          return // await 期间会话可能已退出
        }
        this.writeRoot('historyJson', buildHistorySyncJson(historyItems))
        this.writeRoot('searchHistoryJson', buildSearchHistorySyncJson(searchItems))
      })
      .catch((e: Object) => {
        hilog.error(DOMAIN, TAG, 'pushHistoryNow failed: %{public}s', JSON.stringify(e))
      })
  }

  /**
   * 浏览历史下行：逐条 LWW（远端 timestamp 严格大于本地才 upsert）。
   * 走 hook-free applier（upsertHistory 内部不触发写钩子），天然无回声，无需 suppress。
   */
  private applyRemoteHistory(): void {
    let parsed = parseHistorySyncJson(this.readRootString('historyJson'))
    if (parsed === null || parsed.length === 0) {
      return
    }
    let items: SyncedHistoryItem[] = parsed
    getDbService()
      .then(async (db) => {
        for (let i = 0; i < items.length; i++) {
          let item = items[i]
          let localTs = await db.getHistoryTimestamp(item.illustId)
          if (item.timestamp > localTs) {
            await db.upsertHistory(item.illustId, item.title, item.imageUrl, item.userName, item.timestamp)
          }
        }
      })
      .catch((e: Object) => {
        hilog.error(DOMAIN, TAG, 'applyRemoteHistory failed: %{public}s', JSON.stringify(e))
      })
  }

  /** 搜索历史下行：逐条 LWW（keyword+searchType 粒度），hook-free applier 无回声 */
  private applyRemoteSearchHistory(): void {
    let parsed = parseSearchHistorySyncJson(this.readRootString('searchHistoryJson'))
    if (parsed === null || parsed.length === 0) {
      return
    }
    let items: SyncedSearchHistoryItem[] = parsed
    getDbService()
      .then(async (db) => {
        for (let i = 0; i < items.length; i++) {
          let item = items[i]
          let localTs = await db.getSearchHistoryTimestamp(item.keyword, item.searchType)
          if (item.timestamp > localTs) {
            await db.upsertSearchHistory(item.keyword, item.searchType, item.timestamp)
          }
        }
      })
      .catch((e: Object) => {
        hilog.error(DOMAIN, TAG, 'applyRemoteSearchHistory failed: %{public}s', JSON.stringify(e))
      })
  }

  /** 远端变更分发：按根属性域路由到对应下行处理 */
  private onRemoteChange(fields: string[]): void {
    if (!this.sessionActive) {
      return
    }
    hilog.info(DOMAIN, TAG, 'remote change fields: %{public}s', fields.join(','))
    for (let i = 0; i < fields.length; i++) {
      let field = fields[i]
      if (field === 'settingsJson' || field === 'metaJson') {
        this.handleRemoteSettings()
      } else if (field === 'historyJson') {
        this.applyRemoteHistory()
      } else if (field === 'searchHistoryJson') {
        this.applyRemoteSearchHistory()
      }
    }
  }

  // ---------------- 内部：工具 ----------------

  private loadOrCreateDeviceId(): string {
    let id = preferenceService.getString(PREF_KEY_DEVICE_ID, '')
    if (id.length === 0) {
      id = util.generateRandomUUID(false)
      preferenceService.setString(PREF_KEY_DEVICE_ID, id)
    }
    return id
  }

  private getLastAppliedSettingsAt(): number {
    return preferenceService.getNumber(PREF_KEY_LAST_APPLIED_SETTINGS_AT, 0)
  }

  private recordAppliedSettingsAt(ts: number): void {
    preferenceService.setNumber(PREF_KEY_LAST_APPLIED_SETTINGS_AT, ts)
  }
}

export const distributedSyncService = DistributedSyncService.getInstance()
