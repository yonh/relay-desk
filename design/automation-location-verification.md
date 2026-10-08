# 真实定位验收记录（Issue #10）

日期：2026-10-08
执行：线上 Devin 会话，独立 macOS debug 实例（`--dart-define=RELAY_DESK_AUTOMATION=true`）
基线：`feature/relay-desk-automation` @ `cfa36ac`；分支 `devin/issue-10-location-verify`
环境：macOS 26.5.2（Devin VM），debug 构建 `build/macos/Build/Products/Debug/relay_desk.app`
查询工具：仓库编译产物 `build/relayctl/macos-arm64/relayctl`（`env -i` 最小环境可运行）

## 运行批次

同一构建先后启动两个应用实例，数据不连续：

| 批次 | 会话文件（pid） | 主窗口 | 项目 | 测试身份 | 覆盖场景 |
|---|---|---|---|---|---|
| R1 | `automation-60929.json`（pid 28527） | windowId 67 | `UpgradeE2E`（`4e990d7d`） | `Verify-A` `6d683554-17ba-4d19-bb0b-bfbc96223e23`、`Verify-B` `b494a75b-a7f0-4895-8c7d-d36ed9c639be`（startPath `/a`、`/b`，页面不可达仅作 ID 映射）；空项目 `VerifyP2`（`983423c5`） | T3 之一、T5、T6 前半、T8、T10、T11 |
| R2 | `automation-61885.json`（pid 30229） | windowId 83 | `VerifyHTTP`（`bf0a306e`，`targetUrl=http://127.0.0.1:8901`，`allowPrivateNetwork=true`） | `Http-A` `98205caa-ac31-46a0-b257-907a4c27702e`（`/a.html`）、`Http-B` `7f78ffc9-a39f-491e-b886-c9d3491ee503`（`/b.html`）；`VerifyP2` 复用 | T1、T2、T3 之二、T4、T6 后半、T7、T9 |

页面由本机 `python3 -m http.server 8901` 提供：`/a.html` 蓝底 `PAGE-ALPHA`/`alpha-marker-111`，`/b.html` 粉底 `PAGE-BETA`/`beta-marker-222`。均为新建测试数据，未操作业务窗口。
界面对照截图随 PR 附：双面板 `PAGE-ALPHA`/`PAGE-BETA`（R2，对应 T1/T2）、"No Panels"（R2，对应 T9）。

## 采样时间说明

`capturedAt` 是每次响应生成时写入的采样时间标记，**不是跨来源的原子快照**：`_state()` 先捕获 Flutter 侧选择状态，再 await 原生窗口/数据库查询。各行为界面在相邻秒内保持静止，命令与截图时间分开记录；界面每次变化后重新取证。

## 验收矩阵（实机执行）

命令形如 `relayctl --session <会话文件> <op> [selector]`；完整命令与脱敏返回见文末证据附录。

| # | 批次 | 场景 | 步骤与采样时间 | 实际结果（脱敏摘要） | 结论 |
|---|---|---|---|---|---|
| T1 | R2 | 双身份同屏+真实页面 | Http-A/Http-B 双面板，截屏约 12:15 | `panels`：A `nativeViewId 0 windowId 83 url …/a.html`；B `nativeViewId 1 windowId 83 url …/b.html`；截图 A→`PAGE-ALPHA`（蓝）、B→`PAGE-BETA`（粉） | 通过 |
| T2 | R2 | state 关联窗口 | `state`，capturedAt `12:15:03Z` | `window.identityIds=[98205caa,7f78ffc9]`、`selectedIdentityId=98205caa`、`focusedIdentityId=null`、`selectionConsistent=true`，与截图对应 | 通过 |
| T3a | R1 | 选中≠焦点 | 点击 Verify-B 的 WebView | `selectedIdentityId=6d683554`（A）、`focusedIdentityId=b494a75b`（B） | 通过 |
| T3b | R2 | 同上（恢复布局后） | 点击 Http-B 的 WebView，capturedAt `12:27:51Z` | 本次 `selectedIdentityId=7f78ffc9`、`focusedIdentityId=7f78ffc9`、`hasKeyboardFocus=true`——点击 WebView 同时选中并聚焦，未发生身份错配 | 通过（行为差异如实记录） |
| T4 | R2 | 地址栏焦点 | 点入 Http-B URL 输入框（光标可见），capturedAt `12:28:13Z` | `focusedIdentityId=null`、panel `hasKeyboardFocus=false`、selected 仍 `7f78ffc9` | 通过 |
| T5 | R1 | 嵌入→独立→重嵌 | Verify-B detach→`windows`/`panel`→关独立窗 | detach：B `state=detached windowId=78`、窗口 `Relay Desk — b494a75b` `identityIds=[b494a75b]`、views `viewId 1→win78`；重嵌：B 回 `windowId=67 state=embedded nativeViewId=2`（视图重建），窗口 78 消失 | 通过 |
| T6 | R1+R2 | 项目切换 | R1：UpgradeE2E→VerifyP2；R2：VerifyHTTP→VerifyP2 | 两批一致：`project=P2`、`identity/panel=null`、旧 `selectedIdentityId` 残留但 `selectionConsistent=false`、`window.identityIds=[]`、后台项目面板 `windowId=null` | 通过 |
| T7 | R2 | 工作区归属 | VerifyHTTP 存 `Ws-HTTP` → `workspaces --project` | `Ws-HTTP`（`06f45e6b`）仅属 VerifyHTTP 且含双面板布局；另两项目返回空；切 P2 后 `workspaceId=null`、`workspace` op `null` | 通过 |
| T8 | R1 | 应用失活→激活 | 激活 Finder→重新激活 | 失活：`currentWindowId=null`（无 mainWindow 回退）、`focused=null`、`state.window=null`；激活：`currentWindowId=67 isKey=true` | 通过 |
| T9 | R2 | 合法无选择 | 关闭全部面板（"No Panels"），capturedAt `12:16:24Z` | `selectedIdentityId=null`、`identity/panel/workspaceId=null`、`panels=[]`、`selectionConsistent=true`；P2 中 `identity`/`panel`/`workspace` 返回 null 不报错 | 通过 |
| T10 | R1 | 未知 ID | `--identity`/`--window`/`panel --identity` 给不存在值 | 三处 `{"code":"not_found"}`，不猜其他目标；`window` 无参数返回 keyWindow | 通过 |
| T11 | R1 | 面板关闭 | Verify-B Close panel | `panels` 仅剩 A；`panel --identity b494a75b`→`not_found`；views 与 `identityIds` 只含 A；旧 `nativeViewId` 不复用 | 通过 |

