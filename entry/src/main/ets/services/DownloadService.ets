import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { getDbService } from './DatabaseService';
import { Constants } from '../utils/Constants';

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

  private getExtensionFromPath(path: string): string {
    let lowerPath = path.toLowerCase()
    if (lowerPath.endsWith('.png')) { return 'png' }
    if (lowerPath.endsWith('.jpg') || lowerPath.endsWith('.jpeg')) { return 'jpg' }
    if (lowerPath.endsWith('.gif')) { return 'gif' }
    return 'jpg'
  }

  async saveToGallery(localPath: string): Promise<boolean> {
    try {
      let ctx = AppStorage.get<common.Context>('context')
      if (!ctx) {
        throw new Error('Context not found')
      }
      let ph = photoAccessHelper.getPhotoAccessHelper(ctx)
      let srcUri = fileUri.getUriFromPath(localPath)
      let photoCreationConfigs: photoAccessHelper.PhotoCreationConfig[] = [{
        title: 'PixEz',
        fileNameExtension: this.getExtensionFromPath(localPath),
        photoType: photoAccessHelper.PhotoType.IMAGE,
        subtype: photoAccessHelper.PhotoSubtype.DEFAULT
      }]
      let desUris = await ph.showAssetsCreationDialog([srcUri], photoCreationConfigs)
      if (desUris.length > 0) {
        let srcFile = fileIo.openSync(srcUri, fileIo.OpenMode.READ_ONLY)
        let dstFile = fileIo.openSync(desUris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
        await fileIo.copyFile(srcFile.fd, dstFile.fd)
        fileIo.closeSync(srcFile)
        fileIo.closeSync(dstFile)
        return true
      }
    } catch (e) {
      console.error('Save to gallery failed: ' + e)
    }
    return false
  }

  async downloadImage(url: string, illustId: number, pageIndex: number): Promise<boolean> {
    let taskId = illustId + '_' + pageIndex
    let proxyUrl = Constants.applyProxy(url)
    let db = await getDbService()
    await db.addDownloadTask(taskId, illustId, pageIndex, url)

    try {
      await db.updateDownloadStatus(taskId, 'downloading', 0, '')
      let httpClient = http.createHttp()
      let response = await new Promise<http.HttpResponse>((resolve, reject) => {
        httpClient.request(proxyUrl, {
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.ARRAY_BUFFER,
          connectTimeout: 30000,
          readTimeout: 30000,
          header: {
            'Referer': 'https://www.pixiv.net/'
          }
        }, (err, data) => {
          if (err) { reject(err) } else { resolve(data) }
        })
      })

      if (response.result instanceof ArrayBuffer) {
        let ctx = AppStorage.get<common.Context>('context')
        if (!ctx) {
          throw new Error('Context not found')
        }
        let cacheDir = ctx.cacheDir + '/downloads'
        if (!fileIo.accessSync(cacheDir)) {
          fileIo.mkdirSync(cacheDir)
        }
        let localPath = cacheDir + '/' + illustId + '_' + pageIndex + '.' + this.getExtension(url)
        let file = fileIo.openSync(localPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
        fileIo.writeSync(file.fd, response.result)
        fileIo.closeSync(file)
        await db.updateDownloadStatus(taskId, 'completed', 100, localPath)
        let savedToGallery = await this.saveToGallery(localPath)
        return savedToGallery
      }
    } catch (e) {
      await db.updateDownloadStatus(taskId, 'failed', 0, '')
      console.error('Download failed: ' + e)
    }
    return false
  }

  async getTasks(): Promise<Array<object>> {
    let db = await getDbService()
    return db.getDownloadTasks()
  }
}

export const downloadService = DownloadService.getInstance()
