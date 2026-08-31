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
  static readonly APP_VERSION: string = '5.0.234'
  static readonly OS_VERSION: string = 'Android 14'
  static readonly PROXY_HOST: string = ''
  static readonly LOCAL_PROXY_HOST: string = '127.0.0.1'
  static readonly LOCAL_PROXY_PORT: number = 10809

  // 网络绕过模式（认证 / API 服务，对齐 pixez 三档：标准 / 兼容 / 增强 + 中继）
  static readonly MODE_STANDARD: string = 'standard'
  static readonly MODE_COMPATIBLE: string = 'compatible'
  static readonly MODE_ECH: string = 'ech'
  static readonly MODE_RELAY: string = 'relay'

  // 图床
  static readonly IMAGE_HOST_DEFAULT: string = 'i.pximg.net'
  static readonly IMAGE_HOST_OPTIONAL: string = 'i.pixiv.re'

  // 下载传输参数（流式下载改造）
  /** 读取超时：相邻数据块间隔上限，弱网停滞容忍（流式模式下语义为块间隔而非整传输） */
  static readonly DOWNLOAD_READ_TIMEOUT: number = 60000
  /** 连接超时 */
  static readonly DOWNLOAD_CONNECT_TIMEOUT: number = 30000
  /** 单任务最大尝试次数（1 初始 + 2 重试） */
  static readonly DOWNLOAD_MAX_ATTEMPTS: number = 3
  /** 重试退避基数（毫秒）：第 n 次重试前等待 base * 2^(n-1)（1s → 2s） */
  static readonly DOWNLOAD_RETRY_BASE_DELAY_MS: number = 1000
  /** 下载中半成品临时文件前缀（cacheDir/downloads/part_<taskId>.<ext>，文件大小即续传偏移） */
  static readonly DOWNLOAD_PART_PREFIX: string = 'part_'

  // Pixiv 直连 IP（兼容模式：连直连 IP + 不发 SNI + 跳过证书校验，绕过 GFW SNI 封锁）
  static readonly DIRECT_IP_API: string = '210.140.139.155'
  static readonly DIRECT_IP_OAUTH: string = '210.140.139.155'
  static readonly DIRECT_IP_IMAGE: string = '210.140.139.133'
  static readonly DIRECT_IP_IMAGE_S: string = '210.140.139.133'

  static readonly RANKING_MODES: string[] = [
    'day', 'week', 'month', 'day_male', 'day_female', 'week_original', 'week_rookie',
    'day_r18', 'day_male_r18', 'day_female_r18', 'week_r18', 'week_r18g'
  ]

  /** 是否为 OAuth 认证主机 */
  static isOauthUrl(url: string): boolean {
    return url.indexOf('oauth.secure.pixiv.net') >= 0
  }

  /** 是否为 API 主机 */
  static isApiUrl(url: string): boolean {
    return url.indexOf('app-api.pixiv.net') >= 0 || url.indexOf('public-api.secure.pixiv.net') >= 0
  }

  /** 是否为图片主机 */
  static isImageUrl(url: string): boolean {
    return url.indexOf('i.pximg.net') >= 0 || url.indexOf('s.pximg.net') >= 0
  }

  /** 按图床类型改写图片域名（default 不改写；optional 用镜像；custom 用自定义域名） */
  static applyImageHost(url: string, hostType: string, customHost: string): string {
    let target = ''
    if (hostType === 'optional') {
      target = Constants.IMAGE_HOST_OPTIONAL
    } else if (hostType === 'custom') {
      target = customHost.trim()
    }
    if (target.length === 0) {
      return url
    }
    if (url.startsWith('https://i.pximg.net')) {
      return url.replace('https://i.pximg.net', 'https://' + target)
    }
    if (url.startsWith('https://s.pximg.net')) {
      return url.replace('https://s.pximg.net', 'https://' + target)
    }
    return url
  }

  /** 把 Pixiv 域名改写为直连 IP（兼容模式，配合 Host 头 + 跳过证书校验） */
  static applyDirectIp(url: string): string {
    if (url.startsWith('https://app-api.pixiv.net')) {
      return url.replace('https://app-api.pixiv.net', 'https://' + Constants.DIRECT_IP_API)
    }
    if (url.startsWith('https://oauth.secure.pixiv.net')) {
      return url.replace('https://oauth.secure.pixiv.net', 'https://' + Constants.DIRECT_IP_OAUTH)
    }
    if (url.startsWith('https://i.pximg.net')) {
      return url.replace('https://i.pximg.net', 'https://' + Constants.DIRECT_IP_IMAGE)
    }
    if (url.startsWith('https://s.pximg.net')) {
      return url.replace('https://s.pximg.net', 'https://' + Constants.DIRECT_IP_IMAGE_S)
    }
    return url
  }

  /** 提取 URL 的 host（不含 scheme/port） */
  static extractHost(url: string): string {
    let start = url.indexOf('://')
    if (start < 0) {
      return ''
    }
    let rest = url.substring(start + 3)
    let end = rest.indexOf('/')
    if (end >= 0) {
      return rest.substring(0, end)
    }
    return rest
  }

  /** 归一化网络模式：兼容旧值（sni/doh/bypass → compatible），relay 原样放行 */
  static normalizeMode(mode: string): string {
    if (mode === Constants.MODE_STANDARD) {
      return Constants.MODE_STANDARD
    }
    if (mode === Constants.MODE_COMPATIBLE) {
      return Constants.MODE_COMPATIBLE
    }
    if (mode === Constants.MODE_ECH) {
      return Constants.MODE_ECH
    }
    if (mode === Constants.MODE_RELAY) {
      return Constants.MODE_RELAY
    }
    return Constants.MODE_COMPATIBLE
  }

  /** 是否为中继模式（API/OAuth/图片全部经 Relay Server 中转） */
  static isRelayMode(mode: string): boolean {
    return mode === Constants.MODE_RELAY
  }

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
