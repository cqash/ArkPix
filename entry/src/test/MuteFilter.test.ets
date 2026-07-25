import { describe, it, expect } from '@ohos/hypium';
import { MuteFilter } from '../main/ets/utils/MuteFilter';
import { Illust, IllustOptions, TagOptions } from '../main/ets/models/Illust';
import { AppSettings, AppSettingsOptions } from '../main/ets/models/AppSettings';

function makeIllust(title: string, tags: string[], userId: number, aiType: number): Illust {
  let tagOpts: TagOptions[] = tags.map((name: string): TagOptions => {
    return { name: name }
  })
  let opts: IllustOptions = {
    id: 1,
    title: title,
    tags: tagOpts,
    user: { id: userId },
    illustAIType: aiType
  }
  return new Illust(opts)
}

function makeSettings(muteTags: string[], muteUsers: number[], aiFilter: boolean): AppSettings {
  let opts: AppSettingsOptions = {
    muteTags: muteTags,
    muteUsers: muteUsers,
    aiFilter: aiFilter
  }
  return new AppSettings(opts)
}

export default function muteFilterTest() {
  describe('MuteFilterTest', () => {
    it('should_not_mute_when_no_rules', 0, () => {
      let illust = makeIllust('美丽的风景', ['风景', '插画'], 100, 0)
      let settings = makeSettings([], [], false)
      expect(MuteFilter.isMuted(illust, settings)).assertFalse()
    })

    it('should_mute_by_title_keyword_case_insensitive', 0, () => {
      let illust = makeIllust('Hello World Test', ['tag1'], 100, 0)
      let settings = makeSettings(['hello'], [], false)
      expect(MuteFilter.isMuted(illust, settings)).assertTrue()
    })

    it('should_mute_by_tag_keyword_case_insensitive', 0, () => {
      let illust = makeIllust('无标题', ['R18G', '其他'], 100, 0)
      let settings = makeSettings(['r18g'], [], false)
      expect(MuteFilter.isMuted(illust, settings)).assertTrue()
    })

    it('should_not_mute_when_keyword_not_match', 0, () => {
      let illust = makeIllust('风景画', ['风景'], 100, 0)
      let settings = makeSettings(['xyz'], [], false)
      expect(MuteFilter.isMuted(illust, settings)).assertFalse()
    })

    it('should_mute_by_user_id', 0, () => {
      let illust = makeIllust('作品', [], 42, 0)
      let settings = makeSettings([], [42], false)
      expect(MuteFilter.isMuted(illust, settings)).assertTrue()
    })

    it('should_mute_ai_illust_when_filter_on', 0, () => {
      let illust = makeIllust('AI 作品', [], 100, 2)
      let settings = makeSettings([], [], true)
      expect(MuteFilter.isMuted(illust, settings)).assertTrue()
    })

    it('should_not_mute_ai_illust_when_filter_off', 0, () => {
      let illust = makeIllust('AI 作品', [], 100, 2)
      let settings = makeSettings([], [], false)
      expect(MuteFilter.isMuted(illust, settings)).assertFalse()
    })

    it('should_not_mute_human_illust_when_filter_on', 0, () => {
      let illust = makeIllust('手绘作品', [], 100, 0)
      let settings = makeSettings([], [], true)
      expect(MuteFilter.isMuted(illust, settings)).assertFalse()
    })
  })
}
