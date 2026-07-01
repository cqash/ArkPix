# Feature Specification: Pixiv Client ArkTS Rewrite

**Created**: 2026-06-30  
**Status**: Draft  
**Input**: Reference pixez-flutter, rewrite a Pixiv third-party client in ArkTS for HarmonyOS

## Overview

Rewrite the PixEz Flutter project as a HarmonyOS ArkTS application, delivering a full-featured Pixiv third-party client. The app supports direct connection from mainland China, providing illustration/novel browsing, search, bookmarks, downloads, user interactions, and advanced features like theme customization, network mode switching, and image quality settings.

## User Scenarios & Testing

### User Story 1 - OAuth2 Login & Account Management (Priority: P1)

Users complete Pixiv OAuth2 authorization via built-in WebView. The app obtains Access Token and Refresh Token, supports automatic token refresh, and allows managing multiple accounts.

**Acceptance Scenarios**:
1. **Given** user is not logged in, **When** user clicks login and authorizes, **Then** app obtains token and navigates to home
2. **Given** token is about to expire, **When** app silently refreshes token, **Then** user continues browsing without interruption
3. **Given** user is logged in, **When** user clicks logout, **Then** local tokens are cleared and login page is shown

---

### User Story 2 - Home Feed & Rankings (Priority: P1)

Users browse recommended illustrations, new works, rankings (daily/weekly/monthly/rookie), and Spotlight features. Supports grid/waterfall layout with pull-to-refresh and infinite scroll.

**Acceptance Scenarios**:
1. **Given** user is logged in, **When** opening home, **Then** recommended illustrations load and display
2. **Given** user is on recommendation page, **When** pulling down to refresh, **Then** list refreshes with latest data
3. **Given** list scrolls to bottom, **When** triggering load more, **Then** paginated data appends to list

---

### User Story 3 - Illustration Search & Discovery (Priority: P1)

Users search illustrations/novels/users by keywords. Search page provides trending tags and search history. Supports auto-complete suggestions.

**Acceptance Scenarios**:
1. **Given** user on search page, **When** entering keyword and searching, **Then** search results display correctly
2. **Given** user on search page, **When** clicking trending tag, **Then** tag is filled and search executes
3. **Given** search results page, **When** switching tabs (illust/novel/user), **Then** corresponding results display

---

### User Story 4 - Illustration Detail & Interaction (Priority: P1)

Users tap thumbnail to view detail page with large image, multi-page navigation, author info, related recommendations. Supports bookmark (public/private), like, download, comments, and Ugoira animation.

**Acceptance Scenarios**:
1. **Given** user taps illustration, **When** entering detail page, **Then** illustration info, author, related works display
2. **Given** user on detail page, **When** clicking bookmark with public/private choice, **Then** bookmark succeeds and UI updates
3. **Given** user views multi-page illustration, **When** swiping, **Then** pages switch correctly
4. **Given** user on detail page, **When** clicking download, **Then** image saves to gallery

---

### User Story 5 - User Profile & Follow Management (Priority: P2)

Users tap author avatar to view profile with basic info, works list, bookmarks. Supports follow/unfollow with public/private setting.

**Acceptance Scenarios**:
1. **Given** user taps author avatar, **When** entering profile, **Then** user info and works display
2. **Given** user on profile page, **When** clicking follow, **Then** follow succeeds and status updates
3. **Given** user already follows author, **When** clicking unfollow, **Then** unfollow succeeds

---

### User Story 6 - Novel Browsing & Reading (Priority: P3)

Users browse novel recommendations, rankings, and follow novels. View novel details and read content. Supports bookmarks and reading history.

**Acceptance Scenarios**:
1. **Given** user enters novel section, **When** browsing recommendations, **Then** novel list loads correctly
2. **Given** user taps novel title, **When** entering detail, **Then** novel content displays correctly
3. **Given** user reads novel, **When** re-entering later, **Then** reading progress restores

---

### User Story 7 - Bookmarks & History (Priority: P2)

Users view bookmark lists (illustrations/novels) with tag filtering. View browsing history and remove items.

**Acceptance Scenarios**:
1. **Given** user enters bookmarks, **When** viewing illustration bookmarks, **Then** list displays correctly
2. **Given** user enters bookmarks, **When** selecting tag filter, **Then** filtered bookmarks display
3. **Given** user enters history, **When** viewing history, **Then** records display in reverse chronological order

---

### User Story 8 - Downloads & Reverse Image Search (Priority: P1)

Users manage download tasks and use SauceNAO reverse image search to find Pixiv sources.

**Acceptance Scenarios**:
1. **Given** user enters downloads, **When** viewing task list, **Then** download statuses display correctly
2. **Given** user selects reverse search, **When** uploading image, **Then** SauceNAO returns results

---

### User Story 9 - Settings & Personalization (Priority: P3)

Users configure image quality, network mode, theme, layout columns, language, mute tags/users, cache cleanup, and data export.

