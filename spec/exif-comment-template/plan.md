# Implementation Plan: EXIF 备注模板自定义

**Input**: Feature specification from `spec/exif-comment-template/spec.md`

## Summary

将 EXIF 备注（UserComment）内容从硬编码改为模板化：新增 `exifCommentTemplate` 设置项（默认 `PID:{illust_id} | {tags}`）并持久化；新建备注模板编辑页（复用文件名模板页的交互模式）；下载写入元数据时由 `ImageExifService` 读取模板并渲染。模板变量在文件名模板变量基础上新增 `{tags}`（仅原文）与 `{tags_translated}`（带翻译）。

**修复（2026-07-23，第三轮：EXIF+XMP 双写）**：设备实证确认根因——HarmonyOS `modifyImageProperty` 仅支持**已包含 EXIF** 的图片，Pixiv 部分图片 EXIF 段被剥离，系统接口写入必然全部失败（62980123），与备注长度无关。修复策略：

1. **JPEG：EXIF + XMP 双重写入**（最大兼容性）——先探测源图 EXIF 存在性：有 EXIF 走 `modifyImageProperty`（探测式逐级截断）+ `packToData` 重打包；无 EXIF 手工构造 EXIF APP1 段注入原始字节流（不重编码）；两条路径最终都再注入 XMP APP1 段。两载体写入相互独立，任一失败不影响另一载体，两者均失败才降级。
2. **PNG 等无法写 EXIF 的格式：XMP 写入**——手工构造 iTXt chunk（keyword `XML:com.adobe.xmp`）插入原始字节流。
3. 全部载体失败 → 降级保存原始图片，下载任务照常标记成功（已实现，保留）。

## Technical Context

**Language/Version**: ArkTS（严格模式，禁止 any/unknown/as 断言/动态访问）  
**Primary Dependencies**: `@ohos.multimedia.image`（EXIF 探测/有 EXIF 时的写入与打包）、`@kit.CoreFileKit`（文件字节读写）、`@kit.ArkTS`（TextEncoder 等）、项目内 `PreferenceService`（KV 持久化）  
**Storage**: PreferenceService KV 存储，key 为 `exif_comment_template`  
**Testing**: 手动验证（构建 + 模拟器下载图片查看图库备注 / 文件字节检查）  
**Target Platform**: HarmonyOS API 12+（SDK 6.1.0）  
**Project Type**: mobile-app（现有 Pixiv 客户端单模块 entry）  
**Performance Goals**: 段构造与字节拼接为纯内存操作，无性能要求  
**Constraints**: `modifyImageProperty` 仅支持已含 EXIF 的 JPEG；JPEG APP1 段最大 0xFFFD 字节；PNG chunk 需合法 CRC32；截断按 UTF-8 字节数且不切断多字节字符；ArkTS 严格模式  
**Scale/Scope**: 修改 2 个现有文件（`ImageExifService.ets` 为主、`DownloadService.ets` 微调），无新增文件

## Project Structure

### Documentation (this feature)

```text
spec/exif-comment-template/
├── spec.md              # 需求规格（Phase 1 输出）
├── plan.md              # 本文件（Phase 2 输出）
└── tasks.md             # 任务列表（Phase 3 输出）
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── models/
│   └── AppSettings.ets                    # [已有] exifCommentTemplate 字段
├── stores/
│   └── UserSettingStore.ets               # [已有] 模板加载/保存/拷贝/setExifCommentTemplate
├── services/
│   ├── ImageExifService.ets               # [修改] EXIF 探测分流；无 EXIF JPEG 手工注入 EXIF APP1；JPEG/PNG 手工注入 XMP；CRC32；返回 boolean 不抛错
│   └── DownloadService.ets                # [已有] finalizeDownload 降级保存原图（本轮按需微调）
└── pages/
    └── settings/
        ├── ExifTemplatePage.ets           # [已有] 备注模板编辑页
        └── SettingsPage.ets               # [已有] 编辑页入口

entry/src/main/resources/base/profile/
└── main_pages.json                        # [已有] 已注册 pages/settings/ExifTemplatePage
```

**Structure Decision**: 遵循现有项目架构（`pages/`、`services/`、`stores/`、`models/` 分层 + router 页面导航），不引入 MVVM 目录或重构。本次修复仅触及 `services/` 层，无新增文件。

