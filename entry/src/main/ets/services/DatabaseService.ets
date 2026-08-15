import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

export interface HistoryItem {
  id: number
  illust_id: number
  title: string
  image_url: string
  user_name: string
  timestamp: number
}

export interface SearchHistoryItem {
  id: number
  keyword: string
  search_type: string
  timestamp: number
}

export interface MuteItem {
  id: number
  type: string
  value: string
  user_id: number
  timestamp: number
}

export interface DownloadTaskItem {
  id: string
  illust_id: number
  page_index: number
  image_url: string
  local_path: string
  status: string
  progress: number
  timestamp: number
}

/** 收藏快照行（data 为 BookmarkSnapshot JSON 串；deleted=1 为墓碑） */
export interface BookmarkSnapshotItem {
  illust_id: number
  data: string
  updated_at: number
  deleted: number
}

export class DatabaseService {
  private static instance: DatabaseService
  private db: relationalStore.RdbStore

  private constructor(db: relationalStore.RdbStore) {
    this.db = db
  }

  static async getInstance(): Promise<DatabaseService> {
    if (!DatabaseService.instance) {
      let ctx = AppStorage.get<common.Context>('context')
      if (!ctx) {
        throw new Error('UIAbilityContext not found in AppStorage')
      }
      let db = await relationalStore.getRdbStore(ctx.getApplicationContext(), {
        name: 'pixiv.db',
        securityLevel: relationalStore.SecurityLevel.S1
      })
      await db.execute('CREATE TABLE IF NOT EXISTS history (id INTEGER PRIMARY KEY, illust_id INTEGER, title TEXT, image_url TEXT, user_name TEXT, timestamp INTEGER)')
      await db.execute('CREATE TABLE IF NOT EXISTS bookmarks (id INTEGER PRIMARY KEY, work_id INTEGER, work_type TEXT, tags TEXT, restrict TEXT, create_date TEXT)')
      await db.execute('CREATE TABLE IF NOT EXISTS mutes (id INTEGER PRIMARY KEY, type TEXT, value TEXT, user_id INTEGER, timestamp INTEGER)')
      await db.execute('CREATE TABLE IF NOT EXISTS search_history (id INTEGER PRIMARY KEY, keyword TEXT, search_type TEXT, timestamp INTEGER)')
      await db.execute('CREATE TABLE IF NOT EXISTS download_tasks (id TEXT PRIMARY KEY, illust_id INTEGER, page_index INTEGER, image_url TEXT, local_path TEXT, status TEXT, progress INTEGER, timestamp INTEGER)')
      await db.execute('CREATE TABLE IF NOT EXISTS image_cache (id INTEGER PRIMARY KEY, url TEXT, local_path TEXT, timestamp INTEGER)')
      await db.execute('CREATE TABLE IF NOT EXISTS recommend_cache (id INTEGER PRIMARY KEY, data TEXT, timestamp INTEGER)')
      await db.execute('CREATE TABLE IF NOT EXISTS ranking_cache (id INTEGER PRIMARY KEY, mode TEXT, date TEXT, data TEXT, timestamp INTEGER)')
      await db.execute('CREATE TABLE IF NOT EXISTS illust_detail_cache (id INTEGER PRIMARY KEY, illust_id INTEGER, data TEXT, timestamp INTEGER)')
      await db.execute('CREATE TABLE IF NOT EXISTS bookmark_snapshots (illust_id INTEGER PRIMARY KEY, data TEXT, updated_at INTEGER, deleted INTEGER DEFAULT 0)')
      DatabaseService.instance = new DatabaseService(db)
      // 应用重启后，残留的 downloading/pending 任务不可能继续，重置为 failed
      await db.execute('UPDATE download_tasks SET status = ?, progress = ? WHERE status = ? OR status = ?',
        ['failed', 0, 'downloading', 'pending'])
    }
    return DatabaseService.instance
  }

