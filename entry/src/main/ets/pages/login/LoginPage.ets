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
  data: WebResourceRequest | string
}

@Entry
@Component
struct LoginPage {
  @State codeVerifier: string = ''
  @State codeChallenge: string = ''
  @State loginUrl: string = ''

  aboutToAppear() {
    this.codeVerifier = this.generateCodeVerifier()
    this.codeChallenge = CryptoUtils.md5(this.codeVerifier)
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

  build() {
    Column() {
      Web({ src: this.loginUrl, controller: new webview.WebviewController() })
        .width('100%')
        .height('100%')
        .onLoadIntercept((event: LoadInterceptEvent) => {
          if (event && event.data && typeof event.data !== 'string') {
            let url = event.data.getRequestUrl()
            if (url && url.includes('pixiv://')) {
              let code = this.extractCode(url)
              if (code) {
                this.doLogin(code)
              }
              return true
            }
          }
          return false
        })
    }
    .width('100%')
    .height('100%')
  }
}
