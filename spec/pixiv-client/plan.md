# Implementation Plan: Pixiv Client ArkTS Rewrite

**Input**: Feature specification from `spec/pixiv-client/spec.md`

## Summary

Rewrite the PixEz Flutter project as a HarmonyOS ArkTS application. The app uses a layered architecture with clear separation between data, state, and UI layers. Core features include OAuth2 authentication, illustration/novel browsing, search, bookmarks, downloads, and user interactions. Implementation follows a phased approach: P1 core browsing first, P2 social features, P3 advanced settings.

## Technical Context

- **Language/Version**: ArkTS (HarmonyOS API 12+)
- **Primary Dependencies**: `@kit.NetworkKit` (http), `@kit.ArkData` (relationalStore, preferences), `@kit.ArkUI` (Navigation, Tabs, LazyForEach), `@kit.BasicServicesKit` (BusinessError, crypto)
- **Storage**: Preferences (settings KV), RelationalStore (SQLite for structured data), AppStorage (runtime global state)
- **Target Platform**: HarmonyOS phones (API 12+, 2in1/Tablet adaptive)
- **Performance Goals**: Home feed first load <3s, search response <2s, smooth 1000+ item list scrolling
- **Constraints**: No `any`/`unknown` types, strict static typing, no runtime dynamic property addition
- **Scale**: ~30 pages, ~50 custom components, 5+ stores, 40+ API endpoints

## Project Structure

```text
entry/src/main/ets/
├── ability/
│   └── EntryAbility.ets
├── pages/
│   ├── splash/SplashPage.ets
│   ├── login/LoginPage.ets
│   ├── home/HomePage.ets (Tabs container)
│   ├── home/RecomPage.ets
│   ├── home/RankPage.ets
│   ├── home/NewPage.ets
│   ├── search/SearchPage.ets
│   ├── search/SearchResultPage.ets
│   ├── detail/IllustDetailPage.ets
│   ├── user/UserProfilePage.ets
│   └── settings/SettingsPage.ets
├── components/
│   ├── common/ (LoadingView, ErrorView, EmptyView)
│   ├── illust/ (IllustCard, IllustList, IllustImage)
│   ├── user/ (UserAvatar)
│   └── comment/ (CommentItem)
├── stores/
│   ├── AccountStore.ets
│   ├── UserSettingStore.ets
│   ├── HomeStore.ets
│   ├── SearchStore.ets
│   ├── IllustDetailStore.ets
│   ├── UserStore.ets
│   ├── BookmarkStore.ets
│   ├── HistoryStore.ets
│   └── DownloadStore.ets
├── models/
│   ├── Illust.ets
│   ├── User.ets
│   ├── Novel.ets
│   ├── Comment.ets
│   ├── Bookmark.ets
│   ├── SearchHistory.ets
│   ├── MuteItem.ets
│   ├── DownloadTask.ets
│   └── AppSettings.ets
├── network/
│   ├── HttpClient.ets
│   ├── AuthInterceptor.ets
│   ├── RetryInterceptor.ets
│   ├── CacheInterceptor.ets
│   ├── ApiService.ets
│   ├── OAuthService.ets
│   └── PixivEndpoints.ets
├── services/
│   ├── ImageCacheService.ets
│   ├── DownloadService.ets
│   ├── PreferenceService.ets
│   ├── DatabaseService.ets
│   └── WebViewService.ets
└── utils/
    ├── Constants.ets
    ├── CryptoUtils.ets
    ├── DateUtils.ets
    └── StringUtils.ets
```

## Research & Decisions

### Decision 1: HTTP Client — `@kit.NetworkKit` http module with custom interceptor chain
- **Rationale**: Standard HarmonyOS HTTP API. Requires custom headers, token refresh, response caching.
- **Alternatives**: rcp has better Promise API but limited interceptor support. Direct http is too low-level.
- **Implementation**: `HttpClient.ets` wraps http module with interceptor chain (Auth -> Retry -> Cache -> Log).

### Decision 2: State Management — AppStorage + LocalStorage + Custom Store classes
- **Rationale**: AppStorage provides global reactive state. Custom Store classes encapsulate business logic.
- **Alternatives**: Pure `@State` lacks cross-page sharing. Emitter bus is too loose.
- **Implementation**: Stores hold `@ObservedV2` data. Pages bind via `@StorageLink`/`@LocalStorageLink`.

