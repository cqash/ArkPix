/**
 * 作品简介（caption）HTML → 分段渲染纯函数（无副作用，可单测）。
 * Pixiv 简介为受限 HTML：`<a href="...">text</a>` 链接、`<br>` 换行、少量 HTML 实体。
 * 解析为 CaptionSegment 序列：href 非空 = 链接段（应用内跳转或开浏览器），否则普通文本段。
 * 畸形输入兜底：整体按纯文本单段输出（剥离标签 + 实体解码）。
 */

export interface CaptionSegment {
  text: string
  href: string
}

/** 基础 HTML 实体解码（&amp; 必须最先解码，避免二次展开） */
function decodeEntities(text: string): string {
  let out = text.replace(new RegExp('&amp;', 'g'), '&')
  out = out.replace(new RegExp('&lt;', 'g'), '<')
  out = out.replace(new RegExp('&gt;', 'g'), '>')
  out = out.replace(new RegExp('&quot;', 'g'), '"')
  out = out.replace(new RegExp('&#39;', 'g'), "'")
  return out
}

/** 纯文本片段规整：<br> 系列 → \n，其余标签剥离，实体解码 */
function normalizePlain(fragment: string): string {
  let out = fragment.replace(new RegExp('<br\\s*/?>', 'gi'), '\n')
  out = out.replace(new RegExp('<[^>]*>', 'g'), '')
  return decodeEntities(out)
}

function pushPlainSegment(segments: CaptionSegment[], fragment: string): void {
  let text = normalizePlain(fragment)
  if (text.trim().length === 0) {
    return
  }
  let seg: CaptionSegment = { text: text, href: '' }
  segments.push(seg)
}

/**
 * 解析简介 HTML 为分段序列。
 * 空输入/全空白返回空数组（调用方据此不渲染简介行）；
 * 空白间隔段被丢弃，链接段保留原始文本与 href（href 亦做实体解码）。
 */
export function parseCaptionHtml(html: string): CaptionSegment[] {
  let segments: CaptionSegment[] = []
  if (!html || html.trim().length === 0) {
    return segments
  }
  try {
    let anchorRe = new RegExp("<a\\b[^>]*href\\s*=\\s*[\"']([^\"']*)[\"'][^>]*>([\\s\\S]*?)</a>", 'gi')
    let lastIndex = 0
    let match = anchorRe.exec(html)
    while (match !== null) {
      if (match.index > lastIndex) {
        pushPlainSegment(segments, html.substring(lastIndex, match.index))
      }
      let href = match.length > 1 ? decodeEntities(match[1] ?? '').trim() : ''
      let inner = match.length > 2 ? normalizePlain(match[2] ?? '') : ''
      if (inner.trim().length > 0) {
        let seg: CaptionSegment = { text: inner, href: href }
        segments.push(seg)
      }
      lastIndex = match.index + match[0].length
      match = anchorRe.exec(html)
    }
    if (lastIndex < html.length) {
      pushPlainSegment(segments, html.substring(lastIndex))
    }
    return segments
  } catch (e) {
    console.error('Parse caption html failed: ' + e)
    // 畸形输入兜底：纯文本单段
    let text = normalizePlain(html)
    if (text.trim().length > 0) {
      let fallback: CaptionSegment = { text: text, href: '' }
      segments.push(fallback)
    }
    return segments
  }
}

/** 简介纯文本输出（复制文案用）：分段文本直接拼接 */
export function captionToPlainText(html: string): string {
  let segments = parseCaptionHtml(html)
  return segments.map((seg: CaptionSegment): string => seg.text).join('')
}
