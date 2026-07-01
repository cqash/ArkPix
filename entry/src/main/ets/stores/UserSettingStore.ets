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
      theme: preferenceService.getString('theme', 'system'),
      language: preferenceService.getString('language', 'zh-CN'),
      networkMode: preferenceService.getString('network_mode', 'direct'),
      crossCount: preferenceService.getNumber('cross_count', 2),
      isTopMode: preferenceService.getBoolean('is_top_mode', false),
      muteTags: preferenceService.getObject('mute_tags', []) as string[],
      muteUsers: preferenceService.getObject('mute_users', []) as number[],
      aiFilter: preferenceService.getBoolean('ai_filter', false),
      saveFormat: preferenceService.getString('save_format', 'png')
    }
    this.settings = new AppSettings(opts)
    AppStorage.setOrCreate('appSettings', this.settings)
  }

  private saveSettings(): void {
    preferenceService.setNumber('picture_quality', this.settings.pictureQuality)
    preferenceService.setNumber('manga_quality', this.settings.mangaQuality)
    preferenceService.setString('theme', this.settings.theme)
    preferenceService.setString('language', this.settings.language)
    preferenceService.setString('network_mode', this.settings.networkMode)
    preferenceService.setNumber('cross_count', this.settings.crossCount)
    preferenceService.setBoolean('is_top_mode', this.settings.isTopMode)
    preferenceService.setObject('mute_tags', this.settings.muteTags)
    preferenceService.setObject('mute_users', this.settings.muteUsers)
    preferenceService.setBoolean('ai_filter', this.settings.aiFilter)
    preferenceService.setString('save_format', this.settings.saveFormat)
    AppStorage.setOrCreate('appSettings', this.settings)
  }

  getSettings(): AppSettings {
    return this.settings
  }

  setPictureQuality(value: number): void {
    this.settings.pictureQuality = value
    this.saveSettings()
  }

  setMangaQuality(value: number): void {
    this.settings.mangaQuality = value
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
