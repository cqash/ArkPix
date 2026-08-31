import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { picker, fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { deviceInfo } from '@kit.BasicServicesKit';
import { AppSettings } from '../../models/AppSettings';
import { userSettingStore } from '../../stores/UserSettingStore';
import { copyText, pasteText } from '../../utils/ClipboardUtils';
import { relayClient } from '../../network/RelayClient';
import { syncService, SYNC_DOMAINS } from '../../services/SyncService';
import {
  relaySelfTestService,
  SelfTestItemResult,
  SELF_TEST_PASSED,
  SELF_TEST_FAILED,
  SELF_TEST_SKIPPED,
  SELF_TEST_RUNNING
} from '../../services/RelaySelfTestService';
import { SettingItem, SwitchItem, TextInputItem } from './SettingWidgets';
import { getStr, getStrf } from '../../utils/I18nUtils';

/** 同步账号导出文件格式（arkpix-sync-account.json） */
interface SyncAccountExportData {
  version: number
  appName: string
  type: string
  accountKey: string
  exportedAt: string
}

/** 从粘贴/文件内容中提取 accountKey：支持导出 JSON（accountKey 字段）或纯文本 key */
function extractAccountKey(text: string): string {
  let trimmed = text.trim()
  if (trimmed.length === 0) {
    return ''
  }
  if (trimmed.startsWith('{')) {
    try {
      let raw = JSON.parse(trimmed) as RawSyncAccountFile
      let key = raw?.accountKey ?? ''
      return key.trim()
    } catch (e) {
      console.error('Parse account key json failed: ' + e)
      return ''
    }
  }
  return trimmed
}

interface RawSyncAccountFile {
  accountKey?: string
}

@Entry
@Component
export struct RelaySettingsPage {
  @State settings: AppSettings = userSettingStore.getSettings()

  // ===== 中继服务器状态 =====
  @State relayRegistered: boolean = false
  @State relayServerVersion: string = ''
  @State relayAccountKeyMasked: string = ''
  @State relayHasSync: boolean = false
  @State relayHasRecover: boolean = false
  @State relayBusy: boolean = false
  @State inviteCodeInput: string = ''
  @State accountKeyInput: string = ''
  @State syncBusy: boolean = false
  @State selfTestShown: boolean = false
  @State selfTestResults: SelfTestItemResult[] = []
  @State selfTestRunning: boolean = false

  private syncDomainRess: Resource[] = [
    $r('app.string.relay_domain_history'),
    $r('app.string.relay_domain_search'),
    $r('app.string.relay_domain_bookmark'),
    $r('app.string.relay_domain_mute'),
    $r('app.string.relay_domain_exif'),
    $r('app.string.relay_domain_settings')
  ]

  aboutToAppear(): void {
    this.refreshRelayState()
  }

  private refreshRelayState(): void {
    this.relayRegistered = relayClient.isRegistered()
    this.relayServerVersion = relayClient.getServerVersion()
    let key = relayClient.getAccountKey()
    this.relayAccountKeyMasked = key.length > 8 ? key.substring(0, 8) + '...' : key
    this.relayHasSync = relayClient.hasCapability('sync')
    this.relayHasRecover = relayClient.hasCapability('recover')
  }

  private getDeviceName(): string {
    try {
      let name = deviceInfo.marketName
      if (name && name.length > 0) {
        return name
      }
    } catch (e) {
      console.error('getDeviceName failed: ' + e)
    }
    return 'HarmonyOS Device'
  }

  private refresh(): void {
    this.settings = userSettingStore.getSettings()
  }

  private async doRegister(): Promise<void> {
    if (this.relayBusy) {
      return
    }
    if (this.settings.relayServerUrl.trim().length === 0) {
      promptAction.showToast({ message: $r('app.string.relay_need_server_url') })
      return
    }
    this.relayBusy = true
    try {
      await relayClient.register(this.settings.relayServerUrl, this.getDeviceName(),
        this.inviteCodeInput.trim(), this.accountKeyInput.trim())
      promptAction.showToast({ message: $r('app.string.relay_register_ok') })
    } catch (e) {
      // 注册失败展示服务端错误 message
      let msg = e instanceof Error ? e.message : String(e)
      promptAction.showToast({ message: getStrf($r('app.string.relay_register_failed'), msg) })
    } finally {
      this.relayBusy = false
      this.refreshRelayState()
    }
  }

  private async doSyncNow(): Promise<void> {
    if (this.syncBusy) {
      return
    }
    if (!syncService.isSyncReady()) {
      promptAction.showToast({ message: $r('app.string.relay_need_sync_ready') })
      return
    }
    this.syncBusy = true
    try {
      let ok = await syncService.syncNow()
      promptAction.showToast({ message: ok ? $r('app.string.relay_sync_done') : $r('app.string.relay_sync_partial') })
    } catch (e) {
      promptAction.showToast({ message: getStrf($r('app.string.relay_sync_failed'),
        (e instanceof Error ? e.message : String(e))) })
    } finally {
      this.syncBusy = false
    }
  }

  /** 导出同步账号（accountKey）：泄露风险提示后复制到剪贴板或导出文件 */
  private showExportAccountKeyDialog(): void {
    let key = relayClient.getAccountKey()
    if (key.length === 0) {
      promptAction.showToast({ message: $r('app.string.relay_no_account') })
      return
    }
    this.getUIContext().showAlertDialog({
      title: $r('app.string.relay_export_account_title'),
      message: $r('app.string.relay_export_account_msg'),
      autoCancel: true,
      primaryButton: {
        value: $r('app.string.relay_copy_accountkey'),
        action: () => {
          copyText(key).then((ok: boolean) => {
            promptAction.showToast({ message: ok ? $r('app.string.relay_copied_accountkey') : $r('app.string.common_copy_failed') })
          })
        }
      },
      secondaryButton: {
        value: $r('app.string.common_export_file'),
        action: () => { this.exportAccountKeyFile(key) }
      }
    })
  }

  /** 导出 accountKey 为 JSON 文件（配合"从文件导入"成对使用） */
  private async exportAccountKeyFile(key: string): Promise<void> {
    let exportData: SyncAccountExportData = {
      version: 1,
      appName: 'ArkPix',
      type: 'sync-account',
      accountKey: key,
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
      options.newFileNames = ['arkpix-sync-account.json']
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

  // ===== 导入同步账号 =====

  /** PasteButton 安全控件点击成功后的临时授权窗口内读取剪贴板 */
  private onPasteImportClick(result: PasteButtonOnClickResult): void {
    if (result !== PasteButtonOnClickResult.SUCCESS) {
      promptAction.showToast({ message: $r('app.string.relay_paste_denied') })
      return
    }
    pasteText().then((text: string) => {
      let key = extractAccountKey(text)
      if (key.length === 0) {
        promptAction.showToast({ message: $r('app.string.relay_paste_no_key') })
        return
      }
      this.confirmImportAccount(key)
    })
  }

  /** 从文件导入：选 JSON/TXT → 提取 accountKey → 二次确认 */
  private async importFromFile(): Promise<void> {
    try {
      let ctx = AppStorage.get<common.Context>('context')
      if (!ctx) {
        promptAction.showToast({ message: $r('app.string.common_import_no_context') })
        return
      }
      let options = new picker.DocumentSelectOptions()
      options.fileSuffixFilters = ['.json', '.txt']
      let docPicker = new picker.DocumentViewPicker(ctx)
      let uris: Array<string> = await docPicker.select(options)
      if (uris.length === 0) {
        return
      }
      let file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_ONLY)
      let stat = fileIo.statSync(file.fd)
      if (stat.size > 64 * 1024) {
        fileIo.closeSync(file)
        promptAction.showToast({ message: $r('app.string.relay_file_too_large') })
        return
      }
      let buf = new ArrayBuffer(stat.size)
      fileIo.readSync(file.fd, buf)
      fileIo.closeSync(file)
      let decoder = util.TextDecoder.create('utf-8')
      let content = decoder.decodeToString(new Uint8Array(buf))
      let key = extractAccountKey(content)
      if (key.length === 0) {
        promptAction.showToast({ message: $r('app.string.relay_file_no_key') })
        return
      }
      this.confirmImportAccount(key)
    } catch (e) {
      promptAction.showToast({ message: getStrf($r('app.string.common_import_failed'), String(e)) })
    }
  }

  /** 导入二次确认：覆盖本机当前注册的同步账号 */
  private confirmImportAccount(key: string): void {
    let masked = key.length > 8 ? key.substring(0, 8) + '...' : key
    this.getUIContext().showAlertDialog({
      title: $r('app.string.relay_import_account_title'),
      message: getStrf($r('app.string.relay_import_account_msg'), masked),
      autoCancel: true,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {}
      },
      secondaryButton: {
        value: $r('app.string.common_import'),
        action: () => { this.doImportAccount(key) }
      }
    })
  }

  private async doImportAccount(key: string): Promise<void> {
    if (this.relayBusy) {
      return
    }
    this.relayBusy = true
    try {
      await relayClient.register(this.settings.relayServerUrl, this.getDeviceName(), '', key)
      promptAction.showToast({ message: $r('app.string.relay_import_done') })
      // 导入成功后立即拉一轮远端数据（开关就绪时）
      if (syncService.isSyncReady()) {
        syncService.syncNow().catch((e: Object) => {
          console.error('Post-import sync failed: ' + e)
        })
      }
    } catch (e) {
      let msg = e instanceof Error ? e.message : String(e)
      promptAction.showToast({ message: getStrf($r('app.string.common_import_failed'), msg) })
    } finally {
      this.relayBusy = false
      this.refreshRelayState()
    }
  }

  // ===== 后端自检 =====

  private startSelfTest(): void {
    if (this.selfTestRunning) {
      return
    }
    this.selfTestResults = relaySelfTestService.initialResults()
    this.selfTestShown = true
    this.selfTestRunning = true
    relaySelfTestService.runAll((results: SelfTestItemResult[]) => {
      this.selfTestResults = results
    }).then(() => {
      this.selfTestRunning = false
    }).catch((e: Object) => {
      console.error('Self test failed: ' + e)
      this.selfTestRunning = false
    })
  }

  private selfTestStatusText(status: string): string {
    if (status === SELF_TEST_PASSED) {
      return getStr($r('app.string.relay_selftest_passed'))
    }
    if (status === SELF_TEST_FAILED) {
      return getStr($r('app.string.relay_selftest_failed'))
    }
    if (status === SELF_TEST_SKIPPED) {
      return getStr($r('app.string.relay_selftest_skipped'))
    }
    if (status === SELF_TEST_RUNNING) {
      return getStr($r('app.string.relay_selftest_running'))
    }
    return getStr($r('app.string.relay_selftest_waiting'))
  }

  private selfTestStatusColor(status: string): string {
    if (status === SELF_TEST_PASSED) {
      return '#34A853'
    }
    if (status === SELF_TEST_FAILED) {
      return '#FF4444'
    }
    if (status === SELF_TEST_SKIPPED) {
      return '#999999'
    }
    return '#0096FA'
  }

  private selfTestSummary(): string {
    if (this.selfTestRunning) {
      return getStr($r('app.string.relay_selftest_running_summary'))
    }
    let passed = relaySelfTestService.countPassed(this.selfTestResults)
    if (passed === this.selfTestResults.length) {
      return getStrf($r('app.string.relay_selftest_all_ready'), passed, this.selfTestResults.length)
    }
    return getStrf($r('app.string.relay_selftest_abnormal'), this.selfTestResults.length - passed)
  }

  private confirmRelayLogout(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.relay_logout_title'),
      message: $r('app.string.relay_logout_msg'),
      autoCancel: true,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {}
      },
      secondaryButton: {
        value: $r('app.string.relay_logout_btn'),
        action: () => {
          relayClient.logout()
          this.refreshRelayState()
          promptAction.showToast({ message: $r('app.string.relay_logged_out') })
        }
      }
    })
  }

  @Builder
  SelfTestOverlay() {
    Column() {
      Column() {
        Text($r('app.string.relay_selftest_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .width('100%')
          .margin({ bottom: 12 })
        Scroll() {
          Column() {
            ForEach(this.selfTestResults, (item: SelfTestItemResult) => {
              Column() {
                Row() {
                  Text(item.name)
                    .fontSize(14)
                    .fontColor('#333333')
                    .layoutWeight(1)
                  Text(this.selfTestStatusText(item.status) +
                    (item.durationMs > 0 ? ' · ' + item.durationMs + 'ms' : ''))
                    .fontSize(13)
                    .fontColor(this.selfTestStatusColor(item.status))
                }
                .width('100%')
                if (item.detail.length > 0) {
                  Text(item.detail)
                    .fontSize(12)
                    .fontColor('#666666')
                    .width('100%')
                    .margin({ top: 2 })
                }
                if (item.status === SELF_TEST_FAILED || item.status === SELF_TEST_SKIPPED) {
                  if (item.errorMessage.length > 0 || item.httpStatus > 0) {
                    Text((item.httpStatus > 0 ? 'HTTP ' + item.httpStatus + ' ' : '') +
                      (item.errorCode.length > 0 ? item.errorCode + ': ' : '') + item.errorMessage)
                      .fontSize(12)
                      .fontColor(item.status === SELF_TEST_FAILED ? '#FF4444' : '#999999')
                      .width('100%')
                      .margin({ top: 2 })
                  }
                }
              }
              .width('100%')
              .padding({ top: 8, bottom: 8 })
              // key 含 status/durationMs：状态变化即换 key 强制重建该行
              //（item 为普通对象，原地改属性 @State/ForEach 观察不到，Service 端已改为替换元素引用）
            }, (item: SelfTestItemResult) => item.name + '|' + item.status + '|' + item.durationMs)
          }
          .width('100%')
        }
        .width('100%')
        .height(260)
        .align(Alignment.TopStart)

        Text(this.selfTestSummary())
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.selfTestRunning ? '#0096FA' :
            (relaySelfTestService.countPassed(this.selfTestResults) === this.selfTestResults.length ? '#34A853' : '#FF4444'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 12 })
        Text($r('app.string.common_close'))
          .fontSize(14)
          .fontColor('#0096FA')
          .padding({ left: 24, right: 24, top: 10, bottom: 10 })
          .margin({ top: 4 })
          .onClick(() => {
            this.selfTestShown = false
          })
      }
      .width('85%')
      .padding(20)
      .backgroundColor('#FFFFFF')
      .borderRadius(12)
      // 内层消费点击防冒泡到遮罩关闭（遵循项目弹窗约定，禁 hitTestBehavior(Block)）
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0, 0, 0, 0.4)')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      if (!this.selfTestRunning) {
        this.selfTestShown = false
      }
    })
  }

  build() {
    Stack() {
      Column() {
        // 顶部导航栏
        Row() {
          Text($r('app.string.common_back_arrow'))
            .fontSize(16)
            .fontColor('#0096FA')
            .onClick(() => {
              router.back()
            })
          Text($r('app.string.relay_page_title'))
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
            TextInputItem({
              title: getStr($r('app.string.relay_server_url')),
              placeholder: 'https://relay.example.com',
              value: this.settings.relayServerUrl,
              onTextChange: (text: string) => {
                userSettingStore.setRelayServerUrl(text)
                this.refresh()
              }
            })
            if (!this.relayRegistered) {
              TextInputItem({
                title: getStr($r('app.string.relay_invite_title')),
                placeholder: getStr($r('app.string.relay_invite_placeholder')),
                value: this.inviteCodeInput,
                onTextChange: (text: string) => {
                  this.inviteCodeInput = text
                }
              })
              TextInputItem({
                title: getStr($r('app.string.relay_account_title')),
                placeholder: getStr($r('app.string.relay_account_placeholder')),
                value: this.accountKeyInput,
                onTextChange: (text: string) => {
                  this.accountKeyInput = text
                }
              })
              SettingItem({
                title: this.relayBusy ? getStr($r('app.string.relay_registering')) : getStr($r('app.string.relay_register_btn')),
                value: '',
                onItemClick: () => {
                  this.doRegister()
                }
              })
            } else {
              SettingItem({
                title: getStr($r('app.string.common_status')),
                value: getStr($r('app.string.relay_connected')) +
                  (this.relayServerVersion.length > 0 ? ' · v' + this.relayServerVersion : '') +
                  (this.relayAccountKeyMasked.length > 0 ? ' · ' + this.relayAccountKeyMasked : '')
              })
              if (this.relayHasSync) {
                SwitchItem({
                  title: getStr($r('app.string.relay_sync_switch')),
                  isOn: this.settings.syncEnabled,
                  onToggle: () => {
                    let next = !this.settings.syncEnabled
                    userSettingStore.setSyncEnabled(next)
                    if (next) {
                      // 开启后立即做一轮全域同步
                      this.doSyncNow()
                    }
                    this.refresh()
                  }
                })
                SwitchItem({
                  title: getStr($r('app.string.relay_autosync_switch')),
                  isOn: this.settings.autoSyncForeground,
                  onToggle: () => {
                    userSettingStore.setAutoSyncForeground(!this.settings.autoSyncForeground)
                    this.refresh()
                  }
                })
                if (this.settings.syncEnabled) {
                  SettingItem({
                    title: getStr($r('app.string.relay_sync_now')),
                    value: this.syncBusy ? getStr($r('app.string.relay_syncing')) : '',
                    onItemClick: () => {
                      this.doSyncNow()
                    }
                  })
                  ForEach(SYNC_DOMAINS, (domain: string, index: number) => {
                    SettingItem({
                      title: index < this.syncDomainRess.length ? getStr(this.syncDomainRess[index]) : domain,
                      value: syncService.getLastSyncText(domain)
                    })
                  }, (domain: string) => domain)
                }
                SettingItem({
                  title: getStr($r('app.string.relay_export_account_title')),
                  value: '',
                  onItemClick: () => {
                    this.showExportAccountKeyDialog()
                  }
                })
              } else {
                Text($r('app.string.relay_no_sync_capability'))
                  .fontSize(12)
                  .fontColor('#999999')
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 4, bottom: 4 })
              }
              // 导入同步账号：剪贴板走 PasteButton 安全控件（点击获临时剪贴板读权限），文件走 DocumentSelectPicker
              Row() {
                Text($r('app.string.relay_import_clipboard'))
                  .fontSize(14)
                  .fontColor('#333333')
                  .layoutWeight(1)
                PasteButton()
                  .onClick((event: ClickEvent, result: PasteButtonOnClickResult) => {
                    this.onPasteImportClick(result)
                  })
              }
              .width('100%')
              .height(48)
              .padding({ left: 16, right: 16 })
              .backgroundColor('#FFFFFF')
              SettingItem({
                title: getStr($r('app.string.relay_import_file')),
                value: '',
                onItemClick: () => {
                  this.importFromFile()
                }
              })
              SettingItem({
                title: getStr($r('app.string.relay_selftest_title')),
                value: this.selfTestRunning ? getStr($r('app.string.relay_selftesting')) : getStr($r('app.string.relay_selftest_value')),
                onItemClick: () => {
                  this.startSelfTest()
                }
              })
              SettingItem({
                title: getStr($r('app.string.relay_logout_title')),
                value: '',
                onItemClick: () => {
                  this.confirmRelayLogout()
                }
              })
            }
            Text($r('app.string.relay_mode_note'))
              .fontSize(12)
              .fontColor('#999999')
              .width('100%')
              .padding({ left: 16, right: 16, top: 4, bottom: 8 })
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

      if (this.selfTestShown) {
        this.SelfTestOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }
}
