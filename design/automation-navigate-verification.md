# navigate 页面导航验收记录（Issue #23）

日期：2026-10-09 ・ 基线：`devin/issue23-navigate` 调试构建（`RELAY_DESK_AUTOMATION=true`）
验收环境：隔离 debug 实例（pid 3937，会话 `automation-57955.json`），VerifyHTTP 项目（`allowPrivateNetwork=true`，身份 Http-A `98205caa…`、Http-B `7f78ffc9…`）与 UpgradeE2E 项目（`allowPrivateNetwork=false`，身份 Verify-A `6d683554…`）；夹具页经 `python3 -m http.server 8901 --directory <repo>` 提供，慢端点为 127.0.0.1:8902（6 秒延迟应答）。

全部命令经 `relayctl`（dart 编译产物，重编译于本分支），无桌面点击。证据 JSON 存 `~/Library/Caches/relay-desk/agent-evidence/issue-23/`。

## 验收矩阵（全部实机执行）

| 场景 | 命令 | 结果（实际返回） | 判定 |
|---|---|---|---|
| 授权页提交 | navigate B → `:8901/build/screenshot-pages/a.html` | `status:committed`，`finalUrl`=a.html，`navigationId:nav-…-0`，dispatch→settle 50ms，`canGoBack:true`；`dom_find --text PAGE-ALPHA` → matchCount:1 证明页面真实渲染 | 通过 |
| 同 URL 导航 | navigate B → 同一 a.html | `sameUrl:true` + `status:committed`（仍派发，与地址栏回车语义一致） | 通过 |
| 404 页面 | navigate B → `no-such-page.html` | `status:committed` + `finalUrl` 指向 404 路径。**如实边界**：WKWebView 提交即完成，HTTP 状态码不经 loadComplete 上抛；404 的可区分性由 `finalUrl` + 后续 DOM/截图承担，接口不虚报"成功内容" | 通过（语义限定） |
| 非法 scheme | navigate B → `ftp://example.com/x` | `invalid_url`(400)，未派发 | 通过 |
| DNS 失败 | navigate B → `http://nonexistent.invalid./x` | `status:failed`，`error:"A server with the specified hostname could not be found."`，`settledAt` 有值，`panelQueryable:true` | 通过 |
| 有界超时 | navigate B → `http://10.255.255.1/x` | 8.03s 后 `status:timeout`，`settledAt:null`，`panelQueryable:true`；此后目标仍可查询（panels 返回正常） | 通过 |
| 在途导航竞争 | 上条 timeout 后底层 WK 加载仍在途 → 后续两次调用 | `navigation_in_flight`(409) ×2 —— 地址栏/残留加载（传输锁看不见的在途）被正确识别，不虚报可导航 | 通过 |
| 传输锁竞争 | navigate B → 8902 慢端点（持锁等待中）并发第二调用 | `panel_busy`(409) —— 与 `navigation_in_flight` 可区分：锁内执行 vs 锁外残留 | 通过 |
| 慢提交成立 | 上述首次调用 6s 后 | `status:committed`，`finalUrl`=slowpage；`panels` 显示该 URL 且 `loading:false` | 通过 |
| 私网门控（拒绝） | Verify-A（priv=false）→ `http://127.0.0.1:8901/…` | `private_network_denied`(403)，未派发 | 通过 |
| 私网门控（放行） | Http-B（VerifyHTTP priv=true）→ 同一 127.0.0.1 夹具 | `status:committed`（即矩阵首行）——同主机两项目不同结果证明按项目标志位门控 | 通过 |
| URL 凭据不回显 | navigate B → `c.html?session=tok123&x=1` | 页面按完整 URL 真实导航（会话参数送达），返回中 `requestedUrl`/`finalUrl` 均为脱敏裸路径；响应体零字节 `tok123` | 通过 |
| 失败后目标可查可用 | 失败/超时/竞争全部结束后 navigate B → c.html | `status:committed`，面板 `loading:false`，`screenshot` 正常产出（1615B PNG） | 通过 |

## 如实边界与说明