## Complexity Tracking

> 无违规项，无需记录。

## Research & Decisions

### D1: 模板读取位置 —— ImageExifService 内部读取

- **Decision**: `embedExif` 内部通过 `userSettingStore.getSettings().exifCommentTemplate` 读取模板并渲染。
- **Rationale**: 调用方 2 处自动生效；设置变更即时生效。
- **Alternatives considered**: 参数传入 —— 被否决。

### D2: 变量替换顺序 —— 长变量名优先

- **Decision**: `{tags_translated}` 先于 `{tags}` 执行 `replaceAll`。
- **Rationale**: 前缀包含关系，反序产生脏文本。
- **Alternatives considered**: 正则单次扫描 —— 被否决。

### D3: `{part}` 变量数据来源 —— ExifInfo 增加 pageIndex

- **Decision**: `ExifInfo` 含 `pageIndex: number`；`DownloadService.buildExifInfo` 传入。
- **Rationale**: FR-003；多页作品每页备注含各自页码。
- **Alternatives considered**: 不支持 `{part}` —— 被否决。

### D4: 未定义占位符处理 —— 原样保留

- **Decision**: 仅替换 7 个已知变量，其余原样保留。
- **Rationale**: FR-008；replaceAll 链天然实现。
- **Alternatives considered**: 校验报错 —— 被否决。

### D5: 空模板回退 —— 编辑页保存时兜底

- **Decision**: trim 为空则写入默认值 `PID:{illust_id} | {tags}`。
- **Rationale**: 复用既有交互模式；渲染侧无需判空。
- **Alternatives considered**: 渲染侧判空 —— 被否决。

### D6: 有 EXIF 时的超长写入策略 —— 探测式逐级截断（已实现，保留）

- **Decision**: `safeWriteExif` 第一轮写入完整值；失败后按 UTF-8 字节指数退避截断（每轮约 1/2，保底约 50 字节）附加 `...` 重试；保底失败放弃该字段不阻断其他字段。
- **Rationale**: 设备实际容量不可预知，以实际写入结果为准（FR-006）。
- **Alternatives considered**: 固定上限 / 二分查找 —— 被否决。

### D7: 失败不阻断下载 —— embedExif 返回结果、DownloadService 降级（已实现，保留）

- **Decision**: `embedExif` 返回 `Promise<boolean>` 不抛异常；`DownloadService.finalizeDownload`：true → 使用输出文件；false → 临时文件重命名为 `baseName.<原扩展名>`，下载照常 completed。
- **Rationale**: FR-009。
- **Alternatives considered**: 抛异常由调用方 catch —— 被否决。

### D8: 根因定位 —— modifyImageProperty 要求源图已含 EXIF（设备实证）

- **Decision**: 确立根因：官方文档明确 `getImageProperty`/`modifyImageProperty` "需要包含Exif信息"；Pixiv 部分图片 EXIF 段被剥离 → 全部字段写入报 62980123。问题图 `146416153_p0.jpg` 实证：连 5 字节 ASCII 的 Copyright 均未写入。与备注长度无关；有 EXIF 的图可成功（符合用户观察）。
- **Rationale**: 设备日志（MediaLibrary/ImageSourceNapi 62980123）+ 用户交叉验证。
- **Alternatives considered**: 继续调整截断参数 —— 被证据否定。

### D9: JPEG 修复策略 —— 探测分流 + EXIF/XMP 双写（本轮核心）

- **Decision**: `embedExif` 对 JPEG 的流程：
  1. **探测**：`getImageProperty`（带默认值）抛 62980123 → 无 EXIF；正常返回 → 有 EXIF；其他异常按无 EXIF 处理并记日志（spec Edge Case）。
  2. **EXIF 载体**：
     - 有 EXIF：`safeWriteExif`（D6）逐字段写入 + `packToData`（`needsPackProperties: true`）重打包，得到中间字节；
     - 无 EXIF：读取原始字节，剥离已有 APP1 Exif/XMP 段（防御），插入手工构造的 EXIF APP1 段（D10），不重编码。
  3. **XMP 载体**：无论 EXIF 路径结果如何，对当前输出字节再注入 XMP APP1 段（先剥离已有 XMP APP1 防重复）。有 EXIF 路径中 XMP 注入发生在 `packToData` 之后（否则重打包会丢弃 XMP）。
  4. **结果判定**：EXIF 与 XMP 两载体写入相互独立；任一成功即返回 true（输出文件含成功载体的数据）；两者均失败返回 false 走 D7 降级。
