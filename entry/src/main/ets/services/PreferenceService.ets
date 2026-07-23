import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

export class PreferenceService {
  private static instance: PreferenceService
  private pref: preferences.Preferences | undefined = undefined

  private constructor() {
  }

  static getInstance(): PreferenceService {
    if (!PreferenceService.instance) {
      PreferenceService.instance = new PreferenceService()
    }
    return PreferenceService.instance
  }

  private ensurePref(): preferences.Preferences {
    if (this.pref === undefined) {
      let ctx = AppStorage.get<common.Context>('context')
      if (!ctx) {
        throw new Error('UIAbilityContext not found in AppStorage')
      }
      this.pref = preferences.getPreferencesSync(ctx.getApplicationContext(), { name: 'pixiv_settings' })
    }
    return this.pref
  }

  setString(key: string, value: string): void {
    let pref = this.ensurePref()
    pref.putSync(key, value)
    pref.flush()
  }

  getString(key: string, defaultValue: string = ''): string {
    return String(this.ensurePref().getSync(key, defaultValue))
  }

  setNumber(key: string, value: number): void {
    let pref = this.ensurePref()
    pref.putSync(key, value)
    pref.flush()
  }

  getNumber(key: string, defaultValue: number = 0): number {
    return Number(this.ensurePref().getSync(key, defaultValue))
  }

  setBoolean(key: string, value: boolean): void {
    let pref = this.ensurePref()
    pref.putSync(key, value)
    pref.flush()
  }

  getBoolean(key: string, defaultValue: boolean = false): boolean {
    let val = this.ensurePref().getSync(key, defaultValue)
    return val === true
  }

  setObject(key: string, value: Object): void {
    let pref = this.ensurePref()
    pref.putSync(key, JSON.stringify(value))
    pref.flush()
  }

  getObject(key: string, defaultValue: Object = JSON.parse('{}')): Object {
    let val = this.ensurePref().getSync(key, JSON.stringify(defaultValue))
    let str = String(val)
    try {
      return JSON.parse(str)
    } catch (e) {
      return defaultValue
    }
  }

  delete(key: string): void {
    let pref = this.ensurePref()
    pref.deleteSync(key)
    pref.flush()
  }
}

export const preferenceService = PreferenceService.getInstance()
