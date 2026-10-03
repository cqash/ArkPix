import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { getDbService, DatabaseService } from './DatabaseService';
import { Constants } from '../utils/Constants';
import { imageExifService, ExifInfo, ExifTag } from './ImageExifService';
import { Illust, Tag } from '../models/Illust';
import { userSettingStore } from '../stores/UserSettingStore';
import { preferenceService } from './PreferenceService';
import { apiService } from '../network/ApiService';
import { relayClient } from '../network/RelayClient';
import { getStr, getStrf } from '../utils/I18nUtils';
import { ugoiraService } from './UgoiraService';

interface IllustDetailResponse {
  illust: Object
}

/** 重试全部失败任务的分类计数：发起/成功/失败/跳过（元信息缺失） */
export interface RetryAllResult {
  started: number
  succeeded: number
  failed: number
  skipped: number
}

/** 任务变更事件回调（任务完成/失败时触发，供页面可见期刷新列表） */
export type TaskChangeListener = () => void

/** 流式传输错误：retryable=可进入任务内自动重试；discardPartial=已写盘内容不可信（HTTP 错误页），须删除临时文件 */
class StreamTransferError extends Error {
  readonly retryable: boolean
  readonly discardPartial: boolean
  constructor(message: string, retryable: boolean, discardPartial: boolean) {
    super(message)
    this.name = 'StreamTransferError'
    this.retryable = retryable
    this.discardPartial = discardPartial
  }
}

/** 跨尝试共享的进度写库节流状态（保证多次尝试间百分比连续、不重复写库） */
interface ProgressThrottle {
  lastSavedPercent: number
}

/** 内存 FIFO 队列任务；DB 中的 pending 记录由 enqueue 时写入，dbReady 保证落库先于任务体执行 */
interface QueuedDownloadTask {
  url: string
  illust: Illust
  pageIndex: number
  taskId: string
  dbReady: Promise<void>
}

export class DownloadService {
  private static instance: DownloadService
  private taskChangeListeners: TaskChangeListener[] = []
  private queue: QueuedDownloadTask[] = []
  private activeCount: number = 0
  /** 排队中+执行中的 taskId 集合：并发重复下载防护（isDownloaded 只查 completed，管不到在途任务） */
  private inflightTaskIds: string[] = []
  /** 已落盘待写图库的路径：攒批到队列排空后一次系统弹窗保存，避免每张图弹一次确认 */
  private pendingGalleryPaths: string[] = []
  private galleryFlushing: boolean = false

  private constructor() {}

  static getInstance(): DownloadService {
    if (!DownloadService.instance) {
      DownloadService.instance = new DownloadService()
    }
    return DownloadService.instance
  }

  /** 注册任务变更回调（页面可见期注册，aboutToDisappear 注销） */
  registerTaskChangeListener(listener: TaskChangeListener): void {
    this.taskChangeListeners.push(listener)
  }

  unregisterTaskChangeListener(listener: TaskChangeListener): void {
    let idx = this.taskChangeListeners.indexOf(listener)
    if (idx >= 0) {
      this.taskChangeListeners.splice(idx, 1)
    }
  }

  private notifyTaskChanged(): void {
    let snapshot = this.taskChangeListeners.slice()
    for (let i = 0; i < snapshot.length; i++) {
      try {
        snapshot[i]()
      } catch (e) {
        console.error('Task change listener failed: ' + e)
      }
    }
  }

  private getExtension(url: string): string {
    let lowerUrl = url.toLowerCase()
    if (lowerUrl.endsWith('.png')) { return 'png' }
    if (lowerUrl.endsWith('.jpg') || lowerUrl.endsWith('.jpeg')) { return 'jpg' }
    if (lowerUrl.endsWith('.gif')) { return 'gif' }
    return 'jpg'
  }

