import { ExifTagMergeRule } from '../models/AppSettings';

/**
 * 合并对话框输入补全的本地候选构建（纯函数，便于单测）。
 * 来源优先级：
 *   1) 已存合并规则（exifMergedTags 的 mainTag + fromTags 拍平）
 *   2) 当前作品的 tag 名列表
 * 行为：前缀匹配；跨来源去重（先出现者优先，即合并规则优先于本作品 tag）；输入为空返回空列表。
 * 本地有匹配时调用方 MUST NOT 再请求 API；本地零匹配才允许防抖后调用自动补全 API。
 */
export function buildLocalSuggestions(input: string, mergedRules: ExifTagMergeRule[], illustTags: string[]): string[] {
  let prefix = input.trim()
  if (prefix.length === 0) {
    return []
  }
  let results: string[] = []
  let addIfMatch = (name: string): void => {
    if (name.length === 0 || !name.startsWith(prefix)) {
      return
    }
    if (!results.includes(name)) {
      results.push(name)
    }
  }
  for (let i = 0; i < mergedRules.length; i++) {
    addIfMatch(mergedRules[i].mainTag)
    let fromTags = mergedRules[i].fromTags
    for (let j = 0; j < fromTags.length; j++) {
      addIfMatch(fromTags[j])
    }
  }
  for (let k = 0; k < illustTags.length; k++) {
    addIfMatch(illustTags[k])
  }
  return results
}
