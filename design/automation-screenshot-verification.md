# 指定身份面板截图 — 实机验收记录（Issue #12）

日期：2026-10-08，macOS 26.5.2（arm64）
构建：`flutter build macos --debug --dart-define=RELAY_DESK_AUTOMATION=true`

**证据对应的代码版本**：以下全部实机证据采集于工作区构建，其源码树与提交 `c241713`（fix: 复审整改——像素上限前置、commit 代次绑定、有界一次性完成、CLI 原子写盘）完全一致——采集完成后原样提交，无未提交差异。其后的 SnapshotPolicy 提取重构（将判定逻辑移到 `macos/Runner/SnapshotPolicy.swift` 并由 `test/fixtures/snapshot` 夹具直测）不改变可观察行为；图片不与该重构后的 SHA 混用。

会话：`automation-64738.json`（app pid 3573，主窗口 windowId 46）
项目：VerifyHTTP `bf0a306e-b7db-469d-95fb-7e0e039b4913`（targetUrl `http://127.0.0.1:8901`）
页面服务：`/tmp/pageserver.py`（SimpleHTTPRequestHandler + `/hop` 无限 302 + `/slow` 600ms 延迟提交 + 静态页）

身份：
- Http-A `98205caa-ac31-46a0-b257-907a4c27702e` → `/a.html`（PAGE-ALPHA 蓝）
- Http-B `7f78ffc9-a39f-491e-b886-c9d3491ee503` → `/b.html`（PAGE-BETA 粉）

## 证据索引

会话文件路径以 `$S` 指代（`…/Library/Application Support/com.example.relayDesk/automation/automation-64738.json`），凭据不公开。

### A 嵌入面板 — `evidence/screenshot-2026-10-08/panel-a.png`

```bash
relayctl --session "$S" screenshot \
  --identity 98205caa-ac31-46a0-b257-907a4c27702e \
  --output build/shot-evidence/panel-a.png
```

```json
{"ok": true, "data": {
  "identityId": "98205caa-ac31-46a0-b257-907a4c27702e",
  "projectId": "bf0a306e-b7db-469d-95fb-7e0e039b4913",
  "nativeViewId": 0, "windowId": 46,
  "capturedAt": "2026-10-08T15:42:17.912450Z",
  "format": "png", "width": 279, "height": 141,
  "url": "http://127.0.0.1:8901/a.html",
  "outputPath": "…/build/shot-evidence/panel-a.png", "byteLength": 4746}}
```

### B 嵌入面板 — `evidence/screenshot-2026-10-08/panel-b.png`

```bash
relayctl --session "$S" screenshot \
  --identity 7f78ffc9-a39f-491e-b886-c9d3491ee503 \
  --output build/shot-evidence/panel-b.png
```

```json
{"ok": true, "data": {
  "identityId": "7f78ffc9-a39f-491e-b886-c9d3491ee503",
  "projectId": "bf0a306e-b7db-469d-95fb-7e0e039b4913",
  "nativeViewId": 6, "windowId": 46,
  "capturedAt": "2026-10-08T15:42:17.929123Z",
  "format": "png", "width": 279, "height": 141,
  "url": "http://127.0.0.1:8901/b.html",
  "outputPath": "…/build/shot-evidence/panel-b.png", "byteLength": 5163}}
```

### B 分离独立窗 — `evidence/screenshot-2026-10-08/panel-b-detached.png`

```bash
relayctl --session "$S" screenshot \
  --identity 7f78ffc9-a39f-491e-b886-c9d3491ee503 \
  --output build/shot-evidence/round2-b-detached.png
```

完整返回 JSON 未留底（本次命令只打印了压缩字段），已记录字段：`nativeViewId=5, windowId=72, width=900, height=640`（279×141 之外的独立窗尺寸即 900×640 CSS px @1x），`url=http://127.0.0.1:8901/b.html`；服务返回的 `capturedAt` 未留存，此处以输出文件的写入时间近似：`2026-10-08T15:41:43Z`（mtime ≠ 服务端采样时刻，仅作近似）。入库文件为同一路径内容（`panel-b-detached.png` 重命名）。

### UI 对照 — `evidence/screenshot-2026-10-08/app-window-for-reference.png`