  private sanitizeFilenamePart(name: string): string {
    let result = name.replace(/[\\/:*?"<>|]/g, '_').trim()
    if (result.length > 50) {
      result = result.substring(0, 50)
    }
    return result
  }

  private buildFilename(illust: Illust, pageIndex: number): string {
    let template = userSettingStore.getSettings().filenameTemplate
    if (!template || template.trim().length === 0) {
      template = '{illust_id}_p{part}'
    }
    let base = template
      .replaceAll('{illust_id}', illust.id.toString())
      .replaceAll('{user_id}', illust.user.id.toString())
      .replaceAll('{part}', pageIndex.toString())
      .replaceAll('{user_name}', this.sanitizeFilenamePart(illust.user.name))
      .replaceAll('{title}', this.sanitizeFilenamePart(illust.title))
    if (!base || base.trim().length === 0) {
      base = illust.id.toString() + '_p' + pageIndex.toString()
    }
    return base
  }

  private buildExifInfo(illust: Illust, pageIndex: number): ExifInfo {
    let tags: ExifTag[] = illust.tags.map((t: Tag): ExifTag => {
      return { name: t.name, translatedName: t.translatedName }
    })
    return {
      illustId: illust.id,
      userId: illust.user.id,
      title: illust.title,
      userName: illust.user.name,
      tags: tags,
      createDate: illust.createDate,
      pageIndex: pageIndex
    }
  }

  private buildDownloadHeaders(): Record<string, string> {
    return {
      'Referer': 'https://app-api.pixiv.net/',
      'User-Agent': Constants.IMAGE_USER_AGENT
    }
  }

  // 下载落盘后的统一收尾（直连 / bypass 共用）：
  // 嵌入成功 → 使用元数据输出文件（扩展名与源格式一致：JPEG→.jpg，PNG→.png）并删除临时文件；
  // 嵌入失败 → 临时文件重命名为 basePath.<原始扩展名>，保留原格式降级保存；
  // 两种情况均照常标记 completed，元数据写入失败不阻断下载。
  private async finalizeDownload(tempPath: string, basePath: string, ext: string,
    shouldEmbedExif: boolean, illust: Illust, pageIndex: number, taskId: string,
    db: DatabaseService): Promise<string> {
    if (shouldEmbedExif) {
      let exifInfo = this.buildExifInfo(illust, pageIndex)
      let exifPath = basePath + (ext === 'png' ? '.png' : '.jpg')
      let embedded = await imageExifService.embedExif(tempPath, exifPath, exifInfo)
      if (embedded) {
        try {
          fileIo.unlinkSync(tempPath)
        } catch (e) {
          console.error('Delete temp download file failed: ' + e)
        }
        await db.updateDownloadStatus(taskId, 'completed', 100, exifPath)
        return exifPath
      }
      // 降级：保留原格式与扩展名，临时文件重命名为最终文件
      let fallbackPath = basePath + '.' + ext
      console.error(`Metadata embed failed for task ${taskId}, fallback to original ${ext} image`)
      if (fileIo.accessSync(fallbackPath)) {
        fileIo.unlinkSync(fallbackPath)
      }
      fileIo.renameSync(tempPath, fallbackPath)
      await db.updateDownloadStatus(taskId, 'completed', 100, fallbackPath)
      return fallbackPath
    }
    // 非嵌入路径（GIF 或关闭 EXIF）：part_ 临时文件重命名为成品（完成转成品，FR-008）
    let finalPath = basePath + '.' + ext
    if (tempPath !== finalPath) {
      if (fileIo.accessSync(finalPath)) {
        fileIo.unlinkSync(finalPath)
      }
      fileIo.renameSync(tempPath, finalPath)
    }
    await db.updateDownloadStatus(taskId, 'completed', 100, finalPath)
    return finalPath
  }

  /**
   * 公开入队入口（fire-and-forget）：
   * 先写 DB pending 记录入 FIFO 队列；activeCount < 当前上限立即执行，否则排队等待补位。
   * 并发上限每次调度时读 userSettingStore.getSettings().downloadConcurrency（防御拷贝，配置即时生效）。
   * 同步返回值（R4 下载反馈四态）：'inflight'=同页已在队列/下载中（跳过不入队）；'enqueued'=正常入队。
   */
  enqueue(url: string, illust: Illust, pageIndex: number): string {
    let taskId = illust.id + '_' + pageIndex
    if (this.inflightTaskIds.indexOf(taskId) >= 0) {
      // 同一页已在排队/下载中，跳过重复入队
      return 'inflight'
    }
    this.inflightTaskIds.push(taskId)
    let dbReady: Promise<void> = getDbService()
      .then(async (db: DatabaseService): Promise<void> => {
        await db.addDownloadTask(taskId, illust.id, pageIndex, url)
      })
      .catch((e: Object) => {
        console.error('Enqueue DB write failed: ' + e)
      })
    let task: QueuedDownloadTask = {
      url: url,
      illust: illust,
      pageIndex: pageIndex,
      taskId: taskId,
      dbReady: dbReady
    }
    this.queue.push(task)
    // 通知监听方刷新（DownloadPage 可见 pending "排队中"）
    this.notifyTaskChanged()
    this.scheduleNext()
    return 'enqueued'
  }

  /**
   * ugoira（动图）入队入口：taskId=<id>_ugoira、page_index=-1、image_url 用封面 URL（供下载页缩略图回退）。
   * 与普通 enqueue 共用 FIFO 队列/并发调度/在途去重；任务体经 runTask 分流到 runUgoiraTask。
   */
  enqueueUgoira(illust: Illust): string {
    let taskId = illust.id + '_ugoira'
    if (this.inflightTaskIds.indexOf(taskId) >= 0) {
      return 'inflight'
    }
    this.inflightTaskIds.push(taskId)
    let coverUrl = illust.imageUrls.large
    let dbReady: Promise<void> = getDbService()
      .then(async (db: DatabaseService): Promise<void> => {
        await db.addDownloadTask(taskId, illust.id, -1, coverUrl)
      })
      .catch((e: Object) => {
        console.error('Enqueue ugoira DB write failed: ' + e)
      })
    let task: QueuedDownloadTask = {
      url: coverUrl,
      illust: illust,
      pageIndex: -1,
      taskId: taskId,
      dbReady: dbReady
    }
    this.queue.push(task)
    this.notifyTaskChanged()
    this.scheduleNext()
    return 'enqueued'
  }

  private currentConcurrencyLimit(): number {
    let limit = userSettingStore.getSettings().downloadConcurrency
    if (limit < 1) {
      return 1
    }
    if (limit > 5) {
      return 5
    }
    return limit
  }

  private scheduleNext(): void {
    let limit = this.currentConcurrencyLimit()
    while (this.activeCount < limit && this.queue.length > 0) {
      let task = this.queue.shift()
      if (task === undefined) {
        break
      }
      this.activeCount++
      this.runTask(task)
        .then(() => {
          this.onTaskSettled()
        })
        .catch((e: Object) => {
          console.error('Download task failed: ' + e)
          this.onTaskSettled()
        })
    }
  }

  private onTaskSettled(): void {
    this.activeCount--
    this.scheduleNext()
    this.flushGalleryIfIdle()
  }

  /** 任务体 = 等待 pending 落库 → 下载落盘 → finalize → 攒批写图库（状态落库与 notifyTaskChanged 在下载链路内完成） */
  private async runTask(task: QueuedDownloadTask): Promise<void> {
    try {
      await task.dbReady
      let localPath = ''
      if (task.pageIndex === -1) {
        // ugoira 动图：拉帧包 → GIF 编码落盘（page_index=-1 标记）
        localPath = await this.runUgoiraTask(task)
      } else {
        localPath = await this.downloadToCache(task.url, task.illust, task.pageIndex)
      }
      if (localPath.length === 0) {
        this.showToastSafe(getStrf($r('app.string.svc_download_failed_title'), task.illust.title))
        return
      }
      // 优先静默写图库：SaveButton 点击后的临时授权窗口内（API≥20 为 1 分钟）applyChanges 可用；
      // 窗口外静默失败则攒批走系统保存确认弹窗
      let ctx = AppStorage.get<common.Context>('context')
      let silentSaved = false
      if (ctx) {
        silentSaved = await this.applySilentToGallery(localPath, ctx)
      }
      if (silentSaved) {
        this.showToastSafe(getStr($r('app.string.svc_saved_to_gallery')))
      } else {
        this.pendingGalleryPaths.push(localPath)
      }
    } finally {
      let idx = this.inflightTaskIds.indexOf(task.taskId)
      if (idx >= 0) {
        this.inflightTaskIds.splice(idx, 1)
      }
    }
  }

  /** 队列排空后统一写图库：一次系统确认弹窗保存本批全部图片 */
  private flushGalleryIfIdle(): void {
    if (this.galleryFlushing || this.activeCount > 0 || this.queue.length > 0 ||
      this.pendingGalleryPaths.length === 0) {
      return
    }
    let paths = this.pendingGalleryPaths.slice()
    this.pendingGalleryPaths = []
    let ctx = AppStorage.get<common.Context>('context')
    if (!ctx) {
      this.showToastSafe(getStrf($r('app.string.svc_download_done_cache_only'), paths.length))
      return
    }
    this.galleryFlushing = true
    this.applyBatchToGallery(paths, ctx)
      .then((saved: boolean) => {
        if (saved) {
          this.showToastSafe(getStrf($r('app.string.svc_saved_n_to_gallery'), paths.length))
        } else {
          this.showToastSafe(getStr($r('app.string.svc_saved_cache_gallery_cancelled')))
        }
      })
      .catch((e: Object) => {
        console.error('Flush gallery failed: ' + e)
        this.showToastSafe(getStr($r('app.string.svc_gallery_write_failed')))
      })
      .finally(() => {
        this.galleryFlushing = false
        // 弹窗期间可能有新任务完成，继续补刷
        this.flushGalleryIfIdle()
      })
  }

  /** 静默删除 part_ 临时文件（不存在/失败均忽略，仅记日志） */
  private deletePartFileQuietly(partPath: string): void {
    if (partPath.length === 0) {
      return
    }
    try {
      if (fileIo.accessSync(partPath)) {
        fileIo.unlinkSync(partPath)
      }
    } catch (e) {
      console.error('Delete part file failed: ' + e)
    }
  }

  private showToastSafe(message: string): void {
    try {
      promptAction.showToast({ message: message, duration: 2500 })
    } catch (e) {
      console.error('Toast failed: ' + e)
    }
  }

  /**
   * 单次流式传输（T002）：先 on() 订阅全部事件再发起 requestInStream，结束一律 off + destroy() 防泄漏。
   * headersReceive 捕获 Content-Length / Content-Range 并决定续传分支（T007）：
   * 206（Content-Range 起点=续传偏移）→ 保留已有内容从偏移追加；200（上游不支持 Range）→ 截断临时文件从头写；
   * 416（Content-Range 为 bytes 星号/total 形式，偏移已越界）→ 视为已完成直接成功。
   * dataReceive 块按递增偏移 writeSync 落盘并做进度节流写库（T004）；
   * dataEnd + 响应码双就绪后校验完成量（有长度依据且写盘字节不足视为传输中断，可重试）。
   * 返回最终落盘字节数；失败抛 StreamTransferError。
   */
  private streamOnce(requestUrl: string, headers: Record<string, string>, useDirectIp: boolean,
    partPath: string, resumeOffset: number, taskId: string, db: DatabaseService,
    throttle: ProgressThrottle): Promise<number> {
    return new Promise<number>((resolve, reject) => {
      let httpClient = http.createHttp()
      let fd = -1
      let writeOffset = resumeOffset
      let appendMode = false
      let alreadyComplete = false
      let badRange = false
      let contentLength = -1
      let rangeTotal = -1
      let statusCode = 0
      let dataEnded = false
      let settled = false
      let cleanup = (): void => {
        try {
          httpClient.off('headersReceive')
          httpClient.off('dataReceive')
          httpClient.off('dataEnd')
          httpClient.destroy()
        } catch (e) {
          console.error('Stream cleanup failed: ' + e)
        }
        if (fd >= 0) {
          try {
            fileIo.closeSync(fd)
          } catch (e) {
            console.error('Stream fd close failed: ' + e)
          }
          fd = -1
        }
      }
      let fail = (err: StreamTransferError): void => {
        if (settled) {
          return
        }
        settled = true
        cleanup()
        reject(err)
      }
      let succeed = (): void => {
        if (settled) {
          return
        }
        settled = true
        cleanup()
        resolve(writeOffset)
      }
      // 期望的最终落盘字节数（无长度依据时返回 -1，不做完成量校验）
      let expectedTotal = (): number => {
        if (appendMode) {
          if (rangeTotal > 0) {
            return rangeTotal
          }
          if (contentLength >= 0) {
            return resumeOffset + contentLength
          }
          return -1
        }
        return contentLength
      }
      // 响应码（requestInStream 回调）与 dataEnd 的到达顺序不作假设，两者齐备才判定终态
      let maybeSettle = (): void => {
        if (settled || !dataEnded || statusCode === 0) {
          return
        }
        if (alreadyComplete) {
          // 续传偏移已越界（416）：临时文件即完整文件，直接成功进入 finalize
          succeed()
          return
        }
        if (badRange) {
          // 206 起点与续传偏移不一致：内容不可信（本次未写盘），按可重试传输错误处理
          fail(new StreamTransferError('Content-Range start mismatch', true, false))
          return
        }
        if (statusCode >= 400) {
          // 4xx 立即失败不重试；5xx 可重试；错误页已写盘内容不可信
          fail(new StreamTransferError('HTTP ' + statusCode, statusCode >= 500, true))
          return
        }
        let expected = expectedTotal()
        if (expected > 0 && writeOffset < expected) {
          fail(new StreamTransferError('Truncated transfer: ' + writeOffset + '/' + expected, true, false))
          return
        }
        succeed()
      }
      try {
        // 不开 TRUNC：保留已有内容供 206 追加；需要整下时在 headersReceive 内显式截断
        fd = fileIo.openSync(partPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE).fd
      } catch (e) {
        fail(new StreamTransferError('Open part file failed: ' + e, true, false))
        return
      }
      httpClient.on('headersReceive', (header: Object) => {
        let h = header as Record<string, Object>
        let rawLen = h['content-length'] ?? h['Content-Length']
        if (rawLen !== undefined) {
          let parsed = parseInt(String(rawLen))
          if (!Number.isNaN(parsed)) {
            contentLength = parsed
          }
        }
        if (resumeOffset <= 0 || settled || fd < 0) {
          return
        }
        let rawRange = h['content-range'] ?? h['Content-Range']
        let contentRange = rawRange !== undefined ? String(rawRange) : ''
        if (contentRange.startsWith('bytes */')) {
          // 416 Range Not Satisfiable：偏移已越界，临时文件视为完整
          alreadyComplete = true
          return
        }
        if (contentRange.startsWith('bytes ')) {
          // 206 Partial Content：校验起点与续传偏移一致后追加
          let slash = contentRange.indexOf('/')
          let dash = contentRange.indexOf('-')
          if (slash > 6 && dash > 6 && dash < slash) {
            let start = parseInt(contentRange.substring(6, dash))
            let total = parseInt(contentRange.substring(slash + 1))
            if (!Number.isNaN(total)) {
              rangeTotal = total
            }
            if (!Number.isNaN(start) && start === resumeOffset && (rangeTotal <= 0 || resumeOffset < rangeTotal)) {
              appendMode = true
            } else {
              badRange = true
            }
          } else {
            badRange = true
          }
          return
        }
        // 上游不支持 Range（200 全量）或错误页：截断临时文件从头写（错误页终态会再删文件）
        try {
          fileIo.truncateSync(fd, 0)
        } catch (e) {
          fail(new StreamTransferError('Truncate part file failed: ' + e, true, false))
          return
        }
        writeOffset = 0
      })
      httpClient.on('dataReceive', (data: ArrayBuffer) => {
        if (settled || fd < 0 || alreadyComplete || badRange) {
          return
        }
        try {
          fileIo.writeSync(fd, data, { offset: writeOffset })
          writeOffset += data.byteLength
        } catch (e) {
          fail(new StreamTransferError('Write part file failed: ' + e, true, false))
          return
        }
        // 进度节流（T004）：有长度依据时按 ≥2% 增量写库；不写 notifyTaskChanged（轮询覆盖刷新）
        let totalSize = expectedTotal()
        if (totalSize > 0) {
          let percent = Math.floor(writeOffset * 100 / totalSize)
          if (percent > 100) {
            percent = 100
          }
          if (percent - throttle.lastSavedPercent >= 2) {
            throttle.lastSavedPercent = percent
            db.updateDownloadStatus(taskId, 'downloading', percent, '').catch((e: Object) => {
              console.error('Progress write failed: ' + e)
            })
          }
        }
      })
      httpClient.on('dataEnd', () => {
        dataEnded = true
        maybeSettle()
      })
      let reqOptions: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        connectTimeout: Constants.DOWNLOAD_CONNECT_TIMEOUT,
        readTimeout: Constants.DOWNLOAD_READ_TIMEOUT,
        header: headers
      }
      if (useDirectIp) {
        reqOptions.remoteValidation = 'skip'
      }
      httpClient.requestInStream(requestUrl, reqOptions, (err: BusinessError<void>, code: number) => {
        if (err) {
          fail(new StreamTransferError('requestInStream error: ' + JSON.stringify(err), true, false))
          return
        }
        statusCode = code
        maybeSettle()
      })
    })
  }

  private async downloadToCache(url: string, illust: Illust, pageIndex: number): Promise<string> {
    let taskId = illust.id + '_' + pageIndex
    let apiMode = Constants.normalizeMode(preferenceService.getString('api_mode', Constants.MODE_STANDARD))
    let isRelay = Constants.isRelayMode(apiMode)
    let requestUrl = ''
    let originalHost = ''
    let useDirectIp = false
    if (isRelay) {
      // relay 模式：URL 包装为 /img/v1/fetch?url=，跳过 applyImageHost/applyDirectIp/Host 头/证书跳过
      requestUrl = relayClient.buildImageUrl(url)
    } else {
      let imageHostType = preferenceService.getString('image_host_type', 'default')
      let imageHostCustom = preferenceService.getString('image_host_custom', 'i.pximg.net')
      let hostUrl = Constants.applyImageHost(Constants.applyProxy(url), imageHostType, imageHostCustom)
      originalHost = Constants.extractHost(hostUrl)
      requestUrl = Constants.applyDirectIp(hostUrl)
      useDirectIp = requestUrl !== hostUrl
    }
    let db = await getDbService()

    let partPath = ''
    try {
      await db.updateDownloadStatus(taskId, 'downloading', 0, '')
      let settings = userSettingStore.getSettings()
      let ext = this.getExtension(url)
      let shouldEmbedExif = settings.embedExifMetadata && ext !== 'gif'
      let baseName = this.buildFilename(illust, pageIndex)
      let ctx = AppStorage.get<common.Context>('context')
      if (!ctx) {
        throw new Error('Context not found')
      }
      let cacheDir = ctx.cacheDir + '/downloads'
      if (!fileIo.accessSync(cacheDir)) {
        fileIo.mkdirSync(cacheDir)
      }
      let basePath = cacheDir + '/' + baseName
      // 统一先落 part_<taskId>.<ext> 临时文件（断点续传载体），完成后经 finalize 转成品
      partPath = cacheDir + '/' + Constants.DOWNLOAD_PART_PREFIX + taskId + '.' + ext

      let headers: Record<string, string> = {}
      if (isRelay) {
        // relay 模式仅注入服务级 Bearer，不注入 Referer/User-Agent
        headers = await relayClient.buildImageAuthHeader()
      } else {
        headers = this.buildDownloadHeaders()
        if (useDirectIp && originalHost.length > 0) {
          headers['Host'] = originalHost
        }
      }
      let throttle: ProgressThrottle = { lastSavedPercent: 0 }
      // 任务内自动重试（T005）：最多 DOWNLOAD_MAX_ATTEMPTS 次（1 初始 + 2 重试），退避 1s→2s；
      // 可重试=网络错误/超时/5xx/传输中断；不可重试=4xx 立即失败
      let maxAttempts = Constants.DOWNLOAD_MAX_ATTEMPTS
      let lastError: Error = new Error('Download failed without attempt')
      let succeeded = false
      for (let attempt = 1; attempt <= maxAttempts; attempt++) {
        // 断点续传（T007）：临时文件大小即偏移，>0 时携带 Range 头从已下载字节处继续
        let resumeOffset = 0
        try {
          if (fileIo.accessSync(partPath)) {
            let size = fileIo.statSync(partPath).size
            if (size > 0) {
              resumeOffset = size
            }
          }
        } catch (e) {
          console.error('Stat part file failed: ' + e)
        }
        let attemptHeaders: Record<string, string> = {}
        let headerKeys = Object.keys(headers)
        for (let i = 0; i < headerKeys.length; i++) {
          attemptHeaders[headerKeys[i]] = headers[headerKeys[i]]
        }
        if (resumeOffset > 0) {
          attemptHeaders['Range'] = 'bytes=' + resumeOffset + '-'
        }
        try {
          await this.streamOnce(requestUrl, attemptHeaders, useDirectIp, partPath, resumeOffset, taskId, db, throttle)
          succeeded = true
          break
        } catch (e) {
          if (e instanceof StreamTransferError) {
            // Error 为接口类型，类实例直接赋值触发 arkts-no-structural-typing，重新构造
            lastError = new Error(e.message)
            if (e.discardPartial) {
              // 已写盘内容为 HTTP 错误页等不可信数据，删除避免污染后续续传
              this.deletePartFileQuietly(partPath)
            }
            if (!e.retryable) {
              break
            }
          } else {
            // 非传输错误（如文件系统异常）：按可重试处理
            lastError = e instanceof Error ? e : new Error(String(e))
          }
          if (attempt < maxAttempts) {
            let delayMs = Constants.DOWNLOAD_RETRY_BASE_DELAY_MS * Math.pow(2, attempt - 1)
            console.info(`Download task ${taskId} attempt ${attempt} failed, retry in ${delayMs}ms: ${lastError.message}`)
            await new Promise<void>((resolve: () => void) => {
              setTimeout(resolve, delayMs)
            })
          }
        }
      }
      if (!succeeded) {
        throw lastError
      }
      let finalPath = await this.finalizeDownload(partPath, basePath, ext, shouldEmbedExif, illust, pageIndex, taskId, db)
      this.notifyTaskChanged()
      return finalPath
    } catch (e) {
      // HTTP 错误页等不可信内容已写盘时删除临时文件，避免污染后续续传（重试循环内已处理，此为兜底）
      if (e instanceof StreamTransferError && e.discardPartial) {
        this.deletePartFileQuietly(partPath)
      }
      await db.updateDownloadStatus(taskId, 'failed', 0, '')
      this.notifyTaskChanged()
      console.error('Download failed: ' + e)
    }
    return ''
  }

  /**
   * ugoira 任务体：UgoiraService 拉 metadata/zip 帧包并编码 GIF 到 <taskId>.gif.tmp，
   * 成功后复用 finalizeDownload 非 EXIF 分支转成品 .gif（GIF 不嵌入元数据），状态落库与 notifyTaskChanged 语义同 downloadToCache。
   */
  private async runUgoiraTask(task: QueuedDownloadTask): Promise<string> {
    let db = await getDbService()
    let tmpPath = ''
    try {
      await db.updateDownloadStatus(task.taskId, 'downloading', 0, '')
      let ctx = AppStorage.get<common.Context>('context')
      if (!ctx) {
        throw new Error('Context not found')
      }
      let cacheDir = ctx.cacheDir + '/downloads'
      if (!fileIo.accessSync(cacheDir)) {
        fileIo.mkdirSync(cacheDir)
      }
      tmpPath = cacheDir + '/' + task.taskId + '.gif.tmp'
      let basePath = cacheDir + '/' + this.buildFilename(task.illust, 0)
      // 进度节流写库：编码回调 ratio 0~1，≥2% 增量才写，100 由 finalize 的 completed 落库
      let throttle: ProgressThrottle = { lastSavedPercent: 0 }
      let ok = await ugoiraService.encodeToGif(task.illust.id, tmpPath, (ratio: number) => {
        let percent = Math.floor(ratio * 100)
        if (percent > 99) {
          percent = 99
        }
        if (percent - throttle.lastSavedPercent >= 2) {
          throttle.lastSavedPercent = percent
          db.updateDownloadStatus(task.taskId, 'downloading', percent, '').catch((e: Object) => {
            console.error('Ugoira progress write failed: ' + e)
          })
        }
      })
      if (!ok) {
        throw new Error('Ugoira GIF encode failed')
      }
      let finalPath = await this.finalizeDownload(tmpPath, basePath, 'gif', false, task.illust, 0, task.taskId, db)
      this.notifyTaskChanged()
      return finalPath
    } catch (e) {
      this.deletePartFileQuietly(tmpPath)
      await db.updateDownloadStatus(task.taskId, 'failed', 0, '')
      this.notifyTaskChanged()
      console.error('Ugoira download failed: ' + e)
    }
    return ''
  }

  /** 静默写图库（需 SaveButton 临时授权窗口内才可用，否则抛错返回 false） */
  private async applySilentToGallery(localPath: string, context: common.Context): Promise<boolean> {
    try {
      let ph = photoAccessHelper.getPhotoAccessHelper(context)
      let srcUri = fileUri.getUriFromPath(localPath)
      let req = photoAccessHelper.MediaAssetChangeRequest.createImageAssetRequest(context, srcUri)
      await ph.applyChanges(req)
      return true
    } catch (e) {
      console.info('Silent gallery save unavailable: ' + e)
      return false
    }
  }

  /** 批量写图库：showAssetsCreationDialog 免权限（WRITE_IMAGEVIDEO 为 ACL 受限权限装不上），系统弹一次保存确认 */
  private async applyBatchToGallery(paths: string[], context: common.Context): Promise<boolean> {
    try {
      let ph = photoAccessHelper.getPhotoAccessHelper(context)
      let srcUris: string[] = []
      let configs: photoAccessHelper.PhotoCreationConfig[] = []
      for (let i = 0; i < paths.length; i++) {
        let ext = 'jpg'
        let dot = paths[i].lastIndexOf('.')
        if (dot >= 0) {
          ext = paths[i].substring(dot + 1)
        }
        srcUris.push(fileUri.getUriFromPath(paths[i]))
        let config: photoAccessHelper.PhotoCreationConfig = {
          fileNameExtension: ext,
          photoType: photoAccessHelper.PhotoType.IMAGE
        }
        configs.push(config)
      }
      let uris = await ph.showAssetsCreationDialog(srcUris, configs)
      if (uris.length === 0) {
        console.info('applyBatchToGallery: user cancelled, 0/' + paths.length)
        return false
      }
      // 弹窗只创建目标 uri，内容必须自行拷入，否则媒体库里是空壳不显示
      let copied = 0
      for (let i = 0; i < uris.length && i < paths.length; i++) {
        try {
          let srcFile = fileIo.openSync(paths[i], fileIo.OpenMode.READ_ONLY)
          let desFile = fileIo.openSync(uris[i], fileIo.OpenMode.WRITE_ONLY)
          await fileIo.copyFile(srcFile.fd, desFile.fd)
          fileIo.closeSync(srcFile)
          fileIo.closeSync(desFile)
          copied++
        } catch (e) {
          console.error('Copy to gallery uri failed: ' + paths[i] + ' -> ' + uris[i] + ': ' + e)
        }
      }
      console.info('applyBatchToGallery result: saved=' + copied + '/' + paths.length)
      return copied > 0
    } catch (e) {
      console.error('Apply to gallery failed: ' + e)
      return false
    }
  }

  async getTasks(): Promise<Array<object>> {
    let db = await getDbService()
    return db.getDownloadTasks()
  }

  /**
   * 重复下载检测：存在 completed 任务记录且对应文件仍存在才判定已下载。
   * DB 不可用时降级返回 false（直接下载）。
   */
  async isDownloaded(illustId: number, part: number): Promise<boolean> {
    try {
      let db = await getDbService()
      let task = await db.getDownloadTaskById(illustId + '_' + part)
      if (!task || task.status !== 'completed' || task.local_path.length === 0) {
        return false
      }
      return fileIo.accessSync(task.local_path)
    } catch (e) {
      console.error('Check downloaded failed: ' + e)
      return false
    }
  }

  /** ugoira 重复下载检测：completed 记录（page_index=-1，taskId=<id>_ugoira）且文件仍存在；DB 异常降级 false */
  async isUgoiraDownloaded(illustId: number): Promise<boolean> {
    try {
      let db = await getDbService()
      let task = await db.getDownloadTaskById(illustId + '_ugoira')
      if (!task || task.status !== 'completed' || task.local_path.length === 0) {
        return false
      }
      return fileIo.accessSync(task.local_path)
    } catch (e) {
      console.error('Check ugoira downloaded failed: ' + e)
      return false
    }
  }

  /** 已下载 ugoira GIF 的本地路径（查看器分享用）；无记录/文件不存在返回 '' */
  async getUgoiraLocalPath(illustId: number): Promise<string> {
    try {
      let db = await getDbService()
      let task = await db.getDownloadTaskById(illustId + '_ugoira')
      if (!task || task.status !== 'completed' || task.local_path.length === 0) {
        return ''
      }
      if (!fileIo.accessSync(task.local_path)) {
        return ''
      }
      return task.local_path
    } catch (e) {
      console.error('Get ugoira local path failed: ' + e)
      return ''
    }
  }

  /** 删除指定状态的任务记录（删记录前同步删除对应 part_ 临时文件，成品文件保留），返回删除数 */
  async clearTasksByStatus(status: string): Promise<number> {
    let db = await getDbService()
    // FR-008：临时文件唯一清理出口——先枚举匹配任务删除 part_<taskId>.<ext>，再删记录
    try {
      let ctx = AppStorage.get<common.Context>('context')
      if (ctx) {
        let cacheDir = ctx.cacheDir + '/downloads'
        let tasks = await db.getDownloadTasks()
        for (let i = 0; i < tasks.length; i++) {
          if (tasks[i].status !== status) {
            continue
          }
          if (tasks[i].page_index === -1) {
            // ugoira 任务的临时文件为 <taskId>.gif.tmp（非 part_ 前缀）
            this.deletePartFileQuietly(cacheDir + '/' + tasks[i].id + '.gif.tmp')
            continue
          }
          let partPath = cacheDir + '/' + Constants.DOWNLOAD_PART_PREFIX + tasks[i].id + '.' +
            this.getExtension(tasks[i].image_url)
          this.deletePartFileQuietly(partPath)
        }
      }
    } catch (e) {
      console.error('Clean part files failed: ' + e)
    }
    return await db.deleteDownloadTasksByStatus(status)
  }

  /** 重试全部失败任务：用任务记录的 URL + 接口元信息重建下载并入队；元信息缺失条目计 skipped。
   *  入队为 fire-and-forget，started=入队数，succeeded/failed 不再同步统计（保持 0）。
   *  onTaskDone 每处理完一条记录回调，供 UI 刷新列表。 */
  async retryAllFailed(onTaskDone?: () => void): Promise<RetryAllResult> {
    let db = await getDbService()
    let tasks = await db.getDownloadTasks()
    let result: RetryAllResult = { started: 0, succeeded: 0, failed: 0, skipped: 0 }
    for (let i = 0; i < tasks.length; i++) {
      let task = tasks[i]
      if (task.status !== 'failed') {
        continue
      }
      if (task.image_url.length === 0) {
        result.skipped++
        if (onTaskDone) { onTaskDone() }
        continue
      }
      try {
        let response = await apiService.getIllustDetail(task.illust_id)
        let raw = (response as IllustDetailResponse).illust
        if (!raw) {
          console.error('Retry task ' + task.id + ' skipped: illust metadata missing')
          result.skipped++
          if (onTaskDone) { onTaskDone() }
          continue
        }
        let illust = Illust.fromJson(raw)
        if (illust.id === 0) {
          result.skipped++
          if (onTaskDone) { onTaskDone() }
          continue
        }
        result.started++
        if (task.page_index === -1) {
          // ugoira 任务重建走 GIF 编码管线，而非普通图片下载（image_url 只是封面）
          this.enqueueUgoira(illust)
        } else {
          this.enqueue(task.image_url, illust, task.page_index)
        }
      } catch (e) {
        console.error('Retry task ' + task.id + ' failed: ' + e)
        result.failed++
      }
      if (onTaskDone) { onTaskDone() }
    }
    return result
  }
}

export const downloadService = DownloadService.getInstance()