### Decision 3: Image Loading — Native Image component + custom disk cache
- **Rationale**: Image component supports memory cache and placeholder, but lacks disk cache for network images.
- **Implementation**: `ImageCacheService` downloads to app sandbox. `IllustImage` checks cache first.

### Decision 4: Navigation — Navigation + NavPathStack + Tabs
- **Rationale**: Bottom tab navigation plus deep page stacks. Navigation supports nested navigation and custom animations.
- **Alternatives**: `router` has 32-page limit and no tab support.
- **Implementation**: Root `Navigation` with `Tabs` inside. Each tab has its own `NavPathStack`.

### Decision 5: Data Persistence — Preferences for settings, RelationalStore for structured data
- **Rationale**: Settings are simple KV. History/bookmarks need SQL queries.
- **Implementation**: `PreferenceService` for settings. `DatabaseService` for tables: history, bookmarks, mutes, search_history, download_tasks.

### Decision 6: OAuth2 — WebView + OAuth code exchange
- **Rationale**: Pixiv requires OAuth2. WebView loads Pixiv login page and intercepts redirect URL with code.
- **Implementation**: `LoginPage` hosts WebView. JavaScript bridge extracts code. `OAuthService` exchanges code for token.

## Data Model

### Illust
- id: number, title: string, type: enum, imageUrls: object, metaPages: array, user: UserPreview, tags: array, createDate: string, pageCount: number, width/height: number, totalView: number, totalBookmarks: number, isBookmarked: boolean, xRestrict: number, illustAIType: number

### User
- id: number, name: string, account: string, profileImageUrls: object, comment: string, isFollowed: boolean, totalFollowUsers: number, totalIllusts/Manga/Novels: number

### Novel
- id: number, title: string, imageUrls: object, tags: array, user: UserPreview, textLength: number, totalView: number, totalBookmarks: number, isBookmarked: boolean, restrict: string

### Comment
- id: number, parentCommentId: number|null, user: UserPreview, comment: string, date: string

### Bookmark
- id: number, workId: number, workType: string, tags: string[], restrict: string, createDate: string

### SearchHistory
- keyword: string, searchType: string, timestamp: number

### MuteItem
- type: string (tag/user/keyword), value: string, userId?: number, timestamp: number

### DownloadTask
- id: string, illustId: number, pageIndex: number, imageUrl: string, localPath: string, status: string, progress: number, timestamp: number

### AppSettings
- pictureQuality: number, mangaQuality: number, theme: string, language: string, networkMode: string, crossCount: number, isTopMode: boolean, muteTags: string[], muteUsers: number[], aiFilter: boolean, saveFormat: string

## Contracts & Interfaces

### Pixiv OAuth2
- Authorization URL: `https://app-api.pixiv.net/web/v1/login?code_challenge=...&client=pixiv-android`
- Token Exchange: `POST https://oauth.secure.pixiv.net/auth/token`
- Refresh Token: `POST https://oauth.secure.pixiv.net/auth/token` with `grant_type=refresh_token`

### Pixiv App API
- Base URL: `https://app-api.pixiv.net` (or custom hosts)
- Auth Header: `Authorization: Bearer {token}`
- Hash Header: `X-Client-Time: ISO8601`, `X-Client-Hash: MD5(time+salt)`

### Key Endpoints
- GET `/v1/illust/recommended` — Recommendations
- GET `/v1/illust/ranking` — Rankings
- GET `/v1/illust/new` — New works
- GET `/v1/search/illust` — Search illustrations
- GET `/v1/search/novel` — Search novels
- GET `/v1/search/user` — Search users
- GET `/v1/illust/detail` — Illustration detail
- GET `/v1/illust/related` — Related illustrations
- GET `/v1/illust/comments` — Comments
- POST `/v2/illust/bookmark/add` — Bookmark
- POST `/v1/illust/bookmark/delete` — Unbookmark
- GET `/v1/user/detail` — User profile
- GET `/v1/user/illusts` — User works
- GET `/v1/user/bookmarks/illust` — Bookmarks
- GET `/v1/trending-tags/illust` — Trending tags
- GET `/v1/spotlight/articles` — Spotlight

### Interceptor Chain
```
Request → AuthInterceptor → RetryInterceptor → CacheInterceptor → LogInterceptor → http → Response
```

### Store to UI Contract
- Stores expose reactive properties via `@ObservedV2`/`@Trace`
- UI pages observe via `@State` or `@StorageLink`
- Store methods are async `Promise<void>`
- Loading/error/empty states managed in stores
