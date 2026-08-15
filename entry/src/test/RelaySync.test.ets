import { describe, it, expect } from '@ohos/hypium';
import { buildRelayImageUrl } from '../main/ets/network/RelayClient';
import { stripSensitiveJson, shouldApplyRemote } from '../main/ets/services/SyncService';
import {
  BookmarkSnapshot,
  bookmarkSnapshotFromIllust,
  bookmarkSnapshotFromJsonString,
  syncPullResultFromJson,
  syncPushResultFromJson,
  recoverResultFromJson,
  parseRelayError,
  SyncItem,
  RECOVER_STATUS_READY,
  RECOVER_STATUS_FETCHING,
  RECOVER_STATUS_NOT_FOUND
} from '../main/ets/models/RelayModels';
import { Illust, ImageUrls, MetaPage } from '../main/ets/models/Illust';

function makeIllust(): Illust {
  let page1 = new MetaPage({ imageUrls: { original: 'https://i.pximg.net/img-original/img/2024/01/01/00/00/00/1_p0.jpg' } })
  let page2 = new MetaPage({ imageUrls: { original: 'https://i.pximg.net/img-original/img/2024/01/01/00/00/00/1_p1.png' } })
  return new Illust({
    id: 12345,
    title: '测试作品',
    pageCount: 2,
    width: 1000,
    height: 2000,
    createDate: '2024-01-01T00:00:00+09:00',
    restrict: 'public',
    imageUrls: new ImageUrls({ large: 'https://i.pximg.net/c/600x1200/img-master/img/2024/01/01/00/00/00/1_p0_master1200.jpg' }),
    metaPages: [page1, page2],
    user: { id: 678, name: '画师甲' },
    tags: [{ name: '女の子', translatedName: '女孩子' }, { name: '原创', translatedName: '' }]
  })
}

