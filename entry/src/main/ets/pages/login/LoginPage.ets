import { router } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { oauthService } from '../../network/OAuthService';
import { accountStore } from '../../stores/AccountStore';
import { Constants } from '../../utils/Constants';
import { CryptoUtils } from '../../utils/CryptoUtils';

interface WebResourceRequest {
  getRequestUrl(): string
}

interface LoadInterceptEvent {
  data: WebResourceRequest
}

@Entry
@Component
struct LoginPage {
  @State codeVerifier: string = ''
  @State codeChallenge: string = ''
  @State loginUrl: string = ''
  @State isLoading: boolean = true

  aboutToAppear() {
    this.codeVerifier = this.generateCodeVerifier()
    this.codeChallenge = CryptoUtils.base64urlEncode(CryptoUtils.sha256(this.codeVerifier))
    this.loginUrl = oauthService.getAuthUrl(this.codeChallenge)
  }

  generateCodeVerifier(): string {
    let chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~'
    let result = ''
    for (let i = 0; i < 128; i++) {
      result += chars.charAt(Math.floor(Math.random() * chars.length))
    }
    return result
  }

  extractCode(url: string): string {
    let match = url.match(/code=([^&]+)/)
    return match ? match[1] : ''
  }

  async doLogin(code: string): Promise<void> {
    let success = await accountStore.addAccount(code, this.codeVerifier)
    if (success) {
      router.replaceUrl({ url: 'pages/home/HomePage' })
    }
  }

  isCallbackUrl(url: string): boolean {
    return url.includes('pixiv://') ||
      url.startsWith('https://app-api.pixiv.net/web/v1/users/auth/pixiv/callback')
  }

  build() {
    Column() {
      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color('#0096FA')
          Text('正在加载 Pixiv 登录页面...')
            .fontSize(14)
            .fontColor('#999999')
            .margin({ top: 12 })
          Text('如长时间未加载，请检查网络代理设置')
            .fontSize(12)
            .fontColor('#FF6600')
            .margin({ top: 8 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }

      Web({ src: this.loginUrl, controller: new webview.WebviewController() })
        .width('100%')
        .height(this.isLoading ? 0 : '100%')
        .onPageBegin(() => {
          this.isLoading = false
        })
        .onPageEnd(() => {
          this.isLoading = false
        })
        .onLoadIntercept((event: LoadInterceptEvent) => {
          let url: string = ''
          try {
            url = event.data.getRequestUrl()
          } catch (e) {
            console.error('getRequestUrl failed: ' + e)
          }
          if (url && this.isCallbackUrl(url)) {
            let code = this.extractCode(url)
            if (code) {
              this.doLogin(code)
            }
            return true
          }
          return false
        })
    }
    .width('100%')
    .height('100%')
  }
}
