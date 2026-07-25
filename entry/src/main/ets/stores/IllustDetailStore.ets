import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { apiService } from '../network/ApiService';
import { getDbService } from '../services/DatabaseService';
import { downloadService } from '../services/DownloadService';
import { Illust } from '../models/Illust';
import { userSettingStore } from './UserSettingStore';
import { bookmarkStateStore, BOOKMARK_LOADING, BOOKMARK_DONE } from './BookmarkStateStore';
import { MuteFilter } from '../utils/MuteFilter';
import { pickDetailUrl } from '../utils/ImageUrlUtils';
import { parseIllustListPage } from '../components/illust/IllustWaterfall';

/** 详情页行模型：image 行×pageCount + info 行 + related_header/related 行 */
export interface DetailRow {
  kind: string
  pageIndex: number
  imageUrl: string
  ratio: number
  related: Illust[]
}

interface IllustDetailResponse {
  illust: Object
}

function makeRow(kind: string, pageIndex: number, imageUrl: string, ratio: number, related: Illust[]): DetailRow {
  let row: DetailRow = { kind: kind, pageIndex: pageIndex, imageUrl: imageUrl, ratio: ratio, related: related }
  return row
}

/**
 * 详情页数据编排：详情加载（缓存→网络→注册表播种→浏览历史）、
 * 行模型组装、相关推荐分页、保存/收藏操作。
 */
export class IllustDetailStore {
  illust: Illust = new Illust()
  relatedIllusts: Illust[] = []
  relatedNextUrl: string = ''
  relatedLoading: boolean = false
  errorMessage: string = ''
  /** 由宿主页面注入，用于下载重复检测确认弹窗；未注入时降级为直接下载 */
  uiContext: UIContext | undefined = undefined

  async load(illustId: number, forceRefresh: boolean = false): Promise<boolean> {
    this.errorMessage = ''
    let db = await getDbService()
    let hasCache = false
    try {
      let cached = await db.getIllustDetailCache(illustId)
      if (cached && !forceRefresh) {
        let rawCached = (JSON.parse(cached) as IllustDetailResponse).illust
        if (rawCached) {
          let illust = Illust.fromJson(rawCached)
          // 缓存可能陈旧：收藏状态以注册表为准
          bookmarkStateStore.seedFromList([illust])
          illust.isBookmarked = bookmarkStateStore.stateOf(illust.id, illust.isBookmarked) === BOOKMARK_DONE
          this.illust = illust
          hasCache = true
        }
      }
    } catch (e) {
      console.error('Load illust detail cache failed: ' + e)
    }
    try {
      let response = await apiService.getIllustDetail(illustId)
      let raw = (response as IllustDetailResponse).illust
      if (!raw) {
        if (!hasCache) {
          this.errorMessage = '返回数据无效，请重试'
        }
        return hasCache
      }
      let parsed = Illust.fromJson(raw)
      if (!parsed.id || !parsed.title) {
        if (!hasCache) {
          this.errorMessage = '作品数据解析失败'
        }
        return hasCache
      }
      // 网络结果播种注册表，收藏状态以注册表为准
      bookmarkStateStore.seedFromList([parsed])
      parsed.isBookmarked = bookmarkStateStore.stateOf(parsed.id, parsed.isBookmarked) === BOOKMARK_DONE
      this.illust = parsed
      await db.setIllustDetailCache(illustId, JSON.stringify(response as object))
      // 写浏览历史
      try {
        await db.addHistory(parsed.id, parsed.title, parsed.imageUrls.medium, parsed.user.name)
      } catch (e) {
        console.error('Add history failed: ' + e)
      }
      return true
    } catch (e) {
      if (!hasCache) {
        this.errorMessage = '加载失败: ' + e
      }
      console.error('Load detail failed: ' + e)
      return hasCache
    }
  }

  private imageRatio(pageIndex: number): number {
    let illust = this.illust
    if (illust.width > 0 && illust.height > 0) {
      return illust.width / illust.height
    }
    return 0.75
  }

  buildRows(detailQuality: number): DetailRow[] {
    let rows: DetailRow[] = []
    let illust = this.illust
    if (illust.id === 0) {
      return rows
    }
    for (let i = 0; i < illust.pageCount; i++) {
      rows.push(makeRow('image', i, pickDetailUrl(illust, i, detailQuality), this.imageRatio(i), []))
    }
    rows.push(makeRow('info', 0, '', 1, []))
    if (this.relatedIllusts.length > 0) {
      rows.push(makeRow('related_header', 0, '', 1, []))
      for (let j = 0; j < this.relatedIllusts.length; j += 3) {
        rows.push(makeRow('related', j, '', 1, this.relatedIllusts.slice(j, j + 3)))
      }
    }
    return rows
  }

  async loadRelated(): Promise<void> {
    if (this.illust.id === 0 || this.relatedLoading) {
      return
    }
    this.relatedLoading = true
    try {
      let response = await apiService.getRelatedIllusts(this.illust.id)
      let page = parseIllustListPage(response)
      bookmarkStateStore.seedFromList(page.illusts)
      let settings = userSettingStore.getSettings()
      this.relatedIllusts = page.illusts.filter((item: Illust) => !MuteFilter.isMuted(item, settings))
      this.relatedNextUrl = page.nextUrl
    } catch (e) {
      console.error('Load related illusts failed: ' + e)
    } finally {
      this.relatedLoading = false
    }
  }

