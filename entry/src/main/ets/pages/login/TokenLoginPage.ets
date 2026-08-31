import { router } from '@kit.ArkUI';
import { accountStore } from '../../stores/AccountStore';
import { getStr, getStrf } from '../../utils/I18nUtils';

interface RawTokenExport {
  refreshToken?: string
  refresh_token?: string
}

@Entry
@Component
struct TokenLoginPage {
  @State tokenInput: string = ''
  @State isLoading: boolean = false
  @State errorMessage: string = ''

  private extractToken(input: string): string {
    let trimmed = input.trim()
    if (trimmed.startsWith('{')) {
      // 兼容粘贴 JSON 导出文件内容（本应用导出用 refreshToken，其他客户端可能用 refresh_token）
      try {
        let parsed = JSON.parse(trimmed) as RawTokenExport
        return parsed.refreshToken ?? parsed.refresh_token ?? ''
      } catch (e) {
        return ''
      }
    }
    // 去除内部空白，防止复制时带入换行/空格
    return trimmed.replace(/\s+/g, '')
  }

  async doLogin() {
    let token = this.extractToken(this.tokenInput)
    if (token.length === 0) {
      this.errorMessage = getStr($r('app.string.login_token_invalid'))
      return
    }
    this.isLoading = true
    this.errorMessage = ''
    try {
      let error = await accountStore.loginWithRefreshToken(token)
      if (error.length === 0) {
        // 清空返回栈（LoginPage 用 pushUrl 压底，仅 replace 换栈顶仍会退回登录页）再进首页
        router.clear()
        router.replaceUrl({ url: 'pages/home/HomePage' })
      } else {
        this.errorMessage = error
      }
    } catch (e) {
      this.errorMessage = getStrf($r('app.string.login_error_detail'), String(e))
    } finally {
      this.isLoading = false
    }
  }

  build() {
    Column({ space: 16 }) {
      Text($r('app.string.login_token_title'))
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')
        .margin({ bottom: 24 })

      Text($r('app.string.login_token_hint'))
        .fontSize(14)
        .fontColor('#666666')

      TextArea({ text: $$this.tokenInput, placeholder: $r('app.string.login_token_placeholder') })
        .height(120)
        .width('90%')
        .borderRadius(8)
        .backgroundColor('#F5F5F5')
        .padding(12)

      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .fontSize(12)
          .fontColor('#FF4444')
      }

      Button(this.isLoading ? $r('app.string.login_logging_in') : $r('app.string.login_login'))
        .width('90%')
        .height(48)
        .backgroundColor('#0096FA')
        .fontColor('#FFFFFF')
        .enabled(!this.isLoading)
        .onClick(() => {
          this.doLogin()
        })

      Button($r('app.string.common_back'))
        .width('90%')
        .height(48)
        .backgroundColor('#F0F0F0')
        .fontColor('#666666')
        .onClick(() => {
          router.back()
        })

      Text($r('app.string.login_token_help'))
        .fontSize(12)
        .fontColor('#0096FA')
        .decoration({ type: TextDecorationType.Underline })
        .onClick(() => {
          // 可以打开帮助页面或外部浏览器
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#FFFFFF')
  }
}
