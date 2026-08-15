# Feature Specification: 登录持久化与启动主动刷新

**Created**: 2026-08-14
**Status**: Draft
**Input**: 用户描述："走做'登录持久化 + 启动主动刷新'"（背景：应用当前 token 容易过期，闲置几天后掉登录，需频繁重新登录）

## Overview

Pixiv 的 access token 寿命仅约 1 小时，长期会话依赖 refresh token 的正确持久化与续期。当前应用仅在收到 401 时才被动刷新，且启动时不校验/不刷新已保存的登录态，导致用户在闲置几天后冷启动时经常被迫重新登录。

本特性目标是：让已登录用户的会话能跨多天稳定保持，具体包括 (1) 可靠地持久化并在每次刷新后正确轮换 refresh token；(2) 在应用启动时主动校验并刷新临期/已过期的凭证，避免把用户直接踢回登录页。

## User Scenarios & Testing

### User Story 1 - 冷启动主动刷新，免重新登录 (Priority: P1)

用户已登录，闲置数天后重新打开应用。应用启动时检测到已保存的 access token 已过期或即将过期，自动在后台用 refresh token 换发新凭证，用户无感知直接进入首页，无需重新登录。

**Why this priority**: 这是用户最直接的痛点——"闲置几天后掉登录"。解决它即解决核心诉求。

**Independent Test**: 登录一次后退出应用，等待 access token 过期（或修改系统时间/等待足够时长），重新打开应用，用户应直接进入首页且能正常加载内容，全程无登录页、无重新授权弹窗。

**Acceptance Scenarios**:

1. **Given** 用户已登录且本地保存了有效的 refresh token，**When** 冷启动应用，**Then** 应用自动刷新凭证并直接进入首页，不跳转登录页。
2. **Given** 用户已登录但 access token 已过期，**When** 冷启动应用，**Then** 应用先刷新凭证再进入首页，首次内容加载不出现因过期导致的失败提示。
3. **Given** 用户已登录且 access token 仍有效（未临期），**When** 冷启动应用，**Then** 不发起多余刷新，直接进入首页。

---

### User Story 2 - Refresh Token 可靠持久化与轮换 (Priority: P1)

每次成功刷新后，服务端返回的新 refresh token（若发生轮换）被正确落盘；应用重启后读取的始终是最新、有效的 refresh token，而不是旧值或损坏值。

**Why this priority**: 历史"掉登录"根因之一正是 refresh token 持久化/轮换出错，导致重启后拿着旧 token 刷新被判失效。这是长期会话稳定的基础。

**Independent Test**: 多次触发刷新（含跨重启），之后重启应用检查仍能正常续期，且不会因旧/损坏 token 被强制登出。

**Acceptance Scenarios**:

1. **Given** 一次刷新返回了新 refresh token，**When** 刷新完成，**Then** 新 refresh token 被持久化，内存与磁盘一致。
2. **Given** 应用重启并读取到已持久化的 refresh token，**When** 下一次需要刷新，**Then** 使用该最新值刷新成功，不出现"凭证无效"错误。
3. **Given** 磁盘中残留历史版本遗留的无效/损坏 token，**When** 启动刷新失败，**Then** 系统明确引导重新登录（一次性），且不会再次静默写坏登录态。

---

### User Story 3 - 网络故障不误登出 (Priority: P2)

刷新过程遇到临时网络故障（超时、断网、5xx）时，应用保留登录态并保留原有凭证，不把用户登出；待网络恢复后自动重试续期。

**Why this priority**: 保障体验的健壮性——避免用户因一次弱网就丢失登录态。

**Independent Test**: 登录后在弱网/断网环境下触发刷新，确认应用不登出、不清空凭证，网络恢复后仍能正常使用。

**Acceptance Scenarios**:

1. **Given** 刷新请求因网络超时失败，**When** 失败发生，**Then** 登录态保持不变，用户仍停留在已登录状态，后续请求可自动重试刷新。
2. **Given** 服务端明确拒绝 refresh token（凭证失效），**When** 刷新返回鉴权错误，**Then** 应用给出清晰提示并引导重新登录（区分于网络故障）。

