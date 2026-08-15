import { preferenceService } from '../services/PreferenceService';
import { AppSettings, AppSettingsOptions, ExifTagMergeRule } from '../models/AppSettings';
import { Constants } from '../utils/Constants';

// ---------------- 同步写入 hook（模块级回调，避免 UserSettingStore 反向 import SyncService 成环） ----------------
// domain：'mute' / 'exif_config' / 'settings'；tombstoneKeys：被移除项的同步 key（删除传播用）

export type SettingsWriteHook = (domain: string, tombstoneKeys: string[]) => void

let settingsWriteHooks: SettingsWriteHook[] = []

/** 注册写钩子监听器（多监听 fan-out：Relay SyncService 与 DistributedSyncService 各自注册） */
export function addSettingsWriteHook(hook: SettingsWriteHook): void {
  if (!settingsWriteHooks.includes(hook)) {
    settingsWriteHooks.push(hook)
  }
}

export function removeSettingsWriteHook(hook: SettingsWriteHook): void {
  let index = settingsWriteHooks.indexOf(hook)
  if (index >= 0) {
    settingsWriteHooks.splice(index, 1)
  }
}

/** 兼容包装：清空后单注册（既有 Relay SyncService 调用点行为不变） */
export function setSettingsWriteHook(hook: SettingsWriteHook): void {
  settingsWriteHooks = []
  settingsWriteHooks.push(hook)
}

function notifySettingsWrite(domain: string, tombstoneKeys: string[] = []): void {
  for (let i = 0; i < settingsWriteHooks.length; i++) {
    try {
      settingsWriteHooks[i](domain, tombstoneKeys)
    } catch (e) {
      console.error('Settings write hook failed: ' + e)
    }
  }
}

export class UserSettingStore {
  private static instance: UserSettingStore
  private settings: AppSettings = new AppSettings()

  private constructor() {
    this.loadSettings()
  }

  static getInstance(): UserSettingStore {
    if (!UserSettingStore.instance) {
      UserSettingStore.instance = new UserSettingStore()
    }
    return UserSettingStore.instance
  }

  private loadSettings(): void {
    let opts: AppSettingsOptions = {
      pictureQuality: preferenceService.getNumber('picture_quality', 1),
      mangaQuality: preferenceService.getNumber('manga_quality', 1),
      previewQuality: preferenceService.getNumber('preview_quality', 1),
      detailQuality: preferenceService.getNumber('detail_quality', 0),
      fullScreenQuality: preferenceService.getNumber('full_screen_quality', 0),
      downloadQuality: preferenceService.getNumber('download_quality', 1),
      theme: preferenceService.getString('theme', 'system'),
      language: preferenceService.getString('language', 'zh-CN'),
      authMode: Constants.normalizeMode(preferenceService.getString('auth_mode', 'standard')),
      apiMode: Constants.normalizeMode(preferenceService.getString('api_mode', 'standard')),
      crossCount: preferenceService.getNumber('cross_count', 2),
      isTopMode: preferenceService.getBoolean('is_top_mode', false),
      muteTags: preferenceService.getObject('mute_tags', []) as string[],
      muteUsers: preferenceService.getObject('mute_users', []) as number[],
      aiFilter: preferenceService.getBoolean('ai_filter', false),
      saveFormat: preferenceService.getString('save_format', 'png'),
      autoBookmarkOnDownload: preferenceService.getBoolean('auto_bookmark_on_download', false),
      filenameTemplate: preferenceService.getString('filename_template', '{illust_id}_p{part}'),
      embedExifMetadata: preferenceService.getBoolean('embed_exif_metadata', true),
      exifCommentTemplate: preferenceService.getString('exif_comment_template', 'PID:{illust_id} | {tags}'),
      showTranslatedTags: preferenceService.getBoolean('show_translated_tags', true),
      showR18Rank: preferenceService.getBoolean('show_r18_rank', false),
      antiSocialDeath: preferenceService.getBoolean('anti_social_death', false),
      exifMutedTags: preferenceService.getObject('exif_muted_tags', []) as string[],
      exifMergedTags: (preferenceService.getObject('exif_merged_tags', []) as ExifTagMergeRule[]).map(
        (rule: ExifTagMergeRule) => new ExifTagMergeRule({ mainTag: rule.mainTag, fromTags: rule.fromTags.slice() })
      ),
      exifTagPriority: preferenceService.getObject('exif_tag_priority', []) as string[],
      autoMergeTranslatedTags: preferenceService.getBoolean('auto_merge_translated_tags', false),
      downloadConcurrency: preferenceService.getNumber('download_concurrency', 3),
      proxyType: preferenceService.getString('proxy_type', 'http'),
      proxyHost: preferenceService.getString('proxy_host', ''),
      proxyPort: preferenceService.getNumber('proxy_port', 1080),
      proxyUsername: preferenceService.getString('proxy_username', ''),
      proxyPassword: preferenceService.getString('proxy_password', ''),
      imageHostType: preferenceService.getString('image_host_type', 'default'),
      imageHostCustom: preferenceService.getString('image_host_custom', 'i.pximg.net'),
      sniHost: preferenceService.getString('sni_host', ''),
      relayServerUrl: preferenceService.getString('relay_server_url', ''),
      syncEnabled: preferenceService.getBoolean('sync_enabled', false),
      autoSyncForeground: preferenceService.getBoolean('auto_sync_foreground', true),
      deviceSyncEnabled: preferenceService.getBoolean('device_sync_enabled', true),
      prevAuthMode: preferenceService.getString('prev_auth_mode', 'standard'),
      prevApiMode: preferenceService.getString('prev_api_mode', 'standard')
    }
    this.settings = new AppSettings(opts)
    AppStorage.setOrCreate('appSettings', this.settings)
  }

