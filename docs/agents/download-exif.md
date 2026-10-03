# 下载、EXIF 与 Ugoira 动图

> 从 AGENTS.md 拆分。改动下载管线/图库写入/EXIF/动图时阅读并同步更新本文档。

## 下载管线

- `DownloadService` 单例：下载到 `cacheDir/downloads/`，写图库走双通道（见下）
- **写图库双通道（勿回退）**：`WRITE_IMAGEVIDEO` 是 ACL 白名单权限（普通签名装不上，安装报 9568289），`WRITE_MEDIA/READ_MEDIA` 声明对媒体库无效。①**静默通道**：`applySilentToGallery`（`MediaAssetChangeRequest.createImageAssetRequest` + `applyChanges`）——仅在 **SaveButton 安全控件点击后的临时授权窗口内**可用（首次点击 SaveButton 系统弹一次授权，之后不弹；API≤19 窗口 10s，API≥20 窗口 1 分钟）；②**兜底通道**：静默失败的路径攒入 `pendingGalleryPaths`，队列排空后 `flushGalleryIfIdle` 一次 `showAssetsCreationDialog` 批量系统确认弹窗——**该弹窗只创建目标 uri，必须用 `fileIo.copyFile` 把沙箱内容拷入**，否则媒体库是空壳不显示（历史"保存成功但图库无图"根因）
- **多任务并发调度层**：公开入口 `enqueue(url, illust, pageIndex)`（fire-and-forget）：先写 DB `pending` 记录入内存 FIFO 队列，`activeCount < 上限` 立即执行否则排队，任务结束补位；上限每次调度时读 `userSettingStore.getSettings().downloadConcurrency`（1-5 默认 3，配置即时生效，进行中任务不受影响）；`downloadToCache` 已转 private，任务体=下载+finalize+静默写图库（失败攒批）+状态落库+notifyTaskChanged；`retryAllFailed` 内部走 enqueue（started=入队数，succeeded/failed 不再同步统计）；`inflightTaskIds` 在途去重防止同一页并发重复入队（R4：`enqueue` 同步返回 `'enqueued' | 'inflight'`，调用点据结果 toast——inflight→"已在下载队列中"（dl_already_in_queue），多页汇总=全部在途才报在途、部分入队报已加入；fire-and-forget 特性不变）；下载时自动收藏（autoBookmarkOnDownload）在入队时触发（非完成时）；应用重启后残留 pending/downloading 按既有规则重置 failed，不自动恢复排队；完成/失败有 toast（showToastSafe：已保存到图库 / 已保存 N 张到图库 / 下载失败）
- 下载任务状态：`pending`（排队中）/ `downloading` / `completed` / `failed`，DownloadPage 列表展示"排队中"
- 文件名模板：默认 `{illust_id}_p{part}`，支持 `{user_id}`、`{user_name}`、`{title}`。模板在 `FilenameTemplatePage` 配置。
- `ImageExifService`：嵌入 EXIF 元数据（ImageDescription=`{title} | PID:{id}`、Artist=`{userName} (UID:{id})`、UserComment=模板渲染、Copyright='Pixiv'），另写 XMP 旁挂（JPEG APP1 / PNG iTXt），字段值超 120 UTF-8 字节时截断（`clampExifField`）。按格式分流：JPEG 保留 JPEG（系统 API 重打包或字节级注入不重编码）、PNG 保留 PNG（`embedPng` 系统 API EXIF + iTXt XMP 双载体，失败降级纯 XMP）、GIF 不嵌入。
- 下载任务状态通过 `DatabaseService` 追踪（pending/downloading/completed/failed）。DB 初始化时将 downloading/pending 重置为 failed。
- `DownloadService` 批量/去重方法：`isDownloaded(illustId, part)`（completed 记录 + `fs.access` 文件存在双条件，DB 异常降级 false）；`retryAllFailed()`（failed 任务逐条重建入队，onTaskDone 回调，返回分类计数 `RetryAllResult{started,succeeded,failed,skipped}`，started=入队数，succeeded/failed 不再同步统计，元信息缺失计 skipped）；`clearTasksByStatus(status)`（仅删记录不删文件，返回删除数）。DB 侧配套 `getDownloadTaskById` / `deleteDownloadTasksByStatus`
- 任务变更事件：DownloadService `register/unregisterTaskChangeListener` 回调注册表，任务完成/失败时触发；DownloadPage 可见期注册 + 1.5s 轮询静默刷新（refreshTasksSilently 不置 isLoading 防闪烁），aboutToDisappear 清理
- **DownloadPage R3 增强（对齐 pixez JobPage）**：①行首 56vp 缩略图由内联 `TaskThumb` 子组件承载——`Image('file://' + localPath)` 优先，`onError`（本地文件被清理）置 `useLocal=false` 回退 `CachedImage(image_url)`（自带加载/错误占位），独立 @State 规避 ForEach 同 key 复用陷阱；②点击任务行 `openTaskDetail` 注册 DetailListContextRegistry（ids=当前筛选可见任务按 illust_id 去重保序、nextUrl=''、fetchNext 返回空页，同 HistoryPage 无续页模式）跳详情可左右滑动，行内"重试"按钮 onClick 不冒泡到父行；③标题栏下状态筛选 chips（全部/进行中=pending+downloading/已完成/失败，选中高亮 #0096FA），`getFilteredTasks()` 纯展示层过滤供 ForEach，1.5s 轮询只更新数据源不打断筛选，批量按钮语义不变作用于全部任务，空筛选结果显示 EmptyView"无匹配任务"
- 下载重复检测：所有下载入口（详情页 savePage/savePages/saveAll、查看器保存、卡片长按保存）先按 插画ID+页码 查 `isDownloaded`，命中统一走 `getUIContext().showAlertDialog`（跳过已下载页/全部重新下载，`AlertDialog.show` 静态方法已废弃不可用）；`IllustDetailStore.uiContext` 由宿主页面 aboutToAppear 注入。saveAll 的原 showActionSheet 例外已迁移为 AlertDialog，ActionSheet 例外清零

