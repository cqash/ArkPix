import { HistoryItem } from '../services/DatabaseService';

/** 导出条目（字段名 camelCase，面向外部工具可读性） */
export interface HistoryExportItem {
  illustId: number
  title: string
  userName: string
  imageUrl: string
  timestamp: number
}

export interface HistoryExportData {
  version: number
  appName: string
  type: string
  exportedAt: string
  count: number
  items: HistoryExportItem[]
}

/** 构建浏览历史导出 JSON（version/appName/type/exportedAt/count/items 结构） */
export function buildHistoryExportJson(items: HistoryItem[]): string {
  let exportItems: HistoryExportItem[] = items.map((item: HistoryItem): HistoryExportItem => {
    return {
      illustId: item.illust_id,
      title: item.title,
      userName: item.user_name,
      imageUrl: item.image_url,
      timestamp: item.timestamp
    }
  })
  let data: HistoryExportData = {
    version: 1,
    appName: 'ArkPix',
    type: 'browse_history',
    exportedAt: new Date().toISOString(),
    count: exportItems.length,
    items: exportItems
  }
  return JSON.stringify(data, null, 2)
}

/** 构建纯文本 PID 列表（每行一个 illust_id） */
export function buildHistoryPidText(items: HistoryItem[]): string {
  let lines: string[] = items.map((item: HistoryItem): string => item.illust_id.toString())
  return lines.join('\n')
}