  private saveSettings(): void {
    preferenceService.setNumber('picture_quality', this.settings.pictureQuality)
    preferenceService.setNumber('manga_quality', this.settings.mangaQuality)
    preferenceService.setNumber('preview_quality', this.settings.previewQuality)
    preferenceService.setNumber('detail_quality', this.settings.detailQuality)
    preferenceService.setNumber('full_screen_quality', this.settings.fullScreenQuality)
    preferenceService.setNumber('download_quality', this.settings.downloadQuality)
    preferenceService.setString('theme', this.settings.theme)
    preferenceService.setString('language', this.settings.language)
    preferenceService.setString('auth_mode', this.settings.authMode)
    preferenceService.setString('api_mode', this.settings.apiMode)
    preferenceService.setNumber('cross_count', this.settings.crossCount)
    preferenceService.setBoolean('is_top_mode', this.settings.isTopMode)
    preferenceService.setObject('mute_tags', this.settings.muteTags)
    preferenceService.setObject('mute_users', this.settings.muteUsers)
    preferenceService.setBoolean('ai_filter', this.settings.aiFilter)
    preferenceService.setString('save_format', this.settings.saveFormat)
    preferenceService.setBoolean('auto_bookmark_on_download', this.settings.autoBookmarkOnDownload)
    preferenceService.setString('filename_template', this.settings.filenameTemplate)
    preferenceService.setBoolean('embed_exif_metadata', this.settings.embedExifMetadata)
    preferenceService.setString('exif_comment_template', this.settings.exifCommentTemplate)
    preferenceService.setBoolean('show_translated_tags', this.settings.showTranslatedTags)
    preferenceService.setBoolean('show_r18_rank', this.settings.showR18Rank)
    preferenceService.setBoolean('anti_social_death', this.settings.antiSocialDeath)
    preferenceService.setObject('exif_muted_tags', this.settings.exifMutedTags)
    preferenceService.setObject('exif_merged_tags', this.settings.exifMergedTags)
    preferenceService.setObject('exif_tag_priority', this.settings.exifTagPriority)
    preferenceService.setBoolean('auto_merge_translated_tags', this.settings.autoMergeTranslatedTags)
    preferenceService.setNumber('download_concurrency', this.settings.downloadConcurrency)
    preferenceService.setString('proxy_type', this.settings.proxyType)
    preferenceService.setString('proxy_host', this.settings.proxyHost)
    preferenceService.setNumber('proxy_port', this.settings.proxyPort)
    preferenceService.setString('proxy_username', this.settings.proxyUsername)
    preferenceService.setString('proxy_password', this.settings.proxyPassword)
    preferenceService.setString('image_host_type', this.settings.imageHostType)
    preferenceService.setString('image_host_custom', this.settings.imageHostCustom)
    preferenceService.setString('sni_host', this.settings.sniHost)
    preferenceService.setString('relay_server_url', this.settings.relayServerUrl)
    preferenceService.setBoolean('sync_enabled', this.settings.syncEnabled)
    preferenceService.setBoolean('auto_sync_foreground', this.settings.autoSyncForeground)
    preferenceService.setBoolean('device_sync_enabled', this.settings.deviceSyncEnabled)
    preferenceService.setString('prev_auth_mode', this.settings.prevAuthMode)
    preferenceService.setString('prev_api_mode', this.settings.prevApiMode)
    let newSettings: AppSettings = this.getSettings()
    this.settings = newSettings
    AppStorage.setOrCreate('appSettings', newSettings)
  }

