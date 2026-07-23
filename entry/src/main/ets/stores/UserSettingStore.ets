import { preferenceService } from '../services/PreferenceService';
import { AppSettings, AppSettingsOptions } from '../models/AppSettings';

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
      showTranslatedTags: preferenceService.getBoolean('show_translated_tags', true)
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
      showTranslatedTags: this.settings.showTranslatedTags
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
}

export const userSettingStore = UserSettingStore.getInstance()