export default function relaySyncTest() {
  describe('RelaySyncTest', () => {

    // ---------- relay URL 包装 ----------

    it('build_image_url_wraps_pixiv_url', 0, () => {
      let url = buildRelayImageUrl('https://relay.example.com', 'https://i.pximg.net/a/b_p0.jpg')
      expect(url).assertEqual('https://relay.example.com/img/v1/fetch?url=' +
        encodeURIComponent('https://i.pximg.net/a/b_p0.jpg'))
    })

    it('build_image_url_strips_trailing_slash', 0, () => {
      let url = buildRelayImageUrl('https://relay.example.com/', 'https://i.pximg.net/x.jpg')
      expect(url.indexOf('//img')).assertEqual(-1)
      expect(url.startsWith('https://relay.example.com/img/v1/fetch?url=')).assertTrue()
    })

    // ---------- LWW 合并判定 ----------

    it('lww_remote_newer_wins', 0, () => {
      expect(shouldApplyRemote(1000, 1001)).assertTrue()
      expect(shouldApplyRemote(1000, 1000)).assertFalse()
      expect(shouldApplyRemote(1000, 999)).assertFalse()
      expect(shouldApplyRemote(0, 1)).assertTrue()
    })

    // ---------- 敏感字段递归剔除 ----------

    it('strip_sensitive_removes_token_keys_at_any_depth', 0, () => {
      let input = '{"title":"ok","accessToken":"abc","nested":{"refreshToken":"xyz","keep":1},"arr":[{"TOKEN":"t","v":2}]}'
      let out = stripSensitiveJson(input)
      expect(out.indexOf('accessToken')).assertEqual(-1)
      expect(out.indexOf('refreshToken')).assertEqual(-1)
      expect(out.indexOf('TOKEN')).assertEqual(-1)
      expect(out.indexOf('abc')).assertEqual(-1)
      expect(out.indexOf('xyz')).assertEqual(-1)
      expect(out.indexOf('"title":"ok"') >= 0).assertTrue()
      expect(out.indexOf('"keep":1') >= 0).assertTrue()
      expect(out.indexOf('"v":2') >= 0).assertTrue()
    })

    it('strip_sensitive_invalid_json_passthrough', 0, () => {
      expect(stripSensitiveJson('not-json')).assertEqual('not-json')
      expect(stripSensitiveJson('')).assertEqual('')
    })

    // ---------- 收藏快照序列化 ----------

    it('snapshot_from_illust_has_numeric_id_and_string_urls', 0, () => {
      let snapshot = bookmarkSnapshotFromIllust(makeIllust(), 1700000000000)
      expect(snapshot.illustId).assertEqual(12345)
      expect(snapshot.imageUrls.length).assertEqual(2)
      expect(snapshot.imageUrls[0].endsWith('1_p0.jpg')).assertTrue()
      expect(snapshot.imageUrls[1].endsWith('1_p1.png')).assertTrue()
      expect(snapshot.tags.length).assertEqual(2)
      expect(snapshot.userName).assertEqual('画师甲')
    })

    it('snapshot_json_round_trip', 0, () => {
      let snapshot = bookmarkSnapshotFromIllust(makeIllust(), 1700000000000)
      let json = snapshot.toJsonString()
      let parsed = JSON.parse(json)
      // illustId 必须是数字（服务端校验：非墓碑条目 illustId 必填数字）
      expect(typeof parsed['illustId']).assertEqual('number')
      let restored = bookmarkSnapshotFromJsonString(json)
      expect(restored !== null).assertTrue()
      if (restored !== null) {
        expect(restored.illustId).assertEqual(12345)
        expect(restored.imageUrls.length).assertEqual(2)
        expect(restored.bookmarkedAt).assertEqual(1700000000000)
      }
    })

    it('snapshot_from_empty_json_returns_null', 0, () => {
      expect(bookmarkSnapshotFromJsonString('')).assertNull()
      expect(bookmarkSnapshotFromJsonString('{{{')).assertNull()
    })

    // ---------- 墓碑语义 ----------

    it('sync_item_tombstone_flags', 0, () => {
      let tombstone = new SyncItem({ key: '12345', data: '', updatedAt: 100, deleted: true })
      expect(tombstone.deleted).assertTrue()
      expect(tombstone.data).assertEqual('')
      let alive = new SyncItem({ key: '12345', data: '{}', updatedAt: 200, deleted: false })
      expect(alive.deleted).assertFalse()
      // 墓碑后于活跃条目 → 应应用（删除）；早于则忽略
      expect(shouldApplyRemote(200, 100)).assertFalse()
      expect(shouldApplyRemote(100, 200)).assertTrue()
    })

    // ---------- 同步响应解析 ----------

    it('sync_pull_result_parse_with_has_more', 0, () => {
      let raw = JSON.parse('{"items":[{"key":"1","data":"{}","updatedAt":5,"deleted":false}],"syncToken":"st_1_abcdef","hasMore":true}')
      let result = syncPullResultFromJson(raw)
      expect(result.items.length).assertEqual(1)
      expect(result.items[0].key).assertEqual('1')
      expect(result.syncToken).assertEqual('st_1_abcdef')
      expect(result.hasMore).assertTrue()
    })

    it('sync_push_result_parse', 0, () => {
      let raw = JSON.parse('{"accepted":3,"syncToken":"st_2_000fff"}')
      let result = syncPushResultFromJson(raw)
      expect(result.accepted).assertEqual(3)
      expect(result.syncToken).assertEqual('st_2_000fff')
      expect(result.fullRequired).assertFalse()
    })

    // ---------- 恢复三态映射 ----------

    it('recover_result_status_mapping', 0, () => {
      let ready = recoverResultFromJson(JSON.parse('{"pages":[{"page":0,"url":"https://x/0.jpg","width":100,"height":200}],"source":"saucenao"}'), 200)
      expect(ready.status).assertEqual(RECOVER_STATUS_READY)
      expect(ready.pages.length).assertEqual(1)
      expect(ready.pages[0].url).assertEqual('https://x/0.jpg')

      let fetching = recoverResultFromJson(JSON.parse('{"retryAfterSec":12}'), 202)
      expect(fetching.status).assertEqual(RECOVER_STATUS_FETCHING)
      expect(fetching.retryAfterSec).assertEqual(12)

      let notFound = recoverResultFromJson(JSON.parse('{}'), 404)
      expect(notFound.status).assertEqual(RECOVER_STATUS_NOT_FOUND)
    })

    // ---------- 统一错误体解析 ----------

    it('parse_relay_error_body', 0, () => {
      let info = parseRelayError('{"error":{"code":"INVALID_TOKEN","message":"token expired","requestId":"r1"}}')
      expect(info.code).assertEqual('INVALID_TOKEN')
      expect(info.message).assertEqual('token expired')
      let empty = parseRelayError('')
      expect(empty.code).assertEqual('')
      expect(empty.message).assertEqual('')
      let bad = parseRelayError('not-json')
      expect(bad.message).assertEqual('')
    })
  })
}
