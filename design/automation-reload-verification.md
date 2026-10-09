# Issue #28 — `reload` 页面刷新 实机验收记录

基线：`devin/issue28-reload`（navigate 共享导航批次机制之上新增 `reload` 写操作）。
实机：pid 9111，debug 构建（`RELAY_DESK_AUTOMATION=true`），会话 `automation-59949.json`，VerifyHTTP 项目（`bf0a306e`，allowPrivateNetwork=true），Http-A `98205caa`、Http-B `7f78ffc9`；仓库根 `python3 -m http.server 8901` + 6s 延迟服务 8902。采样 17:19–17:21 UTC。证据 JSON 在 `~/Library/Caches/relay-desk/agent-evidence/issue-28/`。

## 设计对应

`reload` 派发走 `WorkspaceController.reload(identityId)` —— 与工具栏/Cmd+R 同一入口，即 WK `reload()` **普通缓存语义**（非强制 no-cache；bypass-cache 变体按 issue 留待另行评估）。完成判定复用 #23 的武装监听+导航批次：等待 `loadStarted(currentUrl)` → `loadCommitted`/`loadComplete`/`blocked`/终态/超时，`status` 集合与 navigate 相同（`committed`/`failed`/`cancelled`/`timeout`）。同 URL 也是新文档、新 `navigationId`。

## 实机矩阵

| 场景 | 操作 | 观测 | 判定 |
|---|---|---|---|
| 普通缓存刷新 | Http-A 已加载评审页 → `reload` | `committed nav-1791566437794-1`，`url` 为脱敏裸路径，dispatched→settled 7ms | 通过 |
| 同 URL 新批次 | 再次 `reload` | `committed nav-1791566443817-2` —— URL 不变，`navigationId` 递增 | 通过 |
| 旧 DOM ref 作废 | reload 前 `dom_find` 签发 `ref 0.8` + `documentId 1prv6…` → reload 后同参数 `dom_inspect` | `stale_element`（非 not_found）—— 新文档使全部旧 ref/documentId 失效 | 通过 |
| 其他身份不受影响 | Http-A 两次 reload 期间/之后查 `panels` | Http-B 面板 `url` 仍为 `review.html`，未重载、未改选中 | 通过 |
| 延迟端点刷新 | Http-B navigate 至 8902 `/never`（文档先行 commit，子资源挂起）→ `reload` | `committed nav-1791566455800-4`，`requestedAt` 17:20:55.800 → `settledAt` 17:21:01.818（子资源挂起不阻塞主文档 commit 语义） | 通过 |
| 刷新后目标可查 | 三次 reload + 一次 navigate 后 | `panels`/`state`/`dom_inspect` 正常返回，`panelQueryable:true` | 通过 |

## 如实边界

- **竞态 409**：`navigation_in_flight`/`panel_busy` 未在本机真实命中——延迟端点主文档 commit 太快，串行 curl 无法制造在途窗口。两分支均由单元测试覆盖（`isNavigating` 短路、传输锁按 identityId 分段）。
- **缓存语义**：`reload()` 即 WK 标准刷新，命中启发式缓存时可能不发请求——接口不承诺"必然回源"，与浏览器 F5 一致；强制 no-cache 属另行评估项。
- **取消/超时**：`cancelled`（外来 loadStarted 抢占、面板关闭）与 `timeout`（8s 预算内无 commit）由单元测试覆盖（stale 事件不误归、外来 loadStarted→`superseded`、预算内无事件→timeout），未实机复现。
- **拒绝链**：`identityId` 缺失 `invalid_input`、跨项目 `project_not_active`、`panel_not_open`、`no_current_url`（面板无 URL）、`no_native_view` 均由单元测试覆盖；实机验证过 `invalid_argument` 级（漏参）与正常路径。

## 范围外（按 issue 未实现）

历史后退/前进（#29/#30 各自 ticket）、点击/输入等交互（#24–#27）、强制 bypass-cache 刷新、脚本注入——均不在本切片。