## 观察记录（如实记录，非缺陷结论）

1. **最小化面板不进入 `panels` 清单**：关闭面板后 UI 显示 "All panels are minimized. Restore one from the toolbar."——控制器保留可恢复的最小化条目，但 `panels` 返回 `[]`、`window.identityIds` 不含其 ID。即"关闭"语义是最小化+销毁原生视图，`panels` 只列活跃目标；按 ID 定位不受影响。经 Ws-HTTP 恢复后同一对身份以新 `nativeViewId`（4）重现。
2. **`layout.detached` 为嵌入快照语义**：`state=detached` 时 `layout.detached=false`；`state` 字段权威。
3. **系统辅助窗口入清单**：`windowId=72`（64×64、不可见、空标题、无 identities），不影响 `currentWindowId` 判定。
4. **独立窗口标题含 identityId 前缀**：`Relay Desk — b494a75b`。
5. **点击 WebView 的选中行为两批不同**：R1 中点 Verify-B WebView 未改变 `selectedIdentityId`（A 保持选中）；R2 中点 Http-B WebView 同时成为选中+聚焦。均如实记录，未判定为缺陷；下游应以查询返回值为准而非假设固定行为。
6. **SIGTERM 后会话文件残留（仅本次观察）**：`pkill` 后 `automation-<port>.json` 留盘。本次实测 `relayctl sessions` 返回空——其发现逻辑仅做 PID 活性过滤，**PID 复用场景未验收**，不能推出旧文件永不会被误列；token 对应已关闭端口不可用。是否清扫由后续生命周期切片决定。

## 本轮执行的检查

- `flutter analyze --no-pub`：无问题（基线复验，本轮无源码改动）
- `flutter test`：209 项通过（同上）
- relayctl 独立运行：`env -i PATH=/usr/bin:/bin` 查询成功
- 未覆盖项：PID 复用下 sessions 过滤；复杂多窗焦点边界未穷尽；均标记待验收

## 证据附录（实际命令与脱敏返回）

会话文件路径记为 `$S`（R1=`automation-60929.json`，R2=`automation-61885.json`）；token/Authorization/完整会话文件不收录。以下为关键定位字段的实际返回节选。

### T2 `relayctl --session $S state`（R2，capturedAt `2026-10-08T12:15:03.895528Z`）

```json
{"project":{"id":"bf0a306e-b7db-469d-95fb-7e0e039b4913","name":"VerifyHTTP"},
 "panel":{"identityId":"98205caa-ac31-46a0-b257-907a4c27702e","state":"embedded",
   "url":"http://127.0.0.1:8901/a.html","selected":true,"nativeViewId":0,"windowId":83,"hasKeyboardFocus":false},
 "window":{"windowId":83,"isKey":true,"identityIds":["98205caa-…","7f78ffc9-…"]},
 "selectedIdentityId":"98205caa-ac31-46a0-b257-907a4c27702e","focusedIdentityId":null,"selectionConsistent":true}
```

### T3b `relayctl --session $S state`（R2，capturedAt `2026-10-08T12:27:51.944940Z`）

