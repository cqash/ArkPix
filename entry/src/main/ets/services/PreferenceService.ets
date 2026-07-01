import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

export class PreferenceService {
  private static instance: PreferenceService
  private pref: preferences.Preferences

  private constructor() {
    let ctx = AppStorage.get<common.Context>('context')
    if (!ctx) {
      throw new Error('UIAbilityContext not found in AppStorage')
    }
    this.pref = preferences.getPreferencesSync(ctx.getApplicationContext(), { name: 'pixiv_settings' })
  }

  static getInstance(): PreferenceService {
    if (!PreferenceService.instance) {
      PreferenceService.instance = new PreferenceService()
    }
    return PreferenceService.instance
  }

  setString(key: string, value: string): void {
    this.pref.putSync(key, value)
    this.pref.flush()
  }

  getString(key: string, defaultValue: string = ''): string {
    return String(this.pref.getSync(key, defaultValue))
  }

  setNumber(key: string, value: number): void {
    this.pref.putSync(key, value)
    this.pref.flush()
  }

  getNumber(key: string, defaultValue: number = 0): number {
    return Number(this.pref.getSync(key, defaultValue))
  }

  setBoolean(key: string, value: boolean): void {
    this.pref.putSync(key, value)
    this.pref.flush()
  }

  getBoolean(key: string, defaultValue: boolean = false): boolean {
    let val = this.pref.getSync(key, defaultValue)
    return val === true
  }

  setObject(key: string, value: Object): void {
    this.pref.putSync(key, JSON.stringify(value))
    this.pref.flush()
  }

  getObject(key: string, defaultValue: Object = JSON.parse('{}')): Object {
    let val = this.pref.getSync(key, JSON.stringify(defaultValue))
    let str = String(val)
    try {
      return JSON.parse(str)
    } catch (e) {
      return defaultValue
    }
  }

  delete(key: string): void {
    this.pref.deleteSync(key)
    this.pref.flush()
  }
}

export const preferenceService = PreferenceService.getInstance()
