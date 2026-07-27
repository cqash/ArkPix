import { promptAction } from '@kit.ArkUI';
import { getDbService, DownloadTaskItem } from '../../services/DatabaseService';
import { downloadService, RetryAllResult, TaskChangeListener } from '../../services/DownloadService';
import { apiService } from '../../network/ApiService';
import { Illust } from '../../models/Illust';

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
        promptAction.showToast({ message: '获取作品信息失败' })
        return
      }
      let illust = Illust.fromJson(illustObj)
      downloadService.enqueue(task.image_url, illust, task.page_index)
      promptAction.showToast({ message: '已加入下载任务' })
      await this.refreshTasksSilently()
    } catch (e) {
      console.error('Retry task failed: ' + e)
      promptAction.showToast({ message: '重试失败: ' + e })
      await this.loadTasks()
    }
  }

  async clearCompleted() {
    let count = await downloadService.clearTasksByStatus('completed')
    promptAction.showToast({ message: '已清空 ' + count + ' 条完成记录' })
    await this.loadTasks()
  }

  async doRetryAllFailed() {
    let result: RetryAllResult = await downloadService.retryAllFailed(() => { this.refreshTasksSilently() })
    if (result.started === 0 && result.skipped === 0 && result.failed === 0) {
      promptAction.showToast({ message: '没有可重试的失败任务' })
    } else {
      // 入队为 fire-and-forget：started=入队数，成功/失败由任务体异步落库，列表轮询反映
      promptAction.showToast({
        message: '已重新加入 ' + result.started + ' 个下载任务' +
          (result.failed > 0 ? '，重建失败 ' + result.failed : '') +
          (result.skipped > 0 ? '，跳过 ' + result.skipped : '')
      })
    }
    await this.refreshTasksSilently()
  }

  async doClearFailed() {
    let count = await downloadService.clearTasksByStatus('failed')
    promptAction.showToast({ message: '已清空 ' + count + ' 条失败记录' })
    await this.loadTasks()
  }

  private confirmBatchAction(title: string, message: string, onConfirm: () => void): void {
    this.getUIContext().showAlertDialog({
      title: title,
      message: message,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '确定',
        action: onConfirm
      }
    })
  }

  private statusText(status: string): string {
    if (status === 'completed') { return '已完成' }
    if (status === 'downloading') { return '下载中' }
    if (status === 'pending') { return '排队中' }
    if (status === 'failed') { return '失败' }
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
        Text('下载管理')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .layoutWeight(1)
        Button('重试失败')
          .fontSize(12)
          .backgroundColor('#0096FA')
          .onClick(() => {
            this.confirmBatchAction('一键重试', '将重试全部失败任务', () => { this.doRetryAllFailed() })
          })
        Button('清空失败')
          .fontSize(12)
          .backgroundColor('#FFAA00')
          .margin({ left: 8 })
          .onClick(() => {
            this.confirmBatchAction('清空失败', '将移除全部失败任务记录（不删除文件）', () => { this.doClearFailed() })
          })
        Button('清空完成')
          .fontSize(12)
          .backgroundColor('#FF4444')
          .margin({ left: 8 })
          .onClick(() => {
            this.confirmBatchAction('清空已完成', '将移除全部已完成任务记录（不删除文件）', () => { this.clearCompleted() })
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
        Text('暂无下载任务')
          .fontSize(14)
          .fontColor('#999999')
          .margin({ top: 32 })
      } else {
        List() {
          ForEach(this.tasks, (task: DownloadTaskItem) => {
            ListItem() {
              Row() {
                Column() {
                  Text('作品 ' + task.illust_id + (task.page_index > 0 ? ' 第' + (task.page_index + 1) + '页' : ''))
                    .fontSize(14)
                    .fontColor('#333333')
                  Text('状态: ' + this.statusText(task.status))
                    .fontSize(12)
                    .fontColor(this.statusColor(task.status))
                  if (task.status === 'downloading') {
                    Text('进度: ' + task.progress + '%')
                      .fontSize(12)
                      .fontColor('#999999')
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                if (task.status === 'failed') {
                  Button('重试')
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
          }, (task: DownloadTaskItem) => task.id)
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
