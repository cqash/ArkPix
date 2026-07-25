import { ImageUrls, Illust } from '../models/Illust';

/** 列表预览图选档：0=缩略图 1=中图 2=大图 */
export function pickPreviewUrl(urls: ImageUrls, quality: number): string {
  if (quality === 0) {
    return urls.squareMedium || urls.medium || urls.large
  }
  if (quality === 1) {
    return urls.medium || urls.large || urls.original
  }
  return urls.large || urls.medium || urls.original
}

/** 通用画质选档：0=中 1=大 2=原图 */
export function pickUrlByQuality(urls: ImageUrls, quality: number): string {
  if (quality === 0) {
    return urls.medium || urls.large || urls.original
  }
  if (quality === 1) {
    return urls.large || urls.original || urls.medium
  }
  return urls.original || urls.large || urls.medium
}

/** 详情/下载选档：0=大图 1=原图，多 P 按页取 metaPages */
export function pickDetailUrl(illust: Illust, pageIndex: number, quality: number): string {
  let hasMetaPage = illust.pageCount > 1 && pageIndex >= 0 && pageIndex < illust.metaPages.length
  let urls = hasMetaPage ? illust.metaPages[pageIndex].imageUrls : illust.imageUrls
  if (quality === 1) {
    if (hasMetaPage) {
      return urls.original || urls.large || urls.medium
    }
    return illust.metaSinglePage.originalImageUrl || urls.large || urls.original || urls.medium
  }
  return urls.large || urls.medium
}

/** 生成整组页的 URL 列表（供全屏查看器多页浏览） */
export function buildPageUrls(illust: Illust, quality: number): string[] {
  let urls: string[] = []
  for (let i = 0; i < illust.pageCount; i++) {
    urls.push(pickDetailUrl(illust, i, quality))
  }
  return urls
}
