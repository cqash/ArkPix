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
}
