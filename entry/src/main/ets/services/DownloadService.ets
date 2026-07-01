import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { getDbService } from './DatabaseService';

export class DownloadService {
  private static instance: DownloadService

  private constructor() {}

  static getInstance(): DownloadService {
    if (!DownloadService.instance) {
      DownloadService.instance = new DownloadService()
    }
    return DownloadService.instance
  }

  async downloadImage(url: string, illustId: number, pageIndex: number): Promise<boolean> {
    let taskId = illustId + '_' + pageIndex
    let db = await getDbService()
    await db.addDownloadTask(taskId, illustId, pageIndex, url)

    try {
      await db.updateDownloadStatus(taskId, 'downloading', 0, '')
      let httpClient = http.createHttp()
      let response = await new Promise<http.HttpResponse>((resolve, reject) => {
        httpClient.request(url, { method: http.RequestMethod.GET }, (err, data) => {
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
        let localPath = cacheDir + '/' + illustId + '_' + pageIndex + '.jpg'
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