  /** 按 illust_id 去重：history 表 illust_id 无 UNIQUE 约束，INSERT OR REPLACE 不去重，先删后插 */
  async addHistory(illustId: number, title: string, imageUrl: string, userName: string): Promise<void> {
    await this.db.execute('DELETE FROM history WHERE illust_id = ?', [illustId])
    await this.db.execute('INSERT INTO history (illust_id, title, image_url, user_name, timestamp) VALUES (?, ?, ?, ?, ?)',
      [illustId, title, imageUrl, userName, Date.now()])
    notifySyncWrite('history')
  }

  async getHistory(limit: number = 500): Promise<HistoryItem[]> {
    // 按 illust_id 合并：同一作品仅取最新一条（MAX(id) 分组在同毫秒 timestamp 下仍唯一），不动存量数据
    let resultSet = await this.db.querySql(
      'SELECT * FROM history WHERE id IN (SELECT MAX(id) FROM history GROUP BY illust_id) ORDER BY timestamp DESC LIMIT ?',
      [limit])
    let results: HistoryItem[] = []
    while (resultSet.goToNextRow()) {
      let item: HistoryItem = {
        id: Number(resultSet.getValue(resultSet.getColumnIndex('id'))),
        illust_id: Number(resultSet.getValue(resultSet.getColumnIndex('illust_id'))),
        title: String(resultSet.getValue(resultSet.getColumnIndex('title'))),
        image_url: String(resultSet.getValue(resultSet.getColumnIndex('image_url'))),
        user_name: String(resultSet.getValue(resultSet.getColumnIndex('user_name'))),
        timestamp: Number(resultSet.getValue(resultSet.getColumnIndex('timestamp')))
      }
      results.push(item)
    }
    resultSet.close()
    return results
  }

  async clearHistory(): Promise<void> {
    // 清空前收集全部 key 作为同步墓碑（删除传播到其他设备）
    let tombstoneKeys: string[] = []
    let resultSet = await this.db.querySql('SELECT DISTINCT illust_id FROM history')
    while (resultSet.goToNextRow()) {
      tombstoneKeys.push(Number(resultSet.getValue(resultSet.getColumnIndex('illust_id'))).toString())
    }
    resultSet.close()
    await this.db.execute('DELETE FROM history')
    notifySyncWrite('history', tombstoneKeys)
  }

  // ---------------- 同步 applier 辅助（history） ----------------

  /** 指定作品的本地历史时间戳（无记录返回 0），供 viewed_at LWW 比较 */
  async getHistoryTimestamp(illustId: number): Promise<number> {
    let resultSet = await this.db.querySql('SELECT MAX(timestamp) AS ts FROM history WHERE illust_id = ?', [illustId])
    let ts = 0
    if (resultSet.goToNextRow()) {
      let val = resultSet.getValue(resultSet.getColumnIndex('ts'))
      if (val !== null) {
        ts = Number(val)
      }
    }
    resultSet.close()
    return ts
  }

  /** 同步下行写入：携带远端时间戳（先删后插，与 addHistory 去重语义一致） */
  async upsertHistory(illustId: number, title: string, imageUrl: string, userName: string, timestamp: number): Promise<void> {
    await this.db.execute('DELETE FROM history WHERE illust_id = ?', [illustId])
    await this.db.execute('INSERT INTO history (illust_id, title, image_url, user_name, timestamp) VALUES (?, ?, ?, ?, ?)',
      [illustId, title, imageUrl, userName, timestamp])
  }

  async deleteHistory(illustId: number): Promise<void> {
    await this.db.execute('DELETE FROM history WHERE illust_id = ?', [illustId])
  }

  /** 按 keyword+search_type 去重：search_history 表无 UNIQUE 约束，INSERT OR REPLACE 不去重，先删后插 */
  async addSearchHistory(keyword: string, searchType: string): Promise<void> {
    await this.db.execute('DELETE FROM search_history WHERE keyword = ? AND search_type = ?', [keyword, searchType])
    await this.db.execute('INSERT INTO search_history (keyword, search_type, timestamp) VALUES (?, ?, ?)',
      [keyword, searchType, Date.now()])
    notifySyncWrite('search_history')
  }

