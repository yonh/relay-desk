# Issue #29 — `back` 历史后退 实机验收记录

基线：`devin/issue29-back`（stacked on `devin/issue27-scroll`）。
实机：debug 构建（`RELAY_DESK_AUTOMATION=true`），会话 `automation-55274.json`，VerifyHTTP Http-A `98205caa` / Http-B `7f78ffc9`。测试页：仓库内夹具 `build/screenshot-pages/hist.html`（pushState 标记页，本机 8901）。采样 18:04–18:13 UTC。证据 JSON：`~/Library/Caches/relay-desk/agent-evidence/issue-29/`。

## 机制声明（按 issue 要求如实）

`back` = 面板自身 WK `backForwardList` 一步 `goBack()`——与工具栏/鼠标侧键完全同一路径（`tryNavigate`），不重导航猜测 URL、不碰其他身份/窗口。支持层分两层如实区分：

- **跨文档后退**（普通页面跳转产生的前进栈）：委托事件可见 → `status:'committed'` + `finalUrl`（脱敏）+ `canGoBack/Forward`，`invalidatedRefs:true`。
- **同文档回退**（`history.pushState`/`replaceState` 条目、`popstate`）：遍历**实际发生**但 WKWebView 不发出 `loadStarted`/`didCommit` 委托事件——靠超时后**回拉 `currentUrl`/`canGoBack`/`canGoForward`** 判定：URL 变化 ⇒ 同文档静默遍历（`status:'committed'` + `sameDocument:true` + `silent:true` + `invalidatedRefs:false`——同一 Document 对象存续，`__rdDocNonce` 未换）；URL 未变 ⇒ 真实未处理层 `status:'timeout'` + `navigationStarted:false` + 提示文案。
- **不支持层**：不经过 `history` 的应用内路由栈（如部分 SPA 内存路由）——无法遍历亦不可辨，落在上面的 timeout 分支，如实报告而非误报成功。

## 实机矩阵

| 场景 | 操作 | 观测 | 判定 |
|---|---|---|---|
| 跨文档后退 | a.html→b.html→`back` | `committed` 5ms（BFCache 一致特征）、`finalUrl:a.html`、`canGoForward:true`、`invalidatedRefs:true`、旧 ref→`stale_element` | 通过 |
| 无历史 | 全新面板 Http-B `back` | `no_history`(409)，canGoBack 前置检查拦截、未派发 goBack | 通过 |
| 同文档 popstate | hist.html 点击 pushState（STATE-0→1）→`back` | `committed`+`sameDocument`+`silent`、`finalUrl` 回落、mark 恢复 `STATE-0`（popstate 实发）、`invalidatedRefs:false` | 通过 |
| 隔离性 | Http-B 从未导航 | Http-A 遍历不影响 Http-B；`no_history` 不误伤其他身份 | 通过 |
| 有界 | 每次一调用一次 goBack | 无超时自动重放；`navigation_in_flight` 前置拒绝 | 通过 |

## 单元测试（11 项，`group('back')`）

参数校验/unknown identity/`project_not_active`/`panel_not_open`/`no_native_view`/`navigation_in_flight`、`no_history` 不派发、committed 批次字段、**静默同文档遍历经 pulled history 判 committed**（`sameDocument`+`silent`+`invalidatedRefs:false`）、pulled url 未变保持 timeout、superseding 遍历取消。

## 实机发现的边界（如实记录，非本切片修复范围）

- **片段 `navigate` 死锁**：`navigate` 到仅差 fragment 的 URL（`b.html#frag`）不产委托事件 → op 超时且 `loading` 闩锁约 30s（native watchdog 复位前后续写 op 报 `navigation_in_flight`）。navigate 期望 URL 比对不含 fragment 语义。属 #23 边界，本 PR 如实记录未扩改。
- **BFCache**：跨文档后退 5ms 落点与 BFCache 恢复特征一致，但无原生标志位区分恢复 vs 快速重载——如实标注"特征一致、未逐位验证"。

## 范围外（按 issue 未实现）

`forward`（#30 待 `back` 稳定后实施）、`goTo` 任意历史项、鼠标侧键之外的历史 API、任意 JS/CDP/MCP——仅 `back`。