  getSettings(): AppSettings {
    return new AppSettings({
      pictureQuality: this.settings.pictureQuality,
      mangaQuality: this.settings.mangaQuality,
      previewQuality: this.settings.previewQuality,
      detailQuality: this.settings.detailQuality,
      fullScreenQuality: this.settings.fullScreenQuality,
      downloadQuality: this.settings.downloadQuality,
      theme: this.settings.theme,
      language: this.settings.language,
      authMode: this.settings.authMode,
      apiMode: this.settings.apiMode,
      crossCount: this.settings.crossCount,
      isTopMode: this.settings.isTopMode,
      muteTags: this.settings.muteTags.slice(),
      muteUsers: this.settings.muteUsers.slice(),
      aiFilter: this.settings.aiFilter,
      saveFormat: this.settings.saveFormat,
      autoBookmarkOnDownload: this.settings.autoBookmarkOnDownload,
      filenameTemplate: this.settings.filenameTemplate,
      embedExifMetadata: this.settings.embedExifMetadata,
      exifCommentTemplate: this.settings.exifCommentTemplate,
      showTranslatedTags: this.settings.showTranslatedTags,
      showR18Rank: this.settings.showR18Rank,
      antiSocialDeath: this.settings.antiSocialDeath,
      exifMutedTags: this.settings.exifMutedTags.slice(),
      exifMergedTags: this.settings.exifMergedTags.map(
        (rule: ExifTagMergeRule) => new ExifTagMergeRule({ mainTag: rule.mainTag, fromTags: rule.fromTags.slice() })
      ),
      exifTagPriority: this.settings.exifTagPriority.slice(),
      autoMergeTranslatedTags: this.settings.autoMergeTranslatedTags,
      downloadConcurrency: this.settings.downloadConcurrency,
      proxyType: this.settings.proxyType,
      proxyHost: this.settings.proxyHost,
      proxyPort: this.settings.proxyPort,
      proxyUsername: this.settings.proxyUsername,
      proxyPassword: this.settings.proxyPassword,
      imageHostType: this.settings.imageHostType,
      imageHostCustom: this.settings.imageHostCustom,
      sniHost: this.settings.sniHost,
      relayServerUrl: this.settings.relayServerUrl,
      syncEnabled: this.settings.syncEnabled,
      autoSyncForeground: this.settings.autoSyncForeground,
      deviceSyncEnabled: this.settings.deviceSyncEnabled,
      prevAuthMode: this.settings.prevAuthMode,
      prevApiMode: this.settings.prevApiMode
    })
  }

  setPictureQuality(value: number): void {
    this.settings.pictureQuality = value
    this.saveSettings()
    notifySettingsWrite('settings')
  }

  setMangaQuality(value: number): void {
    this.settings.mangaQuality = value
    this.saveSettings()
    notifySettingsWrite('settings')
  }

  setPreviewQuality(value: number): void {
    this.settings.previewQuality = value
    this.saveSettings()
    notifySettingsWrite('settings')
  }

  setDetailQuality(value: number): void {
    this.settings.detailQuality = value
    this.saveSettings()
    notifySettingsWrite('settings')
  }

  setFullScreenQuality(value: number): void {
    this.settings.fullScreenQuality = value
    this.saveSettings()
    notifySettingsWrite('settings')
  }

  setDownloadQuality(value: number): void {
    this.settings.downloadQuality = value
    this.saveSettings()
    notifySettingsWrite('settings')
  }

  setDownloadConcurrency(value: number): void {
    this.settings.downloadConcurrency = value
    this.saveSettings()
    notifySettingsWrite('settings')
  }

  setAutoBookmarkOnDownload(value: boolean): void {
    this.settings.autoBookmarkOnDownload = value
    this.saveSettings()
    notifySettingsWrite('settings')
  }

  setFilenameTemplate(value: string): void {
    this.settings.filenameTemplate = value
    this.saveSettings()
    notifySettingsWrite('settings')
  }

  setEmbedExifMetadata(value: boolean): void {
    this.settings.embedExifMetadata = value
    this.saveSettings()
  }

  setExifCommentTemplate(value: string): void {
    this.settings.exifCommentTemplate = value
    this.saveSettings()
    notifySettingsWrite('exif_config')
  }