---

### Edge Cases

- 启动刷新与首次 API 请求并发：不应发起重复刷新，仅刷新一次并共享结果。
- 启动刷新遇到网络故障：不阻塞进入首页，保留登录态，靠首次 API 请求的 401 兜底重试。
- 刷新返回的新 refresh token 与旧值相同：不应错误覆盖或丢失。
- 多个账号（多账号切换）场景：刷新只作用于当前账号，不串号。
- 旧版本遗留的坏 token：升级后首次启动刷新失败，应一次性引导重登，之后恢复正常。

## Requirements

### Functional Requirements

- **FR-001**: 系统 MUST 在应用启动时，若存在已登录账号，检测其 access token 是否过期或即将过期（临期）。
- **FR-002**: 系统 MUST 在 access token 过期或临期时，于启动阶段主动使用 refresh token 刷新凭证，使用户无需手动重新登录。
- **FR-003**: 系统 MUST 在 access token 仍有效且未临期时，跳过启动刷新，避免无谓请求。
- **FR-004**: 系统 MUST 在每次刷新成功后，将服务端返回的最新 access token 与 refresh token（若发生轮换）持久化到本地，并保持内存与磁盘一致。
- **FR-005**: 系统 MUST 记录 access token 的有效期（expires_in / 过期时间），作为临期判定依据。
- **FR-006**: 系统 MUST 在启动刷新遇到网络类临时故障时保留登录态、不清空凭证、不登出，并允许后续重试。
- **FR-007**: 系统 MUST 在服务端明确拒绝 refresh token（凭证失效）时，给出清晰提示并引导重新登录，且不静默写坏本地登录态。
- **FR-008**: 系统 MUST 保证并发触发的刷新仅执行一次（去重/合并），避免同一 refresh token 被重复使用导致服务端判失效。
- **FR-009**: 系统 MUST 在多账号场景下，刷新仅作用于当前登录账号，不污染其他账号的凭证。

### Key Entities

- **Account（登录账号）**: 表示一个已登录的 Pixiv 账号，含用户标识、access token、refresh token、token 过期时间等属性。
- **Token Credential（凭证）**: access token 与 refresh token 的组合，以及 access token 的有效期信息；是持久化与刷新的核心对象。
- **Refresh Result（刷新结果）**: 一次刷新操作的产物，含新 access token、可能轮换的新 refresh token，或按失败类型（凭证失效 / 网络故障）分类的错误。

## Success Criteria

### Measurable Outcomes

- **SC-001**: 已登录用户冷启动应用后，95% 的情况下无需手动重新登录，会话可跨多天保持。
- **SC-002**: 用户闲置 3 天后重新打开应用，若 refresh token 仍有效，可直接进入首页并正常加载内容，无需重新登录。
- **SC-003**: 刷新过程中的临时网络故障不会导致登录态丢失（100% 保留登录态，网络恢复后自动恢复）。
- **SC-004**: 凭证确实失效时，用户被清晰、明确地提示重新登录，而非静默失败或进入空白/错误状态。

## Assumptions

- Pixiv access token 的有效期约为 1 小时，作为临期判定的基础。
- 续期仍使用 Pixiv 官方 refresh token 授权，不新增账号密码登录方式（该方式服务端已关闭）。
- 临期判定默认阈值：剩余有效期不足 5 分钟即视为"临期"，触发启动刷新。
- 启动刷新采用非阻塞方式：优先快速进入首页，刷新在后台完成；刷新失败（网络类）由首次 API 请求的 401 兜底重试。
- 现有 `needsRelogin`（凭证失效引导重登）与网络错误/凭证错误分类语义保持不变。

## Open Questions

- 临期阈值（默认 5 分钟）是否需要可配置或采用不同默认值？
- 启动刷新失败（网络类）时，是否需要在首页展示轻量"离线/待续期"提示，还是完全静默重试？