  async getSearchHistory(limit: number = 50): Promise<SearchHistoryItem[]> {
    let resultSet = await this.db.querySql('SELECT * FROM search_history ORDER BY timestamp DESC LIMIT ?', [limit])
    let results: SearchHistoryItem[] = []
    while (resultSet.goToNextRow()) {
      let item: SearchHistoryItem = {
        id: Number(resultSet.getValue(resultSet.getColumnIndex('id'))),
        keyword: String(resultSet.getValue(resultSet.getColumnIndex('keyword'))),
        search_type: String(resultSet.getValue(resultSet.getColumnIndex('search_type'))),
        timestamp: Number(resultSet.getValue(resultSet.getColumnIndex('timestamp')))
      }
      results.push(item)
    }
    resultSet.close()
    return results
  }

  async clearSearchHistory(): Promise<void> {
    // 清空前收集全部 key（search_type:keyword，与同步 collector 的 key 格式一致）作为墓碑
    let tombstoneKeys: string[] = []
    let resultSet = await this.db.querySql('SELECT DISTINCT keyword, search_type FROM search_history')
    while (resultSet.goToNextRow()) {
      let keyword = String(resultSet.getValue(resultSet.getColumnIndex('keyword')))
      let searchType = String(resultSet.getValue(resultSet.getColumnIndex('search_type')))
      tombstoneKeys.push(searchType + ':' + keyword)
    }
    resultSet.close()
    await this.db.execute('DELETE FROM search_history')
    notifySyncWrite('search_history', tombstoneKeys)
  }

  // ---------------- 同步 applier 辅助（search_history） ----------------

  /** 指定 keyword+search_type 的本地时间戳（无记录返回 0），供 LWW 比较 */
  async getSearchHistoryTimestamp(keyword: string, searchType: string): Promise<number> {
    let resultSet = await this.db.querySql(
      'SELECT MAX(timestamp) AS ts FROM search_history WHERE keyword = ? AND search_type = ?', [keyword, searchType])
    let ts = 0
    if (resultSet.goToNextRow()) {
      let val = resultSet.getValue(resultSet.getColumnIndex('ts'))
      if (val !== null) {
        ts = Number(val)
      }
    }
    resultSet.close()
    return ts
  }

  /** 同步下行写入：携带远端时间戳（先删后插，与 addSearchHistory 去重语义一致） */
  async upsertSearchHistory(keyword: string, searchType: string, timestamp: number): Promise<void> {
    await this.db.execute('DELETE FROM search_history WHERE keyword = ? AND search_type = ?', [keyword, searchType])
    await this.db.execute('INSERT INTO search_history (keyword, search_type, timestamp) VALUES (?, ?, ?)',
      [keyword, searchType, timestamp])
  }

  async deleteSearchHistory(keyword: string, searchType: string): Promise<void> {
    await this.db.execute('DELETE FROM search_history WHERE keyword = ? AND search_type = ?', [keyword, searchType])
  }

  async addMute(type: string, value: string, userId: number = 0): Promise<void> {
    await this.db.execute('INSERT OR REPLACE INTO mutes (type, value, user_id, timestamp) VALUES (?, ?, ?, ?)',
      [type, value, userId, Date.now()])
  }

  async getMutes(): Promise<MuteItem[]> {
    let resultSet = await this.db.querySql('SELECT * FROM mutes ORDER BY timestamp DESC')
    let results: MuteItem[] = []
    while (resultSet.goToNextRow()) {
      let item: MuteItem = {
        id: Number(resultSet.getValue(resultSet.getColumnIndex('id'))),
        type: String(resultSet.getValue(resultSet.getColumnIndex('type'))),
        value: String(resultSet.getValue(resultSet.getColumnIndex('value'))),
        user_id: Number(resultSet.getValue(resultSet.getColumnIndex('user_id'))),
        timestamp: Number(resultSet.getValue(resultSet.getColumnIndex('timestamp')))
      }
      results.push(item)
    }
    resultSet.close()
    return results
  }