  setShowTranslatedTags(value: boolean): void {
    this.settings.showTranslatedTags = value
    this.saveSettings()
    notifySettingsWrite('settings')
  }

  setShowR18Rank(value: boolean): void {
    this.settings.showR18Rank = value
    this.saveSettings()
    notifySettingsWrite('settings')
  }

  setAntiSocialDeath(value: boolean): void {
    this.settings.antiSocialDeath = value
    this.saveSettings()
    notifySettingsWrite('settings')
  }

  setTheme(value: string): void {
    this.settings.theme = value
    this.saveSettings()
    notifySettingsWrite('settings')
  }

  setLanguage(value: string): void {
    this.settings.language = value
    this.saveSettings()
    notifySettingsWrite('settings')
  }

  setAuthMode(value: string): void {
    this.settings.authMode = value
    this.saveSettings()
  }

  setApiMode(value: string): void {
    this.settings.apiMode = value
    this.saveSettings()
  }

  setCrossCount(value: number): void {
    this.settings.crossCount = value
    this.saveSettings()
    notifySettingsWrite('settings')
  }

  setIsTopMode(value: boolean): void {
    this.settings.isTopMode = value
    this.saveSettings()
    notifySettingsWrite('settings')
  }

  addMuteTag(tag: string): void {
    if (!this.settings.muteTags.includes(tag)) {
      this.settings.muteTags.push(tag)
      this.saveSettings()
      notifySettingsWrite('mute')
    }
  }

  removeMuteTag(tag: string): void {
    let index = this.settings.muteTags.indexOf(tag)
    if (index >= 0) {
      this.settings.muteTags.splice(index, 1)
      this.saveSettings()
      notifySettingsWrite('mute', ['tag:' + tag])
    }
  }

  addMuteUser(userId: number): void {
    if (!this.settings.muteUsers.includes(userId)) {
      this.settings.muteUsers.push(userId)
      this.saveSettings()
      notifySettingsWrite('mute')
    }
  }

  removeMuteUser(userId: number): void {
    let index = this.settings.muteUsers.indexOf(userId)
    if (index >= 0) {
      this.settings.muteUsers.splice(index, 1)
      this.saveSettings()
      notifySettingsWrite('mute', ['user:' + userId.toString()])
    }
  }

  setAiFilter(value: boolean): void {
    this.settings.aiFilter = value
    this.saveSettings()
    notifySettingsWrite('mute')
  }

  /** 同步 applier 用：整体替换屏蔽标签/用户列表 */
  setMuteTags(tags: string[]): void {
    this.settings.muteTags = tags.slice()
    this.saveSettings()
    notifySettingsWrite('mute')
  }

  setMuteUsers(users: number[]): void {
    this.settings.muteUsers = users.slice()
    this.saveSettings()
    notifySettingsWrite('mute')
  }

  setSaveFormat(value: string): void {
    this.settings.saveFormat = value
    this.saveSettings()
    notifySettingsWrite('settings')
  }

  addExifMutedTag(tag: string): void {
    if (!this.settings.exifMutedTags.includes(tag)) {
      this.settings.exifMutedTags.push(tag)
      this.saveSettings()
      notifySettingsWrite('exif_config')
    }
  }

  removeExifMutedTag(tag: string): void {
    let index = this.settings.exifMutedTags.indexOf(tag)
    if (index >= 0) {
      this.settings.exifMutedTags.splice(index, 1)
      this.saveSettings()
      notifySettingsWrite('exif_config')
    }
  }

  setExifMutedTags(tags: string[]): void {
    this.settings.exifMutedTags = tags.slice()
    this.saveSettings()
    notifySettingsWrite('exif_config')
  }

  addExifMergeRule(mainTag: string, fromTags: string[]): void {
    // If mainTag is already a fromTag of an existing rule, remove it from that rule first
    for (let i = 0; i < this.settings.exifMergedTags.length; i++) {
      let rule = this.settings.exifMergedTags[i]
      let fromIdx = rule.fromTags.indexOf(mainTag)
      if (fromIdx >= 0) {
        rule.fromTags.splice(fromIdx, 1)
      }
    }
    // Filter out mainTag from fromTags
    let filteredFromTags: string[] = []
    for (let i = 0; i < fromTags.length; i++) {
      if (fromTags[i] !== mainTag) {
        filteredFromTags.push(fromTags[i])
      }
    }
    // Check if mainTag already has a rule; if so, append fromTags
    let existingRule: ExifTagMergeRule | undefined = undefined
    for (let i = 0; i < this.settings.exifMergedTags.length; i++) {
      if (this.settings.exifMergedTags[i].mainTag === mainTag) {
        existingRule = this.settings.exifMergedTags[i]
        break
      }
    }
    if (existingRule !== undefined) {
      for (let i = 0; i < filteredFromTags.length; i++) {
        if (!existingRule.fromTags.includes(filteredFromTags[i])) {
          existingRule.fromTags.push(filteredFromTags[i])
        }
      }
    } else {
      let newRule = new ExifTagMergeRule({ mainTag: mainTag, fromTags: filteredFromTags })
      this.settings.exifMergedTags.push(newRule)
    }
    this.saveSettings()
    notifySettingsWrite('exif_config')
  }

