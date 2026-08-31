import { promptAction } from '@kit.ArkUI';
import { apiService } from '../network/ApiService';
import { getDbService } from '../services/DatabaseService';
import { Illust } from '../models/Illust';
import { getStr } from '../utils/I18nUtils';

/**
 * 收藏状态三态：
 * 0 = 未收藏（空心灰心）
 * 1 = 请求中（实心灰心，防连点）
 * 2 = 已收藏（实心红心）
 */
export const BOOKMARK_NONE: number = 0
export const BOOKMARK_LOADING: number = 1
export const BOOKMARK_DONE: number = 2

/** 收藏变更回调（star/unstar 成功后触发，供 SyncService 生成快照/墓碑，避免反向依赖成环） */
export type BookmarkChangeListener = (illust: Illust, bookmarked: boolean) => void

/**
 * 全局收藏状态注册表（跨页同步收藏状态）。
 * 内存态 Map<illustId, 0|1|2>，每次变更以新 Map 引用写入
 * AppStorage key 'bookmarkStates'，驱动 @StorageLink 绑定的 UI 刷新。
 */
export class BookmarkStateStore {
  private static instance: BookmarkStateStore
  private states: Map<number, number> = new Map<number, number>()
  private bookmarkChangeListeners: BookmarkChangeListener[] = []

  protected constructor() {
    AppStorage.setOrCreate('bookmarkStates', new Map<number, number>())
  }

  static getInstance(): BookmarkStateStore {
    if (!BookmarkStateStore.instance) {
      BookmarkStateStore.instance = new BookmarkStateStore()
    }
    return BookmarkStateStore.instance
  }

  registerBookmarkChangeListener(listener: BookmarkChangeListener): void {
    this.bookmarkChangeListeners.push(listener)
  }

  unregisterBookmarkChangeListener(listener: BookmarkChangeListener): void {
    let idx = this.bookmarkChangeListeners.indexOf(listener)
    if (idx >= 0) {
      this.bookmarkChangeListeners.splice(idx, 1)
    }
  }

  private notifyBookmarkChanged(illust: Illust, bookmarked: boolean): void {
    let snapshot = this.bookmarkChangeListeners.slice()
    for (let i = 0; i < snapshot.length; i++) {
      try {
        snapshot[i](illust, bookmarked)
      } catch (e) {
        console.error('Bookmark change listener failed: ' + e)
      }
    }
  }

  private syncToAppStorage(): void {
    let snapshot: Map<number, number> = new Map<number, number>(this.states)
    AppStorage.setOrCreate('bookmarkStates', snapshot)
  }

  private setState(illustId: number, state: number): void {
    this.states.set(illustId, state)
    this.syncToAppStorage()
  }

  stateOf(illustId: number, fallbackBookmarked: boolean): number {
    let state = this.states.get(illustId)
    if (state !== undefined) {
      return state
    }
    return fallbackBookmarked ? BOOKMARK_DONE : BOOKMARK_NONE
  }

  seedFromList(illusts: Illust[]): void {
    let changed = false
    for (let i = 0; i < illusts.length; i++) {
      let illust = illusts[i]
      if (!this.states.has(illust.id)) {
        this.states.set(illust.id, illust.isBookmarked ? BOOKMARK_DONE : BOOKMARK_NONE)
        changed = true
      }
    }
    if (changed) {
      this.syncToAppStorage()
    }
  }

  protected async requestStar(illustId: number, restrict: string): Promise<void> {
    await apiService.addBookmark(illustId, restrict)
  }

  protected async requestUnstar(illustId: number): Promise<void> {
    await apiService.deleteBookmark(illustId)
  }

  protected showToast(message: string): void {
    try {
      promptAction.showToast({ message: message })
    } catch (e) {
      console.error('Toast failed: ' + e)
    }
  }

  protected async invalidateDetailCache(illustId: number): Promise<void> {
    try {
      let db = await getDbService()
      await db.deleteIllustDetailCache(illustId)
    } catch (e) {
      console.error('Invalidate detail cache failed: ' + e)
    }
  }

  async star(illust: Illust, restrict: string = 'public'): Promise<boolean> {
    if (this.states.get(illust.id) === BOOKMARK_LOADING) {
      return false
    }
    this.setState(illust.id, BOOKMARK_LOADING)
    try {
      await this.requestStar(illust.id, restrict)
      illust.isBookmarked = true
      this.setState(illust.id, BOOKMARK_DONE)
      await this.invalidateDetailCache(illust.id)
      this.showToast(restrict === 'private' ? getStr($r('app.string.store_bookmarked_private')) :
        getStr($r('app.string.store_bookmarked')))
      this.notifyBookmarkChanged(illust, true)
      return true
    } catch (e) {
      console.error('Bookmark failed: ' + e)
      this.setState(illust.id, BOOKMARK_NONE)
      this.showToast(getStr($r('app.string.store_bookmark_failed')))
      return false
    }
  }

  async unstar(illust: Illust): Promise<boolean> {
    if (this.states.get(illust.id) === BOOKMARK_LOADING) {
      return false
    }
    this.setState(illust.id, BOOKMARK_LOADING)
    try {
      await this.requestUnstar(illust.id)
      illust.isBookmarked = false
      this.setState(illust.id, BOOKMARK_NONE)
      await this.invalidateDetailCache(illust.id)
      this.showToast(getStr($r('app.string.store_unbookmarked')))
      this.notifyBookmarkChanged(illust, false)
      return true
    } catch (e) {
      console.error('Unbookmark failed: ' + e)
      this.setState(illust.id, BOOKMARK_DONE)
      this.showToast(getStr($r('app.string.store_unbookmark_failed')))
      return false
    }
  }

  clear(): void {
    this.states.clear()
    this.syncToAppStorage()
  }
}

export const bookmarkStateStore = BookmarkStateStore.getInstance()
