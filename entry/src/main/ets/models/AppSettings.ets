export interface ExifTagMergeRuleOptions {
  mainTag?: string
  fromTags?: string[]
}

export class ExifTagMergeRule {
  mainTag: string = ''
  fromTags: string[] = []
  constructor(options?: ExifTagMergeRuleOptions) {
    if (options) {
      this.mainTag = options.mainTag ?? ''
      this.fromTags = options.fromTags ?? []
    }
  }
}

export interface AppSettingsOptions {
  pictureQuality?: number
  mangaQuality?: number
  previewQuality?: number
  detailQuality?: number
  fullScreenQuality?: number
  downloadQuality?: number
  theme?: string
  language?: string
  authMode?: string
  apiMode?: string
  crossCount?: number
  isTopMode?: boolean
  muteTags?: string[]
  muteUsers?: number[]
  aiFilter?: boolean
  saveFormat?: string
  autoBookmarkOnDownload?: boolean
  filenameTemplate?: string
  embedExifMetadata?: boolean
  exifCommentTemplate?: string
  showTranslatedTags?: boolean
  showR18Rank?: boolean
  antiSocialDeath?: boolean
  exifMutedTags?: string[]
  exifMergedTags?: ExifTagMergeRule[]
  exifTagPriority?: string[]
  downloadConcurrency?: number
  proxyType?: string
  proxyHost?: string
  proxyPort?: number
  proxyUsername?: string
  proxyPassword?: string
  imageHostType?: string
  imageHostCustom?: string
  sniHost?: string
  relayServerUrl?: string
  syncEnabled?: boolean
  autoSyncForeground?: boolean
  deviceSyncEnabled?: boolean
  hapticFeedback?: boolean
  longPressSaveConfirm?: boolean
  prevAuthMode?: string
  prevApiMode?: string
}

export class AppSettings {
  // 以下 5 个画质字段为设备本地，不参与设备间同步（FR-012：不同设备屏幕尺寸/形态不同）
  pictureQuality: number = 1
  mangaQuality: number = 1
  previewQuality: number = 1
  detailQuality: number = 0
  fullScreenQuality: number = 0
  downloadQuality: number = 1
  theme: string = 'system'
  /** 界面语言偏好：'system'（跟随系统，默认）/ 'zh-Hans' / 'zh-Hant' / 'en-Latn-US'；设备本地，不参与任何同步域 */
  language: string = 'system'
  authMode: string = 'standard'
  apiMode: string = 'standard'
  // 以下 2 个浏览布局字段为设备本地，不参与设备间同步（FR-012）
  crossCount: number = 2
  isTopMode: boolean = false
  muteTags: string[] = []
  muteUsers: number[] = []
  aiFilter: boolean = false
  saveFormat: string = 'png'
  autoBookmarkOnDownload: boolean = false
  filenameTemplate: string = '{illust_id}_p{part}'
  embedExifMetadata: boolean = true
  exifCommentTemplate: string = 'PID:{illust_id} | {tags}'
  showTranslatedTags: boolean = true
  showR18Rank: boolean = false
  antiSocialDeath: boolean = false
  exifMutedTags: string[] = []
  exifMergedTags: ExifTagMergeRule[] = []
  exifTagPriority: string[] = []
  downloadConcurrency: number = 3
  proxyType: string = 'http'
  proxyHost: string = ''
  proxyPort: number = 1080
  proxyUsername: string = ''
  proxyPassword: string = ''
  imageHostType: string = 'default'
  imageHostCustom: string = 'i.pximg.net'
  sniHost: string = ''
  relayServerUrl: string = ''
  syncEnabled: boolean = false
  /** 回到前台时自动补偿同步（设备本地开关，不随 settings 域同步） */
  autoSyncForeground: boolean = true
  /** 设备间同步（分布式数据对象）开关：设备本地，不参与任何同步域，避免"关同步被同步"悖论 */
  deviceSyncEnabled: boolean = true
  /** 触觉反馈总开关（设备本地，不随任何同步域） */
  hapticFeedback: boolean = true
  /** 长按保存前确认（设备本地，不随任何同步域） */
  longPressSaveConfirm: boolean = false
  prevAuthMode: string = 'standard'
  prevApiMode: string = 'standard'

  constructor(options?: AppSettingsOptions) {
    if (options) {
      this.pictureQuality = options.pictureQuality ?? 1
      this.mangaQuality = options.mangaQuality ?? 1
      this.previewQuality = options.previewQuality ?? 1
      this.detailQuality = options.detailQuality ?? 0
      this.fullScreenQuality = options.fullScreenQuality ?? 0
      this.downloadQuality = options.downloadQuality ?? 1
      this.theme = options.theme ?? 'system'
      this.language = options.language ?? 'system'
      this.authMode = options.authMode ?? 'standard'
      this.apiMode = options.apiMode ?? 'standard'
      this.crossCount = options.crossCount ?? 2
      this.isTopMode = options.isTopMode ?? false
      this.muteTags = options.muteTags ?? []
      this.muteUsers = options.muteUsers ?? []
      this.aiFilter = options.aiFilter ?? false
      this.saveFormat = options.saveFormat ?? 'png'
      this.autoBookmarkOnDownload = options.autoBookmarkOnDownload ?? false
      this.filenameTemplate = options.filenameTemplate ?? '{illust_id}_p{part}'
      this.embedExifMetadata = options.embedExifMetadata ?? true
      this.exifCommentTemplate = options.exifCommentTemplate ?? 'PID:{illust_id} | {tags}'
      this.showTranslatedTags = options.showTranslatedTags ?? true
      this.showR18Rank = options.showR18Rank ?? false
      this.antiSocialDeath = options.antiSocialDeath ?? false
      this.exifMutedTags = options.exifMutedTags ?? []
      this.exifMergedTags = (options.exifMergedTags ?? []).map(
        (rule: ExifTagMergeRule) => new ExifTagMergeRule({ mainTag: rule.mainTag, fromTags: rule.fromTags.slice() })
      )
      this.exifTagPriority = options.exifTagPriority ?? []
      this.downloadConcurrency = options.downloadConcurrency ?? 3
      this.proxyType = options.proxyType ?? 'http'
      this.proxyHost = options.proxyHost ?? ''
      this.proxyPort = options.proxyPort ?? 1080
      this.proxyUsername = options.proxyUsername ?? ''
      this.proxyPassword = options.proxyPassword ?? ''
      this.imageHostType = options.imageHostType ?? 'default'
      this.imageHostCustom = options.imageHostCustom ?? 'i.pximg.net'
      this.sniHost = options.sniHost ?? ''
      this.relayServerUrl = options.relayServerUrl ?? ''
      this.syncEnabled = options.syncEnabled ?? false
      this.autoSyncForeground = options.autoSyncForeground ?? true
      this.deviceSyncEnabled = options.deviceSyncEnabled ?? true
      this.hapticFeedback = options.hapticFeedback ?? true
      this.longPressSaveConfirm = options.longPressSaveConfirm ?? false
      this.prevAuthMode = options.prevAuthMode ?? 'standard'
      this.prevApiMode = options.prevApiMode ?? 'standard'
    }
  }
}
