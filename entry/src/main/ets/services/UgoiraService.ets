import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { apiService } from '../network/ApiService';
import { relayClient } from '../network/RelayClient';
import { Constants } from '../utils/Constants';
import { preferenceService } from './PreferenceService';
import {
  RawUgoiraCacheMeta,
  UgoiraCacheMeta,
  ugoiraCacheMetaFromJson,
  ugoiraCacheMetaToJson
} from '../models/UgoiraMetadata';

export interface UgoiraPlayback {
  illustId: number
  framePaths: string[]
  delaysMs: number[]
  width: number
  height: number
}

/**
 * ugoira（动图）服务：metadata 拉取、zip 帧包下载解压、帧缓存管理、GIF 导出编码。
 * 帧解压到 cacheDir/ugoira/<id>/（系统可清理），meta.json 记录帧清单校验缓存；
 * 播放与 GIF 编码共用同一份帧缓存，下载过再看不再重复拉包。
 */
export class UgoiraService {
  private static instance: UgoiraService
  private baseDir: string
  private memoryCache: Map<number, UgoiraPlayback> = new Map<number, UgoiraPlayback>()
  private inflight: Map<number, Promise<UgoiraPlayback | null>> = new Map<number, Promise<UgoiraPlayback | null>>()

  private constructor() {
    let ctx = AppStorage.get<common.Context>('context')
    if (!ctx) {
      throw new Error('Context not found')
    }
    this.baseDir = ctx.cacheDir + '/ugoira'
    try {
      if (!fileIo.accessSync(this.baseDir)) {
        fileIo.mkdirSync(this.baseDir)
      }
    } catch (e) {
      console.error('UgoiraService: create base dir failed: ' + e)
    }
  }

  static getInstance(): UgoiraService {
    if (!UgoiraService.instance) {
      UgoiraService.instance = new UgoiraService()
    }
    return UgoiraService.instance
  }

  private fileExists(path: string): boolean {
    try {
      return fileIo.accessSync(path)
    } catch (e) {
      return false
    }
  }

  private frameDir(illustId: number): string {
    return this.baseDir + '/' + illustId
  }

  /** 获取可播放帧序列；命中缓存直接返回，未命中拉 metadata→下载 zip→解压。失败返回 null（播放端静默回退封面） */
  getPlayback(illustId: number, onProgress?: (ratio: number) => void): Promise<UgoiraPlayback | null> {
    let mem = this.memoryCache.get(illustId)
    if (mem) {
      return Promise.resolve(mem)
    }
    let pending = this.inflight.get(illustId)
    if (pending) {
      return pending
    }
    let task = this.loadFrames(illustId, onProgress)
    this.inflight.set(illustId, task)
    return task.then((result: UgoiraPlayback | null) => {
      this.inflight.delete(illustId)
      if (result) {
        this.memoryCache.set(illustId, result)
      }
      return result
    }).catch((e: Error) => {
      this.inflight.delete(illustId)
      console.error('UgoiraService: loadFrames failed: ' + e)
      return null
    })
  }

