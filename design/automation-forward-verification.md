# forward 操作 — 真实运行验收（Refs #30）

基线：`devin/issue30-forward`，构建为 macOS debug + `RELAY_DESK_AUTOMATION=true`；
隔离项目 VerifyHTTP、身份 Http-A（`98205caa`），fixture 服务
`python3 -m http.server 8901`（`test/fixtures/pages/` 即 `build/screenshot-pages/`）。
采样时间：2026-10-09 18:34–18:40 UTC。

## 验收矩阵

| 场景 | 操作 | 结果 |
|---|---|---|
| 跨文档 forward | navigate a.html → b.html → back → forward | `status: committed`，`finalUrl=…/b.html`，`invalidatedRefs: true`，`canGoForward: false` ✅ |
| 无前进历史 | forward（位于历史栈顶） | `ok:false`，`error.code: no_history` ✅ |
| 缺 identityId | `{"op":"forward"}` | `invalid_argument`（代码层；运行中旧构建为 `invalid_input`，本提交统一为 `invalid_argument`） |
| 同文档（popstate）链 | hist.html click PUSH-STATE → back → forward | back：`committed`+`sameDocument:true`+`invalidatedRefs:false`+`canGoForward:true`；forward：`committed`+`sameDocument:true`+`invalidatedRefs:false`+`canGoForward:false` ✅ |

## 实现要点

- 与 `back` 同构：dispatch 前 `pullHistoryState` 拉取真实历史基线
  （事件驱动的 `navInfo.canGoForward` 在同文档 back 后会过期，曾误报
  `no_history` —— issue #30 实机捕获）。
- 超时兜底用基线差值判定：URL 变化 **或** `canGoBack`/`canGoForward`
  变化 → `committed`/`sameDocument`；否则如实 `timeout`。
- 同文档遍历 refs 保持有效（`invalidatedRefs:false`）；跨文档遍历全部
  失效（`invalidatedRefs:true`）。
- `identityId` 走 `_optionalString` 严格校验（非字符串/空 →
  `invalid_argument`），与 navigate/reload/back 等一致。
- 原生侧：`back`/`forward` 触发的 load watchdog 在 URL KVO 或
  `canGoForward` 变化且 `!isLoading` 时解除 —— 同文档遍历不再在
  75s 后收到伪 `loadFailed`。

## 边界（如实记录）

- 仅 macOS；`forward` 走 WK `goForward()`，不重放猜测 URL。
- 页面内自建路由栈（不经 `history`/backForwardList）仍如实 `timeout`。
- 单元测试：automation_queries 套件 164 项全绿（含 forward 专项：
  committed 批次、静默同文档、navigation_in_flight 拦截、no_history）。
