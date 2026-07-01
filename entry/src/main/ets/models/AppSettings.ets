export interface AppSettingsOptions {
  pictureQuality?: number
  mangaQuality?: number
  theme?: string
  language?: string
  networkMode?: string
  crossCount?: number
  isTopMode?: boolean
  muteTags?: string[]
  muteUsers?: number[]
  aiFilter?: boolean
  saveFormat?: string
}

export class AppSettings {
  pictureQuality: number = 1
  mangaQuality: number = 1
  theme: string = 'system'
  language: string = 'zh-CN'
  networkMode: string = 'direct'
  crossCount: number = 2
  isTopMode: boolean = false
  muteTags: string[] = []
  muteUsers: number[] = []
  aiFilter: boolean = false
  saveFormat: string = 'png'

  constructor(options?: AppSettingsOptions) {
    if (options) {
      this.pictureQuality = options.pictureQuality ?? 1
      this.mangaQuality = options.mangaQuality ?? 1
      this.theme = options.theme ?? 'system'
      this.language = options.language ?? 'zh-CN'
      this.networkMode = options.networkMode ?? 'direct'
      this.crossCount = options.crossCount ?? 2
      this.isTopMode = options.isTopMode ?? false
      this.muteTags = options.muteTags ?? []
      this.muteUsers = options.muteUsers ?? []
      this.aiFilter = options.aiFilter ?? false
      this.saveFormat = options.saveFormat ?? 'png'
    }
  }
}