- **Rationale**: FR-005（双写最大兼容性）；手工注入不依赖系统对源图 EXIF 的要求；XMP 作为第二载体覆盖"图库/查看器只读 XMP"的场景。
- **Alternatives considered**: (a) 仅 EXIF 单写 —— 用户明确要求双写，被否决；(b) 全部格式统一手工注入（有 EXIF 的图丢失源 EXIF）——被否决；(c) 无 EXIF 图先重编码再 modifyImageProperty —— 重编码是否产生可修改 EXIF 段无官方承诺且有画质损失，被否决。

### D10: 手工 EXIF APP1 段格式（无 EXIF JPEG 分支，第四轮修正）

- **Decision**: 最小合法 EXIF 结构（小端 TIFF）：`FFE1` + 长度（大端）+ `Exif\0\0` + TIFF 头（`II`、`0x002A`、IFD0 偏移 8）+ **IFD0**（ImageDescription 0x010E / Artist 0x013B / Copyright 0x8298 ASCII + **ExifIFDPointer 0x8769（LONG，指向 Exif SubIFD）**）+ **Exif SubIFD**（**UserComment 0x9286** UNDEFINED 带 8 字节 `ASCII\0\0\0` 前缀 + UTF-8 字节）。段容量约 64KB，触顶时按 UTF-8 字节安全截断 UserComment（防御，实际不会触顶）。
- **Rationale**: **第四轮实证修正**——初版实现把 UserComment 直接放在 IFD0，经 piexif 本地复现验证：严格解码器只从 Exif SubIFD 读取 UserComment，IFD0 中的 0x9286 被忽略（piexif 读出 `UserComment=None`，而 ImageDescription/Artist 正常），这与设备上"手工注入路径备注丢失、系统接口路径备注正常"的现象完全吻合。修正后经 piexif/PIL 验证：UserComment（含日文 UTF-8）完整可读，JPEG 结构完整。`ASCII\0\0\0` + UTF-8 前缀维持不变（业界事实标准）。
- **Alternatives considered**: UNICODE 前缀 + UTF-16BE —— 兼容性不如前者，被否决（遗留风险：如图库显示异常再调整）。

### D11: XMP 数据包内容与字段映射

- **Decision**: 构造标准 XMP packet（`x:xmpmeta` + RDF，`http://ns.adobe.com/xap/1.0/` 命名空间），字段映射与 EXIF 使用同一份模板渲染结果（FR-004）：
  - `dc:description` ← 模板渲染的备注全文（与 UserComment 一致）；
  - `dc:title` ← 作品标题（与 ImageDescription 对应）；
  - `dc:creator` ← 作者名（与 Artist 对应）；
  - `xmp:Rights`/`dc:rights` ← 'Pixiv'（与 Copyright 对应）。
  XML 特殊字符（`&<>"'`）必须转义；内容按 UTF-8 编码。
- **Rationale**: Dublin Core 是 XMP 最通用的元数据字段集，查看器支持面最广；与 EXIF 字段一一对应保证"同一渲染结果、双载体一致"。
- **Alternatives considered**: 仅写 dc:description 单字段 —— 字段集合与 EXIF 对齐更一致，成本相当，被否决。

### D12: XMP 载体格式 —— JPEG APP1 / PNG iTXt

- **Decision**:
  - **JPEG**：XMP 存于独立 APP1 段，段头 `FFE1` + 长度 + 29 字节标识 `http://ns.adobe.com/xap/1.0/\0` + XMP packet；与 EXIF APP1 共存（两个 APP1 段合法）。注入前剥离已有 XMP APP1 防重复。
  - **PNG**：XMP 存于 iTXt chunk：keyword `XML:com.adobe.xmp` + `\0` + 压缩标志 `0` + 压缩方法 `0` + 语言 tag `\0` + 翻译 keyword `\0` + UTF-8 XMP packet；插入到 IEND 之前；chunk 需带合法 CRC32（对 chunk type + data 计算，IEEE 多项式，ArkTS 手工表驱动实现）。
  - PNG 写入失败或源字节非合法 PNG → 返回 false 走降级。
