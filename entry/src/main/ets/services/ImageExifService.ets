import image from '@ohos.multimedia.image';
import { fileIo, ReadOptions } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from '../utils/Constants';
import { userSettingStore } from '../stores/UserSettingStore';
import { AppSettings } from '../models/AppSettings';

// 设备日志统一入口（console.* 在设备 hilog 中不可见，故全部经 hilog 输出）
const EXIF_LOG_DOMAIN = 0x0001
const EXIF_LOG_TAG = 'PixEzExif'

function logInfo(msg: string): void {
  hilog.info(EXIF_LOG_DOMAIN, EXIF_LOG_TAG, '%{public}s', msg)
}

function logError(msg: string): void {
  hilog.error(EXIF_LOG_DOMAIN, EXIF_LOG_TAG, '%{public}s', msg)
}

export interface ExifTag {
  name: string
  translatedName: string
}

export interface ExifInfo {
  illustId: number
  userId: number
  title: string
  userName: string
  tags: ExifTag[]
  createDate: string
  pageIndex: number
}

// 计算字符串的UTF-8字节长度（EXIF底层限制的是字节数，不是字符数）
export function utf8ByteLength(str: string): number {
  let len = 0
  for (let i = 0; i < str.length; i++) {
    let code = str.charCodeAt(i)
    if (code <= 0x7f) {
      len += 1
    } else if (code <= 0x7ff) {
      len += 2
    } else {
      len += 3
    }
  }
  return len
}

// 按UTF-8字节长度截断字符串，确保不会切在多字节字符中间
function utf8ByteSubstring(str: string, maxBytes: number): string {
  let len = 0
  let result = ''
  for (let i = 0; i < str.length; i++) {
    let code = str.charCodeAt(i)
    let charBytes = code <= 0x7f ? 1 : (code <= 0x7ff ? 2 : 3)
    if (len + charBytes > maxBytes) {
      break
    }
    result += str[i]
    len += charBytes
  }
  return result
}

function formatTags(tags: ExifTag[]): string {
  return tags.map((t: ExifTag) => {
    let displayTranslation = Constants.filterTranslatedName(t.name, t.translatedName)
    if (displayTranslation.length > 0) {
      return `${t.name} (${displayTranslation})`
    }
    return t.name
  }).join(', ')
}

// 纯目标语言输出：优先用有效的中文翻译，无翻译或无效翻译时用原文
function formatTagsLocalized(tags: ExifTag[]): string {
  return tags.map((t: ExifTag) => {
    let displayTranslation = Constants.filterTranslatedName(t.name, t.translatedName)
    if (displayTranslation.length > 0) {
      return displayTranslation
    }
    return t.name
  }).join(', ')
}

// 按模板渲染EXIF备注内容
// 替换顺序固定：{tags_localized} → {tags_translated} → {tags}（前缀包含关系，最长先替换）
function renderCommentTemplate(template: string, info: ExifInfo, tags: ExifTag[]): string {
  let tagsLocalized = formatTagsLocalized(tags)
  let tagsTranslated = formatTags(tags)
  let tagsOriginal = tags.map((t: ExifTag) => t.name).join(', ')
  return template
    .replaceAll('{tags_localized}', tagsLocalized)
    .replaceAll('{tags_translated}', tagsTranslated)
    .replaceAll('{tags}', tagsOriginal)
    .replaceAll('{illust_id}', info.illustId.toString())
    .replaceAll('{user_id}', info.userId.toString())
    .replaceAll('{user_name}', info.userName)
    .replaceAll('{title}', info.title)
    .replaceAll('{part}', info.pageIndex.toString())
}

// 对 EXIF 备注的 tag 进行过滤和合并
// 1. 过滤 exifMutedTags（屏蔽的移除）
// 2. 应用 exifMergedTags（从属 tag 移除，只保留主 tag）
// 2.5 自动合并翻译相同的 tag（autoMergeTranslatedTags 开启时，translatedName 相同且非空的 tag 保留第一个，移除其余）
// 3. 按 exifTagPriority 排序（优先级高的排前面，不在优先级列表中的排末尾保持原序）
// 返回过滤合并排序后的 ExifTag[]
export function filterTagsForExif(tags: ExifTag[], settings: AppSettings): ExifTag[] {
  // Step 1: Filter muted tags
  let filtered: ExifTag[] = []
  for (let i = 0; i < tags.length; i++) {
    if (!settings.exifMutedTags.includes(tags[i].name)) {
      filtered.push(tags[i])
    }
  }

  // Step 2: Apply merge rules
  // Build a map of mainTag -> fromTags from settings
  for (let r = 0; r < settings.exifMergedTags.length; r++) {
    let rule = settings.exifMergedTags[r]
    let mainTagInFiltered = false
    for (let i = 0; i < filtered.length; i++) {
      if (filtered[i].name === rule.mainTag) {
        mainTagInFiltered = true
        break
      }
    }
    if (mainTagInFiltered) {
      // mainTag exists: remove all fromTags
      let result: ExifTag[] = []
      for (let i = 0; i < filtered.length; i++) {
        if (!rule.fromTags.includes(filtered[i].name)) {
          result.push(filtered[i])
        }
      }
      filtered = result
    } else {
      // mainTag not in tags: find first fromTag that exists, replace it with mainTag (keep translatedName)
      let firstFromIdx = -1
      let firstFromTag: ExifTag | undefined = undefined
      for (let i = 0; i < filtered.length; i++) {
        if (rule.fromTags.includes(filtered[i].name)) {
          firstFromIdx = i
          firstFromTag = filtered[i]
          break
        }
      }
      if (firstFromIdx >= 0 && firstFromTag !== undefined) {
        // Replace the first fromTag with mainTag, keeping its translatedName
        let replacement: ExifTag = { name: rule.mainTag, translatedName: firstFromTag.translatedName }
        filtered[firstFromIdx] = replacement
        // Remove remaining fromTags
        let result: ExifTag[] = []
        for (let i = 0; i < filtered.length; i++) {
          if (i === firstFromIdx) {
            result.push(filtered[i])
          } else if (!rule.fromTags.includes(filtered[i].name)) {
            result.push(filtered[i])
          }
        }
        filtered = result
      }
    }
  }

  // Step 2.5: Auto-merge tags with same translatedName (via exifMergedTags rules)
  // When autoMergeTranslatedTags is enabled, the manual exifMergedTags rules already
  // handle known synonym groups (including user-reviewed ones). No auto-discovery here —
  // new synonym groups are detected by findUnresolvedMergeGroups and presented to the user
  // for review, after which they are persisted into exifMergedTags.

  // Step 3: Sort by exifTagPriority
  if (settings.exifTagPriority.length > 0) {
    let prioritized: ExifTag[] = []
    let remaining: ExifTag[] = []
    // Tags in priority list come first, in priority order
    for (let p = 0; p < settings.exifTagPriority.length; p++) {
      for (let i = 0; i < filtered.length; i++) {
        if (filtered[i].name === settings.exifTagPriority[p]) {
          prioritized.push(filtered[i])
        }
      }
    }
    // Tags not in priority list keep original order, appended at end
    for (let i = 0; i < filtered.length; i++) {
      if (!settings.exifTagPriority.includes(filtered[i].name)) {
        remaining.push(filtered[i])
      }
    }
    let result: ExifTag[] = []
    for (let i = 0; i < prioritized.length; i++) {
      result.push(prioritized[i])
    }
    for (let i = 0; i < remaining.length; i++) {
      result.push(remaining[i])
    }
    filtered = result
  }

  return filtered
}

