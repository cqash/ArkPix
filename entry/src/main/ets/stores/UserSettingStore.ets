import { preferenceService } from '../services/PreferenceService';
import { AppSettings, AppSettingsOptions, ExifTagMergeRule } from '../models/AppSettings';

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
      networkMode: preferenceService.getString('network_mode', 'direct'),
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
      exifTagPriority: preferenceService.getObject('exif_tag_priority', []) as string[]
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
    preferenceService.setString('network_mode', this.settings.networkMode)
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
      networkMode: this.settings.networkMode,
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
      exifTagPriority: this.settings.exifTagPriority.slice()
    })
  }

  setPictureQuality(value: number): void {
    this.settings.pictureQuality = value
    this.saveSettings()
  }

  setMangaQuality(value: number): void {
    this.settings.mangaQuality = value
    this.saveSettings()
  }

  setPreviewQuality(value: number): void {
    this.settings.previewQuality = value
    this.saveSettings()
  }

  setDetailQuality(value: number): void {
    this.settings.detailQuality = value
    this.saveSettings()
  }

  setFullScreenQuality(value: number): void {
    this.settings.fullScreenQuality = value
    this.saveSettings()
  }

  setDownloadQuality(value: number): void {
    this.settings.downloadQuality = value
    this.saveSettings()
  }

  setAutoBookmarkOnDownload(value: boolean): void {
    this.settings.autoBookmarkOnDownload = value
    this.saveSettings()
  }

  setFilenameTemplate(value: string): void {
    this.settings.filenameTemplate = value
    this.saveSettings()
  }

  setEmbedExifMetadata(value: boolean): void {
    this.settings.embedExifMetadata = value
    this.saveSettings()
  }

  setExifCommentTemplate(value: string): void {
    this.settings.exifCommentTemplate = value
    this.saveSettings()
  }

  setShowTranslatedTags(value: boolean): void {
    this.settings.showTranslatedTags = value
    this.saveSettings()
  }

  setShowR18Rank(value: boolean): void {
    this.settings.showR18Rank = value
    this.saveSettings()
  }

  setAntiSocialDeath(value: boolean): void {
    this.settings.antiSocialDeath = value
    this.saveSettings()
  }

  setTheme(value: string): void {
    this.settings.theme = value
    this.saveSettings()
  }

  setLanguage(value: string): void {
    this.settings.language = value
    this.saveSettings()
  }

  setNetworkMode(value: string): void {
    this.settings.networkMode = value
    this.saveSettings()
  }

  setCrossCount(value: number): void {
    this.settings.crossCount = value
    this.saveSettings()
  }

  setIsTopMode(value: boolean): void {
    this.settings.isTopMode = value
    this.saveSettings()
  }

  addMuteTag(tag: string): void {
    if (!this.settings.muteTags.includes(tag)) {
      this.settings.muteTags.push(tag)
      this.saveSettings()
    }
  }

  removeMuteTag(tag: string): void {
    let index = this.settings.muteTags.indexOf(tag)
    if (index >= 0) {
      this.settings.muteTags.splice(index, 1)
      this.saveSettings()
    }
  }

  addMuteUser(userId: number): void {
    if (!this.settings.muteUsers.includes(userId)) {
      this.settings.muteUsers.push(userId)
      this.saveSettings()
    }
  }

  removeMuteUser(userId: number): void {
    let index = this.settings.muteUsers.indexOf(userId)
    if (index >= 0) {
      this.settings.muteUsers.splice(index, 1)
      this.saveSettings()
    }
  }

  setAiFilter(value: boolean): void {
    this.settings.aiFilter = value
    this.saveSettings()
  }

  setSaveFormat(value: string): void {
    this.settings.saveFormat = value
    this.saveSettings()
  }

  addExifMutedTag(tag: string): void {
    if (!this.settings.exifMutedTags.includes(tag)) {
      this.settings.exifMutedTags.push(tag)
      this.saveSettings()
    }
  }

  removeExifMutedTag(tag: string): void {
    let index = this.settings.exifMutedTags.indexOf(tag)
    if (index >= 0) {
      this.settings.exifMutedTags.splice(index, 1)
      this.saveSettings()
    }
  }

  setExifMutedTags(tags: string[]): void {
    this.settings.exifMutedTags = tags.slice()
    this.saveSettings()
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
  }

  removeExifMergeRule(mainTag: string): void {
    for (let i = 0; i < this.settings.exifMergedTags.length; i++) {
      if (this.settings.exifMergedTags[i].mainTag === mainTag) {
        this.settings.exifMergedTags.splice(i, 1)
        break
      }
    }
    this.saveSettings()
  }

  setExifMergedTags(rules: ExifTagMergeRule[]): void {
    this.settings.exifMergedTags = rules.map(
      (rule: ExifTagMergeRule) => new ExifTagMergeRule({ mainTag: rule.mainTag, fromTags: rule.fromTags.slice() })
    )
    this.saveSettings()
  }

  setExifTagPriority(priority: string[]): void {
    this.settings.exifTagPriority = priority.slice()
    this.saveSettings()
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
  }
}

export const userSettingStore = UserSettingStore.getInstance()
