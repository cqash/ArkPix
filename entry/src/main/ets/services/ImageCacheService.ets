import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { rcp } from '@kit.RemoteCommunicationKit';
import { fileIo } from '@kit.CoreFileKit';
import { getDbService, DatabaseService } from './DatabaseService';
import { Constants } from '../utils/Constants';
import { preferenceService } from './PreferenceService';
import { hoster } from '../network/Hoster';

export class ImageCacheService {
  private static instance: ImageCacheService
  private cacheDir: string
  private oldCacheDir: string = ''
  private migrationPromise: Promise<void> | null = null
  private memoryCache: Map<string, string> = new Map<string, string>()

  private constructor() {
    let ctx = AppStorage.get<common.Context>('context')
    if (!ctx) {
      throw new Error('Context not found')
    }
    this.cacheDir = ctx.filesDir + '/images'
    this.oldCacheDir = ctx.cacheDir + '/images'
    this.ensureCacheDir()
    this.migrationPromise = this.migrateOldCache()
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

  private async migrateOldCache(): Promise<void> {
    if (!fileIo.accessSync(this.oldCacheDir)) {
      return
    }
    try {
      let files = fileIo.listFileSync(this.oldCacheDir)
      for (let file of files) {
        let oldPath = this.oldCacheDir + '/' + file
        let newPath = this.cacheDir + '/' + file
        try {
          fileIo.moveFile(oldPath, newPath)
        } catch (moveErr) {
          console.error('Move cache file failed: ' + moveErr)
        }
      }
      let db = await getDbService()
      await db.updateImageCachePathPrefix(this.oldCacheDir, this.cacheDir)
      try {
        fileIo.rmdirSync(this.oldCacheDir)
      } catch (rmdirErr) {
        console.error('Remove old cache dir failed: ' + rmdirErr)
      }
    } catch (e) {
      console.error('Migrate old cache failed: ' + e)
    }
  }

  private async ensureMigrated(): Promise<void> {
    if (this.migrationPromise) {
      await this.migrationPromise
      this.migrationPromise = null
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
    await this.ensureMigrated()
    let memory = this.memoryCache.get(url)
    if (memory && this.fileExists(memory)) {
      return memory
    }
    let proxyUrl = Constants.applyProxy(url)
    let db = await getDbService()
    let cached = await db.getImageCache(url)
    if (cached && this.fileExists(cached)) {
      this.memoryCache.set(url, cached)
      return cached
    }
    let localPath = this.cacheDir + '/' + this.getFileName(url)

    let networkMode = preferenceService.getString('network_mode', 'direct')
    if (networkMode === 'bypass') {
      return this.getLocalPathBypass(url, localPath, db)
    }

    try {
      let httpClient = http.createHttp()
      let response = await new Promise<http.HttpResponse>((resolve, reject) => {
        httpClient.request(proxyUrl, {
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.ARRAY_BUFFER,
          connectTimeout: 30000,
          readTimeout: 30000,
          header: {
            'Referer': 'https://app-api.pixiv.net/',
            'User-Agent': Constants.IMAGE_USER_AGENT
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
        this.memoryCache.set(url, localPath)
        return localPath
      }
    } catch (e) {
      console.error('ImageCache download failed: ' + e)
    }
    return ''
  }

  private async getLocalPathBypass(url: string, localPath: string, db: DatabaseService): Promise<string> {
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
      request.headers = {
        'Referer': 'https://app-api.pixiv.net/',
        'User-Agent': Constants.IMAGE_USER_AGENT
      }
      let response: rcp.Response = await session.fetch(request)
      if (response.statusCode === 200 && response.body) {
        let file = fileIo.openSync(localPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
        fileIo.writeSync(file.fd, response.body)
        fileIo.closeSync(file)
        await db.addImageCache(url, localPath)
        this.memoryCache.set(url, localPath)
        return localPath
      }
    } catch (e) {
      console.error('ImageCache bypass download failed: ' + e)
    } finally {
      session.close()
    }
    return ''
  }

  async clearCache(): Promise<void> {
    this.memoryCache.clear()
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
