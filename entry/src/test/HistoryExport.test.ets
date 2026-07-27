import { describe, it, expect } from '@ohos/hypium';
import { buildHistoryExportJson, buildHistoryPidText, HistoryExportData } from '../main/ets/utils/HistoryExport';
import { HistoryItem } from '../main/ets/services/DatabaseService';

function makeItem(illustId: number, title: string, userName: string, timestamp: number): HistoryItem {
  let item: HistoryItem = {
    id: illustId,
    illust_id: illustId,
    title: title,
    image_url: 'https://i.pximg.net/img/' + illustId + '.jpg',
    user_name: userName,
    timestamp: timestamp
  }
  return item
}

export default function historyExportTest() {
  describe('HistoryExportTest', () => {
    it('should_build_json_with_all_fields_and_count', 0, () => {
      let items: HistoryItem[] = [
        makeItem(1001, '作品A', '画师甲', 1720000000000),
        makeItem(1002, '作品B', '画师乙', 1720000001000)
      ]
      let json = buildHistoryExportJson(items)
      let parsed = JSON.parse(json) as HistoryExportData
      expect(parsed.version).assertEqual(1)
      expect(parsed.appName).assertEqual('ArkPix')
      expect(parsed.type).assertEqual('browse_history')
      expect(parsed.count).assertEqual(2)
      expect(parsed.items.length).assertEqual(2)
      expect(parsed.items[0].illustId).assertEqual(1001)
      expect(parsed.items[0].title).assertEqual('作品A')
      expect(parsed.items[0].userName).assertEqual('画师甲')
      expect(parsed.items[0].imageUrl).assertEqual('https://i.pximg.net/img/1001.jpg')
      expect(parsed.items[0].timestamp).assertEqual(1720000000000)
      expect(parsed.items[1].illustId).assertEqual(1002)
      expect(parsed.exportedAt.length > 0).assertTrue()
    })

    it('should_build_empty_json_for_empty_history', 0, () => {
      let items: HistoryItem[] = []
      let parsed = JSON.parse(buildHistoryExportJson(items)) as HistoryExportData
      expect(parsed.count).assertEqual(0)
      expect(parsed.items.length).assertEqual(0)
    })

    it('should_build_pid_text_one_per_line', 0, () => {
      let items: HistoryItem[] = [
        makeItem(111, 'a', 'u', 1),
        makeItem(222, 'b', 'u', 2),
        makeItem(333, 'c', 'u', 3)
      ]
      let text = buildHistoryPidText(items)
      let lines = text.split('\n')
      expect(lines.length).assertEqual(3)
      expect(lines[0]).assertEqual('111')
      expect(lines[1]).assertEqual('222')
      expect(lines[2]).assertEqual('333')
    })

    it('should_build_empty_text_for_empty_history', 0, () => {
      let items: HistoryItem[] = []
      expect(buildHistoryPidText(items)).assertEqual('')
    })
  })
}
