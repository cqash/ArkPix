import { vibrator } from '@kit.SensorServiceKit';
import { userSettingStore } from '../stores/UserSettingStore';

/**
 * 全局触觉反馈统一入口（对齐 pixez）。
 * 四级语义：
 *  - selectionClick：点击卡片/Tab 等轻点感（SOFT intensity 40，降级 10ms）
 *  - light：开关切换/取消收藏（SOFT 70，降级 20ms）
 *  - medium：收藏成功/发送评论成功（HARD 80，降级 35ms）
 *  - heavy：长按手势/破坏性确认（HARD 100，降级 50ms）
 * 内置开关（settings.hapticFeedback）+ 50ms 全局节流；设备不支持预置效果时降级 VibrateTime 时长振动；
 * 全程 try/catch 静默（无马达/模拟器/系统振动关闭时不报错不闪退）。
 */
type HapticLevel = 'selectionClick' | 'light' | 'medium' | 'heavy'

const THROTTLE_MS: number = 50
/** 预置效果 ID（API 12 可用的 EffectId 字面量，等值于 HapticFeedback 枚举成员） */
const EFFECT_SOFT: string = 'haptic.effect.soft'
const EFFECT_HARD: string = 'haptic.effect.hard'

let lastTriggerAt: number = 0
let presetSupported: boolean | undefined = undefined

function isPresetSupported(): boolean {
  if (presetSupported !== undefined) {
    return presetSupported
  }
  try {
    presetSupported = vibrator.isSupportEffectSync(EFFECT_SOFT)
  } catch (e) {
    presetSupported = false
  }
  return presetSupported
}

function effectIdOf(level: HapticLevel): string {
  if (level === 'selectionClick' || level === 'light') {
    return EFFECT_SOFT
  }
  return EFFECT_HARD
}

function intensityOf(level: HapticLevel): number {
  if (level === 'selectionClick') {
    return 40
  }
  if (level === 'light') {
    return 70
  }
  if (level === 'medium') {
    return 80
  }
  return 100
}

function fallbackDuration(level: HapticLevel): number {
  if (level === 'selectionClick') {
    return 10
  }
  if (level === 'light') {
    return 20
  }
  if (level === 'medium') {
    return 35
  }
  return 50
}

function trigger(level: HapticLevel): void {
  try {
    if (!userSettingStore.getSettings().hapticFeedback) {
      return
    }
    let now = Date.now()
    if (now - lastTriggerAt < THROTTLE_MS) {
      return
    }
    lastTriggerAt = now
    let attribute: vibrator.VibrateAttribute = { usage: 'touch' }
    if (isPresetSupported()) {
      let effect: vibrator.VibratePreset = {
        type: 'preset',
        effectId: effectIdOf(level),
        count: 1,
        intensity: intensityOf(level)
      }
      vibrator.startVibration(effect, attribute).catch(() => {})
    } else {
      let effect: vibrator.VibrateTime = { type: 'time', duration: fallbackDuration(level) }
      vibrator.startVibration(effect, attribute).catch(() => {})
    }
  } catch (e) {
    // 静默降级
  }
}

export class HapticUtils {
  /** 轻点感：卡片点击、Tab 切换 */
  static selectionClick(): void {
    trigger('selectionClick')
  }

  /** 轻震：设置开关切换、取消收藏 */
  static light(): void {
    trigger('light')
  }

  /** 中震：收藏成功、发送评论成功 */
  static medium(): void {
    trigger('medium')
  }

  /** 重震：长按手势、破坏性操作确认 */
  static heavy(): void {
    trigger('heavy')
  }
}