## Ugoira 动图

- Pixiv "GIF 动图"实为 ugoira 格式（`illust.type === 'ugoira'`）：动画数据不在图片 URL 里，而在 `GET /v1/ugoira/metadata?illust_id=` 返回的 zip 帧包（`zip_urls.medium`）+ 每帧延迟（`frames[{file, delay}]`）；普通图片 URL 只是静态封面。模型 `models/UgoiraMetadata.ets`（UgoiraFrame/UgoiraMetadata/UgoiraCacheMeta + 序列化纯函数），`ApiService.getUgoiraMetadata` 返回类型化模型。
- **UgoiraService**（单例）：`getPlayback(illustId, onProgress?)`（内存缓存 + in-flight 去重；帧解压缓存 `cacheDir/ugoira/<id>/` + meta.json 帧数校验，播放与下载共用；zip 下载镜像 ImageCacheService 图床分流 relay/直连 IP/Referer/UA；解压用 `zlib.decompressFile`）+ `encodeToGif(illustId, outPath, onProgress?)`（逐帧 decode PixelMap → 系统 `ImagePacker.packToFileFromPixelmapSequence` 原生 GIF 编码，API 18+；delayTimeList 单位 10ms 且须 >0，loopCount 0=无限循环；HarmonyOS 动画编码仅 GIF，无动画 WebP 编码 API）。
- **播放**：`components/illust/UgoiraPlayer`（ImageAnimator + ImageFrameInfo 逐帧 duration + iterations(-1) 无限循环，封面 CachedImage 常渲染底层兜底，加载失败静默停留封面；ImageAnimator 无 objectFit，默认 fixedSize 拉伸到组件尺寸，组件 aspectRatio 定比例）；详情页 ImageRow 与查看器 ugoira 分支接入，卡片/详情角标 "GIF"。
- **下载**：`DownloadService.enqueueUgoira(illust)`（taskId `<id>_ugoira`，DB 记录 page_index=-1、image_url=封面 URL 供缩略图）→ runUgoiraTask（encodeToGif → finalize 模板命名 .gif → 既有写图库双通道；ext='gif' 天然跳过 EXIF 嵌入）；`isUgoiraDownloaded(id)`/`getUgoiraLocalPath(id)`（page_index=-1 completed + 文件存在）；retryAllFailed 对 page_index=-1 路由回 enqueueUgoira；DownloadPage page_index=-1 显示"动图"；详情页/查看器保存与卡片长按直存对 ugoira 统一分流 enqueueUgoira，跳过合并审查/EXIF Picker/多页选页弹窗；查看器 ugoira 分支隐藏 HD 切换，分享改为分享已下载 GIF（未下载置灰提示）。

## EXIF 标签系统

### 核心数据结构

- `ExifTag`: `{ name: string, translatedName: string }` — 原始 tag 名 + API 翻译名（定义在 `services/ImageExifService.ets`）
- `ExifTagMergeRule`: `{ mainTag: string, fromTags: string[] }` — 去重式合并规则（定义在 `models/AppSettings.ets`）
- `MergeGroup`: `{ translatedName: string, tags: ExifTag[] }` — 同义 tag 组（审查弹窗用，定义在 `services/ImageExifService.ets`）
- `AppSettings` EXIF 相关字段：`embedExifMetadata`、`exifCommentTemplate`、`exifMutedTags`、`exifMergedTags`、`exifTagPriority`、`showTranslatedTags`

