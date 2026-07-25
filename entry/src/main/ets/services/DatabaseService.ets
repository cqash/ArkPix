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
      DatabaseService.instance = new DatabaseService(db)
    }
    return DatabaseService.instance
  }

  async addHistory(illustId: number, title: string, imageUrl: string, userName: string): Promise<void> {
    await this.db.execute('INSERT OR REPLACE INTO history (illust_id, title, image_url, user_name, timestamp) VALUES (?, ?, ?, ?, ?)',
      [illustId, title, imageUrl, userName, Date.now()])
  }

  async getHistory(limit: number = 100): Promise<HistoryItem[]> {
    let resultSet = await this.db.querySql('SELECT * FROM history ORDER BY timestamp DESC LIMIT ?', [limit])
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
    await this.db.execute('DELETE FROM history')
  }

  async addSearchHistory(keyword: string, searchType: string): Promise<void> {
    await this.db.execute('INSERT OR REPLACE INTO search_history (keyword, search_type, timestamp) VALUES (?, ?, ?)',
      [keyword, searchType, Date.now()])
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
    await this.db.execute('DELETE FROM search_history')
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
}

let dbServiceInstance: DatabaseService | null = null
export async function getDbService(): Promise<DatabaseService> {
  if (!dbServiceInstance) {
    dbServiceInstance = await DatabaseService.getInstance()
  }
  return dbServiceInstance
}