// 同义 tag 组（用于审查弹窗展示）
export interface MergeGroup {
  translatedName: string  // 共享的翻译名
  tags: ExifTag[]         // 拥有此翻译名的所有 tag
}

// 检测未在 exifMergedTags 中定义的同义 tag 组
// 当 autoMergeTranslatedTags 开启时，找出 tags 中 translatedName 相同且非空的 tag 组，
// 排除已在 exifMergedTags 规则中覆盖的组（即组内所有 tag 名都已被某条规则的 mainTag 或 fromTags 包含）。
// 返回需要用户审查的组列表。
export function findUnresolvedMergeGroups(tags: ExifTag[], settings: AppSettings): MergeGroup[] {
  if (!settings.autoMergeTranslatedTags) {
    return []
  }

  // Build a set of all tag names already covered by exifMergedTags rules
  let coveredTags: string[] = []
  for (let r = 0; r < settings.exifMergedTags.length; r++) {
    let rule = settings.exifMergedTags[r]
    coveredTags.push(rule.mainTag)
    for (let f = 0; f < rule.fromTags.length; f++) {
      coveredTags.push(rule.fromTags[f])
    }
  }

  // Group tags by translatedName
  let groups: Map<string, ExifTag[]> = new Map()
  for (let i = 0; i < tags.length; i++) {
    let tn = tags[i].translatedName
    if (tn.length === 0) {
      continue
    }
    let existing = groups.get(tn)
    if (existing !== undefined) {
      existing.push(tags[i])
    } else {
      groups.set(tn, [tags[i]])
    }
  }

  // Find groups with 2+ tags that are not fully covered by existing rules
  let result: MergeGroup[] = []
  groups.forEach((groupTags: ExifTag[], tn: string) => {
    if (groupTags.length < 2) {
      return
    }
    // Check if ALL tags in this group are already covered by some rule
    let allCovered = true
    for (let g = 0; g < groupTags.length; g++) {
      if (!coveredTags.includes(groupTags[g].name)) {
        allCovered = false
        break
      }
    }
    if (!allCovered) {
      result.push({ translatedName: tn, tags: groupTags })
    }
  })

  return result
}

// 用指定的 tags（已过滤合并）渲染备注模板，返回渲染结果字符串
export function renderCommentWithTags(info: ExifInfo, filteredTags: ExifTag[]): string {
  let template = userSettingStore.getSettings().exifCommentTemplate
  return renderCommentTemplate(template, info, filteredTags)
}

// 检测渲染后的备注是否超过 EXIF 字段上限（120 UTF-8 字节）
export function isCommentOverLimit(info: ExifInfo, filteredTags: ExifTag[]): boolean {
  return renderCommentBytes(info, filteredTags) > EXIF_FIELD_MAX_BYTES
}

// 计算渲染后的备注 UTF-8 字节数
export function renderCommentBytes(info: ExifInfo, filteredTags: ExifTag[]): number {
  let rendered = renderCommentWithTags(info, filteredTags)
  return utf8ByteLength(rendered)
}

// 设备实证（第六轮修复）：MediaLibrary 入册扫描器对 EXIF 字段值有约 128 字节上限，
// 超长时整个 EXIF 段被扫描器拒绝（62980123，图库无备注）。故字段值统一限制在
// 120 UTF-8 字节以内——UserComment 另有 8 字节 "ASCII\0\0\0" 前缀，8+120=正好 128。
export const EXIF_FIELD_MAX_BYTES = 120

// EXIF 字段值统一截断：超过 120 UTF-8 字节时按 117 字节截断 + '...'（117+3=120，
// utf8ByteSubstring 保证不切多字节字符），并用 hilog 记录一次截断事件便于排查。
function clampExifField(fieldName: string, value: string): string {
  let originalBytes = utf8ByteLength(value)
  if (originalBytes <= EXIF_FIELD_MAX_BYTES) {
    return value
  }
  logInfo(`EXIF field truncated: ${fieldName} ${originalBytes}b -> ${EXIF_FIELD_MAX_BYTES}b`)
  return utf8ByteSubstring(value, EXIF_FIELD_MAX_BYTES - 3) + '...'
}