- **Rationale**: 两种载体均为各格式 XMP 的标准容器；PNG iTXt 不触碰 IDAT 像素数据（FR-012）；CRC32 无系统 API，表驱动实现为纯算术、可控可靠。
- **Alternatives considered**: PNG 用 zTXt 压缩 —— 无压缩库可用且不必要，被否决；PNG 写 eXIf chunk —— 用户已指定 XMP 路线，被否决。

### D13: 输出文件组装顺序与防重复

- **Decision**: 字节级组装统一规则：SOI（`FFD8`）→ 保留源文件非 EXIF/XMP 的其余段与图像数据 → 在 SOI 之后依次插入新 EXIF APP1（无 EXIF 分支）与新 XMP APP1。剥离规则：遍历源文件段，丢弃含 `Exif\0\0` 头（无 EXIF 分支）或 XMP 标识头的 APP1 段，其余原样保留。PNG：保留全部 chunk，仅在 IEND 前插入 iTXt（若已存在 `XML:com.adobe.xmp` iTXt 则先移除）。
- **Rationale**: 防止双 APP1/双 iTXt 冲突导致解析器行为不确定；保证输出文件结构合法。
- **Alternatives considered**: 直接追加不剥离 —— 双段冲突风险，被否决。

## Data Model

### AppSettings（已有，不变）

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `exifCommentTemplate` | `string` | `'PID:{illust_id} \| {tags}'` | EXIF 备注模板，持久化 key：`exif_comment_template` |

### ExifInfo（已有，不变）

`illustId` / `userId` / `title` / `userName` / `tags` / `createDate` / `pageIndex`

### 元数据嵌入分流总表（本轮核心）

| 源图 | EXIF 载体 | XMP 载体 | 输出 | 降级条件 |
|------|----------|---------|------|---------|
| JPEG 有 EXIF | `modifyImageProperty` 探测式截断 + `packToData` | 打包后注入 XMP APP1 | 重打包 JPEG + XMP | EXIF 与 XMP 均失败 |
| JPEG 无 EXIF | 注入手工 EXIF APP1（不重编码） | 注入 XMP APP1 | 原始字节 + EXIF APP1 + XMP APP1 | EXIF 与 XMP 均失败 |
| PNG | —（不支持） | 插入 iTXt（`XML:com.adobe.xmp`） | 原始字节 + iTXt | XMP 失败 |
| GIF | — | —（既有行为不嵌入） | 原始文件 | — |

### 手工 EXIF APP1 段结构（D10）

| 部分 | 内容 |
|------|------|
| 段标记 | `FF E1` + 长度（2 字节大端，含长度自身） |
| EXIF 头 | `45 78 69 66 00 00`（"Exif\0\0"） |
| TIFF 头 | 小端 `49 49 2A 00` + IFD0 偏移 `08 00 00 00` |
| IFD0 | 条目数 + 4 条目（0x010E/0x013B/0x8298 + **0x8769 ExifIFDPointer**）+ nextIFD `00 00 00 00` |
| Exif SubIFD | 条目数 + 1 条目（**0x9286 UserComment**，UNDEFINED）+ nextIFD `00 00 00 00` |
| 数据区 | >4 字节字段按偏移存放；ASCII 以 `\0` 结尾；UserComment 前缀 "ASCII\0\0\0" + UTF-8 |

### XMP 字段映射（D11）

| XMP 字段 | 内容来源 | 对应 EXIF 字段 |
|---------|---------|---------------|
| `dc:description` | 模板渲染备注全文 | UserComment |
| `dc:title` | 作品标题 | ImageDescription |
| `dc:creator` | 作者名（UID） | Artist |
| `dc:rights` | 'Pixiv' | Copyright |

### 嵌入结果（EmbedOutcome）

| 结果 | 表达 | 调用方行为 |
|------|------|-----------|
| 成功 | `embedExif` 返回 `true`（至少一个载体写入成功） | 使用输出文件，删除临时文件 |
| 失败 | `embedExif` 返回 `false`（全部载体失败） | 临时文件重命名为 `baseName.<原扩展名>`，下载标记成功 |

## Contracts & Interfaces

### ImageExifService（本轮变更）

