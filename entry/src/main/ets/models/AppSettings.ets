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
  autoMergeTranslatedTags?: boolean
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
  prevAuthMode?: string
  prevApiMode?: string
}

export class AppSettings {
  pictureQuality: number = 1
  mangaQuality: number = 1
  previewQuality: number = 1
  detailQuality: number = 0
  fullScreenQuality: number = 0
  downloadQuality: number = 1
  theme: string = 'system'
  language: string = 'zh-CN'
  authMode: string = 'standard'
  apiMode: string = 'standard'
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
  autoMergeTranslatedTags: boolean = false
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
      this.language = options.language ?? 'zh-CN'
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
      this.autoMergeTranslatedTags = options.autoMergeTranslatedTags ?? false
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
      this.prevAuthMode = options.prevAuthMode ?? 'standard'
      this.prevApiMode = options.prevApiMode ?? 'standard'
    }
  }
}