// EXIF 字段探测式写入：第一轮尝试完整值，失败后按 UTF-8 字节指数退避截断
// （每轮预算约为上一轮 1/2，保底约 50 字节），截断后附加 '...' 重试；
// 保底仍失败则放弃该字段，不阻断其他字段与整体流程。
async function safeWriteExif(source: image.ImageSource, key: image.PropertyKey, value: string): Promise<void> {
  // 第一轮：不做预截断，直接尝试写入完整值
  try {
    await source.modifyImageProperty(key, value)
    return
  } catch (e) {
    logError(`EXIF write failed for ${key} (full value, ${utf8ByteLength(value)}b): ` + e)
  }

  // 降级循环：指数退避截断至保底约 50 字节
  // 起始预算封顶 120（设备扫描器上限），加速收敛到设备允许范围以下
  const MIN_BUDGET = 50
  let budget = Math.min(Math.floor(utf8ByteLength(value) / 2), EXIF_FIELD_MAX_BYTES)
  while (budget >= MIN_BUDGET) {
    let truncated = utf8ByteSubstring(value, budget - 3) + '...'
    try {
      await source.modifyImageProperty(key, truncated)
      return
    } catch (e) {
      logError(`EXIF write failed for ${key} at ~${budget}b: ` + e)
    }
    budget = Math.floor(budget / 2)
  }
  logError(`EXIF write abandoned for ${key}: still failing at ${MIN_BUDGET}b fallback`)
}

// 读取当前备注模板并渲染（EXIF 与 XMP 共用同一份渲染结果，FR-004）
function renderComment(info: ExifInfo): string {
  let settings = userSettingStore.getSettings()
  let filteredTags = filterTagsForExif(info.tags, settings)
  return renderCommentWithTags(info, filteredTags)
}

// 字节级 EXIF 存在性检测（替代 getImageProperty 探测——后者带 defaultValue 时对无 EXIF 图片
// 可能不抛异常而返回默认值，导致误判走系统接口路径）：
// 遍历 JPEG 段（逻辑同 injectJpegSegments 的段遍历），找到 marker=0xE1 且 payload
// 以 "Exif\0\0"（EXIF_MAGIC）开头的 APP1 段即返回 true；遍历结束（含 SOS/损坏/非 JPEG）返回 false。
function hasExifSegment(srcBytes: Uint8Array): boolean {
  if (srcBytes.length < 4 || srcBytes[0] !== 0xFF || srcBytes[1] !== 0xD8) {
    return false // 非 JPEG（缺 SOI）
  }
  let pos = 2
  while (pos + 1 < srcBytes.length) {
    if (srcBytes[pos] !== 0xFF) {
      break // 非段标记，停止解析
    }
    let marker = srcBytes[pos + 1]
    if (marker === 0xFF) {
      pos += 1 // 填充字节
      continue
    }
    if (marker === 0xDA) {
      break // SOS：其后为熵编码图像数据，APP 段只可能出现在此之前
    }
    if (marker === 0xD8 || marker === 0xD9 || (marker >= 0xD0 && marker <= 0xD7) || marker === 0x01) {
      pos += 2 // 无长度字段的标记（SOI/EOI/RSTn/TEM）
      continue
    }
    if (pos + 4 > srcBytes.length) {
      break
    }
    let segLen = (srcBytes[pos + 2] << 8) | srcBytes[pos + 3]
    if (segLen < 2 || pos + 2 + segLen > srcBytes.length) {
      break // 段长度损坏
    }
    if (marker === 0xE1 && startsWithBytes(srcBytes, pos + 4, EXIF_MAGIC)) {
      return true
    }
    pos = pos + 2 + segLen
  }
  return false
}

// ===================== 字节级工具（纯内存操作，不重编码） =====================

function asciiBytes(str: string): Uint8Array {
  let out = new Uint8Array(str.length)
  for (let i = 0; i < str.length; i++) {
    out[i] = str.charCodeAt(i) & 0x7F
  }
  return out
}

function concatBytes(a: Uint8Array, b: Uint8Array): Uint8Array {
  let out = new Uint8Array(a.length + b.length)
  out.set(a)
  out.set(b, a.length)
  return out
}

function encodeUtf8(str: string): Uint8Array {
  return new util.TextEncoder('utf-8').encodeInto(str)
}

// EXIF APP1 段标识 "Exif\0\0"
const EXIF_MAGIC: Uint8Array = concatBytes(asciiBytes('Exif'), new Uint8Array(2))
// JPEG XMP APP1 段标识 "http://ns.adobe.com/xap/1.0/\0"（29 字节）
const XMP_APP1_HEADER: Uint8Array = concatBytes(asciiBytes('http://ns.adobe.com/xap/1.0/'), new Uint8Array(1))
// UserComment UNDEFINED 数据的 8 字节字符集前缀 "ASCII\0\0\0"（业界事实标准，后接 UTF-8 字节）
const USER_COMMENT_PREFIX: Uint8Array = new Uint8Array([0x41, 0x53, 0x43, 0x49, 0x49, 0x00, 0x00, 0x00])

function startsWithBytes(bytes: Uint8Array, offset: number, prefix: Uint8Array): boolean {
  if (offset < 0 || offset + prefix.length > bytes.length) {
    return false
  }
  for (let i = 0; i < prefix.length; i++) {
    if (bytes[offset + i] !== prefix[i]) {
      return false
    }
  }
  return true
}

function writeUint16LE(bytes: Uint8Array, offset: number, value: number): void {
  bytes[offset] = value & 0xFF
  bytes[offset + 1] = (value >> 8) & 0xFF
}

function writeUint16BE(bytes: Uint8Array, offset: number, value: number): void {
  bytes[offset] = (value >> 8) & 0xFF
  bytes[offset + 1] = value & 0xFF
}

function writeUint32LE(bytes: Uint8Array, offset: number, value: number): void {
  bytes[offset] = value & 0xFF
  bytes[offset + 1] = (value >> 8) & 0xFF
  bytes[offset + 2] = (value >> 16) & 0xFF
  bytes[offset + 3] = (value >> 24) & 0xFF
}

function writeUint32BE(bytes: Uint8Array, offset: number, value: number): void {
  bytes[offset] = (value >>> 24) & 0xFF
  bytes[offset + 1] = (value >>> 16) & 0xFF
  bytes[offset + 2] = (value >>> 8) & 0xFF
  bytes[offset + 3] = value & 0xFF
}

