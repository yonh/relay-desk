# Issue #16 只读媒体状态采样 — 实现与实机验收记录

日期：2026-10-08。环境：macOS（本机 debug 构建，`RELAY_DESK_AUTOMATION=true`）。
实现切片：`devin/issue16-media-state`，base `feature/relay-desk-automation`。

## 实现方案（先于实现说明）

沿用现有链路 `relayctl → 本地接口 → WKWebView.evaluateJavaScript`，**不开放任意脚本**：

- 原生侧新增 `sampleMedia`：与 `takeSnapshot` 同一绑定纪律（viewId + expectedIdentityId + 实例 + 窗口 + provisional/commit 导航代次），eval 完成后复核，漂移返回 `target_changed`。复用 `SnapshotCompletionGate` + `SnapshotPolicy.deadline`（8s 原生 deadline、9s Dart 兜底）。
- 固定脚本 `mediaProbeScript`（Swift 字符串字面量）：主文档采 `video`/`audio`，再遍历 `iframe` 尝试 `contentDocument`——同源可读则采样，跨源/不可达入 `reachable:false`、`reason:unavailable`，不越界探测也不把"无结果"当"无媒体"。`duration` 非有限（NaN/Infinity）输出 `duration:null` + `durationKind: unknown|live`，永不输出非法 JSON 数字。
- 查询层 `media` op：显式 `identityId` 必需；所有 URL（页面+各 frame）过同一 `_stripUrl`（仅留 scheme/host/port/path）；返回 `sampledAt`/`identityId`/`nativeViewId`/`windowId`/`frames[]`。
- relayctl 新增 `media --identity <id>`（必需选择器），透传 JSON；Python 镜像同步。

## 版本固定

- 应用源码树：见本 PR 顶端提交（实机验收在源码完成、提交前的同一工作区内容上进行）。
- 夹具页面：`build/screenshot-pages/`（gitignored，本机 HTTP :8901 静态服务）：
  - `media.html`：4×`<video>` + 1×`<audio>` + 同源 iframe + 跨域 iframe（example.com）
  - `media-frame.html`：1×`<video>`；`no-media.html`：无媒体；`v.mp4`（90s，ffmpeg testsrc+sine）、`a.wav`（6s）
- 会话：`automation-56733.json`，pid 3387；VerifyHTTP 项目，Http-B=`7f78ffc9`（→/media.html）、Http-A=`98205caa`（→/no-media.html）。

## 实机验收（全部来自实际返回，时间 UTC）

`relayctl media --identity 7f78ffc9` → Http-B，`viewId 1 / windowId 39`：

| 场景 | 实际结果 |
|---|---|
| 播放中推进 | 三次采样 `t=6.947→9.994→13.033`，`paused:false`、`ended:false`、`duration:90`、`durationKind:finite`、`seekable:[[0,90]]`、`sampledAt` 每次更新（21:17:29/32/35Z） |
| 播完 | 早前 8s 片版本：`t=8.00`、`paused:true`、`ended:true` |
| 暂停在零秒 | `v-pause`：`currentTime:0`、`paused:true`、`ended:false`、`readyState:4` |
| 媒体错误 | `v-broken`（missing.mp4）：`error.code:4`（SRC_NOT_SUPPORTED）、`durationKind:unknown`、`readyState:0` |
| 无源元素 | `v-nosrc`：`duration:null`、`durationKind:unknown`、`readyState:0`、`seekable:[]` |
| audio | `a-pause`：`duration:6` finite、`paused:true` |
| 同源 iframe | `frames[1]` label=iframe0 → `media-frame.html`，`reachable:true`、内层 video 单独列出 |
| 跨域 iframe | `frames[2]` → `https://example.com/`：`reachable:false`、`reason:unavailable`、`mediaCount:0`，URL 脱敏后保留 host/path |
| 无媒体页 | Http-A（/no-media.html）：`frames:[{main, reachable:true, mediaCount:0}]`——"无媒体"与"不可达"可区分 |

`relayctl media --identity 98205caa`（Http-A）只返回自身页面，**双身份不串目标** ✓。

错误路径实际返回：
- 未知 identityId → `{"ok":false,"error":{"code":"not_found",...}}`（404）
- 缺 `--identity` → CLI 侧 `exit 2`，未发请求
- 无原生视图 → `no_native_view`（409）；`media_failed`/`media_timeout`/`target_changed` 各有独立 wire code（单测覆盖）

## 自动测试

- `automation_queries_test.dart` 新增 media 组 7 项：显式 ID 必需/未选回退、not_found、no_native_view、URL 逐帧脱敏、target_changed→409、media_failed/timeout 透传、畸形 JSON→media_failed、capabilities 声明。全量 232 项通过。
- `automation_server_test.dart` 白名单集合加 `media`；`relayctl_test.py` 26 项通过（media 转发 + 必需 identity）。
- `flutter analyze` 零问题；Swift 侧无新增告警（编译干净）。

## 如实标注的未覆盖项

- `durationKind:"live"`（Infinity）未实机触发——需 MediaSource/直播源，夹具未覆盖；分支逻辑在固定脚本内（`isFinite` 判定）。
- `seeking:true` 与媒体在 `<iframe>` 内 seek 过程中的瞬态未专门构造。
- `sampledAt` 是本次采样完成的时间标记；frame 列表是脚本一次遍历的结果，**不是**跨 frame 原子快照；媒体状态（currentTime 等）在采样期间持续变化，按 issue 要求仅作状态证明，不作观看时长/账号结论。
- uni-app 同源嵌套 iframe 结构用同源 `iframe` 等价覆盖（contentDocument 可达即采样，跨源即 unavailable）；未在真实 uni-app 页面上验收。
- 页面切换中采样：`target_changed` 绑定复核沿用 snapshot 已验证机制，本次未单独构造命中。