同刻 macOS 全屏截图：主窗内 Http-A（蓝）与 Http-B（粉）面板与各自 PNG 一一对应，不含窗框/侧栏/地址栏。

像素规则：截图 = 该 WKWebView 的 bounds × 所在窗口 backingScaleFactor；279×141 为 2x 缩放下的视口物理像素，分离窗 900×640 为 1x。

## 绑定与失效判定

绑定因子 = (viewId, expectedIdentityId, WKWebView 实例, provisional 代次, commit 代次, windowNumber)，采样完成时全部复核。

### 夹具直测（生产代码，`test/fixtures/snapshot/`）

`run.sh` 用 `swiftc` 直接编译 `macos/Runner/SnapshotPolicy.swift`（`takeSnapshot` 实际调用的同一份代码，非 stub），31 项断言全过：

- **尺寸边界**：正常 2x 视口 ok；零/负/非有限 bounds、非有限/零 scale → notMeasurable；单边 18000>16384 → tooLarge（报实际像素数）；同 bounds @1x → ok（scale 参与判定）；总像素 144MP>64MP → tooLarge；边界 16384/16384.5 恰好两侧；1e300 有限巨值与 1e308×2→+inf 溢出 → tooLarge 且不 trap。
- **PNG 字节上限**：恰好 16MiB 放行，+1 字节拒绝。
- **绑定失效**：未变→bound；仅 commit 代次 +1（同 URL reload / 采样中提交）→ not bound；provisional +1 → not bound；实例替换、注册表空（视图销毁）、窗口号改变、窗口丢失（nil）、身份重映射、身份查询空 → not bound。
- **一次性完成门控**：首次 `claim()` 成功、迟到回调 claim 失败；deadline-first 排序仅交付 timeout 一次——即原生层迟到回调在绑定复核与转码之前返回。
- **诊断格式化**：`describePixels` 对 +inf/巨大 Double 不 trap（替代原 `Int()` 强转风险）。

### 实机复核

| 场景 | 操作 | 结果 |
|---|---|---|
| 视图重建失效 | B 修改 Start path `/b.html`→`/hop`→`/slow`→`/e.html`→`/b.html` | viewId 1→2→3→4→6 每次重建均重新解析，截图返回当前实例正常 |
| 分离→关窗→重嵌 | B 分离独立窗（win 72）→ 原生关闭 → 自动重嵌 | 分离态截图 win 72 正常；重嵌后视图重建 viewId 6，截图正常；无残留目标 |
| 采样中导航 | B 指向 `/e.html`（50ms meta refresh 连续导航）后 60 连拍 | **22 target_changed + 38 ok**；无一返回错位页面。各次 ok 是否落在导航间隙窗口内无逐次归因（见下） |
| pending→commit 跨越 | `/slow`（didStart→600ms→commit 循环）150 连拍 | 150/150 ok。**未验证** pending→commit 跨越是否命中——无逐次日志可区分各次完成相对 commit 的位置（`webview.log` 被 e.html 事件风暴轮转），不断言全部完成于 pending 窗口。该路径的实际拒绝行为由上述夹具中 commit 代次直测覆盖 |

关闭面板后 `no_native_view` 为本 PR 首轮实机结果（B 面板关闭后 screenshot 返回 409）；401、URL 脱敏、白名单沿用 Issue #10/PR #11 轮实机结论，本轮 diff 未触碰这些路径。

## 剩余限制 / 未验证项

- `snapshot_too_large` 像素上限未实机触发（无构造异常 bounds 的手段）——边界判定已由夹具直测生产代码覆盖，实机路径未验证。
- commit 代次的 pending→commit 跨越未实机复现（如上，无逐次归因）——判定逻辑由夹具直测覆盖。
- `no_native_view` 实机证据来自本 PR 首轮；401、脱敏、白名单沿用 Issue #10/PR #11 轮实机结论，本轮 diff 未触碰。
- macOS only；Windows/Linux 未实现。

## 测试与静态检查

- `flutter analyze`：零问题。
- `flutter test`：**224 全绿**（queries +1、transport +1、adapter +4）。
- `test/tool/relayctl_test.py`：25/25 ×2（Python 与编译产物）。
- `test/fixtures/snapshot/run.sh`：**31 断言全过**（生产 SnapshotPolicy 直编译）。
- `flutter build macos --debug` 成功（仅 Metal toolchain 警告）。
