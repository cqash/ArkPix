import { promptAction } from '@kit.ArkUI';
import { getDbService, DownloadTaskItem } from '../../services/DatabaseService';
import { downloadService, RetryAllResult, TaskChangeListener } from '../../services/DownloadService';
import { apiService } from '../../network/ApiService';
import { Illust } from '../../models/Illust';
import { getStr, getStrf } from '../../utils/I18nUtils';

interface IllustDetailResponse {
  illust: Object
}

@Entry
@Component
export struct DownloadPage {
  @State tasks: DownloadTaskItem[] = []
  @State isLoading: boolean = false
  private pollTimer: number = -1
  private taskChangeListener: TaskChangeListener = () => {
    this.refreshTasksSilently()
  }

  aboutToAppear() {
    this.loadTasks()
    // 可见期 1.5s 轮询静默刷新 + 任务变更事件回调，进度/状态无需退出重进
    downloadService.registerTaskChangeListener(this.taskChangeListener)
    this.pollTimer = setInterval(() => {
      this.refreshTasksSilently()
    }, 1500)
  }

  aboutToDisappear() {
    downloadService.unregisterTaskChangeListener(this.taskChangeListener)
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer)
      this.pollTimer = -1
    }
  }

  async loadTasks() {
    this.isLoading = true
    try {
      let db = await getDbService()
      this.tasks = await db.getDownloadTasks()
    } catch (e) {
      console.error('Load download tasks failed: ' + e)
    } finally {
      this.isLoading = false
    }
  }

  /** 静默刷新：不置 isLoading，避免列表 Loading 闪烁 */
  async refreshTasksSilently() {
    try {
      let db = await getDbService()
      this.tasks = await db.getDownloadTasks()
    } catch (e) {
      console.error('Refresh download tasks failed: ' + e)
    }
  }

  async retryTask(task: DownloadTaskItem) {
    if (task.status === 'downloading' || task.status === 'pending') { return }
    try {
      let response = await apiService.getIllustDetail(task.illust_id)
      let illustObj = (response as IllustDetailResponse).illust
      if (!illustObj) {
        promptAction.showToast({ message: $r('app.string.dl_fetch_failed') })
        return
      }
      let illust = Illust.fromJson(illustObj)
      downloadService.enqueue(task.image_url, illust, task.page_index)
      promptAction.showToast({ message: $r('app.string.common_added_download') })
      await this.refreshTasksSilently()
    } catch (e) {
      console.error('Retry task failed: ' + e)
      promptAction.showToast({ message: getStrf($r('app.string.dl_retry_failed'), String(e)) })
      await this.loadTasks()
    }
  }

  async clearCompleted() {
    let count = await downloadService.clearTasksByStatus('completed')
    promptAction.showToast({ message: getStrf($r('app.string.dl_cleared_completed'), count) })
    await this.loadTasks()
  }

  async doRetryAllFailed() {
    let result: RetryAllResult = await downloadService.retryAllFailed(() => { this.refreshTasksSilently() })
    if (result.started === 0 && result.skipped === 0 && result.failed === 0) {
      promptAction.showToast({ message: $r('app.string.dl_no_failed_tasks') })
    } else {
      // 入队为 fire-and-forget：started=入队数，成功/失败由任务体异步落库，列表轮询反映
      promptAction.showToast({
        message: getStrf($r('app.string.dl_retry_readded'), result.started) +
          (result.failed > 0 ? getStrf($r('app.string.dl_retry_failed_part'), result.failed) : '') +
          (result.skipped > 0 ? getStrf($r('app.string.dl_retry_skipped_part'), result.skipped) : '')
      })
    }
    await this.refreshTasksSilently()
  }

  async doClearFailed() {
    let count = await downloadService.clearTasksByStatus('failed')
    promptAction.showToast({ message: getStrf($r('app.string.dl_cleared_failed'), count) })
    await this.loadTasks()
  }

  private confirmBatchAction(title: string, message: string, onConfirm: () => void): void {
    this.getUIContext().showAlertDialog({
      title: title,
      message: message,
      autoCancel: true,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {}
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        action: onConfirm
      }
    })
  }

  private statusText(status: string): string {
    if (status === 'completed') { return getStr($r('app.string.dl_status_completed')) }
    if (status === 'downloading') { return getStr($r('app.string.dl_status_downloading')) }
    if (status === 'pending') { return getStr($r('app.string.dl_status_pending')) }
    if (status === 'failed') { return getStr($r('app.string.dl_status_failed')) }
    return status
  }

  private statusColor(status: string): ResourceColor {
    if (status === 'completed') { return '#0096FA' }
    if (status === 'downloading') { return '#FFAA00' }
    if (status === 'pending') { return '#999999' }
    if (status === 'failed') { return '#FF4444' }
    return '#999999'
  }

  build() {
    Column() {
      Row() {
        Text($r('app.string.settings_download_manager'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .layoutWeight(1)
        Button($r('app.string.dl_retry_failed_btn'))
          .fontSize(12)
          .backgroundColor('#0096FA')
          .onClick(() => {
            this.confirmBatchAction(getStr($r('app.string.dl_retry_all_title')),
              getStr($r('app.string.dl_retry_all_msg')), () => { this.doRetryAllFailed() })
          })
        Button($r('app.string.dl_clear_failed_btn'))
          .fontSize(12)
          .backgroundColor('#FFAA00')
          .margin({ left: 8 })
          .onClick(() => {
            this.confirmBatchAction(getStr($r('app.string.dl_clear_failed_btn')),
              getStr($r('app.string.dl_clear_failed_msg')), () => { this.doClearFailed() })
          })
        Button($r('app.string.dl_clear_completed_btn'))
          .fontSize(12)
          .backgroundColor('#FF4444')
          .margin({ left: 8 })
          .onClick(() => {
            this.confirmBatchAction(getStr($r('app.string.dl_clear_completed_title')),
              getStr($r('app.string.dl_clear_completed_msg')), () => { this.clearCompleted() })
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .justifyContent(FlexAlign.SpaceBetween)
      .backgroundColor('#FFFFFF')

      if (this.isLoading) {
        LoadingProgress()
          .width(40)
          .height(40)
          .color('#0096FA')
          .margin({ top: 32 })
      } else if (this.tasks.length === 0) {
        Text($r('app.string.dl_empty'))
          .fontSize(14)
          .fontColor('#999999')
          .margin({ top: 32 })
      } else {
        List() {
          ForEach(this.tasks, (task: DownloadTaskItem) => {
            ListItem() {
              Row() {
                Column() {
                  Text(getStrf($r('app.string.dl_task_prefix'), task.illust_id) +
                    (task.page_index > 0 ? getStrf($r('app.string.dl_task_page'), task.page_index + 1) : ''))
                    .fontSize(14)
                    .fontColor('#333333')
                  Text(getStrf($r('app.string.dl_task_status'), this.statusText(task.status)))
                    .fontSize(12)
                    .fontColor(this.statusColor(task.status))
                  if (task.status === 'downloading') {
                    Text(getStrf($r('app.string.dl_task_progress'), task.progress))
                      .fontSize(12)
                      .fontColor('#999999')
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                if (task.status === 'failed') {
                  Button($r('app.string.common_retry'))
                    .fontSize(12)
                    .backgroundColor('#0096FA')
                    .onClick(() => { this.retryTask(task) })
                }
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .justifyContent(FlexAlign.SpaceBetween)
              .backgroundColor('#FFFFFF')
            }
            .width('100%')
            // key 含 status/progress：状态或进度变化即换 key 强制重建该行
            //（仅 task.id 作 key 时同 key 复用子组件，轮询换的新数组也刷不动行内容）
          }, (task: DownloadTaskItem) => task.id + '|' + task.status + '|' + task.progress)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#F5F5F5')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
