# 指定身份面板截图 — 实机验收记录（Issue #12）

日期：2026-10-08，macOS 26.5.2（arm64）
构建：`flutter build macos --debug --dart-define=RELAY_DESK_AUTOMATION=true`
基准提交：`3d802af`（含评审整改后的 HEAD 见 PR #14 最新 SHA）
会话：`automation-64738.json`（app pid 3573，主窗口 windowId 46）
项目：VerifyHTTP `bf0a306e-b7db-469d-95fb-7e0e039b4913`（targetUrl `http://127.0.0.1:8901`）
页面服务：`/tmp/pageserver.py`（SimpleHTTPRequestHandler + `/hop` 无限 302 + `/slow` 600ms 延迟提交 + 静态页）

身份：
- Http-A `98205caa-ac31-46a0-b257-907a4c27702e` → `/a.html`（PAGE-ALPHA 蓝）
- Http-B `7f78ffc9-a39f-491e-b886-c9d3491ee503` → `/b.html`（PAGE-BETA 粉）

## 证据索引

| 证据 | 命令 | capturedAt | 元数据 | 文件 |
|---|---|---|---|---|
| A 嵌入 | `relayctl --session …/automation-64738.json screenshot --identity 98205caa-… --output panel-a.png` | 15:42:17.912Z | view 0, win 46, 279×141 PNG, 4746B, url `/a.html` | `evidence/screenshot-2026-10-08/panel-a.png` |
| B 嵌入 | 同上 `--identity 7f78ffc9-… --output panel-b.png` | 15:42:17.929Z | view 6, win 46, 279×141 PNG, 5163B, url `/b.html` | `evidence/screenshot-2026-10-08/panel-b.png` |
| B 分离窗 | 同上（B 经 ⧉ 分离后） | 08:41（本机 PDT） | view 5, win 72, 900×640 PNG, 25746B | `evidence/screenshot-2026-10-08/panel-b-detached.png` |
| UI 对照 | （截图见仓库） | 08:42 PDT | 主窗内 A 蓝 / B 粉面板与 PNG 一一对应 | `evidence/screenshot-2026-10-08/app-window-for-reference.png` |

像素规则：截图 = 该 WKWebView 的 bounds × 所在窗口 backingScaleFactor；279×141 为 2x 缩放下的视口物理像素。PNG 不含窗框、相邻面板、侧栏或地址栏（见 UI 对照图）。

## 绑定与失效判定（实机复核）

绑定因子 = (viewId, expectedIdentityId, WKWebView 实例, provisional 代次, commit 代次, windowNumber)，采样完成时全部复核。

| 场景 | 操作 | 结果 |
|---|---|---|
| 视图重建失效 | B 修改 Start path `/b.html`→`/hop`→`/slow`→`/e.html`→`/b.html` | viewId 1→2→3→4→6 每次重建均重新解析，截图返回当前实例 900×640/279×141 正常 |
| 分离→关窗→重嵌 | B 分离独立窗（win 72）→ 原生关闭 → 自动重嵌 | 分离态截图 win 72 正常；关闭后视图重建 viewId 6，嵌入态截图正常；无残留目标 |
| 采样中导航 | B 指向 `/e.html`（50ms meta refresh 连续导航）后 60 连拍 | **22 target_changed + 38 ok**；ok 均在无导航事件窗口完成（一致旧文档），无一返回错位页面 |
| 采样中提交（pending 窗口） | `/slow`：didStart→600ms→commit 循环，150 连拍 | 150/150 ok——全部完成于 pending 窗口内（像素+URL 同属旧已提交文档，一致）；无一次跨 commit 越界完成。commit 代次为构造性绑定，pending→commit 的跨越命中未在可控窗口内复现（`webview.log` 被 e.html 事件风暴轮转，逐次归因不可恢复） |
| 关闭后查询 | B 面板经 ✕ 关闭（上轮 R3 验证，本轮路径未变） | `no_native_view` 409（上轮已证） |

## 尺寸上限与编码（评审整改）

- 分配前检查：视口有限且为正；按窗口 backingScaleFactor 换算像素，单边 ≤16384 px、总像素 ≤64 MP，否则 `snapshot_too_large`（不产生 TIFF/bitmap/PNG 分配）。
- 编码后复查：PNG > 16 MiB → `snapshot_too_large`；Dart 层 16 MiB 上限保留（双保险）。
- 无异常视口实机路径（bounds 恒为正常值）；超限路径由代码审查+边界常量覆盖，未实机触发——标记**待观察**。

## 有界完成与超时恢复（评审整改）

- 原生侧 8 s 一次性完成（`snapshotDeadline`）：WebKit 回调迟到即在转码前丢弃，不重复 result、不产出成功。
- 适配器侧 9 s `pending.timeout()` + `pending.ignore()`：`snapshot_timeout` PlatformException；迟到应答不再挂起，不报未处理 zone 错误。
- 查询层：`snapshot_timeout`/`snapshot_too_large` → 500（`target_changed` → 409）。
- 传输层回归：`a failed dispatch releases the target lock for retries`——超时后同一 identityId 立即可查（无永久 panel_busy）。适配器单测验证 wedged 回调→`snapshot_timeout`→再调用正常+迟到应答丢弃。

## 原子写盘（评审整改）

两入口（`tool/relayctl.dart`、`tool/relayctl.py`）均改为同目录唯一临时文件 → 校验+写+flush → `rename`/`os.replace` 原子覆盖；失败仅删本次临时文件，原文件不动。

回归（两实现各 3 条，共入 `test/tool/relayctl_test.py`）：
- 已有输出 + 成功 → 原子替换为 PNG，无 `.relayctl-*.tmp` 残留；
- 已有输出 + 非 PNG 载荷 → 原文件内容不变、无残留；
- 输出路径为目录（rename 失败）→ 原目录不动、无残留。

## 剩余限制 / 待验收

- `snapshot_too_large` 像素上限未实机触发（无构造异常 bounds 的手段）——构造覆盖。
- commit 代次的 pending→commit 跨越命中未实机复现；pending 窗口内一致性已证。
- `no_native_view`、401、脱敏、白名单沿用上一轮实机结论，本轮 diff 未触碰。
- macOS only；Windows/Linux 未实现。

## 测试与静态检查

- `flutter analyze`：零问题。
- `flutter test`：**224 全绿**（queries +1、transport +1、adapter +4）。
- `test/tool/relayctl_test.py`：25/25 ×2（Python 与编译产物）。
- `bash -n` / 构建：`flutter build macos --debug` 成功（仅 Metal toolchain 警告）。
