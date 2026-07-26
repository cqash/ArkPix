import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { rcp } from '@kit.RemoteCommunicationKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { promptAction } from '@kit.ArkUI';
import { getDbService, DatabaseService } from './DatabaseService';
import { Constants } from '../utils/Constants';
import { imageExifService, ExifInfo, ExifTag } from './ImageExifService';
import { Illust, Tag } from '../models/Illust';
import { userSettingStore } from '../stores/UserSettingStore';
import { preferenceService } from './PreferenceService';
import { hoster } from '../network/Hoster';
import { apiService } from '../network/ApiService';

interface IllustDetailResponse {
  illust: Object
}

export class DownloadService {
  private static instance: DownloadService

  private constructor() {}

  static getInstance(): DownloadService {
    if (!DownloadService.instance) {
      DownloadService.instance = new DownloadService()
    }
    return DownloadService.instance
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
    await db.updateDownloadStatus(taskId, 'completed', 100, tempPath)
    return tempPath
  }

  async downloadToCache(url: string, illust: Illust, pageIndex: number): Promise<string> {
    let taskId = illust.id + '_' + pageIndex
    let proxyUrl = Constants.applyProxy(url)
    let db = await getDbService()
    await db.addDownloadTask(taskId, illust.id, pageIndex, url)

    promptAction.showToast({ message: '开始下载...' })

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
      let tempPath = shouldEmbedExif ? (cacheDir + '/temp_' + taskId + '.' + ext) : (basePath + '.' + ext)

      let networkMode = preferenceService.getString('network_mode', 'direct')
      if (networkMode === 'bypass') {
        return await this.downloadBypass(url, tempPath, basePath, ext, taskId, db, shouldEmbedExif, illust, pageIndex)
      }

      let httpClient = http.createHttp()
      let response = await new Promise<http.HttpResponse>((resolve, reject) => {
        httpClient.request(proxyUrl, {
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.ARRAY_BUFFER,
          connectTimeout: 30000,
          readTimeout: 30000,
          header: this.buildDownloadHeaders()
        }, (err, data) => {
          if (err) { reject(err) } else { resolve(data) }
        })
      })

      if (response.result instanceof ArrayBuffer) {
        let file = fileIo.openSync(tempPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
        fileIo.writeSync(file.fd, response.result)
        fileIo.closeSync(file)
        return await this.finalizeDownload(tempPath, basePath, ext, shouldEmbedExif, illust, pageIndex, taskId, db)
      }
    } catch (e) {
      await db.updateDownloadStatus(taskId, 'failed', 0, '')
      console.error('Download failed: ' + e)
    }
    return ''
  }

  private async downloadBypass(url: string, tempPath: string, basePath: string, ext: string, taskId: string,
    db: DatabaseService, shouldEmbedExif: boolean, illust: Illust, pageIndex: number): Promise<string> {
    let session: rcp.Session = rcp.createSession({
      requestConfiguration: {
        dns: {
          dnsRules: (host: string, port: number): string[] => {
            return hoster.resolveIps(host)
          }
        },
        transfer: {
          timeout: { connectMs: 30000, transferMs: 30000 }
        }
      }
    })
    try {
      let request: rcp.Request = new rcp.Request(url, 'GET')
      request.headers = this.buildDownloadHeaders()
      let response: rcp.Response = await session.fetch(request)
      if (response.statusCode === 200 && response.body) {
        let file = fileIo.openSync(tempPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
        fileIo.writeSync(file.fd, response.body)
        fileIo.closeSync(file)
        return await this.finalizeDownload(tempPath, basePath, ext, shouldEmbedExif, illust, pageIndex, taskId, db)
      }
    } catch (e) {
      console.error('Download bypass failed: ' + e)
      await db.updateDownloadStatus(taskId, 'failed', 0, '')
    } finally {
      session.close()
    }
    return ''
  }

  async applyToGallery(localPath: string, context: common.Context): Promise<boolean> {
    try {
      let ph = photoAccessHelper.getPhotoAccessHelper(context)
      let srcUri = fileUri.getUriFromPath(localPath)
      let assetChangeRequest: photoAccessHelper.MediaAssetChangeRequest =
        photoAccessHelper.MediaAssetChangeRequest.createImageAssetRequest(context, srcUri)
      await ph.applyChanges(assetChangeRequest)
      return true
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

  /** 删除指定状态的任务记录（仅删记录不删文件），返回删除数 */
  async clearTasksByStatus(status: string): Promise<number> {
    let db = await getDbService()
    return await db.deleteDownloadTasksByStatus(status)
  }

  /** 重试全部失败任务：用任务记录的 URL + 接口元信息重建下载；元信息缺失条目跳过。返回成功发起数 */
  async retryAllFailed(): Promise<number> {
    let db = await getDbService()
    let tasks = await db.getDownloadTasks()
    let started = 0
    for (let i = 0; i < tasks.length; i++) {
      let task = tasks[i]
      if (task.status !== 'failed' || task.image_url.length === 0) {
        continue
      }
      try {
        let response = await apiService.getIllustDetail(task.illust_id)
        let raw = (response as IllustDetailResponse).illust
        if (!raw) {
          console.error('Retry task ' + task.id + ' skipped: illust metadata missing')
          continue
        }
        let illust = Illust.fromJson(raw)
        if (illust.id === 0) {
          continue
        }
        let localPath = await this.downloadToCache(task.image_url, illust, task.page_index)
        if (localPath.length > 0) {
          let ctx = AppStorage.get<common.Context>('context')
          if (ctx) {
            await this.applyToGallery(localPath, ctx)
          }
          started++
        }
      } catch (e) {
        console.error('Retry task ' + task.id + ' failed: ' + e)
      }
    }
    return started
  }
}

export const downloadService = DownloadService.getInstance()