### 翻译过滤（filterTranslatedName）

Pixiv API 在 `Accept-Language: zh-CN` 时会将 CJK tag "翻译"成英文（爱莉希雅→Elysia），对中文用户无意义。
- `Constants.filterTranslatedName(tagName, translatedName)`：tagName 含 CJK + translatedName 纯 ASCII → 视为无意义翻译，返回空串
- 日文→英文同理被过滤（エリシア→Ellicia）
- 所有显示和 EXIF 写入点统一调用此函数（例外：合并审查弹窗内有意展示原始未过滤的 translatedName，供用户判断同义关系）

### EXIF 标签处理管线（filterTagsForExif）

4 步管线，输入 `ExifTag[]` + `AppSettings`，输出过滤后 `ExifTag[]`：
1. **屏蔽**：移除 `exifMutedTags` 中的 tag
2. **手动合并**：遍历 `exifMergedTags` 规则——mainTag 在列表则移除 fromTags；mainTag 不在则将首个 fromTag 替换为 mainTag（保留翻译名）
3. _(Step 2.5 已移除自动合并，改由审查弹窗处理)_
4. **优先级排序**：按 `exifTagPriority` 顺序排前，其余保持原序追加

### 同义标签合并检测（findUnresolvedMergeGroups）

3 种检测方式（审查弹窗本身需用户确认）：
- **A) 原始 translatedName 相同**：如 女の子/女孩子 都翻译为"女孩子"
- **B) 有效翻译匹配另一 tag 名**：如 崩壊3rd→崩坏3rd + tag 崩坏3rd 存在；崩坏3rd→崩坏3 + tag 崩坏3 存在
- **C) CJK→ASCII 被过滤的翻译匹配另一 tag 名**：如 爱莉希雅→Elysia（过滤）+ tag Elysia 存在

排除已在 `exifMergedTags` 规则中覆盖的组（组内所有 tag 名都在**所有规则**的 mainTag/fromTags **并集**中，允许跨多条规则拼覆盖）。

### 合并审查弹窗流程

1. 时机：点击**保存**按钮时触发（`handleSavePage/handleSaveAll`），不在页面加载时打断
2. `hasUnresolvedMergeGroups()` 预检 → `checkMergeReview()` 弹窗
3. 用户每组选一个主 tag → 确认 → 写入 `exifMergedTags` 规则 → toast 提示"请再次点击保存"
4. 跳过则不持久化，下次保存仍会弹出
5. 弹窗内层内容区用 `.onClick(() => {})` 消费点击事件防止冒泡到外层遮罩关闭弹窗；禁止对覆盖层容器使用 `.hitTestBehavior(HitTestMode.Block)`——实测会导致自带手势子组件选中需点两次/有延迟（cd20189），且会完全挡住 TextInput/按钮交互（MergeDialogOverlay 原 Block 已移除，统一为 .onClick 方案）

### EXIF Picker（IllustDetailPage 内联底部弹层）

- 实现形态：IllustDetailPage 内联 Stack 底部弹层（`exifPickerShown`）
- 触发：渲染后的 EXIF 备注超 **120 UTF-8 字节**（`EXIF_FIELD_MAX_BYTES`，设备图库扫描器约 128 字节上限）且 `embedExifMetadata` 开启时，保存前弹出（在合并审查通过之后）
- 可写入区：勾选/取消勾选（取消=跳过本次，不持久化）；拖拽排序（`onMove`，确认后写入 `exifTagPriority`）；长按屏蔽手势仅绑在左侧 Checkbox+文字区域，右侧把手 `≡` 不绑长按以避免与拖拽排序冲突
- 长按 tag → 二次确认 → 移入弹层内屏蔽区列表；点"确认"时才写入 `exifMutedTags` 持久化（点"跳过"则屏蔽不持久化）
- 屏蔽区"恢复"按钮移回可写入区
- 预览区实时显示渲染结果和字节数（x / 120 字节，超限变红）

### 模板变量

- `{tags}`：原始 tag 名（逗号分隔）
- `{tags_translated}`：带翻译的 tag 输出（tag名(翻译) 格式）
- `{tags_localized}`：纯目标语言 tag 输出（优先中文翻译，无翻译保留原文）
- 替换顺序：`{tags_localized}` → `{tags_translated}` → `{tags}`（最长前缀优先防误替换）
- 其他变量：`{illust_id}`、`{user_id}`、`{user_name}`、`{title}`、`{part}`

### EXIF 标签管理页（ExifTagConfigPage）

- 查看/编辑合并规则、屏蔽列表、优先级排序
- 导入/导出（JSON 格式）
