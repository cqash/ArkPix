import { i18n } from '@kit.LocalizationKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * 多语言工具：语言偏好归一化 / 偏好→locale 映射 / 生效 Accept-Language 解析 / 非组件上下文同步取串。
 * 本模块无模块级 Store 依赖，可安全被 EntryAbility 静态 import。
 */

/** 语言偏好取值：跟随系统 */
export const LANG_SYSTEM: string = 'system'
/** 语言偏好取值：简体中文 */
export const LANG_ZH_HANS: string = 'zh-Hans'
/** 语言偏好取值：繁体中文 */
export const LANG_ZH_HANT: string = 'zh-Hant'
/** 语言偏好取值：英文 */
export const LANG_EN: string = 'en-Latn-US'

const DOMAIN = 0x0000;

/** 存量/非法语言偏好归一化（旧默认 'zh-CN' 及任何未知值 → 'system'） */
export function normalizeLanguagePref(raw: string): string {
  if (raw === LANG_ZH_HANS || raw === LANG_ZH_HANT || raw === LANG_EN) {
    return raw
  }
  return LANG_SYSTEM
}

/** 偏好 → setAppPreferredLanguage 参数（'system' → 'default' 恢复跟随系统） */
export function prefToLocale(pref: string): string {
  let p = normalizeLanguagePref(pref)
  if (p === LANG_SYSTEM) {
    return 'default'
  }
  return p
}

/** 解析当前系统语言标签（如 'zh-Hans' / 'en-Latn-US'）；失败回退 'default' */
export function resolveSystemLocale(): string {
  try {
    let sys = i18n.System.getSystemLanguage()
    if (sys.length > 0) {
      return sys
    }
  } catch (e) {
    hilog.error(DOMAIN, 'I18nUtils', 'getSystemLanguage failed: %{public}s', JSON.stringify(e));
  }
  return 'default'
}

/**
 * 应用语言偏好（立即生效）。
 * 'system' 时显式回放任一系统语言标签而非 'default'——setAppPreferredLanguage('default') 需重启才生效，
 * 显式设置当前系统语言可立即切换；后续系统语言变化由启动/写偏好时的重放兜底。
 */
export function applyLanguagePref(pref: string): void {
  let p = normalizeLanguagePref(pref)
  let locale: string = p === LANG_SYSTEM ? resolveSystemLocale() : prefToLocale(p)
  try {
    i18n.System.setAppPreferredLanguage(locale)
  } catch (e) {
    hilog.error(DOMAIN, 'I18nUtils', 'setAppPreferredLanguage(%{public}s) failed: %{public}s', locale, JSON.stringify(e));
    if (locale !== 'default') {
      try {
        i18n.System.setAppPreferredLanguage('default')
      } catch (e2) {
        hilog.error(DOMAIN, 'I18nUtils', 'fallback setAppPreferredLanguage(default) failed: %{public}s', JSON.stringify(e2));
      }
    }
  }
}

/** 偏好（system 时结合系统语言）→ Pixiv API Accept-Language 头值；非三语回退 en-US */
export function effectiveAcceptLanguage(pref: string): string {
  let p = normalizeLanguagePref(pref)
  let tag: string = p === LANG_SYSTEM ? resolveSystemLocale() : p
  if (tag.indexOf('Hant') >= 0) {
    return 'zh-TW'
  }
  if (tag.startsWith('zh')) {
    return 'zh-CN'
  }
  if (tag.startsWith('en')) {
    return 'en-US'
  }
  return 'en-US'
}

function getContextResourceManager(): common.Context | undefined {
  let ctx = AppStorage.get<common.Context>('context')
  return ctx
}

/** 非组件上下文同步取串（resourceManager 尊重当前应用偏好语言，与 $r 行为一致） */
export function getStr(res: Resource): string {
  try {
    let ctx = getContextResourceManager()
    if (!ctx) {
      return ''
    }
    return ctx.resourceManager.getStringSync(res.id)
  } catch (e) {
    hilog.error(DOMAIN, 'I18nUtils', 'getStr failed: %{public}s', JSON.stringify(e));
    return ''
  }
}

/** 带 %s/%d 参数格式化的同步取串 */
export function getStrf(res: Resource, ...args: (string | number)[]): string {
  try {
    let ctx = getContextResourceManager()
    if (!ctx) {
      return ''
    }
    return ctx.resourceManager.getStringSync(res.id, ...args)
  } catch (e) {
    hilog.error(DOMAIN, 'I18nUtils', 'getStrf failed: %{public}s', JSON.stringify(e));
    return ''
  }
}
