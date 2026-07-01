import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { getDbService } from './DatabaseService';
import { Constants } from '../utils/Constants';

export class ImageCacheService {
  private static instance: ImageCacheService
  private cacheDir: string

  private constructor() {
    let ctx = AppStorage.get<common.Context>('context')
    if (!ctx) {
      throw new Error('Context not found')
    }
    this.cacheDir = ctx.getApplicationContext().cacheDir + '/images'
    this.ensureCacheDir()
  }

  static getInstance(): ImageCacheService {
    if (!ImageCacheService.instance) {
      ImageCacheService.instance = new ImageCacheService()
    }
    return ImageCacheService.instance
  }

  private ensureCacheDir(): void {
    try {
      let exists = fileIo.accessSync(this.cacheDir)
      if (!exists) {
        fileIo.mkdirSync(this.cacheDir)
      }
    } catch (e) {
      try {
        fileIo.mkdirSync(this.cacheDir)
      } catch (mkdirErr) {
        console.error('Failed to create cache dir: ' + mkdirErr)
      }
    }
  }

  private fileExists(path: string): boolean {
    try {
      return fileIo.accessSync(path)
    } catch (e) {
      return false
    }
  }

  private getExtension(url: string): string {
    let lowerUrl = url.toLowerCase()
    if (lowerUrl.endsWith('.png')) { return 'png' }
    if (lowerUrl.endsWith('.jpg') || lowerUrl.endsWith('.jpeg')) { return 'jpg' }
    if (lowerUrl.endsWith('.gif')) { return 'gif' }
    return 'jpg'
  }

  private getFileName(url: string): string {
    let hash = 0
    for (let i = 0; i < url.length; i++) {
      let char = url.charCodeAt(i)
      hash = ((hash << 5) - hash) + char
      hash = hash & hash
    }
    return Math.abs(hash).toString() + '.' + this.getExtension(url)
  }

  async getLocalPath(url: string): Promise<string> {
    if (!url) { return '' }
    let proxyUrl = Constants.applyProxy(url)
    let db = await getDbService()
    let cached = await db.getImageCache(url)
    if (cached && this.fileExists(cached)) {
      return cached
    }
    let localPath = this.cacheDir + '/' + this.getFileName(url)
    try {
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
    try {
      let files = fileIo.listFileSync(this.cacheDir)
      for (let file of files) {
        fileIo.unlinkSync(this.cacheDir + '/' + file)
      }
    } catch (e) {
      console.error('Clear cache failed: ' + e)
    }
  }
}

export const imageCacheService = ImageCacheService.getInstance()