function readFileBytes(path: string): Uint8Array {
  let file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY)
  try {
    let stat = fileIo.statSync(file.fd)
    let buf = new ArrayBuffer(stat.size)
    let totalRead = 0
    while (totalRead < stat.size) {
      let options: ReadOptions = { offset: totalRead }
      let readLen = fileIo.readSync(file.fd, buf, options)
      if (readLen <= 0) {
        break
      }
      totalRead += readLen
    }
    if (totalRead < stat.size) {
      throw new Error(`Read file incomplete: ${totalRead}/${stat.size} bytes`)
    }
    return new Uint8Array(buf)
  } finally {
    fileIo.closeSync(file.fd)
  }
}

function writeFileBytes(path: string, bytes: Uint8Array): void {
  let file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC)
  try {
    fileIo.writeSync(file.fd, bytes.buffer)
  } finally {
    fileIo.closeSync(file.fd)
  }
}

// ===================== 手工 EXIF APP1 段构造与 JPEG 段注入（plan D10/D13） =====================

const EXIF_TYPE_ASCII = 2
const EXIF_TYPE_LONG = 4
const EXIF_TYPE_UNDEFINED = 7
// APP1 段长度字段为 2 字节（含长度字段自身，不含 marker），故 payload 上限 0xFFFD
const JPEG_APP1_MAX_PAYLOAD = 0xFFFD
// 手工 EXIF 段布局（小端 TIFF，偏移均相对 TIFF 头起点）：
// IFD0（54 字节 = 2 + 4 条目*12 + nextIFD 4）位于 TIFF 偏移 8；
// Exif SubIFD（18 字节 = 2 + 1 条目*12 + nextIFD 4）紧随 IFD0，位于 TIFF 偏移 62；
// 数据区位于 TIFF 偏移 80。
const IFD0_SIZE = 2 + 4 * 12 + 4
const SUB_IFD_TIFF_OFFSET = 8 + IFD0_SIZE // 62
const SUB_IFD_SIZE = 2 + 1 * 12 + 4 // 18
const DATA_AREA_TIFF_OFFSET = SUB_IFD_TIFF_OFFSET + SUB_IFD_SIZE // 80
// 手工 EXIF 段固定部分：Exif\0\0(6) + TIFF 头(8) + IFD0(54) + Exif SubIFD(18) = 86
const EXIF_FIXED_SIZE = 6 + 8 + IFD0_SIZE + SUB_IFD_SIZE

interface ExifEntry {
  tag: number
  type: number
  data: Uint8Array
}

function withNullTerminator(bytes: Uint8Array): Uint8Array {
  return concatBytes(bytes, new Uint8Array(1))
}

// 写一组 IFD 条目（不含条目数与 nextIFD），返回推进后的数据区 TIFF 相对偏移。
// >4 字节的值写入数据区并在条目内记录 TIFF 相对偏移；≤4 字节内联存储，剩余字节补 0（out 零初始化保证）。
// TIFF 头位于段内偏移 10，故数据区写入位置 = 10 + TIFF 相对偏移。
function writeIfdEntries(out: Uint8Array, entriesBase: number, entries: ExifEntry[], dataOffset: number): number {
  let offset = dataOffset
  for (let i = 0; i < entries.length; i++) {
    let entryPos = entriesBase + 2 + i * 12
    writeUint16LE(out, entryPos, entries[i].tag)
    writeUint16LE(out, entryPos + 2, entries[i].type)
    writeUint32LE(out, entryPos + 4, entries[i].data.length)
    if (entries[i].data.length > 4) {
      writeUint32LE(out, entryPos + 8, offset)
      out.set(entries[i].data, 10 + offset)
      offset += entries[i].data.length
    } else {
      out.set(entries[i].data, entryPos + 8)
    }
  }
  return offset
}

