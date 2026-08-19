# PixEz Flutter 参考项目分析

> 来源：pixez-flutter（开源参考工程，本地分析、未入库）
> 分析时间：2026-07-02
> 用途：为鸿蒙 ArkTS 重写版提供实现参考

---

## 1. 自定义下载文件命名

### 核心实现
文件：`lib/store/save_store.dart` — 函数 `buildSaveFileName`（约 75-104 行）

```dart
Future<String> buildSaveFileName(
  Illusts illust,
  int index,
  String memType, {
  bool withExtension = true,
}) async {
  if (userSetting.fileNameEval == 1) {
    if (userSetting.nameEval != null) {
      final result = await JSEvalPlugin.eval(...);
      if (result != null && result.isNotEmpty) return result;
    } else {
      await userSetting.setFileNameEval(0);
    }
  }
  final result = userSetting.format!
      .replaceAll("{illust_id}", illust.id.toString())
      .replaceAll("{user_id}", illust.user.id.toString())
      .replaceAll("{part}", index.toString())
      .replaceAll("{user_name}", illust.user.name.toString())
      .replaceAll("{title}", illust.title);
  if (withExtension) {
    return "$result$memType".toLegal();
  }
  return result.toLegal();
}
```

**支持的模板变量：**
- `{illust_id}` — 作品 ID
- `{user_id}` — 作者用户 ID
- `{part}` — 页码索引
- `{user_name}` — 作者名
- `{title}` — 作品标题

文件名非法字符清理在 `lib/exts.dart` lines 52-62（`toLegal()`）。

### 相关设置键
文件：`lib/store/user_setting.dart`

| 设置 | Key | 默认值/说明 |
|---|---|---|
| 文件名模板 | `SAVE_FORMAT_KEY = "save_format"` | `'{illust_id}_p{part}'` |
| 启用 JS 命名 | `file_name_eval` | `0`=模板，`1`=JS 脚本 |
| JS 脚本体 | `NAME_EVAL_KEY = "name_eval"` | 自定义函数 |
| 单作者子目录 | `SINGLE_FOLDER_KEY` | `false` |
| 保存模式 | `SAVE_MODE_KEY` | `0` |

### UI 页面
- `lib/page/hello/setting/save_format_page.dart` — 模板编辑器
- `lib/page/hello/setting/save_eval_page.dart` — JS 高级命名编辑器

---

## 2. Tag 翻译机制

**Flutter 版没有调用专门的 tag 翻译 API。** 它通过 `Accept-Language` 请求头，让 Pixiv 标准 API 在返回中附带 `translated_name` 字段。

### 设置入口
文件：`lib/store/user_setting.dart` lines 700-707

```dart
@action
setLanguageNum(int value) async {
  await prefs.setInt(LANGUAGE_NUM_KEY, value);
  languageNum = value;
  ApiClient.Accept_Language = languageList[languageNum];
  apiClient.httpClient.options.headers[HttpHeaders.acceptLanguageHeader] =
      ApiClient.Accept_Language;
  locale = iSupportedLocales[languageNum];
}
```

`Accept_Language` 初始化为 `zh-CN`（`lib/network/api_client.dart` line 47）。

### 返回翻译字段的端点

| 端点 | 方法 | 翻译来源 |
|---|---|---|
| `GET /v1/illust/detail?filter=for_android` | `getIllustDetail` | `tags[].translated_name` |
| `GET /v1/trending-tags/illust?filter=for_android` | `getIllustTrendTags` | `trend_tags[].translated_name` |
| `GET /v1/trending-tags/novel?filter=for_android` | `getNovelTrendTags` | `trend_tags[].translated_name` |
| `GET /v2/search/autocomplete` | `getSearchAutoCompleteKeywords` | `tags[].translated_name` |
| `GET /v1/search/popular-preview/illust` | `getPopularPreview` | `include_translated_tag_results=true` |

### Tag 模型
文件：`lib/models/illust.dart` lines 230-241

```dart
@JsonSerializable()
class Tags {
  String name;
  @JsonKey(name: 'translated_name')
  String? translatedName;
  Tags({required this.name, this.translatedName});
}
```

---

## 3. 图片元数据（EXIF）

**Flutter 版没有写入 EXIF、XMP 或任何 tag 到图片文件。** 所有平台实现都只是把下载的字节数组直接保存。

- Android：`android/app/.../Imager.kt` — 只设置 `DISPLAY_NAME`、`MIME_TYPE`、`RELATIVE_PATH`。
- iOS：`ios/Runner/DocumentPlugin.swift` — 直接写入相册。
- Windows：`windows/runner/plugins/document_plugin.cpp` — 直接写入文件。