  /** 读取已解压帧缓存（meta.json + 帧文件存在性校验），无效返回 null */
  private readCachedPlayback(illustId: number): UgoiraPlayback | null {
    let dir = this.frameDir(illustId)
    let metaPath = dir + '/meta.json'
    if (!this.fileExists(metaPath)) {
      return null
    }
    try {
      let file = fileIo.openSync(metaPath, fileIo.OpenMode.READ_ONLY)
      let stat = fileIo.statSync(metaPath)
      let buf = new ArrayBuffer(stat.size)
      fileIo.readSync(file.fd, buf)
      fileIo.closeSync(file)
      let text = util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buf))
      let meta = ugoiraCacheMetaFromJson(JSON.parse(text) as RawUgoiraCacheMeta)
      if (meta.frameFiles.length === 0 || meta.frameFiles.length !== meta.delaysMs.length) {
        return null
      }
      let paths: string[] = []
      for (let i = 0; i < meta.frameFiles.length; i++) {
        let p = dir + '/' + meta.frameFiles[i]
        if (!this.fileExists(p)) {
          return null
        }
        paths.push(p)
      }
      return {
        illustId: illustId,
        framePaths: paths,
        delaysMs: meta.delaysMs,
        width: meta.width,
        height: meta.height
      }
    } catch (e) {
      console.error('UgoiraService: read cache meta failed: ' + e)
      return null
    }
  }

  private async loadFrames(illustId: number, onProgress?: (ratio: number) => void): Promise<UgoiraPlayback | null> {
    let cached = this.readCachedPlayback(illustId)
    if (cached) {
      return cached
    }
    let metadata = await apiService.getUgoiraMetadata(illustId)
    if (!metadata.zipUrl || metadata.frames.length === 0) {
      return null
    }
    let zipPath = this.baseDir + '/' + illustId + '.zip'
    if (!this.fileExists(zipPath)) {
      let ok = await this.downloadZip(metadata.zipUrl, zipPath, onProgress)
      if (!ok) {
        return null
      }
    }
    let dir = this.frameDir(illustId)
    try {
      if (this.fileExists(dir)) {
        fileIo.rmdirSync(dir)
      }
      fileIo.mkdirSync(dir)
      await zlib.decompressFile(zipPath, dir)
    } catch (e) {
      console.error('UgoiraService: decompress failed: ' + e)
      try {
        fileIo.unlinkSync(zipPath)
      } catch (e2) {
        console.error('UgoiraService: remove bad zip failed: ' + e2)
      }
      return null
    }
    let frameFiles: string[] = []
    let delaysMs: number[] = []
    let framePaths: string[] = []
    for (let i = 0; i < metadata.frames.length; i++) {
      let frame = metadata.frames[i]
      let p = dir + '/' + frame.file
      if (!this.fileExists(p)) {
        console.error('UgoiraService: missing frame ' + frame.file)
        return null
      }
      frameFiles.push(frame.file)
      delaysMs.push(frame.delay)
      framePaths.push(p)
    }
    let width = 0
    let height = 0
    try {
      let source = image.createImageSource(framePaths[0])
      let info = await source.getImageInfo()
      width = info.size.width
      height = info.size.height
      source.release()
    } catch (e) {
      console.error('UgoiraService: read frame info failed: ' + e)
    }
    let meta = new UgoiraCacheMeta({
      zipUrl: metadata.zipUrl,
      frameFiles: frameFiles,
      delaysMs: delaysMs,
      width: width,
      height: height
    })
    try {
      let metaFile = fileIo.openSync(dir + '/meta.json', fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
      fileIo.writeSync(metaFile.fd, ugoiraCacheMetaToJson(meta))
      fileIo.closeSync(metaFile)
    } catch (e) {
      console.error('UgoiraService: write cache meta failed: ' + e)
    }
    try {
      fileIo.unlinkSync(zipPath)
    } catch (e) {
      console.error('UgoiraService: remove zip failed: ' + e)
    }
    return {
      illustId: illustId,
      framePaths: framePaths,
      delaysMs: delaysMs,
      width: width,
      height: height
    }
  }

  /** 下载 zip 帧包（镜像 ImageCacheService 的图床分流：relay / 直连 IP + Host 头 + Referer/UA） */
  private async downloadZip(zipUrl: string, zipPath: string, onProgress?: (ratio: number) => void): Promise<boolean> {
    let apiMode = Constants.normalizeMode(preferenceService.getString('api_mode', Constants.MODE_STANDARD))
    let isRelay = Constants.isRelayMode(apiMode)
    let requestUrl = ''
    let originalHost = ''
    let useDirectIp = false
    if (isRelay) {
      requestUrl = relayClient.buildImageUrl(zipUrl)
    } else {
      let imageHostType = preferenceService.getString('image_host_type', 'default')
      let imageHostCustom = preferenceService.getString('image_host_custom', 'i.pximg.net')
      let hostUrl = Constants.applyImageHost(Constants.applyProxy(zipUrl), imageHostType, imageHostCustom)
      originalHost = Constants.extractHost(hostUrl)
      requestUrl = Constants.applyDirectIp(hostUrl)
      useDirectIp = requestUrl !== hostUrl
    }
    try {
      let httpClient = http.createHttp()
      let headers: Record<string, string> = {}
      if (isRelay) {
        headers = await relayClient.buildImageAuthHeader()
      } else {
        headers['Referer'] = 'https://app-api.pixiv.net/'
        headers['User-Agent'] = Constants.IMAGE_USER_AGENT
        if (useDirectIp && originalHost.length > 0) {
          headers['Host'] = originalHost
        }
      }
      let reqOptions: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 30000,
        readTimeout: 60000,
        header: headers
      }
      if (useDirectIp) {
        reqOptions.remoteValidation = 'skip'
      }
      if (onProgress) {
        httpClient.on('dataReceiveProgress', (data: http.DataReceiveProgressInfo) => {
          if (data.totalSize > 0) {
            onProgress(data.receiveSize / data.totalSize)
          }
        })
      }
      let response = await httpClient.request(requestUrl, reqOptions)
      if (response.responseCode < 200 || response.responseCode >= 300) {
        console.error('UgoiraService: zip download HTTP ' + response.responseCode)
        return false
      }
      if (response.result instanceof ArrayBuffer) {
        let file = fileIo.openSync(zipPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
        fileIo.writeSync(file.fd, response.result)
        fileIo.closeSync(file)
        return true
      }
      return false
    } catch (e) {
      console.error('UgoiraService: zip download failed: ' + e)
      try {
        if (this.fileExists(zipPath)) {
          fileIo.unlinkSync(zipPath)
        }
      } catch (e2) {
        console.error('UgoiraService: cleanup partial zip failed: ' + e2)
      }
      return false
    }
  }

  /**
   * 导出 GIF：取帧（含按需下载解压）→ 逐帧解码 PixelMap → 系统动画编码写 outPath。
   * delayTimeList 单位 10ms 且必须 >0；loopCount=0 无限循环。失败返回 false。
   */
  async encodeToGif(illustId: number, outPath: string, onProgress?: (ratio: number) => void): Promise<boolean> {
    let playback = await this.getPlayback(illustId, (ratio: number) => {
      if (onProgress) {
        onProgress(ratio * 0.7)
      }
    })
    if (!playback || playback.framePaths.length === 0) {
      return false
    }
    let pixelmaps: image.PixelMap[] = []
    try {
      for (let i = 0; i < playback.framePaths.length; i++) {
        let source = image.createImageSource(playback.framePaths[i])
        let opts: image.DecodingOptions = { desiredPixelFormat: image.PixelMapFormat.RGBA_8888 }
        let pixelmap = await source.createPixelMap(opts)
        pixelmaps.push(pixelmap)
        source.release()
        if (onProgress) {
          onProgress(0.7 + 0.25 * (i + 1) / playback.framePaths.length)
        }
      }
      let delayTimeList: number[] = []
      for (let i = 0; i < playback.delaysMs.length; i++) {
        delayTimeList.push(Math.max(1, Math.round(playback.delaysMs[i] / 10)))
      }
      let packOptions: image.PackingOptionsForSequence = {
        frameCount: pixelmaps.length,
        delayTimeList: delayTimeList,
        loopCount: 0
      }
      let packer = image.createImagePacker()
      let file = fileIo.openSync(outPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
      await packer.packToFileFromPixelmapSequence(pixelmaps, file.fd, packOptions)
      fileIo.closeSync(file)
      packer.release()
      if (onProgress) {
        onProgress(1)
      }
      return this.fileExists(outPath)
    } catch (e) {
      console.error('UgoiraService: gif encode failed: ' + e)
      return false
    } finally {
      for (let i = 0; i < pixelmaps.length; i++) {
        try {
          pixelmaps[i].release()
        } catch (e) {
          console.error('UgoiraService: release pixelmap failed: ' + e)
        }
      }
    }
  }
}

export const ugoiraService = UgoiraService.getInstance()
