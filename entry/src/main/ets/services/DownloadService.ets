import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { promptAction } from '@kit.ArkUI';
import { getDbService } from './DatabaseService';
import { Constants } from '../utils/Constants';
import { imageExifService, ExifInfo, ExifTag } from './ImageExifService';
import { Illust, Tag } from '../models/Illust';
import { userSettingStore } from '../stores/UserSettingStore';

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

  private getFinalExtension(url: string, embedExif: boolean): string {
    let ext = this.getExtension(url)
    if (embedExif && ext !== 'gif') {
      return 'jpg'
    }
    return ext
  }

  private buildExifInfo(illust: Illust): ExifInfo {
    let tags: ExifTag[] = illust.tags.map((t: Tag): ExifTag => {
      return { name: t.name, translatedName: t.translatedName }
    })
    return {
      title: illust.title,
      userName: illust.user.name,
      tags: tags,
      createDate: illust.createDate
    }
  }

  private buildDownloadHeaders(): Record<string, string> {
    return {
      'Referer': 'https://app-api.pixiv.net/',
      'User-Agent': Constants.IMAGE_USER_AGENT
    }
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
      let finalExt = this.getFinalExtension(url, shouldEmbedExif)
      let ctx = AppStorage.get<common.Context>('context')
      if (!ctx) {
        throw new Error('Context not found')
      }
      let cacheDir = ctx.cacheDir + '/downloads'
      if (!fileIo.accessSync(cacheDir)) {
        fileIo.mkdirSync(cacheDir)
      }
      let finalPath = cacheDir + '/' + baseName + '.' + finalExt
      let tempPath = shouldEmbedExif ? (cacheDir + '/temp_' + taskId + '.' + ext) : finalPath

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
        if (shouldEmbedExif) {
          let exifInfo = this.buildExifInfo(illust)
          await imageExifService.embedExif(tempPath, finalPath, exifInfo)
          try {
            fileIo.unlinkSync(tempPath)
          } catch (e) {
            console.error('Delete temp download file failed: ' + e)
          }
        }
        await db.updateDownloadStatus(taskId, 'completed', 100, finalPath)
        return finalPath
      }
    } catch (e) {
      await db.updateDownloadStatus(taskId, 'failed', 0, '')
      console.error('Download failed: ' + e)
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
}

export const downloadService = DownloadService.getInstance()
