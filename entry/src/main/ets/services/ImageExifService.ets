import image from '@ohos.multimedia.image';
import { fileIo } from '@kit.CoreFileKit';

export interface ExifTag {
  name: string
  translatedName: string
}

export interface ExifInfo {
  title: string
  userName: string
  tags: ExifTag[]
  createDate: string
}

function padTwo(n: number): string {
  return n.toString().padStart(2, '0')
}

function formatExifDateTime(isoDate: string): string {
  let date = new Date(isoDate)
  if (isNaN(date.getTime())) {
    return ''
  }
  return `${date.getFullYear()}:${padTwo(date.getMonth() + 1)}:${padTwo(date.getDate())} ${padTwo(date.getHours())}:${padTwo(date.getMinutes())}:${padTwo(date.getSeconds())}`
}

function formatTags(tags: ExifTag[]): string {
  return tags.map((t: ExifTag) => {
    if (t.translatedName && t.translatedName !== t.name) {
      return `${t.name} (${t.translatedName})`
    }
    return t.name
  }).join(', ')
}

export class ImageExifService {
  private static instance: ImageExifService

  private constructor() {}

  static getInstance(): ImageExifService {
    if (!ImageExifService.instance) {
      ImageExifService.instance = new ImageExifService()
    }
    return ImageExifService.instance
  }

  async embedExif(srcPath: string, dstPath: string, info: ExifInfo): Promise<void> {
    let source: image.ImageSource | undefined = undefined
    let packer: image.ImagePacker | undefined = undefined
    let file: fileIo.File | undefined = undefined
    try {
      source = image.createImageSource(srcPath)
      await source.modifyImageProperty(image.PropertyKey.USER_COMMENT, formatTags(info.tags))
      if (info.title) {
        await source.modifyImageProperty(image.PropertyKey.IMAGE_DESCRIPTION, info.title)
      }
      await source.modifyImageProperty(image.PropertyKey.ARTIST, info.userName)
      await source.modifyImageProperty(image.PropertyKey.COPYRIGHT, 'Pixiv')
      let dateTime = formatExifDateTime(info.createDate)
      if (dateTime) {
        await source.modifyImageProperty(image.PropertyKey.DATE_TIME_ORIGINAL, dateTime)
      }
      packer = image.createImagePacker()
      let options: image.PackingOption = { format: 'image/jpeg', quality: 95 }
      let data: ArrayBuffer = await packer.packToData(source, options)
      file = fileIo.openSync(dstPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
      fileIo.writeSync(file.fd, data)
      fileIo.closeSync(file)
      file = undefined
    } catch (e) {
      throw new Error('Embed EXIF failed: ' + e)
    } finally {
      if (file) {
        try {
          fileIo.closeSync(file.fd)
        } catch (e) {
          console.error('Close EXIF output file failed: ' + e)
        }
      }
      if (packer) {
        try {
          await packer.release()
        } catch (e) {
          console.error('Release packer failed: ' + e)
        }
      }
      if (source) {
        try {
          await source.release()
        } catch (e) {
          console.error('Release image source failed: ' + e)
        }
      }
    }
  }
}

export const imageExifService = ImageExifService.getInstance()
