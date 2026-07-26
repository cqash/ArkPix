export interface AppSettingsOptions {
  pictureQuality?: number
  mangaQuality?: number
  previewQuality?: number
  detailQuality?: number
  fullScreenQuality?: number
  downloadQuality?: number
  theme?: string
  language?: string
  networkMode?: string
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
  networkMode: string = 'direct'
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
      this.networkMode = options.networkMode ?? 'direct'
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
    }
  }
}
