import { promptAction, router } from '@kit.ArkUI';
import { getDbService, DownloadTaskItem } from '../../services/DatabaseService';
import { downloadService, RetryAllResult, TaskChangeListener } from '../../services/DownloadService';
import { apiService } from '../../network/ApiService';
import { Illust } from '../../models/Illust';
import { getStr, getStrf } from '../../utils/I18nUtils';
import { HapticUtils } from '../../utils/HapticUtils';
import { CachedImage } from '../../components/common/CachedImage';
import { EmptyView } from '../../components/common/CommonViews';
import { IllustListPage } from '../../components/illust/IllustWaterfall';
import { DetailListContextRegistry, DetailListContext } from '../../services/DetailListContextRegistry';

interface IllustDetailResponse {
  illust: Object
}

/**
 * 任务行缩略图（三级回退）：本地文件优先，Image onError（文件被清理）或 localPath 为空时
 * 回退 CachedImage 网络图（自带加载/错误占位）。独立子组件自持 useLocal 状态，
 * 规避轮询刷新下 ForEach 同 key 复用导致的行内状态不刷新问题。
 */
@Component
struct TaskThumb {
  @Prop localPath: string = ''
  @Prop imageUrl: string = ''
  @State useLocal: boolean = true

  build() {
    if (this.useLocal && this.localPath.length > 0) {
      Image('file://' + this.localPath)
        .width(56)
        .height(56)
        .borderRadius(4)
        .clip(true)
        .objectFit(ImageFit.Cover)
        .onError(() => {
          this.useLocal = false
        })
    } else {
      CachedImage({ url: this.imageUrl, ratio: 1 })
        .width(56)
        .height(56)
        .borderRadius(4)
        .clip(true)
    }
  }
}

@Entry
@Component
export struct DownloadPage {
  @State tasks: DownloadTaskItem[] = []
  @State isLoading: boolean = false
  /** 状态筛选：all/active(pending+downloading)/completed/failed，纯展示层过滤 */
  @State filterMode: string = 'all'
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
      if (task.page_index === -1) {
        // ugoira 任务重试走 GIF 编码管线（image_url 只是封面，普通 enqueue 会误下封面图）
        downloadService.enqueueUgoira(illust)
      } else {
        downloadService.enqueue(task.image_url, illust, task.page_index)
      }
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
        action: () => {
          HapticUtils.heavy()
          onConfirm()
        }
      }
    })
  }

  /** 纯展示层过滤：轮询 refreshTasksSilently 只更新 this.tasks 数据源，不打断筛选 */
  private getFilteredTasks(): DownloadTaskItem[] {
    if (this.filterMode === 'active') {
      return this.tasks.filter((task: DownloadTaskItem) => task.status === 'pending' || task.status === 'downloading')
    }
    if (this.filterMode === 'completed') {
      return this.tasks.filter((task: DownloadTaskItem) => task.status === 'completed')
    }
    if (this.filterMode === 'failed') {
      return this.tasks.filter((task: DownloadTaskItem) => task.status === 'failed')
    }
    return this.tasks
  }

  /**
   * 点击任务行跳作品详情：ids=当前筛选后可见任务按 illust_id 去重（保列表顺序）、
   * 无续页游标（nextUrl='' + fetchNext 返回空页，滑到末尾自然 No More），同 HistoryPage 模式
   */
  private openTaskDetail(task: DownloadTaskItem): void {
    let visible = this.getFilteredTasks()
    let ids: number[] = []
    let seen: Set<number> = new Set<number>()
    for (let i = 0; i < visible.length; i++) {
      if (!seen.has(visible[i].illust_id)) {
        seen.add(visible[i].illust_id)
        ids.push(visible[i].illust_id)
      }
    }
    let index = ids.indexOf(task.illust_id)
    if (index < 0) {
      index = 0
    }
    let ctx: DetailListContext = {
      ids: ids,
      nextUrl: '',
      fetchNext: async (nextUrl: string): Promise<IllustListPage> => {
        let empty: IllustListPage = { illusts: [], nextUrl: '' }
        return empty
      }
    }
    let token = DetailListContextRegistry.register(ctx)
    router.pushUrl({
      url: 'pages/detail/IllustDetailPage',
      params: { illustId: task.illust_id, contextToken: token, contextIndex: index }
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

  @Builder
  FilterChip(label: Resource, mode: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.filterMode === mode ? '#FFFFFF' : '#666666')
      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
      .backgroundColor(this.filterMode === mode ? '#0096FA' : '#EEEEEE')
      .borderRadius(14)
      .margin({ right: 8 })
      .onClick(() => {
        HapticUtils.selectionClick()
        this.filterMode = mode
      })
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

      if (!this.isLoading && this.tasks.length > 0) {
        // 状态筛选 chips：全部 / 进行中(pending+downloading) / 已完成 / 失败（选中高亮 #0096FA）
        Row() {
          this.FilterChip($r('app.string.dl_filter_all'), 'all')
          this.FilterChip($r('app.string.dl_filter_active'), 'active')
          this.FilterChip($r('app.string.dl_filter_completed'), 'completed')
          this.FilterChip($r('app.string.dl_filter_failed'), 'failed')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor('#FFFFFF')
      }

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
      } else if (this.getFilteredTasks().length === 0) {
        EmptyView({ message: getStr($r('app.string.dl_filter_empty')) })
          .margin({ top: 32 })
      } else {
        List() {
          ForEach(this.getFilteredTasks(), (task: DownloadTaskItem) => {
            ListItem() {
              Row() {
                TaskThumb({ localPath: task.local_path, imageUrl: task.image_url })
                  .margin({ right: 12 })
                Column() {
                  // dl_task_prefix 资源为 %s（string 占位），必须显式 toString——传 number 会让
                  // getStringSync 抛错被 getStrf 吞成 ''，任务行标题空白；dl_task_page 为 %d，传 number 正确
                  // page_index=-1 为 ugoira 动图任务，显示"动图"标签而非页码
                  Text(getStrf($r('app.string.dl_task_prefix'), task.illust_id.toString()) +
                    (task.page_index === -1 ? ' ' + getStr($r('app.string.dl_ugoira_label')) :
                      (task.page_index > 0 ? getStrf($r('app.string.dl_task_page'), task.page_index + 1) : '')))
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
                    // 按钮 onClick 不冒泡到父行，重试不会误触跳详情
                    .onClick(() => { this.retryTask(task) })
                }
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .justifyContent(FlexAlign.SpaceBetween)
              .backgroundColor('#FFFFFF')
              .onClick(() => { this.openTaskDetail(task) })
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
