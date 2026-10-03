import { pasteboard } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';

/**
 * 复制纯文本到系统剪贴板。
 * 写入剪贴板无需权限；异常捕获返回 false，由调用方据结果 toast。
 */
export async function copyText(text: string): Promise<boolean> {
  try {
    let data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
    let systemPasteboard = pasteboard.getSystemPasteboard()
    await systemPasteboard.setData(data)
    return true
  } catch (e) {
    console.error('Copy to clipboard failed: ' + e)
    return false
  }
}

/**
 * 复制本地图片文件到系统剪贴板（PixelMap 通道）。
 * 写入剪贴板无需权限；任一步失败（解码/写剪贴板）捕获返回 false，由调用方回退复制链接。
 */
export async function copyImage(filePath: string): Promise<boolean> {
  let pixelMap: image.PixelMap | undefined = undefined
  try {
    let source = image.createImageSource(filePath)
    pixelMap = await source.createPixelMap()
    let data = pasteboard.createData(pasteboard.MIMETYPE_PIXELMAP, pixelMap)
    let systemPasteboard = pasteboard.getSystemPasteboard()
    await systemPasteboard.setData(data)
    return true
  } catch (e) {
    console.error('Copy image to clipboard failed: ' + e)
    return false
  } finally {
    if (pixelMap !== undefined) {
      try {
        pixelMap.release()
      } catch (e) {
        console.error('Release pixelmap failed: ' + e)
      }
    }
  }
}

/**
 * 读取系统剪贴板纯文本。
 * 读取剪贴板受权限管控：普通读取需 READ_PASTEBOARD（受限场景才可申请），
 * 请在 PasteButton 安全控件点击后的临时授权窗口内调用；窗口外/无权限时捕获异常返回 ''。
 */
export async function pasteText(): Promise<string> {
  try {
    let systemPasteboard = pasteboard.getSystemPasteboard()
    let data = await systemPasteboard.getData()
    let text = data.getPrimaryText()
    return text ?? ''
  } catch (e) {
    console.error('Paste from clipboard failed: ' + e)
    return ''
  }
}
