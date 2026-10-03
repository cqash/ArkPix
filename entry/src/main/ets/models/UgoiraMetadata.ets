export interface RawUgoiraFrame {
  file?: string
  delay?: number
}

interface RawUgoiraZipUrls {
  medium?: string
}

interface RawUgoiraMetadata {
  zip_urls?: RawUgoiraZipUrls
  frames?: RawUgoiraFrame[]
}

export interface RawUgoiraMetadataResponse {
  ugoira_metadata?: RawUgoiraMetadata
}

export interface UgoiraFrameOptions {
  file?: string
  delay?: number
}

/** ugoira 单帧：file 为 zip 内文件名（如 000000.jpg），delay 为该帧停留毫秒数 */
export class UgoiraFrame {
  file: string = ''
  delay: number = 0

  constructor(options: UgoiraFrameOptions = {}) {
    this.file = options.file ?? ''
    this.delay = options.delay ?? 0
  }
}

export interface UgoiraMetadataOptions {
  zipUrl?: string
  frames?: UgoiraFrame[]
}

/** /v1/ugoira/metadata 响应：zipUrl 为 600x600 帧包地址，frames 为逐帧延迟表 */
export class UgoiraMetadata {
  zipUrl: string = ''
  frames: UgoiraFrame[] = []

  constructor(options: UgoiraMetadataOptions = {}) {
    this.zipUrl = options.zipUrl ?? ''
    this.frames = options.frames ?? []
  }
}

export function ugoiraMetadataFromJson(raw: RawUgoiraMetadataResponse): UgoiraMetadata {
  let meta = raw.ugoira_metadata
  let frames: UgoiraFrame[] = []
  if (meta?.frames) {
    frames = meta.frames.map((f: RawUgoiraFrame) => new UgoiraFrame({ file: f.file ?? '', delay: f.delay ?? 0 }))
  }
  return new UgoiraMetadata({
    zipUrl: meta?.zip_urls?.medium ?? '',
    frames: frames
  })
}

export interface RawUgoiraCacheMeta {
  zipUrl?: string
  frameFiles?: string[]
  delaysMs?: number[]
  width?: number
  height?: number
}

export interface UgoiraCacheMetaOptions {
  zipUrl?: string
  frameFiles?: string[]
  delaysMs?: number[]
  width?: number
  height?: number
}

/** ugoira 帧解压缓存元信息（meta.json 落盘，校验缓存有效性用） */
export class UgoiraCacheMeta {
  zipUrl: string = ''
  frameFiles: string[] = []
  delaysMs: number[] = []
  width: number = 0
  height: number = 0

  constructor(options: UgoiraCacheMetaOptions = {}) {
    this.zipUrl = options.zipUrl ?? ''
    this.frameFiles = options.frameFiles ?? []
    this.delaysMs = options.delaysMs ?? []
    this.width = options.width ?? 0
    this.height = options.height ?? 0
  }
}

export function ugoiraCacheMetaFromJson(raw: RawUgoiraCacheMeta): UgoiraCacheMeta {
  return new UgoiraCacheMeta({
    zipUrl: raw.zipUrl ?? '',
    frameFiles: raw.frameFiles ?? [],
    delaysMs: raw.delaysMs ?? [],
    width: raw.width ?? 0,
    height: raw.height ?? 0
  })
}

export function ugoiraCacheMetaToJson(meta: UgoiraCacheMeta): string {
  let raw: RawUgoiraCacheMeta = {
    zipUrl: meta.zipUrl,
    frameFiles: meta.frameFiles,
    delaysMs: meta.delaysMs,
    width: meta.width,
    height: meta.height
  }
  return JSON.stringify(raw)
}
