import { Illust } from '../models/Illust';
import { AppSettings } from '../models/AppSettings';

/**
 * 屏蔽过滤纯函数：屏蔽词（标题/标签包含匹配，不区分大小写）、
 * 屏蔽作者、AI 作品过滤（illustAIType === 2 为 AI 生成）。
 */
export class MuteFilter {
  static isMuted(illust: Illust, settings: AppSettings): boolean {
    if (settings.muteUsers.includes(illust.user.id)) {
      return true
    }
    if (settings.aiFilter && illust.illustAIType === 2) {
      return true
    }
    if (settings.muteTags.length === 0) {
      return false
    }
    let title = illust.title.toLowerCase()
    for (let i = 0; i < settings.muteTags.length; i++) {
      let keyword = settings.muteTags[i].toLowerCase().trim()
      if (keyword.length === 0) {
        continue
      }
      if (title.includes(keyword)) {
        return true
      }
      for (let j = 0; j < illust.tags.length; j++) {
        if (illust.tags[j].name.toLowerCase().includes(keyword)) {
          return true
        }
      }
    }
    return false
  }
}
