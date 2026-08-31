import { promptAction } from '@kit.ArkUI';
import { apiService, HttpStatusError } from '../network/ApiService';
import { getDbService } from '../services/DatabaseService';
import { downloadService } from '../services/DownloadService';
import { Illust, Tag } from '../models/Illust';
import { userSettingStore } from './UserSettingStore';
import { bookmarkStateStore, BOOKMARK_LOADING, BOOKMARK_DONE } from './BookmarkStateStore';
import { MuteFilter } from '../utils/MuteFilter';
import { pickDetailUrl } from '../utils/ImageUrlUtils';
import { parseIllustListPage } from '../components/illust/IllustWaterfall';
import { relayClient } from '../network/RelayClient';
import { recoverService, RecoverPollToken, RECOVER_STATUS_CANCELLED } from '../services/RecoverService';
import {
  BookmarkSnapshot,
  bookmarkSnapshotFromJsonString,
  RecoverPage,
  RECOVER_STATUS_READY
} from '../models/RelayModels';
import {
  ExifTag,
  ExifInfo,
  filterTagsForExif,
  isCommentOverLimit
} from '../services/ImageExifService';
import { getStr, getStrf } from '../utils/I18nUtils';

/** 恢复流程状态机 */
export const RECOVER_STATE_IDLE: string = 'idle'
export const RECOVER_STATE_POLLING: string = 'polling'
export const RECOVER_STATE_READY: string = 'ready'
export const RECOVER_STATE_FAILED: string = 'failed'

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
  /** 404 且命中本地收藏快照时非空，页面走快照兜底分支 */
  deletedSnapshot: BookmarkSnapshot | null = null
  /** 恢复状态机：idle / polling / ready / failed */
  recoverState: string = RECOVER_STATE_IDLE
  recoverProgressText: string = ''
  /** 恢复成功后的图片 URL 列表（页面据此跳查看器） */
  recoveredImageUrls: string[] = []
  private recoverToken: RecoverPollToken | null = null
  /** 由宿主页面注入，用于下载重复检测确认弹窗；未注入时降级为直接下载 */
  uiContext: UIContext | undefined = undefined

  async load(illustId: number, forceRefresh: boolean = false): Promise<boolean> {
    this.errorMessage = ''
    this.deletedSnapshot = null
    this.recoverState = RECOVER_STATE_IDLE
    this.recoverProgressText = ''
    this.recoveredImageUrls = []
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
          this.errorMessage = getStr($r('app.string.store_detail_invalid_data'))
        }
        return hasCache
      }
      let parsed = Illust.fromJson(raw)
      if (!parsed.id || !parsed.title) {
        if (!hasCache) {
          this.errorMessage = getStr($r('app.string.store_detail_parse_failed'))
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
      // 404（作品已删除）且无可用缓存：检查本地/同步收藏快照，命中则走兜底态
      if (!hasCache && e instanceof HttpStatusError && e.statusCode === 404) {
        let snapshot = await this.findSnapshot(illustId)
        if (snapshot !== null) {
          this.deletedSnapshot = snapshot
          return false
        }
      }
      if (!hasCache) {
        this.errorMessage = getStrf($r('app.string.common_load_failed_detail'), String(e))
      }
      console.error('Load detail failed: ' + e)
      return hasCache
    }
  }

  /** 查本地收藏快照（deleted=0 的活跃快照才用于兜底展示） */
  private async findSnapshot(illustId: number): Promise<BookmarkSnapshot | null> {
    try {
      let db = await getDbService()
      let row = await db.getBookmarkSnapshot(illustId)
      if (row !== null && row.deleted === 0 && row.data.length > 0) {
        return bookmarkSnapshotFromJsonString(row.data)
      }
    } catch (e) {
      console.error('Find bookmark snapshot failed: ' + e)
    }
    return null
  }

  /** 恢复能力是否可用（已注册中继 + 服务端 capabilities 含 recover） */
  canRecover(): boolean {
    return relayClient.isRegistered() && relayClient.hasCapability('recover')
  }

  /**
   * 尝试从第三方恢复：编排 RecoverService 轮询（retryAfterSec 间隔，≤30 次，可取消）。
   * 成功置 recoverState=ready 并填充 recoveredImageUrls；not_found/超时置 failed + toast；取消回 idle。
   */
  async startRecover(onProgress?: (text: string) => void): Promise<void> {
    let snapshot = this.deletedSnapshot
    if (snapshot === null || this.recoverState === RECOVER_STATE_POLLING) {
      return
    }
    if (!this.canRecover()) {
      this.showToast(getStr($r('app.string.store_recover_unavailable')))
      return
    }
    this.recoverState = RECOVER_STATE_POLLING
    this.recoverProgressText = ''
    let token = new RecoverPollToken()
    this.recoverToken = token
    try {
      let result = await recoverService.pollUntilReady(snapshot.illustId, (attempt: number, retryAfterSec: number) => {
        this.recoverProgressText = getStrf($r('app.string.store_recover_progress'), attempt, retryAfterSec)
        if (onProgress !== undefined) {
          onProgress(this.recoverProgressText)
        }
      }, 30, token)
      if (result.status === RECOVER_STATUS_READY && result.pages.length > 0) {
        this.recoveredImageUrls = result.pages.map((p: RecoverPage) => p.url)
        this.recoverState = RECOVER_STATE_READY
      } else if (result.status === RECOVER_STATUS_CANCELLED) {
        this.recoverState = RECOVER_STATE_IDLE
        this.recoverProgressText = ''
      } else {
        this.recoverState = RECOVER_STATE_FAILED
        this.showToast(getStr($r('app.string.store_recover_not_found')))
      }
    } catch (e) {
      this.recoverState = RECOVER_STATE_FAILED
      this.showToast(getStrf($r('app.string.store_recover_failed'), e instanceof Error ? e.message : String(e)))
    } finally {
      this.recoverToken = null
    }
  }

  /** 取消轮询（页面退出/用户点取消）；恢复出的图片可用来跳查看器 */
  cancelRecover(): void {
    if (this.recoverToken !== null) {
      this.recoverToken.cancel()
      this.recoverToken = null
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

  /** 构建 ExifInfo（供 isExifOverLimit 使用） */
  buildExifInfo(): ExifInfo {
    let tags: ExifTag[] = this.illust.tags.map((t: Tag): ExifTag => {
      return { name: t.name, translatedName: t.translatedName }
    })
    return {
      illustId: this.illust.id,
      userId: this.illust.user.id,
      title: this.illust.title,
      userName: this.illust.user.name,
      tags: tags,
      createDate: this.illust.createDate,
      pageIndex: 0
    }
  }

  /** 检测当前 illust 的 EXIF 备注是否超限（120 UTF-8 字节） */
  isExifOverLimit(): boolean {
    let settings = userSettingStore.getSettings()
    if (!settings.embedExifMetadata) {
      return false
    }
    let filteredTags = filterTagsForExif(this.illust.tags.map((t: Tag): ExifTag => {
      return { name: t.name, translatedName: t.translatedName }
    }), settings)
    let info = this.buildExifInfo()
    return isCommentOverLimit(info, filteredTags)
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
        title: getStr($r('app.string.common_tip')),
        message: getStr($r('app.string.common_img_downloaded')),
        autoCancel: true,
        primaryButton: {
          value: getStr($r('app.string.common_cancel')),
          action: () => {}
        },
        secondaryButton: {
          value: getStr($r('app.string.common_download_anyway')),
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
    downloadService.enqueue(url, this.illust, pageIndex)
    this.showToast(getStr($r('app.string.common_added_download')))
    await this.maybeAutoBookmark()
  }

  /** 保存指定页集合：逐页 isDownloaded 检测，有重复走 AlertDialog（跳过已下载页 / 全部重新下载所选页） */
  async savePages(pageIndexes: number[]): Promise<void> {
    if (pageIndexes.length === 0) {
      return
    }
    let downloadedPages: number[] = []
    for (let i = 0; i < pageIndexes.length; i++) {
      if (await downloadService.isDownloaded(this.illust.id, pageIndexes[i])) {
        downloadedPages.push(pageIndexes[i])
      }
    }
    let ctx = this.uiContext
    if (downloadedPages.length > 0 && ctx !== undefined) {
      let freshPages: number[] = []
      for (let i = 0; i < pageIndexes.length; i++) {
        if (downloadedPages.indexOf(pageIndexes[i]) < 0) {
          freshPages.push(pageIndexes[i])
        }
      }
      ctx.showAlertDialog({
        title: getStr($r('app.string.store_dup_confirm_title')),
        message: getStrf($r('app.string.store_pages_downloaded'), downloadedPages.length),
        autoCancel: true,
        primaryButton: {
          value: getStr($r('app.string.store_skip_downloaded')),
          action: () => { this.doSavePages(freshPages) }
        },
        secondaryButton: {
          value: getStr($r('app.string.store_redownload_all')),
          action: () => { this.doSavePages(pageIndexes) }
        }
      })
      return
    }
    await this.doSavePages(pageIndexes)
  }

  /** 循环入队（fire-and-forget，不再 await 下载结果）；汇总 toast 语义为"已加入 N 个下载任务" */
  private async doSavePages(pageIndexes: number[]): Promise<void> {
    if (pageIndexes.length === 0) {
      this.showToast(getStr($r('app.string.store_no_pages_to_download')))
      return
    }
    let quality = userSettingStore.getSettings().downloadQuality
    for (let i = 0; i < pageIndexes.length; i++) {
      let url = pickDetailUrl(this.illust, pageIndexes[i], quality)
      downloadService.enqueue(url, this.illust, pageIndexes[i])
    }
    this.showToast(getStrf($r('app.string.store_added_downloads'), pageIndexes.length))
    await this.maybeAutoBookmark()
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
      ctx.showAlertDialog({
        title: getStr($r('app.string.store_dup_confirm_title')),
        message: getStrf($r('app.string.store_pages_downloaded'), downloadedPages.length),
        autoCancel: true,
        primaryButton: {
          value: getStr($r('app.string.store_skip_downloaded')),
          action: () => { this.doSaveAll(downloadedPages) }
        },
        secondaryButton: {
          value: getStr($r('app.string.store_redownload_all')),
          action: () => { this.doSaveAll([]) }
        }
      })
      return
    }
    await this.doSaveAll([])
  }

  /** 全量保存重构：复用 doSavePages，skipPages 取补集 */
  private async doSaveAll(skipPages: number[]): Promise<void> {
    let pages: number[] = []
    for (let i = 0; i < this.illust.pageCount; i++) {
      if (skipPages.indexOf(i) < 0) {
        pages.push(i)
      }
    }
    await this.doSavePages(pages)
  }
}