// 构造最小合法 EXIF APP1 段（小端 TIFF，plan D10），用于无 EXIF 的 JPEG：
// FFE1 + 长度(大端) + "Exif\0\0" + TIFF 头("II" 0x002A, IFD0 偏移 8)
// + IFD0（ImageDescription 0x010E / Artist 0x013B / Copyright 0x8298 ASCII，
//   ExifIFDPointer 0x8769 LONG 内联指向 Exif SubIFD 的 TIFF 相对偏移 62）+ nextIFD 0
// + Exif SubIFD（UserComment 0x9286 UNDEFINED 带 "ASCII\0\0\0" 前缀 + UTF-8 字节）+ nextIFD 0
// + 数据区（TIFF 偏移 80 起，>4 字节的值按写入顺序存放）。
// UserComment 必须位于 Exif SubIFD（EXIF 规范），严格解码器（系统图库/piexif）只从 SubIFD 读取。
// 段容量约 64KB，触顶时按 UTF-8 字节安全截断 UserComment（防御，实际不会触顶）。
function buildExifSegment(info: ExifInfo): Uint8Array {
  // 设备上限统一截断（120 UTF-8 字节）：模板拼接完成后再截断；
  // UserComment 的 8 字节前缀在截断之后拼接（8+120=正好 128，符合扫描器上限）
  let settings = userSettingStore.getSettings()
  let filteredTags = filterTagsForExif(info.tags, settings)
  let desc = withNullTerminator(encodeUtf8(clampExifField('ImageDescription', `${info.title} | PID:${info.illustId}`)))
  let artist = withNullTerminator(encodeUtf8(clampExifField('Artist', `${info.userName} (UID:${info.userId})`)))
  let copyright = withNullTerminator(asciiBytes(clampExifField('Copyright', 'Pixiv')))
  let comment = clampExifField('UserComment', renderCommentWithTags(info, filteredTags))
  let commentBytes = encodeUtf8(comment)
  // 段容量防御：数据区上限 = 0xFFFD - 固定部分 - 其余数据字段
  let commentBudget = JPEG_APP1_MAX_PAYLOAD - EXIF_FIXED_SIZE - desc.length - artist.length - copyright.length -
    USER_COMMENT_PREFIX.length
  if (commentBytes.length > commentBudget) {
    commentBytes = encodeUtf8(utf8ByteSubstring(comment, commentBudget))
  }
  let userComment = concatBytes(USER_COMMENT_PREFIX, commentBytes)
  // IFD0 前 3 个条目（tag 升序 0x010E < 0x013B < 0x8298），第 4 个为 0x8769 ExifIFDPointer
  let ifd0Entries: ExifEntry[] = [
    { tag: 0x010E, type: EXIF_TYPE_ASCII, data: desc },
    { tag: 0x013B, type: EXIF_TYPE_ASCII, data: artist },
    { tag: 0x8298, type: EXIF_TYPE_ASCII, data: copyright }
  ]
  // Exif SubIFD：UserComment 0x9286
  let subIfdEntries: ExifEntry[] = [
    { tag: 0x9286, type: EXIF_TYPE_UNDEFINED, data: userComment }
  ]
  // 布局：marker(2) + 长度(2) + Exif\0\0(6) + TIFF 头(8) + IFD0(54) + SubIFD(18) + 数据区
  let dataAreaLen = 0
  for (let i = 0; i < ifd0Entries.length; i++) {
    if (ifd0Entries[i].data.length > 4) {
      dataAreaLen += ifd0Entries[i].data.length
    }
  }
  for (let i = 0; i < subIfdEntries.length; i++) {
    if (subIfdEntries[i].data.length > 4) {
      dataAreaLen += subIfdEntries[i].data.length
    }
  }
  let totalLen = 2 + 2 + EXIF_FIXED_SIZE + dataAreaLen
  let out = new Uint8Array(totalLen)
  out[0] = 0xFF
  out[1] = 0xE1
  writeUint16BE(out, 2, totalLen - 2) // 长度字段含自身，不含 marker
  out.set(EXIF_MAGIC, 4)
  // TIFF 头：小端 "II" + 0x002A + IFD0 偏移 8（段内偏移 10 起）
  out[10] = 0x49
  out[11] = 0x49
  out[12] = 0x2A
  out[13] = 0x00
  writeUint32LE(out, 14, 8)
  // IFD0（段内偏移 18）：4 个条目 + nextIFD 0
  writeUint16LE(out, 18, ifd0Entries.length + 1)
  let dataOffset = writeIfdEntries(out, 18, ifd0Entries, DATA_AREA_TIFF_OFFSET)
  // 第 4 个条目：0x8769 ExifIFDPointer，LONG count=1，值内联 = SubIFD 的 TIFF 相对偏移
  let ptrEntryPos = 18 + 2 + ifd0Entries.length * 12
  writeUint16LE(out, ptrEntryPos, 0x8769)
  writeUint16LE(out, ptrEntryPos + 2, EXIF_TYPE_LONG)
  writeUint32LE(out, ptrEntryPos + 4, 1)
  writeUint32LE(out, ptrEntryPos + 8, SUB_IFD_TIFF_OFFSET)
  // IFD0 nextIFD = 0（零初始化保证）
  // Exif SubIFD（段内偏移 10 + 62 = 72）：1 个条目 + nextIFD 0
  let subIfdBase = 10 + SUB_IFD_TIFF_OFFSET
  writeUint16LE(out, subIfdBase, subIfdEntries.length)
  writeIfdEntries(out, subIfdBase, subIfdEntries, dataOffset)
  // SubIFD nextIFD = 0（零初始化保证）
  return out
}

// JPEG 段注入（plan D13）：SOI 之后依次插入新 EXIF APP1 与新 XMP APP1；
// 剥离规则——exifSeg 提供时丢弃源文件含 "Exif\0\0" 头的 APP1，xmpSeg 提供时丢弃含 XMP 标识头的 APP1，
// 其余段与图像数据（含 SOS 之后的熵编码数据）原样保留，纯字节拼接不重编码。
function injectJpegSegments(srcBytes: Uint8Array, exifSeg: Uint8Array | undefined,
  xmpSeg: Uint8Array | undefined): Uint8Array {
  if (srcBytes.length < 4 || srcBytes[0] !== 0xFF || srcBytes[1] !== 0xD8) {
    throw new Error('Not a valid JPEG (missing SOI)')
  }
  let kept: number[] = [] // 保留区间 [start, end) 扁平存储
  let keepStart = 2
  let pos = 2
  while (pos + 1 < srcBytes.length) {
    if (srcBytes[pos] !== 0xFF) {
      break // 非段标记（异常数据），剩余部分原样保留
    }
    let marker = srcBytes[pos + 1]
    if (marker === 0xFF) {
      pos += 1 // 填充字节
      continue
    }
    if (marker === 0xDA) {
      break // SOS：其后为熵编码图像数据，停止解析，剩余原样保留
    }
    if (marker === 0xD8 || marker === 0xD9 || (marker >= 0xD0 && marker <= 0xD7) || marker === 0x01) {
      pos += 2 // 无长度字段的标记（SOI/EOI/RSTn/TEM）
      continue
    }
    if (pos + 4 > srcBytes.length) {
      break
    }
    let segLen = (srcBytes[pos + 2] << 8) | srcBytes[pos + 3]
    if (segLen < 2 || pos + 2 + segLen > srcBytes.length) {
      break // 段长度损坏，剩余部分原样保留
    }
    let segEnd = pos + 2 + segLen
    if (marker === 0xE1) {
      let payloadOffset = pos + 4
      let dropExif = exifSeg !== undefined && startsWithBytes(srcBytes, payloadOffset, EXIF_MAGIC)
      let dropXmp = xmpSeg !== undefined && startsWithBytes(srcBytes, payloadOffset, XMP_APP1_HEADER)
      if (dropExif || dropXmp) {
        if (pos > keepStart) {
          kept.push(keepStart)
          kept.push(pos)
        }
        keepStart = segEnd
      }
    }
    pos = segEnd
  }
  if (srcBytes.length > keepStart) {
    kept.push(keepStart)
    kept.push(srcBytes.length)
  }
  let total = 2 + (exifSeg !== undefined ? exifSeg.length : 0) + (xmpSeg !== undefined ? xmpSeg.length : 0)
  for (let i = 0; i < kept.length; i += 2) {
    total += kept[i + 1] - kept[i]
  }
  let out = new Uint8Array(total)
  out[0] = 0xFF
  out[1] = 0xD8
  let outPos = 2
  if (exifSeg !== undefined) {
    out.set(exifSeg, outPos)
    outPos += exifSeg.length
  }
  if (xmpSeg !== undefined) {
    out.set(xmpSeg, outPos)
    outPos += xmpSeg.length
  }
  for (let i = 0; i < kept.length; i += 2) {
    out.set(srcBytes.subarray(kept[i], kept[i + 1]), outPos)
    outPos += kept[i + 1] - kept[i]
  }
  return out
}

