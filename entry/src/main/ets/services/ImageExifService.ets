import image from '@ohos.multimedia.image';
import { fileIo } from '@kit.CoreFileKit';

export interface ExifTag {
  name: string
  translatedName: string
}

export interface ExifInfo {
  illustId: number
  userId: number
  title: string
  userName: string
  tags: ExifTag[]
  createDate: string
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
      let desc = `Pixiv ID: ${info.illustId} | User ID: ${info.userId} | ${info.title}`
      await source.modifyImageProperty(image.PropertyKey.IMAGE_DESCRIPTION, desc)
      await source.modifyImageProperty(image.PropertyKey.ARTIST, `${info.userName} (ID: ${info.userId})`)
      let tagStr = formatTags(info.tags)
      await source.modifyImageProperty(image.PropertyKey.USER_COMMENT, `Pixiv ID: ${info.illustId} | Tags: ${tagStr}`)
      await source.modifyImageProperty(image.PropertyKey.COPYRIGHT, 'Pixiv')
      packer = image.createImagePacker()
      let options: image.PackingOption = { format: 'image/jpeg', quality: 95, needsPackProperties: true }
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
