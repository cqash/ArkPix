import { router } from '@kit.ArkUI';
import { oauthService } from '../../network/OAuthService';
import { accountStore } from '../../stores/AccountStore';

@Entry
@Component
struct TokenLoginPage {
  @State tokenInput: string = ''
  @State isLoading: boolean = false
  @State errorMessage: string = ''

  async doLogin() {
    if (this.tokenInput.trim().length === 0) {
      this.errorMessage = '请输入 Refresh Token'
      return
    }
    this.isLoading = true
    this.errorMessage = ''
    try {
      let success = await accountStore.loginWithRefreshToken(this.tokenInput.trim())
      if (success) {
        router.replaceUrl({ url: 'pages/home/HomePage' })
      } else {
        this.errorMessage = '登录失败，请检查 Token 是否有效'
      }
    } catch (e) {
      this.errorMessage = '登录出错: ' + e
    } finally {
      this.isLoading = false
    }
  }

  build() {
    Column({ space: 16 }) {
      Text('Token 登录')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')
        .margin({ bottom: 24 })

      Text('请输入您的 Pixiv Refresh Token')
        .fontSize(14)
        .fontColor('#666666')

      TextArea({ text: $$this.tokenInput, placeholder: '粘贴 Refresh Token 到这里' })
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

      Button(this.isLoading ? '登录中...' : '登录')
        .width('90%')
        .height(48)
        .backgroundColor('#0096FA')
        .fontColor('#FFFFFF')
        .enabled(!this.isLoading)
        .onClick(() => {
          this.doLogin()
        })

      Button('返回')
        .width('90%')
        .height(48)
        .backgroundColor('#F0F0F0')
        .fontColor('#666666')
        .onClick(() => {
          router.back()
        })

      Text('如何获取 Refresh Token？')
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
