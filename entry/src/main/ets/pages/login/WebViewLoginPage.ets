import { router } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { oauthService } from '../../network/OAuthService';
import { accountStore } from '../../stores/AccountStore';
import { CryptoUtils } from '../../utils/CryptoUtils';
import { Constants } from '../../utils/Constants';
import { preferenceService } from '../../services/PreferenceService';
import { localProxyServer } from '../../network/LocalProxyServer';

interface WebResourceRequest {
  getRequestUrl(): string
}

interface LoadInterceptEvent {
  data: WebResourceRequest
}

@Entry
@Component
struct WebViewLoginPage {
  @State codeVerifier: string = ''
  @State codeChallenge: string = ''
  @State loginUrl: string = ''
  private proxyApplied: boolean = false
  private controller: webview.WebviewController = new webview.WebviewController()
  private schemeHandler: webview.WebSchemeHandler = new webview.WebSchemeHandler()

  aboutToAppear() {
    this.codeVerifier = this.generateCodeVerifier()
    this.codeChallenge = CryptoUtils.base64urlEncode(CryptoUtils.sha256(this.codeVerifier))
    this.loginUrl = oauthService.getAuthUrl(this.codeChallenge)
    this.setupSchemeHandler()
    this.applyProxyIfNeeded()
  }

  // OAuth 完成后页面跳 pixiv:// 自定义协议，onLoadIntercept 收不到（被系统 AppLinking 接管），
  // 必须用 WebSchemeHandler 拦截才能拿到 code
  private setupSchemeHandler(): void {
    this.schemeHandler.onRequestStart((request: webview.WebSchemeHandlerRequest, handler: webview.WebResourceHandler) => {
      let url = request.getRequestUrl()
      let code = this.extractCode(url)
      if (code.length === 0) {
        return false
      }
      try {
        let response = new webview.WebSchemeHandlerResponse()
        response.setUrl(url)
        response.setStatus(200)
        response.setStatusText('OK')
        response.setMimeType('text/html')
        response.setEncoding('utf-8')
        handler.didReceiveResponse(response)
        handler.didReceiveResponseBody(new ArrayBuffer(0))
        handler.didFinish()
      } catch (e) {
        console.error('respond pixiv scheme failed: ' + e)
      }
      this.doLogin(code)
      return true
    })
  }

  aboutToDisappear() {
    if (this.proxyApplied) {
      this.proxyApplied = false
      try {
        webview.ProxyController.removeProxyOverride(() => {})
      } catch (e) {
        console.error('removeProxyOverride failed: ' + e)
      }
    }
  }

  private applyProxyIfNeeded(): void {
    let authMode = preferenceService.getString('auth_mode', Constants.MODE_STANDARD)
    let apiMode = preferenceService.getString('api_mode', Constants.MODE_STANDARD)
    if (authMode === Constants.MODE_STANDARD && apiMode === Constants.MODE_STANDARD) {
      return
    }
    localProxyServer.start().then((started: boolean) => {
      if (!started) {
        return
      }
      try {
        let config = new webview.ProxyConfig()
        config.insertProxyRule('http://' + Constants.LOCAL_PROXY_HOST + ':' + Constants.LOCAL_PROXY_PORT)
        webview.ProxyController.applyProxyOverride(config, () => {})
        this.proxyApplied = true
      } catch (e) {
        console.error('applyProxyOverride failed: ' + e)
      }
    })
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
      // 清空返回栈（LoginPage 用 pushUrl 压底，仅 replace 换栈顶仍会退回登录页）再进首页
      router.clear()
      router.replaceUrl({ url: 'pages/home/HomePage' })
    }
  }

  isCallbackUrl(url: string): boolean {
    return url.includes('pixiv://') ||
      url.startsWith('https://app-api.pixiv.net/web/v1/users/auth/pixiv/callback')
  }

  build() {
    Column() {
      Web({ src: this.loginUrl, controller: this.controller })
        .width('100%')
        .height('100%')
        .onControllerAttached(() => {
          try {
            this.controller.setWebSchemeHandler('pixiv', this.schemeHandler)
          } catch (e) {
            console.error('setWebSchemeHandler failed: ' + e)
          }
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