```json
{"panel":{"identityId":"7f78ffc9-a39f-491e-b886-c9d3491ee503","state":"embedded",
   "url":"http://127.0.0.1:8901/b.html","selected":true,"nativeViewId":4,"windowId":83,"hasKeyboardFocus":true},
 "workspaceId":"06f45e6b-9890-4e22-b2f5-d5671c620d3c",
 "selectedIdentityId":"7f78ffc9-a39f-491e-b886-c9d3491ee503","focusedIdentityId":"7f78ffc9-a39f-491e-b886-c9d3491ee503"}
```

### T4 `relayctl --session $S state`（R2，capturedAt `2026-10-08T12:28:13.596243Z`，地址栏聚焦中）

```json
{"selectedIdentityId":"7f78ffc9-a39f-491e-b886-c9d3491ee503","focusedIdentityId":null,
 "panel":{"identityId":"7f78ffc9-…","hasKeyboardFocus":false}}
```

### T5 `relayctl --session $S windows`（R1，Verify-B detach 后）

```json
{"windows":[{"windowId":67,"title":"relay_desk","isKey":true,"identityIds":["6d683554-…"]},
  {"windowId":72,"title":"","isVisible":false,"identityIds":[]},
  {"windowId":78,"title":"Relay Desk — b494a75b","isVisible":true,"identityIds":["b494a75b-…"]}],
 "views":[{"viewId":0,"identityId":"6d683554-…","windowId":67},
  {"viewId":1,"identityId":"b494a75b-…","windowId":78}]}
```

`relayctl --session $S panel --identity b494a75b-a7f0-4895-8c7d-d36ed9c639be`（同期）：
`{"panel":{"identityId":"b494a75b-…","state":"detached","nativeViewId":1,"windowId":78}}`
重嵌后：`{"state":"embedded","nativeViewId":2,"windowId":67}`，windows 清单不再有 78。

### T6 `relayctl --session $S state`（切到 VerifyP2 后，R1 12:41Z / R2 12:15:55Z 两次一致）

```json
{"project":{"id":"983423c5-65a8-4b08-8b17-a11f26c988e8","name":"VerifyP2"},
 "identity":null,"panel":null,"window":{"windowId":<67|83>,"identityIds":[]},
 "selectedIdentityId":"<旧批次选中id>","focusedIdentityId":null,"selectionConsistent":false,"workspaceId":null}
```

`relayctl --session $S identities --project 4e990d7d-5234-4e87-a397-b58f27898e7c` → `["Verify-A","Verify-B"]`；不带 `--project`（当前 P2）→ `{"identities":[]}`。

### T7 `relayctl --session $S workspaces --project bf0a306e-b7db-469d-95fb-7e0e039b4913`（R2）

```json
{"workspaces":[{"id":"06f45e6b-9890-4e22-b2f5-d5671c620d3c","projectId":"bf0a306e-…","name":"Ws-HTTP",
  "panels":[{"identityId":"7f78ffc9-…","x":480,"y":0,"width":480,"height":360},
            {"identityId":"98205caa-…","x":0,"y":0,"width":480,"height":360}]}]}
```

`--project 4e990d7d…` 与 `--project 983423c5…` → `{"workspaces":[]}`。P2 中 `relayctl --session $S workspace` → `{"workspace":null}`。

### T8 `relayctl --session $S windows`（R1，激活 Finder 后）

```json
{"currentWindowId":null,"mainWindowId":null,
 "windows":[{"windowId":67,"isKey":false,"isMain":false},{"windowId":72,"isKey":false}]}
```

重新激活后：`"currentWindowId":67`、窗口 67 `isKey=true`。

### T9 `relayctl --session $S state`（R2，capturedAt `2026-10-08T12:16:24.949171Z`）

```json
{"project":{"id":"bf0a306e-…"},"identity":null,"panel":null,
 "window":{"windowId":83,"identityIds":[]},"workspaceId":null,
 "selectedIdentityId":null,"focusedIdentityId":null,"selectionConsistent":true}
```

`relayctl --session $S panels` → `{"panels":[]}`；P2 中 `identity`/`panel`/`workspace` 各 op → `{"identity":null}`/`{"panel":null}`/`{"workspace":null}`。

### T10（R1）

`relayctl --session $S identity --identity 00000000-0000-0000-0000-000000000000` → `{"error":{"code":"not_found","message":"Requested identity does not exist"}}`
`relayctl --session $S window --window 9999` → `{"code":"not_found","message":"Requested window does not exist"}`
`relayctl --session $S panel --identity <不存在id>` → `{"code":"not_found","message":"Requested panel does not exist"}`

### T11（R1，Verify-B 关闭后）

`panels` → 仅剩 Verify-A；`panel --identity b494a75b-…` → `not_found`；`windows` → `views` 仅 `{"viewId":3,"identityId":"6d683554-…","windowId":67}`；`selectedIdentityId=6d683554` consistent=true。

## 结论

矩阵内场景均实机执行并记录证据，未发现需要修改源码的定位缺陷；本切片无生产代码变更，仅含本文档。结论仅覆盖定位可靠性，不代表页面截图、DOM 或业务能力已验收；最终状态以审查通过为准。
