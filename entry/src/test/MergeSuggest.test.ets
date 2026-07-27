import { describe, it, expect } from '@ohos/hypium';
import { buildLocalSuggestions } from '../main/ets/utils/MergeSuggest';
import { ExifTagMergeRule } from '../main/ets/models/AppSettings';

function makeRule(mainTag: string, fromTags: string[]): ExifTagMergeRule {
  return new ExifTagMergeRule({ mainTag: mainTag, fromTags: fromTags })
}

export default function mergeSuggestTest() {
  describe('MergeSuggestTest', () => {
    it('should_return_empty_for_empty_input', 0, () => {
      let rules: ExifTagMergeRule[] = [makeRule('女の子', ['女孩子'])]
      let tags: string[] = ['女の子']
      expect(buildLocalSuggestions('', rules, tags).length).assertEqual(0)
      expect(buildLocalSuggestions('   ', rules, tags).length).assertEqual(0)
    })

    it('should_match_merged_rule_main_tag_by_prefix', 0, () => {
      let rules: ExifTagMergeRule[] = [makeRule('崩坏3rd', ['崩壊3rd']), makeRule('原神', [])]
      let result = buildLocalSuggestions('崩', rules, [])
      expect(result.length).assertEqual(2)
      expect(result[0]).assertEqual('崩坏3rd')
      expect(result[1]).assertEqual('崩壊3rd')
    })

    it('should_match_from_tags_flattened', 0, () => {
      let rules: ExifTagMergeRule[] = [makeRule('主标签', ['女の子', '女孩子'])]
      let result = buildLocalSuggestions('女', rules, [])
      expect(result.length).assertEqual(2)
      expect(result[0]).assertEqual('女の子')
      expect(result[1]).assertEqual('女孩子')
    })

    it('should_match_current_illust_tags_after_rules', 0, () => {
      let rules: ExifTagMergeRule[] = [makeRule('爱莉希雅', [])]
      let tags: string[] = ['爱莉希雅（崩坏3）', '崩坏3rd']
      let result = buildLocalSuggestions('爱', rules, tags)
      expect(result.length).assertEqual(2)
      expect(result[0]).assertEqual('爱莉希雅')
      expect(result[1]).assertEqual('爱莉希雅（崩坏3）')
    })

    it('should_dedupe_across_sources_with_rule_priority', 0, () => {
      let rules: ExifTagMergeRule[] = [makeRule('崩坏3rd', [])]
      let tags: string[] = ['崩坏3rd', '崩坏学园']
      let result = buildLocalSuggestions('崩坏', rules, tags)
      expect(result.length).assertEqual(2)
      expect(result[0]).assertEqual('崩坏3rd')
      expect(result[1]).assertEqual('崩坏学园')
    })

    it('should_return_empty_when_no_match', 0, () => {
      let rules: ExifTagMergeRule[] = [makeRule('原神', ['Genshin'])]
      let tags: string[] = ['女の子']
      expect(buildLocalSuggestions('zzz', rules, tags).length).assertEqual(0)
    })
  })
}
