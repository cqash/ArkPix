/**
 * pixiv 链接直达解析（纯函数，无副作用，可单测）。
 * 支持：
 *  - https://www.pixiv.net/artworks/{id}
 *  - https://www.pixiv.net/users/{id}
 *  - https://www.pixiv.net/member_illust.php?illust_id={id}（及 mode=medium 旧链）
 *  - pixiv://illusts/{id}
 *  - pixiv://user/{id}
 * 不识别返回 null（UI 静默不显示直达入口）。
 */

export type PixivLinkKind = 'illust' | 'user'

export interface PixivLinkTarget {
  kind: PixivLinkKind
  id: number
}

function parseTrailingDigits(text: string): number {
  let m = new RegExp('^(\\d+)').exec(text)
  if (m === null || m.length < 2) {
    return 0
  }
  let id = Number(m[1])
  if (!Number.isInteger(id) || id <= 0) {
    return 0
  }
  return id
}

export class PixivLinkParser {
  static parse(input: string): PixivLinkTarget | null {
    let text = input.trim()
    if (text.length === 0) {
      return null
    }
    let lower = text.toLowerCase()
    // pixiv:// 自定义协议
    if (lower.startsWith('pixiv://')) {
      let rest = text.substring('pixiv://'.length)
      if (rest.startsWith('illusts/')) {
        let id = parseTrailingDigits(rest.substring('illusts/'.length))
        if (id > 0) {
          let target: PixivLinkTarget = { kind: 'illust', id: id }
          return target
        }
      } else if (rest.startsWith('user/') || rest.startsWith('users/')) {
        let idx = rest.indexOf('/')
        let id = parseTrailingDigits(rest.substring(idx + 1))
        if (id > 0) {
          let target: PixivLinkTarget = { kind: 'user', id: id }
          return target
        }
      }
      return null
    }
    // https:// 明文链接
    if (!lower.startsWith('https://')) {
      return null
    }
    let noScheme = text.substring('https://'.length)
    let lowerNoScheme = lower.substring('https://'.length)
    if (!lowerNoScheme.startsWith('www.pixiv.net') && !lowerNoScheme.startsWith('pixiv.net')) {
      return null
    }
    let artworksIdx = lowerNoScheme.indexOf('/artworks/')
    if (artworksIdx >= 0) {
      let id = parseTrailingDigits(noScheme.substring(artworksIdx + '/artworks/'.length))
      if (id > 0) {
        let target: PixivLinkTarget = { kind: 'illust', id: id }
        return target
      }
      return null
    }
    let usersIdx = lowerNoScheme.indexOf('/users/')
    if (usersIdx >= 0) {
      let id = parseTrailingDigits(noScheme.substring(usersIdx + '/users/'.length))
      if (id > 0) {
        let target: PixivLinkTarget = { kind: 'user', id: id }
        return target
      }
      return null
    }
    if (lowerNoScheme.indexOf('member_illust.php') >= 0) {
      let m = new RegExp('[?&]illust_id=(\\d+)').exec(noScheme)
      if (m !== null && m.length >= 2) {
        let id = Number(m[1])
        if (Number.isInteger(id) && id > 0) {
          let target: PixivLinkTarget = { kind: 'illust', id: id }
          return target
        }
      }
      return null
    }
    return null
  }
}