因此，鸿蒙版如果要实现相册按 tag 搜索，需要自行新增 EXIF 写入能力。

---

## 4. 下载原图的 URL 与请求头

### 关键发现：不要用 `illust.image_urls.original`
Flutter 保存时只下载原图，URL 取自：
- **单页作品**：`illusts.metaSinglePage!.originalImageUrl!`
  - 文件：`lib/store/save_store.dart` line 449
- **多页作品（指定页）**：`illusts.metaPages[index].imageUrls!.original`
  - 文件：`lib/store/save_store.dart` line 455
- **多页作品（全部）**：循环 `metaPages` 取 `f.imageUrls!.original`
  - 文件：`lib/store/save_store.dart` line 462

顶层 `ImageUrls` 模型（`lib/models/illust.dart` lines 179-192）只有 `squareMedium`、`medium`、`large`，**没有 `original`**。原图 URL 在：
- `MetaSinglePage.originalImageUrl`（`lib/models/illust.dart` lines 244-254）
- `MetaPagesImageUrls.original`（`lib/models/illust.dart` lines 34-52）

### 下载请求头
图片下载请求头（不是 API 调用）：

```dart
{
  'referer': 'https://app-api.pixiv.net/',
  'User-Agent': 'PixivIOSApp/5.8.0',
}
```

**注意：** 图片下载不需要 `Authorization`、哈希头等 API 头。

相关位置：
- `lib/er/fetcher.dart` lines 336-341（下载流）
- `lib/er/hoster.dart` lines 139-145（`Hoster.header()`）
- `lib/component/pixiv_image.dart` line 193（预览图也使用同一套头）

### 缺失原图 URL 的处理
Flutter 没有 fallback。如果 `originalImageUrl` 或 `metaPages.imageUrls.original` 为空，会直接抛空断言异常（`!` 操作）。没有从 `large` URL 构造原图的逻辑。

---

## 5. `filter=for_android` 的使用端点

文件：`lib/network/api_client.dart`

| 端点 | filter 值 |
|---|---|
| `/v1/novel/ranking` | `for_android` |
| `/v1/novel/recommended` | `for_android` |
| `/v1/user/recommended` | `for_android` |
| `/v1/user/detail` | `for_android` |
| `/v1/illust/ranking` | `for_android` |
| `/v1/user/illusts` | `for_android` |
| `/v1/trending-tags/illust` | `for_android` |
| `/v1/search/illust` | `for_android`（Android）/ `for_ios`（iOS） |
| `/v2/illust/related` | `for_android` |
| `/v1/illust/detail` | `for_android` |
| `/v1/illust/recommended` | `for_ios` |
| `/v1/manga/recommended` | `for_ios` |

---

## 6. 保存到相册流程

1. Dart 下载到临时目录（`flutter_cache_manager`）。
2. `lib/er/fetcher.dart` 读取临时文件字节。
3. `lib/store/save_store.dart` 的 `saveToGallery` / `saveToGalleryWithUser` 通过 `DocumentPlugin.save` 把字节传给原生层。
4. 原生层直接写字节到系统相册，**不做任何重编码**。

---

## 7. 其他设置

文件：`lib/store/user_setting.dart`

| 设置 | Key | 作用 |
|---|---|---|
| H 内容过滤 | `h_is_not_allow` | 隐藏 `R-18` 标签作品 |
| 收藏时自动 tag | `AUTO_TAG_WHEN_STAR_KEY` | 收藏时使用已有标签 |
| AI 作品标识 | `FEED_AI_BADGE_KEY` | 缩略图显示 AI 标识 |

---

## 8. 对鸿蒙版的迁移建议

基于以上分析，鸿蒙版实现时应：
1. 文件名模板变量与 Flutter 保持一致：`{illust_id}`、`{user_id}`、`{part}`、`{user_name}`、`{title}`。
2. Tag 翻译依赖 `Accept-Language` + 标准 API 返回的 `translated_name`。
3. 原图 URL 从 `meta_single_page.original_image_url`（单页）和 `meta_pages[].image_urls.original`（多页）读取。
4. 图片下载请求头使用 `Referer: https://app-api.pixiv.net/` 和 `User-Agent: PixivIOSApp/5.8.0`，不需要 `Authorization`。
5. 需要 `filter=for_android` 的端点要加上该参数。
6. 如要写入 EXIF 让相册可搜 tag，必须自行实现，因为 Flutter 版没有参考实现。