// ===================== XMP 数据包与 JPEG XMP APP1 段（plan D11/D12） =====================

// XML 特殊字符转义（& 必须最先替换）
function escapeXml(str: string): string {
  return str
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;')
}

// 构造标准 XMP packet（plan D11）：字段与 EXIF 一一对应，共用同一份模板渲染结果（FR-004）
// dc:description ← 模板渲染备注全文（对应 UserComment）；dc:title ← 标题（ImageDescription）；
// dc:creator ← 作者（Artist）；dc:rights ← 'Pixiv'（Copyright）。
function buildXmpPacket(info: ExifInfo): string {
  let settings = userSettingStore.getSettings()
  let filteredTags = filterTagsForExif(info.tags, settings)
  let title = escapeXml(info.title)
  let creator = escapeXml(`${info.userName} (UID:${info.userId})`)
  let description = escapeXml(renderCommentWithTags(info, filteredTags))
  return '<?xpacket begin="\uFEFF" id="W5M0MpCehiHzreSzNTczkc9d"?>' +
    '<x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="PixEz">' +
    '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">' +
    '<rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/">' +
    `<dc:title><rdf:Alt><rdf:li xml:lang="x-default">${title}</rdf:li></rdf:Alt></dc:title>` +
    `<dc:creator><rdf:Seq><rdf:li>${creator}</rdf:li></rdf:Seq></dc:creator>` +
    `<dc:description><rdf:Alt><rdf:li xml:lang="x-default">${description}</rdf:li></rdf:Alt></dc:description>` +
    '<dc:rights><rdf:Alt><rdf:li xml:lang="x-default">Pixiv</rdf:li></rdf:Alt></dc:rights>' +
    '</rdf:Description></rdf:RDF></x:xmpmeta>' +
    '<?xpacket end="w"?>'
}

// JPEG XMP 载体（plan D12）：独立 APP1 段 = FFE1 + 长度 + 29 字节标识头 + UTF-8 XMP packet
function buildXmpApp1Segment(xmpPacket: string): Uint8Array {
  let payload = encodeUtf8(xmpPacket)
  let segLen = 2 + XMP_APP1_HEADER.length + payload.length
  if (segLen > 0xFFFF) {
    throw new Error(`XMP packet too large for APP1 segment: ${payload.length} bytes`)
  }
  let out = new Uint8Array(2 + segLen)
  out[0] = 0xFF
  out[1] = 0xE1
  writeUint16BE(out, 2, segLen)
  out.set(XMP_APP1_HEADER, 4)
  out.set(payload, 4 + XMP_APP1_HEADER.length)
  return out
}

// ===================== PNG XMP iTXt 写入（plan D12/D13） =====================