| 方法 | 签名 | 说明 |
|------|------|------|
| embedExif | `(srcPath: string, dstPath: string, info: ExifInfo): Promise<boolean>` | 总控：按扩展名与 EXIF 探测分流（D9/D12）；任一载体成功返回 true；全失败返回 false；内部全异常捕获 |
| hasExif（模块内私有） | `(source: image.ImageSource): Promise<boolean>` | `getImageProperty` 探测，62980123 → false，其他异常 → false + 日志 |
| safeWriteExif（模块内私有） | `(source, key, value): Promise<void>` | 不变（D6，有 EXIF 分支逐字段写入） |
| buildExifSegment（模块内私有） | `(info: ExifInfo): Uint8Array` | 构造 EXIF APP1 段（D10） |
| buildXmpPacket（模块内私有） | `(info: ExifInfo): string` | 构造 XMP packet XML（D11，含转义） |
| buildXmpApp1Segment（模块内私有） | `(xmpPacket: string): Uint8Array` | JPEG XMP APP1 段（D12） |
| buildPngItxtChunk（模块内私有） | `(xmpPacket: string): Uint8Array` | PNG iTXt chunk（D12，含 CRC32） |
| injectJpegSegments（模块内私有） | `(srcBytes, exifSeg?: Uint8Array, xmpSeg?: Uint8Array): Uint8Array` | 剥离旧 EXIF/XMP APP1 + 插入新段（D13） |
| injectPngItxt（模块内私有） | `(srcBytes, itxtChunk: Uint8Array): Uint8Array` | 移除旧 XMP iTXt + IEND 前插入（D13） |
| crc32（模块内私有） | `(bytes: Uint8Array): number` | PNG chunk CRC32（表驱动） |

### DownloadService（既有，本轮按需微调）

| 方法 | 签名 | 说明 |
|------|------|------|
| finalizeDownload | `(tempPath, basePath, ext, shouldEmbedExif, illust, pageIndex, taskId, db): Promise<string>` | 不变；embedExif 内部分流，调用方无感知 |
| downloadToCache / downloadBypass | 不变 | 不变 |

### 既有契约（不变）

- `UserSettingStore.setExifCommentTemplate(value: string): void`
- 路由 `pages/settings/ExifTemplatePage`；SettingsPage 入口
- ExifTemplatePage 交互契约

## Changelog

| 时间 | 修改章节 | 变更说明 |
|------|---------|---------|
| 2026-07-24（第六轮，闭环） | tasks.md Phase 7 | 设备实证最终根因：MediaLibrary 入册扫描器对 EXIF 字段值有约 128 字节上限（备注 67b/123b 正常、148b/155b 整段被拒 62980123）。修复：EXIF 字段值统一截断 120 UTF-8 字节（UserComment 8 字节前缀+120=正好 128），XMP 保留完整内容。原问题图 146416153_p0 验证通过，全链路闭环 |
| 2026-07-24（第五轮） | tasks.md Phase 6 | 字节级 EXIF 检测（hasExifSegment 扫描源文件 APP1 段）替代 getImageProperty 探测；写出后 USER_COMMENT 回读自检；console.* → hilog（tag PixEzExif）。另发现：覆盖安装不会杀死运行中的旧进程，验证必须强制冷启动（aa force-stop + aa start） |
| 2026-07-23（第四轮） | plan D10 修正 | UserComment 从 IFD0 移入 Exif SubIFD（0x8769 指针），piexif 本地复现证实 IFD0 中 0x9286 被严格解码器忽略 |
| 2026-07-23（第三轮） | Summary、Technical Context、D9-D13、Data Model（分流总表/XMP 映射）、Contracts | 按用户决策改为 JPEG EXIF+XMP 双写、PNG XMP：新增 XMP packet 构造（dc 字段映射）、JPEG XMP APP1 与 PNG iTXt 载体、CRC32、段组装防重复规则；双载体独立写入、任一成功即嵌入成功 |
| 2026-07-23（第二轮） | Summary、D8/D9/D10、Data Model、Contracts | 根因实证（modifyImageProperty 需源图含 EXIF）；"先检测后分流"：无 EXIF JPEG 手工注入 EXIF 段 |
| 2026-07-23（第一轮） | D6-D9 等 | 探测式逐级截断；embedExif 返回布尔、失败降级不阻断下载（第一轮长度假设已被第二轮证据修正） |
