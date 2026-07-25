import { describe, it, expect } from '@ohos/hypium';
import { BookmarkStateStore, BOOKMARK_NONE, BOOKMARK_DONE } from '../main/ets/stores/BookmarkStateStore';
import { Illust, IllustOptions } from '../main/ets/models/Illust';

/** 可测试子类：网络请求/提示/缓存失效均为可控替身 */
class TestStore extends BookmarkStateStore {
  failNext: boolean = false
  slowMs: number = 0

  constructor() {
    super()
  }

  protected async requestStar(illustId: number, restrict: string): Promise<void> {
    if (this.slowMs > 0) {
      await new Promise<void>((resolve) => {
        setTimeout(() => { resolve() }, this.slowMs)
      })
    }
    if (this.failNext) {
      throw new Error('network down')
    }
  }

  protected async requestUnstar(illustId: number): Promise<void> {
    if (this.failNext) {
      throw new Error('network down')
    }
  }

  protected showToast(message: string): void {
    // 测试环境无 UI，静默
  }

  protected async invalidateDetailCache(illustId: number): Promise<void> {
    // 测试环境无数据库，静默
  }
}

function makeIllust(id: number, bookmarked: boolean): Illust {
  let opts: IllustOptions = { id: id, title: 't' + id, isBookmarked: bookmarked }
  return new Illust(opts)
}

export default function bookmarkStateStoreTest() {
  describe('BookmarkStateStoreTest', () => {
    it('state_of_fallback_to_isBookmarked', 0, () => {
      let store = new TestStore()
      expect(store.stateOf(1, true)).assertEqual(BOOKMARK_DONE)
      expect(store.stateOf(2, false)).assertEqual(BOOKMARK_NONE)
    })

    it('seed_from_list_only_fills_absent', 0, () => {
      let store = new TestStore()
      store.seedFromList([makeIllust(1, true), makeIllust(2, false)])
      expect(store.stateOf(1, false)).assertEqual(BOOKMARK_DONE)
      expect(store.stateOf(2, true)).assertEqual(BOOKMARK_NONE)
    })

    it('star_success_sets_done_and_updates_illust', 0, async () => {
      let store = new TestStore()
      let illust = makeIllust(10, false)
      let ok = await store.star(illust, 'public')
      expect(ok).assertTrue()
      expect(store.stateOf(10, false)).assertEqual(BOOKMARK_DONE)
      expect(illust.isBookmarked).assertTrue()
    })

    it('star_failure_rolls_back_to_none', 0, async () => {
      let store = new TestStore()
      store.failNext = true
      let illust = makeIllust(11, false)
      let ok = await store.star(illust, 'public')
      expect(ok).assertFalse()
      expect(store.stateOf(11, false)).assertEqual(BOOKMARK_NONE)
      expect(illust.isBookmarked).assertFalse()
    })

    it('unstar_success_sets_none', 0, async () => {
      let store = new TestStore()
      let illust = makeIllust(12, true)
      store.seedFromList([illust])
      let ok = await store.unstar(illust)
      expect(ok).assertTrue()
      expect(store.stateOf(12, true)).assertEqual(BOOKMARK_NONE)
      expect(illust.isBookmarked).assertFalse()
    })

    it('unstar_failure_rolls_back_to_done', 0, async () => {
      let store = new TestStore()
      let illust = makeIllust(13, true)
      store.seedFromList([illust])
      store.failNext = true
      let ok = await store.unstar(illust)
      expect(ok).assertFalse()
      expect(store.stateOf(13, false)).assertEqual(BOOKMARK_DONE)
      expect(illust.isBookmarked).assertTrue()
    })

    it('loading_lock_prevents_concurrent_star', 0, async () => {
      let store = new TestStore()
      store.slowMs = 100
      let illust = makeIllust(14, false)
      let first = store.star(illust, 'public')
      let second = await store.star(illust, 'public')
      expect(second).assertFalse()
      let firstResult = await first
      expect(firstResult).assertTrue()
      expect(store.stateOf(14, false)).assertEqual(BOOKMARK_DONE)
    })
  })
}