const PNG_SIGNATURE: Uint8Array = new Uint8Array([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
const ITXT_TYPE: Uint8Array = asciiBytes('iTXt')
const IEND_TYPE: Uint8Array = asciiBytes('IEND')
const XMP_ITXT_KEYWORD: Uint8Array = asciiBytes('XML:com.adobe.xmp')

// CRC32（IEEE 802.3 多项式 0xEDB88320，表驱动手工实现；PNG 规范要求，无系统 API 可用）
function buildCrc32Table(): number[] {
  let table: number[] = []
  for (let n = 0; n < 256; n++) {
    let c = n
    for (let k = 0; k < 8; k++) {
      c = (c & 1) !== 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1)
    }
    table.push(c >>> 0)
  }
  return table
}

const CRC32_TABLE: number[] = buildCrc32Table()

function crc32(bytes: Uint8Array): number {
  let crc = 0xFFFFFFFF
  for (let i = 0; i < bytes.length; i++) {
    crc = CRC32_TABLE[(crc ^ bytes[i]) & 0xFF] ^ (crc >>> 8)
  }
  return (crc ^ 0xFFFFFFFF) >>> 0
}

// 构造 PNG iTXt chunk（plan D12）：
// data = keyword "XML:com.adobe.xmp" + \0 + 压缩标志(0) + 压缩方法(0) + 语言tag(\0) + 翻译keyword(\0) + UTF-8 XMP packet
// chunk = 长度(4 大端) + "iTXt" + data + CRC32(4 大端，对 type+data 计算)
function buildPngItxtChunk(xmpPacket: string): Uint8Array {
  let textBytes = encodeUtf8(xmpPacket)
  let dataLen = XMP_ITXT_KEYWORD.length + 5 + textBytes.length
  let out = new Uint8Array(12 + dataLen)
  writeUint32BE(out, 0, dataLen)
  out.set(ITXT_TYPE, 4)
  out.set(XMP_ITXT_KEYWORD, 8)
  // 分隔符/压缩标志/压缩方法/空语言tag/空翻译keyword 均为 0，由零初始化保证
  out.set(textBytes, 8 + XMP_ITXT_KEYWORD.length + 5)
  let crc = crc32(out.subarray(4, 8 + dataLen))
  writeUint32BE(out, 8 + dataLen, crc)
  return out
}

// PNG iTXt 注入（plan D13）：校验 PNG 签名，移除已有 XMP iTXt 防重复，
// 在 IEND 前插入新 chunk；不触碰 IDAT 像素数据，其余 chunk 原样保留。
function injectPngItxt(srcBytes: Uint8Array, itxtChunk: Uint8Array): Uint8Array {
  if (srcBytes.length < 8 || !startsWithBytes(srcBytes, 0, PNG_SIGNATURE)) {
    throw new Error('Not a valid PNG (bad signature)')
  }
  let kept: number[] = [] // 保留区间 [start, end) 扁平存储
  let keepStart = 0
  let pos = 8
  let iendStart = -1
  while (pos + 8 <= srcBytes.length) {
    let chunkLen = ((srcBytes[pos] << 24) | (srcBytes[pos + 1] << 16) |
      (srcBytes[pos + 2] << 8) | srcBytes[pos + 3]) >>> 0
    let chunkEnd = pos + 12 + chunkLen
    if (chunkEnd > srcBytes.length) {
      throw new Error('Corrupt PNG: chunk length exceeds file size')
    }
    if (startsWithBytes(srcBytes, pos + 4, IEND_TYPE)) {
      iendStart = pos
      break
    }
    if (startsWithBytes(srcBytes, pos + 4, ITXT_TYPE) &&
      startsWithBytes(srcBytes, pos + 8, XMP_ITXT_KEYWORD) &&
      srcBytes[pos + 8 + XMP_ITXT_KEYWORD.length] === 0) {
      // 丢弃旧的 XMP iTXt chunk
      if (pos > keepStart) {
        kept.push(keepStart)
        kept.push(pos)
      }
      keepStart = chunkEnd
    }
    pos = chunkEnd
  }
  if (iendStart < 0) {
    throw new Error('Corrupt PNG: missing IEND')
  }
  if (srcBytes.length > keepStart) {
    kept.push(keepStart)
    kept.push(srcBytes.length)
  }
  let total = itxtChunk.length
  for (let i = 0; i < kept.length; i += 2) {
    total += kept[i + 1] - kept[i]
  }
  let out = new Uint8Array(total)
  let outPos = 0
  let inserted = false
  for (let i = 0; i < kept.length; i += 2) {
    let rangeStart = kept[i]
    let rangeEnd = kept[i + 1]
    if (!inserted && rangeEnd > iendStart) {
      // 在 IEND 前插入新 iTXt chunk
      out.set(srcBytes.subarray(rangeStart, iendStart), outPos)
      outPos += iendStart - rangeStart
      out.set(itxtChunk, outPos)
      outPos += itxtChunk.length
      out.set(srcBytes.subarray(iendStart, rangeEnd), outPos)
      outPos += rangeEnd - iendStart
      inserted = true
    } else {
      out.set(srcBytes.subarray(rangeStart, rangeEnd), outPos)
      outPos += rangeEnd - rangeStart
    }
  }
  return out
}

export class ImageExifService {
  private static instance: ImageExifService

  private constructor() {}

  static getInstance(): ImageExifService {
    if (!ImageExifService.instance) {
      ImageExifService.instance = new ImageExifService()
    }
    return ImageExifService.instance
  }

  // 写出后回读自检：对 dstPath 用系统 API 读 USER_COMMENT 验证写入效果并记日志。
  // 自检失败仅记日志，不改变返回值（诊断用途，锁定设备端写入真相）。
  private async verifyWrittenComment(dstPath: string): Promise<void> {
    let source: image.ImageSource | undefined = undefined
    try {
      source = image.createImageSource(dstPath)
      let options: image.ImagePropertyOptions = { index: 0, defaultValue: '' }
      let value = await source.getImageProperty(image.PropertyKey.USER_COMMENT, options)
      logInfo(`Verify USER_COMMENT readback OK (${utf8ByteLength(value)}b): ${value.substring(0, 50)}`)
    } catch (e) {
      logError(`Verify USER_COMMENT readback FAILED for ${dstPath}: ` + e)
    } finally {
      if (source !== undefined) {
        try {
          await source.release()
        } catch (e) {
          logError('Release verify image source failed: ' + e)
        }
      }
    }
  }

  // 返回 true = 嵌入成功并产出 dstPath；false = 失败降级（半成品已清理），调用方应保存原图。
  // 内部捕获全部异常，不向外抛出，保证元数据写入失败不阻断下载主流程。
  // 分流策略（plan D9/D12）：JPEG → EXIF + XMP 双写；PNG → XMP iTXt 写入；GIF 等其他格式不嵌入。
  async embedExif(srcPath: string, dstPath: string, info: ExifInfo): Promise<boolean> {
    let success = false
    try {
      let lowerDst = dstPath.toLowerCase()
      if (lowerDst.endsWith('.jpg') || lowerDst.endsWith('.jpeg')) {
        success = await this.embedJpeg(srcPath, dstPath, info)
      } else if (lowerDst.endsWith('.png')) {
        success = this.embedPng(srcPath, dstPath, info)
      } else {
        // GIF 等格式：维持不嵌入任何元数据的既有行为
        logInfo(`Skip metadata embed for unsupported format: ${dstPath}`)
      }
    } catch (e) {
      logError('Embed metadata failed, fallback to original image: ' + e)
    }
    if (!success) {
      // 清理可能已产出的半成品输出文件，避免残留
      try {
        if (fileIo.accessSync(dstPath)) {
          fileIo.unlinkSync(dstPath)
        }
      } catch (e) {
        logError('Delete partial metadata output file failed: ' + e)
      }
    }
    logInfo(`embedExif final result: success=${success ? 'true' : 'false'} for ${dstPath}`)
    return success
  }

  // JPEG 双写总控：起始即读入源文件字节（注入路径复用，避免二次读文件），
  // 用字节级 hasExifSegment 确定 EXIF 存在性——
  // 有 EXIF → 系统接口写入 + 重打包后注入 XMP APP1；无 EXIF → 原始字节注入手工 EXIF APP1 + XMP APP1。
  // 两载体写入相互独立，任一成功即返回 true，均失败返回 false 走降级。
  private async embedJpeg(srcPath: string, dstPath: string, info: ExifInfo): Promise<boolean> {
    let srcBytes: Uint8Array
    try {
      srcBytes = readFileBytes(srcPath)
    } catch (e) {
      logError(`Read source JPEG bytes failed (${srcPath}), fallback to original: ` + e)
      return false
    }
    let exifPresent = hasExifSegment(srcBytes)
    logInfo(`embedJpeg branch decision: hasExifSegment=${exifPresent ? 'true' : 'false'} ` +
      `(system api path=${exifPresent ? 'true' : 'false'}) for ${srcPath}`)
    if (exifPresent) {
      // 有 EXIF 分支：此时才创建 ImageSource（由 embedJpegViaSystemApi 内部创建并负责释放）
      return await this.embedJpegViaSystemApi(srcPath, dstPath, info)
    }
    // 无 EXIF 分支：传入已读字节，避免二次读文件
    return await this.embedJpegViaInjection(srcBytes, dstPath, info)
  }

  // 有 EXIF 分支（plan D9）：safeWriteExif 逐字段探测式截断写入 + packToData 重打包，
  // 再对重打包输出字节注入 XMP APP1（必须在重打包之后，否则 XMP 会被丢弃）。
  // EXIF 与 XMP 两载体相互独立：任一成功即写出 dstPath 返回 true；均失败返回 false。
  private async embedJpegViaSystemApi(srcPath: string, dstPath: string, info: ExifInfo): Promise<boolean> {
    let source: image.ImageSource | undefined = undefined
    let packer: image.ImagePacker | undefined = undefined
    let packedBytes: Uint8Array | undefined = undefined
    let exifOk = false
    try {
      source = image.createImageSource(srcPath)
      // IMAGE_DESCRIPTION: 图库通常不显示此字段
      await safeWriteExif(source, image.PropertyKey.IMAGE_DESCRIPTION, `${info.title} | PID:${info.illustId}`)
      // ARTIST: 作者信息
      await safeWriteExif(source, image.PropertyKey.ARTIST, `${info.userName} (UID:${info.userId})`)
      // USER_COMMENT: 图库"备注"显示此字段，按用户模板渲染
      await safeWriteExif(source, image.PropertyKey.USER_COMMENT, renderComment(info))
      // COPYRIGHT
      await safeWriteExif(source, image.PropertyKey.COPYRIGHT, 'Pixiv')
      packer = image.createImagePacker()
      let options: image.PackingOption = { format: 'image/jpeg', quality: 95, needsPackProperties: true }
      let data: ArrayBuffer = await packer.packToData(source, options)
      packedBytes = new Uint8Array(data)
      exifOk = true
    } catch (e) {
      logError('EXIF carrier failed (system write + repack): ' + e)
    } finally {
      if (packer) {
        try {
          await packer.release()
        } catch (e) {
          logError('Release packer failed: ' + e)
        }
      }
      if (source !== undefined) {
        try {
          await source.release()
        } catch (e) {
          logError('Release image source failed: ' + e)
        }
      }
    }

    // XMP 载体：在重打包输出（EXIF 失败时退回原始字节）上注入 XMP APP1
    let outBytes: Uint8Array | undefined = undefined
    let xmpOk = false
    try {
      let xmpSeg = buildXmpApp1Segment(buildXmpPacket(info))
      let baseBytes = packedBytes !== undefined ? packedBytes : readFileBytes(srcPath)
      outBytes = injectJpegSegments(baseBytes, undefined, xmpSeg)
      xmpOk = true
    } catch (e) {
      logError('XMP carrier failed (JPEG APP1 inject after repack): ' + e)
    }

    if (!exifOk && !xmpOk) {
      logError('Both EXIF and XMP carriers failed for JPEG (system path), fallback to original')
      return false
    }
    if (outBytes === undefined) {
      // 仅 EXIF 载体成功：直接写出重打包字节
      outBytes = packedBytes
    }
    if (outBytes === undefined) {
      return false // 防御：理论上不可达
    }
    try {
      writeFileBytes(dstPath, outBytes)
    } catch (e) {
      logError('Write embedded JPEG output failed: ' + e)
      return false
    }
    // 写出后回读自检（仅记日志，不影响返回值）
    await this.verifyWrittenComment(dstPath)
    return true
  }

  // 无 EXIF 分支（plan D9/D13）：不重编码，向原始字节（由 embedJpeg 读入并传入）注入手工构造的
  // EXIF APP1 与 XMP APP1。两载体独立构造：任一成功即注入写出返回 true；均失败返回 false 走降级。
  private async embedJpegViaInjection(srcBytes: Uint8Array, dstPath: string, info: ExifInfo): Promise<boolean> {
    let exifSeg: Uint8Array | undefined = undefined
    let xmpSeg: Uint8Array | undefined = undefined
    try {
      exifSeg = buildExifSegment(info)
    } catch (e) {
      logError('EXIF carrier failed (manual APP1 build): ' + e)
    }
    try {
      xmpSeg = buildXmpApp1Segment(buildXmpPacket(info))
    } catch (e) {
      logError('XMP carrier failed (APP1 build): ' + e)
    }
    if (exifSeg === undefined && xmpSeg === undefined) {
      logError('Both EXIF and XMP segments failed to build, fallback to original')
      return false
    }
    try {
      let outBytes = injectJpegSegments(srcBytes, exifSeg, xmpSeg)
      writeFileBytes(dstPath, outBytes)
    } catch (e) {
      logError(`Metadata inject failed (EXIF segment ${exifSeg !== undefined ? 'ready' : 'failed'}, ` +
        `XMP segment ${xmpSeg !== undefined ? 'ready' : 'failed'}): ` + e)
      return false
    }
    // 写出后回读自检（仅记日志，不影响返回值）
    await this.verifyWrittenComment(dstPath)
    return true
  }

  // PNG 分支（plan D12）：写入 XMP iTXt chunk（keyword "XML:com.adobe.xmp"），插入 IEND 前，
  // 不触碰像素数据；失败返回 false 走既有降级（保存原图、下载成功）。
  private embedPng(srcPath: string, dstPath: string, info: ExifInfo): boolean {
    try {
      let itxtChunk = buildPngItxtChunk(buildXmpPacket(info))
      let srcBytes = readFileBytes(srcPath)
      let outBytes = injectPngItxt(srcBytes, itxtChunk)
      writeFileBytes(dstPath, outBytes)
      return true
    } catch (e) {
      logError('XMP carrier failed (PNG iTXt inject): ' + e)
      return false
    }
  }
}

export const imageExifService = ImageExifService.getInstance()