**Acceptance Scenarios**:
1. **Given** user enters settings, **When** changing image quality, **Then** setting persists and takes effect
2. **Given** user changes network mode, **When** switching direct/proxy, **Then** requests use corresponding mode
3. **Given** user adds mute tag, **When** browsing content with that tag, **Then** content is filtered

---

### User Story 10 - Internationalization & Theme (Priority: P3)

App supports multi-language switching, dark mode adaptation, and dynamic theming.

**Acceptance Scenarios**:
1. **Given** user switches language, **When** selecting English, **Then** UI language changes to English
2. **Given** system is in dark mode, **When** app theme follows system, **Then** app switches to dark theme

---

### Edge Cases

- Network errors: graceful error messages with retry mechanisms
- Token refresh failure: guide user to re-login
- Large image lists: memory optimization and list performance
- Rapid page switching: cancel pending requests to avoid race conditions
- Download interrupted: resume capability
- Failed image pages: placeholder and retry
- Empty search results: friendly user prompt
- Failed bookmark/follow: maintain UI state consistency

## Requirements

### Functional Requirements

- **FR-001**: OAuth2 authentication with Access/Refresh Token management
- **FR-002**: Automatic silent token refresh before expiration
- **FR-003**: Multi-account login and switching
- **FR-004**: Home feed with recommendations, new works, rankings, Spotlight in grid/waterfall layout
- **FR-005**: Pull-to-refresh and infinite scroll pagination
- **FR-006**: Keyword search for illustrations/novels/users with history and trending tags
- **FR-007**: Search auto-complete suggestions
- **FR-008**: Illustration detail with large image, multi-page, author info, related works
- **FR-009**: Bookmark (public/private) and unbookmark illustrations
- **FR-010**: Like and unlike illustrations
- **FR-011**: Download illustrations to local gallery
- **FR-012**: Ugoira animation playback
- **FR-013**: View and post comments on illustrations
- **FR-014**: User profile with info, works, bookmarks
- **FR-015**: Follow/unfollow users with public/private setting
- **FR-016**: Novel recommendations, rankings, follows browsing
- **FR-017**: Novel detail page with content reading
- **FR-018**: Novel bookmarks and reading history
- **FR-019**: Bookmark lists with tag filtering
- **FR-020**: Browsing history management
- **FR-021**: Download task management
- **FR-022**: SauceNAO reverse image search
- **FR-023**: Image quality settings (thumbnail/medium/large/original)
- **FR-024**: Network mode switching (direct/proxy/custom hosts)
- **FR-025**: Theme switching (light/dark/follow system) with custom colors
- **FR-026**: Customizable layout column count
- **FR-027**: Tag and user muting with content filtering
- **FR-028**: AI work filtering
- **FR-029**: Cache cleanup and data export
- **FR-030**: Multi-language support (at least Chinese and English)
- **FR-031**: Long-press image save and share
- **FR-032**: Built-in WebView for login and browsing
- **FR-033**: Error handling and retry with friendly network failure prompts
- **FR-034**: Lazy image loading and caching for list performance

### Key Entities

- **Illust**: id, title, author, image URLs (multiple sizes), tags, bookmark count, like count, view count, create time, page count, type (illust/manga/ugoira), AI flag
- **User**: id, name, avatar URL, bio, follow count, follower count, works count, is_followed, is_friend
- **Novel**: id, title, author, cover URL, tags, word count, bookmark count, create time, content, series_id
- **Comment**: id, user_id, user_name, avatar_url, content, create_time, reply_to_id
- **Bookmark**: id, work_id, work_type, bookmark_time, public/private, tags
- **SearchHistory**: keyword, search_time, search_type
- **MuteItem**: type (tag/user/keyword), value, add_time
- **DownloadTask**: id, work_id, image_url, save_path, status, progress
- **AppSettings**: image_quality, network_mode, theme, columns, language, mute_list, ai_filter

## Success Criteria

- **SC-001**: OAuth2 login completes within 30 seconds
- **SC-002**: Home feed first load under 3 seconds
- **SC-003**: Search response under 2 seconds
- **SC-004**: Illustration detail large image load under 5 seconds (standard network)
- **SC-005**: Smooth scrolling with 1000+ thumbnail images without lag
- **SC-006**: Bookmark/follow interaction response under 1 second
- **SC-007**: App crash rate below 1% in daily usage
- **SC-008**: Image cache hit rate above 80%
- **SC-009**: Offline viewing of cached content when network unavailable
- **SC-010**: 90% of users complete login and basic browsing on first use without help

## Assumptions

- Users have stable internet and can access Pixiv domains (app optimizes for direct connection)
- Target devices are HarmonyOS phones with API 9+
- Pixiv API remains compatible with current OAuth2 and REST endpoints
- User grants necessary permissions (storage, network, gallery)

## Open Questions

- [NEEDS CLARIFICATION]: Should the initial release focus only on illustration features and defer novel support to a later phase?
- [NEEDS CLARIFICATION]: What is the target minimum HarmonyOS API level?
