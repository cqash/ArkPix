import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { picker, fileIo } from '@kit.CoreFileKit';
import { accountStore } from '../../stores/AccountStore';
import { copyText } from '../../utils/ClipboardUtils';
import { SettingItem } from './SettingWidgets';

interface TokenExportData {
  version: number
  appName: string
  type: string
  userId: number
  userName: string
  account: string
  refreshToken: string
  exportedAt: string
}

@Entry
@Component
export struct AccountSettingsPage {
  // ===== 导出 Token =====
  private showExportTokenDialog(): void {
    let account = accountStore.getCurrentAccount()
    if (!account || account.refreshToken.length === 0) {
      promptAction.showToast({ message: '无可用 token' })
      return
    }
    this.getUIContext().showAlertDialog({
      title: '导出 Token',
      message: 'Token 等同于登录凭证，泄露后他人可直接登录你的账号。请仅在可信环境使用，导出后妥善保管。',
      autoCancel: true,
      primaryButton: {
        value: '复制到剪贴板',
        action: () => { this.copyToken() }
      },
      secondaryButton: {
        value: '导出为文件',
        action: () => { this.exportTokenFile() }
      }
    })
  }

  private async copyToken(): Promise<void> {
    let account = accountStore.getCurrentAccount()
    if (!account || account.refreshToken.length === 0) {
      promptAction.showToast({ message: '无可用 token' })
      return
    }
    let ok = await copyText(account.refreshToken)
    promptAction.showToast({ message: ok ? '已复制 refresh token 到剪贴板' : '复制失败' })
  }

  private async exportTokenFile(): Promise<void> {
    let account = accountStore.getCurrentAccount()
    if (!account || account.refreshToken.length === 0) {
      promptAction.showToast({ message: '无可用 token' })
      return
    }
    let exportData: TokenExportData = {
      version: 1,
      appName: 'ArkPix',
      type: 'token',
      userId: account.id,
      userName: account.name,
      account: account.account,
      refreshToken: account.refreshToken,
      exportedAt: new Date().toISOString()
    }
    let json = JSON.stringify(exportData, null, 2)
    try {
      let ctx = AppStorage.get<common.Context>('context')
      if (!ctx) {
        promptAction.showToast({ message: '导出失败：无法获取上下文' })
        return
      }
      let options = new picker.DocumentSaveOptions()
      options.newFileNames = ['arkpix-token.json']
      let docPicker = new picker.DocumentViewPicker(ctx)
      let uris: Array<string> = await docPicker.save(options)
      if (uris.length === 0) {
        return
      }
      let file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
      fileIo.writeSync(file.fd, json)
      fileIo.closeSync(file)
      promptAction.showToast({ message: '导出成功' })
    } catch (e) {
      promptAction.showToast({ message: '导出失败: ' + e })
    }
  }

  private confirmLogout(): void {
    this.getUIContext().showAlertDialog({
      title: '退出登录',
      message: '确定要退出当前账号吗？',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '退出',
        action: () => {
          accountStore.logout()
          router.replaceUrl({ url: 'pages/login/LoginPage' })
        }
      }
    })
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Text('< 返回')
          .fontSize(16)
          .fontColor('#0096FA')
          .onClick(() => {
            router.back()
          })
        Text('账户')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text('    ')
          .fontSize(16)
          .width(48)
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor('#FFFFFF')

      Scroll() {
        Column() {
          SettingItem({
            title: '导出 Token',
            value: '',
            onItemClick: () => {
              this.showExportTokenDialog()
            }
          })
          Row() {
            Text('退出登录')
              .fontSize(14)
              .fontColor('#FF4444')
            Text(' >')
              .fontSize(16)
              .fontColor('#999999')
          }
          .width('100%')
          .height(48)
          .justifyContent(FlexAlign.SpaceBetween)
          .padding({ left: 16, right: 16 })
          .backgroundColor('#FFFFFF')
          .stateStyles({
            pressed: {
              .backgroundColor('#F0F0F0')
            }
          })
          .onClick(() => {
            this.confirmLogout()
          })
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })
      }
      .width('100%')
      .layoutWeight(1)
      // Scroll 限高后内容不足一屏时默认居中，须显式顶部对齐
      .align(Alignment.TopStart)
      .backgroundColor('#F5F5F5')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