  async loadMoreRelated(): Promise<void> {
    if (this.relatedLoading || this.relatedNextUrl.length === 0) {
      return
    }
    this.relatedLoading = true
    try {
      let response = await apiService.fetchNext(this.relatedNextUrl)
      let page = parseIllustListPage(response)
      bookmarkStateStore.seedFromList(page.illusts)
      let settings = userSettingStore.getSettings()
      let fresh = page.illusts.filter((item: Illust) => {
        if (MuteFilter.isMuted(item, settings)) {
          return false
        }
        return this.relatedIllusts.findIndex((exist: Illust) => exist.id === item.id) < 0
      })
      this.relatedIllusts = this.relatedIllusts.concat(fresh)
      this.relatedNextUrl = page.nextUrl
    } catch (e) {
      console.error('Load more related illusts failed: ' + e)
    } finally {
      this.relatedLoading = false
    }
  }

  async toggleBookmark(): Promise<void> {
    let state = bookmarkStateStore.stateOf(this.illust.id, this.illust.isBookmarked)
    if (state === BOOKMARK_LOADING) {
      return
    }
    if (state === BOOKMARK_DONE) {
      await bookmarkStateStore.unstar(this.illust)
    } else {
      await bookmarkStateStore.star(this.illust, 'public')
    }
  }

  async starWithRestrict(restrict: string): Promise<void> {
    let state = bookmarkStateStore.stateOf(this.illust.id, this.illust.isBookmarked)
    if (state !== 0) {
      return
    }
    await bookmarkStateStore.star(this.illust, restrict)
  }

  private showToast(message: string): void {
    try {
      promptAction.showToast({ message: message })
    } catch (e) {
      console.error('Toast failed: ' + e)
    }
  }

  private async maybeAutoBookmark(): Promise<void> {
    if (userSettingStore.getSettings().autoBookmarkOnDownload &&
      bookmarkStateStore.stateOf(this.illust.id, this.illust.isBookmarked) !== BOOKMARK_DONE) {
      await bookmarkStateStore.star(this.illust, 'public')
    }
  }

  async savePage(pageIndex: number): Promise<void> {
    let downloaded = await downloadService.isDownloaded(this.illust.id, pageIndex)
    let ctx = this.uiContext
    if (downloaded && ctx !== undefined) {
      ctx.showAlertDialog({
        title: '提示',
        message: '该图片已下载过',
        autoCancel: true,
        primaryButton: {
          value: '取消',
          action: () => {}
        },
        secondaryButton: {
          value: '仍要下载',
          action: () => { this.doSavePage(pageIndex) }
        }
      })
      return
    }
    await this.doSavePage(pageIndex)
  }

  private async doSavePage(pageIndex: number): Promise<void> {
    let quality = userSettingStore.getSettings().downloadQuality
    let url = pickDetailUrl(this.illust, pageIndex, quality)
    let localPath = await downloadService.downloadToCache(url, this.illust, pageIndex)
    if (!localPath) {
      this.showToast('下载失败')
      return
    }
    let ctx = AppStorage.get<common.Context>('context')
    if (!ctx) {
      this.showToast('保存失败')
      return
    }
    let saved = await downloadService.applyToGallery(localPath, ctx)
    if (saved) {
      this.showToast('已保存到图库')
      await this.maybeAutoBookmark()
    } else {
      this.showToast('保存失败')
    }
  }

  async saveAll(): Promise<void> {
    if (this.illust.pageCount <= 0) {
      return
    }
    let downloadedPages: number[] = []
    for (let i = 0; i < this.illust.pageCount; i++) {
      if (await downloadService.isDownloaded(this.illust.id, i)) {
        downloadedPages.push(i)
      }
    }
    let ctx = this.uiContext
    if (downloadedPages.length > 0 && ctx !== undefined) {
      ctx.showActionSheet({
        title: '重复下载确认',
        message: '其中 ' + downloadedPages.length + ' 页已下载过',
        sheets: [
          {
            title: '跳过已下载页',
            action: () => { this.doSaveAll(downloadedPages) }
          },
          {
            title: '全部重新下载',
            action: () => { this.doSaveAll([]) }
          }
        ],
        confirm: {
          value: '取消',
          action: () => {}
        }
      })
      return
    }
    await this.doSaveAll([])
  }

  private async doSaveAll(skipPages: number[]): Promise<void> {
    let quality = userSettingStore.getSettings().downloadQuality
    let ctx = AppStorage.get<common.Context>('context')
    if (!ctx) {
      this.showToast('保存失败')
      return
    }
    let successCount = 0
    let failCount = 0
    let skipCount = 0
    for (let i = 0; i < this.illust.pageCount; i++) {
      if (skipPages.indexOf(i) >= 0) {
        skipCount++
        continue
      }
      let url = pickDetailUrl(this.illust, i, quality)
      let localPath = await downloadService.downloadToCache(url, this.illust, i)
      if (!localPath) {
        failCount++
        continue
      }
      let saved = await downloadService.applyToGallery(localPath, ctx)
      if (saved) {
        successCount++
      } else {
        failCount++
      }
    }
    let summary = '完成: 成功' + successCount + ', 失败' + failCount
    if (skipCount > 0) {
      summary += ', 跳过' + skipCount
    }
    this.showToast(summary)
    if (successCount > 0) {
      await this.maybeAutoBookmark()
    }
  }
}
