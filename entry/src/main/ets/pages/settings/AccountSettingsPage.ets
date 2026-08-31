import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { picker, fileIo } from '@kit.CoreFileKit';
import { accountStore } from '../../stores/AccountStore';
import { copyText } from '../../utils/ClipboardUtils';
import { SettingItem } from './SettingWidgets';
import { getStr, getStrf } from '../../utils/I18nUtils';

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
      promptAction.showToast({ message: $r('app.string.account_no_token') })
      return
    }
    this.getUIContext().showAlertDialog({
      title: $r('app.string.account_export_token_title'),
      message: $r('app.string.account_export_token_msg'),
      autoCancel: true,
      primaryButton: {
        value: $r('app.string.account_copy_clipboard'),
        action: () => { this.copyToken() }
      },
      secondaryButton: {
        value: $r('app.string.common_export_file'),
        action: () => { this.exportTokenFile() }
      }
    })
  }

  private async copyToken(): Promise<void> {
    let account = accountStore.getCurrentAccount()
    if (!account || account.refreshToken.length === 0) {
      promptAction.showToast({ message: $r('app.string.account_no_token') })
      return
    }
    let ok = await copyText(account.refreshToken)
    promptAction.showToast({ message: ok ? $r('app.string.account_token_copied') : $r('app.string.common_copy_failed') })
  }

  private async exportTokenFile(): Promise<void> {
    let account = accountStore.getCurrentAccount()
    if (!account || account.refreshToken.length === 0) {
      promptAction.showToast({ message: $r('app.string.account_no_token') })
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
        promptAction.showToast({ message: $r('app.string.common_export_no_context') })
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
      promptAction.showToast({ message: $r('app.string.common_export_success') })
    } catch (e) {
      promptAction.showToast({ message: getStrf($r('app.string.common_export_failed'), String(e)) })
    }
  }

  private confirmLogout(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.account_logout_title'),
      message: $r('app.string.account_logout_msg'),
      autoCancel: true,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {}
      },
      secondaryButton: {
        value: $r('app.string.account_logout_btn'),
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
        Text($r('app.string.common_back_arrow'))
          .fontSize(16)
          .fontColor('#0096FA')
          .onClick(() => {
            router.back()
          })
        Text($r('app.string.settings_cat_account'))
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
            title: getStr($r('app.string.account_export_token_title')),
            value: '',
            onItemClick: () => {
              this.showExportTokenDialog()
            }
          })
          Row() {
            Text($r('app.string.account_logout_title'))
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