  async deleteMute(id: number): Promise<void> {
    await this.db.execute('DELETE FROM mutes WHERE id = ?', [id])
  }

  async addDownloadTask(taskId: string, illustId: number, pageIndex: number, imageUrl: string): Promise<void> {
    await this.db.execute('INSERT OR REPLACE INTO download_tasks (id, illust_id, page_index, image_url, local_path, status, progress, timestamp) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [taskId, illustId, pageIndex, imageUrl, '', 'pending', 0, Date.now()])
  }

  async updateDownloadStatus(taskId: string, status: string, progress: number, localPath: string = ''): Promise<void> {
    await this.db.execute('UPDATE download_tasks SET status = ?, progress = ?, local_path = ? WHERE id = ?',
      [status, progress, localPath, taskId])
  }

  async getDownloadTasks(): Promise<DownloadTaskItem[]> {
    let resultSet = await this.db.querySql('SELECT * FROM download_tasks ORDER BY timestamp DESC')
    let results: DownloadTaskItem[] = []
    while (resultSet.goToNextRow()) {
      let item: DownloadTaskItem = {
        id: String(resultSet.getValue(resultSet.getColumnIndex('id'))),
        illust_id: Number(resultSet.getValue(resultSet.getColumnIndex('illust_id'))),
        page_index: Number(resultSet.getValue(resultSet.getColumnIndex('page_index'))),
        image_url: String(resultSet.getValue(resultSet.getColumnIndex('image_url'))),
        local_path: String(resultSet.getValue(resultSet.getColumnIndex('local_path'))),
        status: String(resultSet.getValue(resultSet.getColumnIndex('status'))),
        progress: Number(resultSet.getValue(resultSet.getColumnIndex('progress'))),
        timestamp: Number(resultSet.getValue(resultSet.getColumnIndex('timestamp')))
      }
      results.push(item)
    }
    resultSet.close()
    return results
  }

  async addImageCache(url: string, localPath: string): Promise<void> {
    await this.db.execute('INSERT OR REPLACE INTO image_cache (url, local_path, timestamp) VALUES (?, ?, ?)',
      [url, localPath, Date.now()])
  }

  async updateImageCachePathPrefix(oldPrefix: string, newPrefix: string): Promise<void> {
    await this.db.execute('UPDATE image_cache SET local_path = REPLACE(local_path, ?, ?) WHERE local_path LIKE ?',
      [oldPrefix, newPrefix, oldPrefix + '%'])
  }

  async getImageCache(url: string): Promise<string> {
    let resultSet = await this.db.querySql('SELECT local_path FROM image_cache WHERE url = ?', [url])
    let path = ''
    if (resultSet.goToNextRow()) {
      path = String(resultSet.getValue(resultSet.getColumnIndex('local_path')))
    }
    resultSet.close()
    return path
  }

  async getRecommendCache(): Promise<string> {
    let resultSet = await this.db.querySql('SELECT data FROM recommend_cache WHERE id = 1')
    let data = ''
    if (resultSet.goToNextRow()) {
      data = String(resultSet.getValue(resultSet.getColumnIndex('data')))
    }
    resultSet.close()
    return data
  }

  async setRecommendCache(data: string): Promise<void> {
    await this.db.execute('INSERT OR REPLACE INTO recommend_cache (id, data, timestamp) VALUES (?, ?, ?)',
      [1, data, Date.now()])
  }

  async getRankingCache(mode: string, date: string): Promise<string> {
    let resultSet = await this.db.querySql('SELECT data FROM ranking_cache WHERE mode = ? AND date = ?', [mode, date])
    let data = ''
    if (resultSet.goToNextRow()) {
      data = String(resultSet.getValue(resultSet.getColumnIndex('data')))
    }
    resultSet.close()
    return data
  }

  async setRankingCache(mode: string, date: string, data: string): Promise<void> {
    await this.db.execute('INSERT OR REPLACE INTO ranking_cache (mode, date, data, timestamp) VALUES (?, ?, ?, ?)',
      [mode, date, data, Date.now()])
  }

  async getIllustDetailCache(illustId: number): Promise<string> {
    let resultSet = await this.db.querySql('SELECT data FROM illust_detail_cache WHERE illust_id = ?', [illustId])
    let data = ''
    if (resultSet.goToNextRow()) {
      data = String(resultSet.getValue(resultSet.getColumnIndex('data')))
    }
    resultSet.close()
    return data
  }

  async setIllustDetailCache(illustId: number, data: string): Promise<void> {
    await this.db.execute('INSERT OR REPLACE INTO illust_detail_cache (illust_id, data, timestamp) VALUES (?, ?, ?)',
      [illustId, data, Date.now()])
  }

  async deleteIllustDetailCache(illustId: number): Promise<void> {
    await this.db.execute('DELETE FROM illust_detail_cache WHERE illust_id = ?', [illustId])
  }

  async clearCompletedDownloadTasks(): Promise<void> {
    await this.db.execute('DELETE FROM download_tasks WHERE status = ?', ['completed'])
  }

  async getDownloadTaskById(taskId: string): Promise<DownloadTaskItem | null> {
    let resultSet = await this.db.querySql('SELECT * FROM download_tasks WHERE id = ?', [taskId])
    let item: DownloadTaskItem | null = null
    if (resultSet.goToNextRow()) {
      let found: DownloadTaskItem = {
        id: String(resultSet.getValue(resultSet.getColumnIndex('id'))),
        illust_id: Number(resultSet.getValue(resultSet.getColumnIndex('illust_id'))),
        page_index: Number(resultSet.getValue(resultSet.getColumnIndex('page_index'))),
        image_url: String(resultSet.getValue(resultSet.getColumnIndex('image_url'))),
        local_path: String(resultSet.getValue(resultSet.getColumnIndex('local_path'))),
        status: String(resultSet.getValue(resultSet.getColumnIndex('status'))),
        progress: Number(resultSet.getValue(resultSet.getColumnIndex('progress'))),
        timestamp: Number(resultSet.getValue(resultSet.getColumnIndex('timestamp')))
      }
      item = found
    }
    resultSet.close()
    return item
  }

  /** 删除指定状态的全部下载任务记录（仅删记录不删文件），返回删除行数 */
  async deleteDownloadTasksByStatus(status: string): Promise<number> {
    let predicates = new relationalStore.RdbPredicates('download_tasks')
    predicates.equalTo('status', status)
    return await this.db.delete(predicates)
  }

  async clearImageCache(): Promise<void> {
    await this.db.execute('DELETE FROM image_cache')
  }

  // ---------------- bookmark_snapshots（收藏快照：待上行暂存 + 404 兜底 + 收藏页占位） ----------------

  async upsertBookmarkSnapshot(illustId: number, data: string, updatedAt: number, deleted: boolean): Promise<void> {
    await this.db.execute('INSERT OR REPLACE INTO bookmark_snapshots (illust_id, data, updated_at, deleted) VALUES (?, ?, ?, ?)',
      [illustId, data, updatedAt, deleted ? 1 : 0])
  }

  async getBookmarkSnapshot(illustId: number): Promise<BookmarkSnapshotItem | null> {
    let resultSet = await this.db.querySql('SELECT * FROM bookmark_snapshots WHERE illust_id = ?', [illustId])
    let item: BookmarkSnapshotItem | null = null
    if (resultSet.goToNextRow()) {
      let found: BookmarkSnapshotItem = {
        illust_id: Number(resultSet.getValue(resultSet.getColumnIndex('illust_id'))),
        data: String(resultSet.getValue(resultSet.getColumnIndex('data'))),
        updated_at: Number(resultSet.getValue(resultSet.getColumnIndex('updated_at'))),
        deleted: Number(resultSet.getValue(resultSet.getColumnIndex('deleted')))
      }
      item = found
    }
    resultSet.close()
    return item
  }

  /** 未删除（deleted=0）的全部快照，按收藏时间（updated_at）倒序 */
  async getAliveBookmarkSnapshots(): Promise<BookmarkSnapshotItem[]> {
    let resultSet = await this.db.querySql('SELECT * FROM bookmark_snapshots WHERE deleted = 0 ORDER BY updated_at DESC')
    let results: BookmarkSnapshotItem[] = []
    while (resultSet.goToNextRow()) {
      let item: BookmarkSnapshotItem = {
        illust_id: Number(resultSet.getValue(resultSet.getColumnIndex('illust_id'))),
        data: String(resultSet.getValue(resultSet.getColumnIndex('data'))),
        updated_at: Number(resultSet.getValue(resultSet.getColumnIndex('updated_at'))),
        deleted: Number(resultSet.getValue(resultSet.getColumnIndex('deleted')))
      }
      results.push(item)
    }
    resultSet.close()
    return results
  }

  /** 覆盖式更新某域快照集合（同步全量重建用）：先清空再批量写入 */
  async replaceBookmarkSnapshots(items: BookmarkSnapshotItem[]): Promise<void> {
    await this.db.execute('DELETE FROM bookmark_snapshots')
    for (let i = 0; i < items.length; i++) {
      await this.upsertBookmarkSnapshot(items[i].illust_id, items[i].data, items[i].updated_at, items[i].deleted !== 0)
    }
  }

  /** 全量快照行（含墓碑），同步 push collector 用 */
  async getAllBookmarkSnapshotRows(): Promise<BookmarkSnapshotItem[]> {
    let resultSet = await this.db.querySql('SELECT * FROM bookmark_snapshots')
    let results: BookmarkSnapshotItem[] = []
    while (resultSet.goToNextRow()) {
      let item: BookmarkSnapshotItem = {
        illust_id: Number(resultSet.getValue(resultSet.getColumnIndex('illust_id'))),
        data: String(resultSet.getValue(resultSet.getColumnIndex('data'))),
        updated_at: Number(resultSet.getValue(resultSet.getColumnIndex('updated_at'))),
        deleted: Number(resultSet.getValue(resultSet.getColumnIndex('deleted')))
      }
      results.push(item)
    }
    resultSet.close()
    return results
  }

  async markBookmarkSnapshotDeleted(illustId: number): Promise<void> {
    await this.db.execute('UPDATE bookmark_snapshots SET deleted = ?, updated_at = ? WHERE illust_id = ?',
      [1, Date.now(), illustId])
  }
}

let dbServiceInstance: DatabaseService | null = null
export async function getDbService(): Promise<DatabaseService> {
  if (!dbServiceInstance) {
    dbServiceInstance = await DatabaseService.getInstance()
  }
  return dbServiceInstance
}

// ---------------- 同步写入 hook（模块级回调，避免 DatabaseService 反向 import SyncService 成环） ----------------

export type SyncWriteHook = (domain: string, tombstoneKeys: string[]) => void

let syncWriteHooks: SyncWriteHook[] = []

/** 注册写钩子监听器（多监听 fan-out：Relay SyncService 与 DistributedSyncService 各自注册） */
export function addSyncWriteHook(hook: SyncWriteHook): void {
  if (!syncWriteHooks.includes(hook)) {
    syncWriteHooks.push(hook)
  }
}

export function removeSyncWriteHook(hook: SyncWriteHook): void {
  let index = syncWriteHooks.indexOf(hook)
  if (index >= 0) {
    syncWriteHooks.splice(index, 1)
  }
}

/** 兼容包装：清空后单注册（既有 Relay SyncService 调用点行为不变） */
export function setSyncWriteHook(hook: SyncWriteHook): void {
  syncWriteHooks = []
  syncWriteHooks.push(hook)
}

function notifySyncWrite(domain: string, tombstoneKeys: string[] = []): void {
  for (let i = 0; i < syncWriteHooks.length; i++) {
    try {
      syncWriteHooks[i](domain, tombstoneKeys)
    } catch (e) {
      console.error('Sync write hook failed: ' + e)
    }
  }
}
