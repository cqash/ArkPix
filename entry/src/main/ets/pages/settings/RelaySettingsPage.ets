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

  private syncDomainLabels: string[] = ['浏览历史', '搜索历史', '收藏快照', '屏蔽列表', 'EXIF 配置', '应用设置']

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
      promptAction.showToast({ message: '请先填写服务器地址' })
      return
    }
    this.relayBusy = true
    try {
      await relayClient.register(this.settings.relayServerUrl, this.getDeviceName(),
        this.inviteCodeInput.trim(), this.accountKeyInput.trim())
      promptAction.showToast({ message: '注册成功，已连接中继服务器' })
    } catch (e) {
      // 注册失败展示服务端错误 message
      let msg = e instanceof Error ? e.message : String(e)
      promptAction.showToast({ message: '注册失败: ' + msg })
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
      promptAction.showToast({ message: '请先开启同步开关并完成中继注册' })
      return
    }
    this.syncBusy = true
    try {
      let ok = await syncService.syncNow()
      promptAction.showToast({ message: ok ? '同步完成' : '部分同步失败，将自动重试' })
    } catch (e) {
      promptAction.showToast({ message: '同步失败: ' + (e instanceof Error ? e.message : String(e)) })
    } finally {
      this.syncBusy = false
    }
  }

  /** 导出同步账号（accountKey）：泄露风险提示后复制到剪贴板或导出文件 */
  private showExportAccountKeyDialog(): void {
    let key = relayClient.getAccountKey()
    if (key.length === 0) {
      promptAction.showToast({ message: '无可用同步账号' })
      return
    }
    this.getUIContext().showAlertDialog({
      title: '导出同步账号',
      message: 'accountKey 等同于同步账号凭证，泄露后他人可加入你的同步账号并读取全部同步数据（历史/屏蔽/设置/收藏快照）。请仅在可信设备间使用。',
      autoCancel: true,
      primaryButton: {
        value: '复制 accountKey',
        action: () => {
          copyText(key).then((ok: boolean) => {
            promptAction.showToast({ message: ok ? '已复制 accountKey' : '复制失败' })
          })
        }
      },
      secondaryButton: {
        value: '导出为文件',
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
        promptAction.showToast({ message: '导出失败：无法获取上下文' })
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
      promptAction.showToast({ message: '导出成功' })
    } catch (e) {
      promptAction.showToast({ message: '导出失败: ' + e })
    }
  }

  // ===== 导入同步账号 =====

  /** PasteButton 安全控件点击成功后的临时授权窗口内读取剪贴板 */
  private onPasteImportClick(result: PasteButtonOnClickResult): void {
    if (result !== PasteButtonOnClickResult.SUCCESS) {
      promptAction.showToast({ message: '粘贴授权被取消' })
      return
    }
    pasteText().then((text: string) => {
      let key = extractAccountKey(text)
      if (key.length === 0) {
        promptAction.showToast({ message: '剪贴板中未找到有效 accountKey' })
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
        promptAction.showToast({ message: '导入失败：无法获取上下文' })
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
        promptAction.showToast({ message: '文件过大，不是有效的账号导出文件' })
        return
      }
      let buf = new ArrayBuffer(stat.size)
      fileIo.readSync(file.fd, buf)
      fileIo.closeSync(file)
      let decoder = util.TextDecoder.create('utf-8')
      let content = decoder.decodeToString(new Uint8Array(buf))
      let key = extractAccountKey(content)
      if (key.length === 0) {
        promptAction.showToast({ message: '文件中未找到有效 accountKey' })
        return
      }
      this.confirmImportAccount(key)
    } catch (e) {
      promptAction.showToast({ message: '导入失败: ' + e })
    }
  }

  /** 导入二次确认：覆盖本机当前注册的同步账号 */
  private confirmImportAccount(key: string): void {
    let masked = key.length > 8 ? key.substring(0, 8) + '...' : key
    this.getUIContext().showAlertDialog({
      title: '导入同步账号',
      message: '将加入 accountKey（' + masked + '）对应的同步账号，并替换本机当前的中继注册。该账号下其他设备的同步数据将拉取到本机。',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '导入',
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
      promptAction.showToast({ message: '导入成功，已加入同步账号' })
      // 导入成功后立即拉一轮远端数据（开关就绪时）
      if (syncService.isSyncReady()) {
        syncService.syncNow().catch((e: Object) => {
          console.error('Post-import sync failed: ' + e)
        })
      }
    } catch (e) {
      let msg = e instanceof Error ? e.message : String(e)
      promptAction.showToast({ message: '导入失败: ' + msg })
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
      return '通过'
    }
    if (status === SELF_TEST_FAILED) {
      return '失败'
    }
    if (status === SELF_TEST_SKIPPED) {
      return '跳过'
    }
    if (status === SELF_TEST_RUNNING) {
      return '进行中…'
    }
    return '等待'
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
      return '正在检测…'
    }
    let passed = relaySelfTestService.countPassed(this.selfTestResults)
    if (passed === this.selfTestResults.length) {
      return '后端功能全部就绪 (' + passed + '/' + this.selfTestResults.length + ')'
    }
    return (this.selfTestResults.length - passed) + ' 项异常'
  }

  private confirmRelayLogout(): void {
    this.getUIContext().showAlertDialog({
      title: '注销中继账号',
      message: '将清除本机的中继服务令牌（不影响 Pixiv 登录态与服务器地址配置）。其他设备数据仍保留在服务器。',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '注销',
        action: () => {
          relayClient.logout()
          this.refreshRelayState()
          promptAction.showToast({ message: '已注销中继账号' })
        }
      }
    })
  }

  @Builder
  SelfTestOverlay() {
    Column() {
      Column() {
        Text('后端自检')
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
        Text('关闭')
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
          Text('< 返回')
            .fontSize(16)
            .fontColor('#0096FA')
            .onClick(() => {
              router.back()
            })
          Text('中继服务器与同步')
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
              title: '服务器地址',
              placeholder: 'https://relay.example.com',
              value: this.settings.relayServerUrl,
              onTextChange: (text: string) => {
                userSettingStore.setRelayServerUrl(text)
                this.refresh()
              }
            })
            if (!this.relayRegistered) {
              TextInputItem({
                title: '邀请码（可选）',
                placeholder: '服务器需要邀请码时填写',
                value: this.inviteCodeInput,
                onTextChange: (text: string) => {
                  this.inviteCodeInput = text
                }
              })
              TextInputItem({
                title: '同步账号（可选）',
                placeholder: '导入 accountKey 加入已有账号',
                value: this.accountKeyInput,
                onTextChange: (text: string) => {
                  this.accountKeyInput = text
                }
              })
              SettingItem({
                title: this.relayBusy ? '注册中…' : '注册 / 登录',
                value: '',
                onItemClick: () => {
                  this.doRegister()
                }
              })
            } else {
              SettingItem({
                title: '状态',
                value: '已连接' +
                  (this.relayServerVersion.length > 0 ? ' · v' + this.relayServerVersion : '') +
                  (this.relayAccountKeyMasked.length > 0 ? ' · ' + this.relayAccountKeyMasked : '')
              })
              if (this.relayHasSync) {
                SwitchItem({
                  title: '数据同步（历史/屏蔽/设置/收藏快照）',
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
                  title: '自动同步（回到前台时，5 分钟节流）',
                  isOn: this.settings.autoSyncForeground,
                  onToggle: () => {
                    userSettingStore.setAutoSyncForeground(!this.settings.autoSyncForeground)
                    this.refresh()
                  }
                })
                if (this.settings.syncEnabled) {
                  SettingItem({
                    title: '立即同步',
                    value: this.syncBusy ? '同步中…' : '',
                    onItemClick: () => {
                      this.doSyncNow()
                    }
                  })
                  ForEach(SYNC_DOMAINS, (domain: string, index: number) => {
                    SettingItem({
                      title: this.syncDomainLabels[index] ?? domain,
                      value: syncService.getLastSyncText(domain)
                    })
                  }, (domain: string) => domain)
                }
                SettingItem({
                  title: '导出同步账号',
                  value: '',
                  onItemClick: () => {
                    this.showExportAccountKeyDialog()
                  }
                })
              } else {
                Text('当前服务器不支持数据同步（capabilities 缺少 sync）')
                  .fontSize(12)
                  .fontColor('#999999')
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 4, bottom: 4 })
              }
              // 导入同步账号：剪贴板走 PasteButton 安全控件（点击获临时剪贴板读权限），文件走 DocumentSelectPicker
              Row() {
                Text('从剪贴板导入同步账号')
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
                title: '从文件导入同步账号',
                value: '',
                onItemClick: () => {
                  this.importFromFile()
                }
              })
              SettingItem({
                title: '后端自检',
                value: this.selfTestRunning ? '检测中…' : '探测六个端点',
                onItemClick: () => {
                  this.startSelfTest()
                }
              })
              SettingItem({
                title: '注销中继账号',
                value: '',
                onItemClick: () => {
                  this.confirmRelayLogout()
                }
              })
            }
            Text('中继模式下 API/OAuth/图片全部经服务器中转（需服务器配置合法 HTTPS 证书）')
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