  removeExifMergeRule(mainTag: string): void {
    for (let i = 0; i < this.settings.exifMergedTags.length; i++) {
      if (this.settings.exifMergedTags[i].mainTag === mainTag) {
        this.settings.exifMergedTags.splice(i, 1)
        break
      }
    }
    this.saveSettings()
    notifySettingsWrite('exif_config')
  }

  setExifMergedTags(rules: ExifTagMergeRule[]): void {
    this.settings.exifMergedTags = rules.map(
      (rule: ExifTagMergeRule) => new ExifTagMergeRule({ mainTag: rule.mainTag, fromTags: rule.fromTags.slice() })
    )
    this.saveSettings()
    notifySettingsWrite('exif_config')
  }

  setExifTagPriority(priority: string[]): void {
    this.settings.exifTagPriority = priority.slice()
    this.saveSettings()
    notifySettingsWrite('exif_config')
  }

  updateExifTagPriority(confirmedTags: string[]): void {
    let result: string[] = []
    // Add confirmed tags in order, deduplicating
    for (let i = 0; i < confirmedTags.length; i++) {
      if (!result.includes(confirmedTags[i])) {
        result.push(confirmedTags[i])
      }
    }
    // Append existing priority tags that are not in confirmedTags
    for (let i = 0; i < this.settings.exifTagPriority.length; i++) {
      if (!result.includes(this.settings.exifTagPriority[i])) {
        result.push(this.settings.exifTagPriority[i])
      }
    }
    this.settings.exifTagPriority = result
    this.saveSettings()
    notifySettingsWrite('exif_config')
  }

  setAutoMergeTranslatedTags(value: boolean): void {
    this.settings.autoMergeTranslatedTags = value
    this.saveSettings()
  }

  setProxyType(value: string): void {
    this.settings.proxyType = value
    this.saveSettings()
  }

  setProxyHost(value: string): void {
    this.settings.proxyHost = value
    this.saveSettings()
  }

  setProxyPort(value: number): void {
    this.settings.proxyPort = value
    this.saveSettings()
  }

  setProxyUsername(value: string): void {
    this.settings.proxyUsername = value
    this.saveSettings()
  }

  setProxyPassword(value: string): void {
    this.settings.proxyPassword = value
    this.saveSettings()
  }

  setImageHostType(value: string): void {
    this.settings.imageHostType = value
    this.saveSettings()
    notifySettingsWrite('settings')
  }

  setImageHostCustom(value: string): void {
    this.settings.imageHostCustom = value
    this.saveSettings()
    notifySettingsWrite('settings')
  }

  setSniHost(value: string): void {
    this.settings.sniHost = value
    this.saveSettings()
  }

  setRelayServerUrl(value: string): void {
    this.settings.relayServerUrl = value.trim()
    this.saveSettings()
    notifySettingsWrite('settings')
  }

  setSyncEnabled(value: boolean): void {
    this.settings.syncEnabled = value
    this.saveSettings()
    notifySettingsWrite('settings')
  }

  /** 设备本地开关：不触发 settings 域上行（同 prevAuthMode/prevApiMode 处理） */
  setAutoSyncForeground(value: boolean): void {
    this.settings.autoSyncForeground = value
    this.saveSettings()
  }

  /** 设备本地开关（分布式对象同步）：不触发任何写钩子，避免"关同步被同步到对端"悖论 */
  setDeviceSyncEnabled(value: boolean): void {
    this.settings.deviceSyncEnabled = value
    this.saveSettings()
  }

  setPrevAuthMode(value: string): void {
    this.settings.prevAuthMode = value
    this.saveSettings()
  }

  setPrevApiMode(value: string): void {
    this.settings.prevApiMode = value
    this.saveSettings()
  }
}

export const userSettingStore = UserSettingStore.getInstance()