- **面板存在性**：激活项目时布局恢复已打开 Http-A/B 双面板，故"无面板"分支未在本机直接命中；`panel_not_open` 由单元测试覆盖（closed/closing/failed 状态均拒绝）。同项目上错误身份→ `not_found`、跨项目身份 → `project_not_active`（单元测试覆盖，路径与 open_panel 一致）。
- **完成定义**：`committed` = 主文档提交（WK `didCommitNavigation` → 新 `loadCommitted` 事件，取与 `didFinish` 先到者），非"资源全部加载完"。此前实现误挂在 `didFinish`（整页完成），已纠正——提交后立即返回的长加载页不再报 `timeout`。`finalUrl` 为观测事实（重定向后与 `requestedUrl` 可能不同，以 finalUrl 为准）。
- **超时语义**：8s 有界预算 < 传输层 10s 命令超时，故慢页回 200 + `status:timeout` 而非 504；底层 WK 加载仍继续，属"可辨识、可恢复"而非静默。
- **同 URL**：`sameUrl` 仅作标记，导航仍派发（地址栏回车即重载的语义）。
- **不隐式创建**：navigate 不创建身份/面板/项目，不切换项目；全部前置校验（项目活跃→面板存活→原生视图→在途检测→关键段复核）先于派发。
- **脱敏**：`requestedUrl`/`finalUrl` 经 `_stripUrl`（剥凭据/query/fragment）；平台错误文本中的内嵌 URL 经 `_scrubUrlsInText` 再 clip 500 字符——带 `?session=` 的真实导航在响应中无凭据字节。
- **范围外**（按 issue 未实现）：项目激活、面板创建、链接点击、刷新/历史导航（#28/#29/#30 各自独立 ticket）。

## 评审整改（第二轮）

Devin Review 六项 finding 全部属实并已修复：

| Finding | 修复 |
|---|---|
| BUG_0001 派发前窗口清单 await 后未复核项目 | `readNativeWindows` 之后、订阅派发之前补第二次关键段复核 |
| BUG_0002 完成挂 `didFinish` 非主文档提交 | 原生 `didCommit` 新发射 `loadCommitted` 事件（含 URL+history 标志）→ Dart `WebviewLoadCommitted`；结算取先到者 |
| BUG_0003 前次导航残留事件误归属本批 | 监听器改为武装-结算：只有本次导航的 `loadStarted`（URL 匹配，容忍尾斜线归一）之后才计入结算事件；武装前事件一律忽略 |
| BUG_0004 `http:/x` 空主机过校验 | 校验补 `uri.host.isNotEmpty` |
| SEC_0001 `[::ffff:127.0.0.1]` 映射写法绕过私网 | `_isLocalHost` 补 IPv4-mapped IPv6（点分+十六进制两式）、inet_aton 数字写法（整数/十六进制/八进制/短点分 `127.1`）、尾点 |
| SEC_0002 请求 URL 带凭据写进诊断日志 | Swift `logFields` 的 url 与 Dart adapter 全部 `_log` URL 字段统一脱敏（`scheme://host[:port]/path`），包括每条 `nativeEvent` 日志 |

附带：被取代语义——武装前后出现指向其他 URL 的 `loadStarted` → `status:cancelled` + `superseded`（替代原误判的 timeout/误归属）。

### 第二轮实机复核（整改后 HEAD `c913e9a`，debug 构建 pid 7462，session automation-52776）

- `hanging.html`（文档秒到、`<img>` 挂 8902 延迟端点）：**58ms 返回 `committed`**——旧实现会等 `didFinish` ~6s，证明完成=主文档提交。慢提交路径（8902 6s 延迟端点）仍 6.05s `committed`（< 8s 预算）。
- 私网绕过写法在 priv=false 项目全部 `private_network_denied`：`http://[::ffff:127.0.0.1]:8901/`、`http://2130706433/`、`http://127.1/`；`http:/x` → `invalid_url`；`8.8.8.8` 正常放行至派发（`timeout`，无可达服务器——门控行为正确）。
- `?session=tok888` 凭据导航后 webview.log 全文 **0 字节** `tok888`；`loadUrl`/`nav.didStart`/`nav.didCommit`/`nav.didFinish`/`dart.nativeEvent` 各事件日志 URL 均为脱敏裸路径，且日志可见 `loadStarted → loadCommitted → loadComplete` 完整事件链。
- 武装-结算的残留事件忽略、superseded 路径由单元测试承载（实机不易稳定复现竞争时序，如实标注）。

## 测试

`flutter test` 291 项全绿，其中 navigate 专项 19 例：参数校验（identityId/url/invalid_url 含空主机）、not_found、project_not_active、private_network_denied 正反、IPv4 写法变形拒绝（`[::ffff:127.0.0.1]`/`2130706433`/`0x7f000001`/`127.1`）、panel_not_open、no_native_view、navigation_in_flight、committed（finalUrl/canGoBack/时间字段/导航 ID）、主文档提交先于整页完成、同 URL、failed（脱敏错误）、cancelled、superseded、残留事件不误归属、timeout。
