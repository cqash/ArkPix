export class Constants {
  static readonly HASH_SALT: string = '28c1fdd170a5204386cb1313c7077b34f83e4aaf4aa829ce78c231e05b0bae2c'
  static readonly CLIENT_ID: string = 'MOBrBDS8blbauoSck0ZfDbtuzpyT'
  static readonly CLIENT_SECRET: string = 'lsACyCD94FhDUtGTXi3QzcFE2uU1hqtDaKeqrdwj'
  static readonly BASE_API_URL: string = 'https://app-api.pixiv.net'
  static readonly BASE_OAUTH_URL: string = 'https://oauth.secure.pixiv.net'
  static readonly BASE_IMAGE_URL: string = 'https://i.pximg.net'
  static readonly REDIRECT_URI: string = 'https://app-api.pixiv.net/web/v1/users/auth/pixiv/callback'
  static readonly USER_AGENT: string = 'PixivAndroidApp/5.0.234 (Android 14; Pixel 7)'
  static readonly IMAGE_USER_AGENT: string = 'PixivIOSApp/5.8.0'
  static readonly ACCEPT_LANGUAGE: string = 'zh-CN'
  static readonly APP_VERSION: string = '5.0.234'
  static readonly OS_VERSION: string = 'Android 14'
  static readonly PROXY_HOST: string = ''

  static readonly RANKING_MODES: string[] = [
    'day', 'week', 'month', 'day_male', 'day_female', 'week_original', 'week_rookie',
    'day_r18', 'day_male_r18', 'day_female_r18', 'week_r18', 'week_r18g'
  ]

  static applyProxy(url: string): string {
    if (Constants.PROXY_HOST.length === 0) {
      return url
    }
    if (url.startsWith('https://app-api.pixiv.net')) {
      return url.replace('https://app-api.pixiv.net', Constants.PROXY_HOST)
    }
    if (url.startsWith('https://oauth.secure.pixiv.net')) {
      return url.replace('https://oauth.secure.pixiv.net', Constants.PROXY_HOST + '/oauth')
    }
    if (url.startsWith('https://i.pximg.net')) {
      return url.replace('https://i.pximg.net', Constants.PROXY_HOST + '/img')
    }
    return url
  }

  /**
   * 判断字符串是否包含 CJK 字符（中文/日文/韩文）
   */
  static containsCjk(str: string): boolean {
    for (let i = 0; i < str.length; i++) {
      let code = str.charCodeAt(i)
      // CJK Unified Ideographs + CJK Extension A/B + Katakana + Hiragana + Hangul
      if ((code >= 0x4E00 && code <= 0x9FFF) ||
        (code >= 0x3400 && code <= 0x4DBF) ||
        (code >= 0x3040 && code <= 0x309F) ||
        (code >= 0x30A0 && code <= 0x30FF) ||
        (code >= 0xAC00 && code <= 0xD7AF)) {
        return true
      }
    }
    return false
  }

  /**
   * 判断字符串是否纯 ASCII（英文字母/数字/标点，无 CJK）
   */
  static isAsciiOnly(str: string): boolean {
    if (str.length === 0) {
      return false
    }
    for (let i = 0; i < str.length; i++) {
      let code = str.charCodeAt(i)
      if (code > 0x7F) {
        return false
      }
    }
    return true
  }

  /**
   * 过滤 tag 的 translated_name：
   * Pixiv API 在 Accept-Language: zh-CN 时，会将中文 tag 名"翻译"成英文
   * （如"爱莉希雅→Elysia"、"琪亚娜→Kiana"），这不是用户期望的中文翻译。
   * 规则：当 tag 名含 CJK 字符而 translatedName 是纯 ASCII 时，视为无意义翻译，返回空。
   */
  static filterTranslatedName(tagName: string, translatedName: string): string {
    if (!translatedName || translatedName.length === 0) {
      return ''
    }
    if (tagName === translatedName) {
      return ''
    }
    // tag 名含 CJK + 翻译是纯 ASCII → 无意义的"中文→英文"翻译，跳过
    if (Constants.containsCjk(tagName) && Constants.isAsciiOnly(translatedName)) {
      return ''
    }
    return translatedName
  }
}
