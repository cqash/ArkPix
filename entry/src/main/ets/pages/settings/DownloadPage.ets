import { router } from '@kit.ArkUI';
import { getDbService, DownloadTaskItem } from '../../services/DatabaseService';
import { downloadService } from '../../services/DownloadService';

@Entry
@Component
export struct DownloadPage {
  @State tasks: DownloadTaskItem[] = []
  @State isLoading: boolean = false

  aboutToAppear() {
    this.loadTasks()
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

  async retryTask(task: DownloadTaskItem) {
    if (task.status === 'downloading') { return }
    await downloadService.downloadToCache(task.image_url, task.illust_id, task.page_index)
    await this.loadTasks()
  }

  async clearCompleted() {
    let db = await getDbService()
    await db.clearCompletedDownloadTasks()
    await this.loadTasks()
  }

  private statusText(status: string): string {
    if (status === 'completed') { return '已完成' }
    if (status === 'downloading') { return '下载中' }
    if (status === 'failed') { return '失败' }
    return status
  }

  private statusColor(status: string): ResourceColor {
    if (status === 'completed') { return '#0096FA' }
    if (status === 'downloading') { return '#FFAA00' }
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
        Button('清空已完成')
          .fontSize(12)
          .backgroundColor('#FF4444')
          .onClick(() => { this.clearCompleted() })
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
