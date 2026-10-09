# Issue #31 激活项目 — 实现与实机验收记录

日期：2026-10-08。环境：macOS（本机 debug 构建，`RELAY_DESK_AUTOMATION=true`）。
实现切片：`devin/issue31-activate-project`，base `devin/issue17-js-errors`（栈叠避免同文件冲突；#33/#34 合入后 rebase 到 `feature/relay-desk-automation`）。

## 实现方案（先于实现说明）

- **写操作白名单**：`automationWriteOperations = {'activate_project'}`，与只读集合分开枚举；传输层放行 read∪write，其余仍在 dispatch 前拒。`capabilities` 升 `protocolVersion:2`、`readOnly:false`、`writeOperations` 单列（reads 留在 `operations`），`limitations.projectActivation:true`。
- **复用 UI 入口**：`_activateProject` 调用注入的 `selectProject`——即侧栏点击所用的 `selectedProjectIdProvider.notifier.select(projectId)`，布局恢复/面板同步全是 UI 自己的语义，不碰数据库。
- **显式 projectId**：缺参 `invalid_argument`；`projects.getById` 为空 `not_found`(404)；无名称匹配、不静默选别的项目。
- **竞争序列化**：传输层 `_project` 单一锁——任何并发 activate（包括不同项目）第二个得 `panel_busy`(409)，杜绝 last-writer-wins 双成功假象。
- **结算语义**：`select` 后等一帧（`endOfFrame`，4s 上限 `frameSettled`）+ `settleBudget`（2s）轮询 `WorkspaceState.selectedProjectId`——workspace 标记因 `restoreProjectLayoutMode` 的异步 repo 读可能滞后。`settled:false` = "仍在收敛，重查 state"，不冒充失败也不冒充成功。
- **返回**：`projectId`/`project`/`alreadyActive`/`activatedAt`/`selectedProjectId`/`workspaceSelectedProjectId`/`selectedPanelId`/`selectionConsistent`/`focusedIdentityId`（原生焦点单列，不假定等于 UI 选中）/`frameSettled`/`settled`/`panels`（当时驻留快照）。
- **幂等**：已激活 → `alreadyActive:true`，不重复调 provider（不触发切换副作用）。

## 实机验收（全部来自实际返回，2026-10-08 UTC）

会话 `automation-63296.json`（pid 见文件）。真实项目：VerifyP2 `983423c5`（零身份）、VerifyHTTP `bf0a306e`（Http-A/B）。

| 场景 | 实际结果 |
|---|---|
| 激活 VerifyP2（零身份） | `alreadyActive:false`→UI 切到 VerifyP2 空工作区视图（截图实证）；`selectedProjectId` 立即命中；`settled:false`——workspace 标记 2s 内未收敛，如实上报；稍后 `state` 显示 VerifyP2、`panels:[]` |
| 激活 VerifyHTTP | `settled:true`（标记在预算内追上）；`panels`=[Http-A,Http-B] 驻留面板返回；`selectionConsistent:true`；UI 截图显示 VerifyHTTP 选中+双面板+布局恢复 |
| 切换不误归旧身份 | VerifyP2→VerifyHTTP：`selectedPanelId`=Http-A（属新项目），旧项目残留不误挂新项目 |
| 重复激活 | `alreadyActive:true`、`settled:true`，provider 未被重复调用（单测断言 calls==0） |
| 无效 projectId | `not_found`(404)，exit 1，UI 状态不变（未静默改选） |
| 缺 `--project` | CLI `exit 2`（双实现一致） |
| 并发激活 | `_project` 锁 → 第二个 `panel_busy`(409)（server 单测覆盖） |
| capabilities | `v2`、`readOnly:false`、`writeOperations:['activate_project']`、`projectActivation:true` |

## 自动测试

- `automation_queries_test` activate_project 组 7 项：显式参/not_found 且零副作用/激活路径+三信号返回+脱敏断言/幂等零调用/`settled:false` 上报/写 op 不再 unsupported/capabilities 声明；capabilities 主测试改 v2 契约。
- `automation_server_test`：写白名单集合断言 + `activate_project` 并发 `panel_busy` 序列化 + 完成后可重试。
- `relayctl_test.py` 29 项（activate_project 转发 + 必需 `--project`）。
- 全量 `flutter test` 通过、`flutter analyze` 零问题。

## 如实标注的未覆盖项

- VerifyP2 激活出现 `settled:false` 的路径：零身份项目下 workspace 标记未在 2s 内收敛（UI 已切且 `state` 一致）——语义为"仍在收敛"，文档已写明读取方式；不同机型收敛耗时未统计。
- "南泥湾"项目不在本机（验收用 VerifyP2/VerifyHTTP 真实项目）；真实 uni-app 业务项目待你环境复核。
- `frameSettled:false`（`endOfFrame` 超时）未实机命中——UI 总能产帧；路径有界（4s）。
- 停用/退出竞态（应用退出中激活）未覆盖——写窗口与进程退出交叠属边缘；`panel_busy` 传输层锁已防并发写入。
