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
- **完成定义**：`committed` = 主文档提交（loadComplete），非"页面加载完/视频可播"；`finalUrl` 为观测事实（重定向后与 `requestedUrl` 可能不同，以 finalUrl 为准）。
- **超时语义**：8s 有界预算 < 传输层 10s 命令超时，故慢页回 200 + `status:timeout` 而非 504；底层 WK 加载仍继续，属"可辨识、可恢复"而非静默。
- **同 URL**：`sameUrl` 仅作标记，导航仍派发（地址栏回车即重载的语义）。
- **不隐式创建**：navigate 不创建身份/面板/项目，不切换项目；全部前置校验（项目活跃→面板存活→原生视图→在途检测→关键段复核）先于派发。
- **脱敏**：`requestedUrl`/`finalUrl` 经 `_stripUrl`（剥凭据/query/fragment）；平台错误文本中的内嵌 URL 经 `_scrubUrlsInText` 再 clip 500 字符——带 `?session=` 的真实导航在响应中无凭据字节。
- **范围外**（按 issue 未实现）：项目激活、面板创建、链接点击、刷新/历史导航（#28/#29/#30 各自独立 ticket）。

## 测试

`flutter test` 286 项全绿，其中 navigate 专项 14 例：参数校验（identityId/url/invalid_url）、not_found、project_not_active、private_network_denied 正反、panel_not_open、no_native_view、navigation_in_flight、committed（finalUrl/canGoBack/时间字段/导航 ID）、sameUrl、failed（脱敏错误）、cancelled、timeout。
