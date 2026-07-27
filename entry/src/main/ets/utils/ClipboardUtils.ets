import { pasteboard } from '@kit.BasicServicesKit';

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
