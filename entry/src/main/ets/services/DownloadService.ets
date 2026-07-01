import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
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
        return true
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
