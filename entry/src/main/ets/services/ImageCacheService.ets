import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { getDbService } from './DatabaseService';

export class ImageCacheService {
  private static instance: ImageCacheService
  private cacheDir: string

  private constructor() {
    let ctx = AppStorage.get<common.Context>('context')
    if (!ctx) {
      throw new Error('Context not found')
    }
    this.cacheDir = ctx.getApplicationContext().cacheDir + '/images'
    if (!fileIo.accessSync(this.cacheDir)) {
      fileIo.mkdirSync(this.cacheDir)
    }
  }

  static getInstance(): ImageCacheService {
    if (!ImageCacheService.instance) {
      ImageCacheService.instance = new ImageCacheService()
    }
    return ImageCacheService.instance
  }

  private getFileName(url: string): string {
    let hash = 0
    for (let i = 0; i < url.length; i++) {
      let char = url.charCodeAt(i)
      hash = ((hash << 5) - hash) + char
      hash = hash & hash
    }
    return Math.abs(hash).toString() + '.jpg'
  }

  async getLocalPath(url: string): Promise<string> {
    if (!url) { return '' }
    let db = await getDbService()
    let cached = await db.getImageCache(url)
    if (cached && fileIo.accessSync(cached)) {
      return cached
    }
    let localPath = this.cacheDir + '/' + this.getFileName(url)
    try {
      let httpClient = http.createHttp()
      let response = await new Promise<http.HttpResponse>((resolve, reject) => {
        httpClient.request(url, { method: http.RequestMethod.GET }, (err, data) => {
          if (err) { reject(err) } else { resolve(data) }
        })
      })
      if (response.result instanceof ArrayBuffer) {
        let file = fileIo.openSync(localPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
        fileIo.writeSync(file.fd, response.result)
        fileIo.closeSync(file)
        await db.addImageCache(url, localPath)
        return localPath
      }
    } catch (e) {
      console.error('ImageCache download failed: ' + e)
    }
    return ''
  }

  async clearCache(): Promise<void> {
    let db = await getDbService()
    await db.clearImageCache()
    let files = fileIo.listFileSync(this.cacheDir)
    for (let file of files) {
      fileIo.unlinkSync(this.cacheDir + '/' + file)
    }
  }
}

export const imageCacheService = ImageCacheService.getInstance()
