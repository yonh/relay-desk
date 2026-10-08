# 真实定位验收记录（Issue #10）

日期：2026-10-08
执行：线上 Devin 会话，独立 macOS debug 实例（`--dart-define=RELAY_DESK_AUTOMATION=true`）
基线：`feature/relay-desk-automation` @ `cfa36ac`；分支 `devin/issue-10-location-verify`
环境：macOS 26.5.2（Devin VM），debug 构建 `build/macos/Build/Products/Debug/relay_desk.app`
查询工具：仓库编译产物 `build/relayctl/macos-arm64/relayctl`（`env -i` 最小环境可运行）

## 测试数据与页面

- 项目 `VerifyHTTP`（id `bf0a306e`，`targetUrl=http://127.0.0.1:8901`，`allowPrivateNetwork=true`），页面为本机 `python3 -m http.server 8901` 提供的两个内容明显不同的静态页：
  - `/a.html`：蓝底、`PAGE-ALPHA` / `alpha-marker-111`
  - `/b.html`：粉底、`PAGE-BETA` / `beta-marker-222`
- 身份 `Http-A`（`98205caa`，startPath `/a.html`）、`Http-B`（`7f78ffc9`，startPath `/b.html`）；另有前一轮在 `UpgradeE2E`（P1，`4e990d7d`）下的 `Verify-A`（`6d683554`）、`Verify-B`（`b494a75b`，指向不可达地址，仅作 ID 映射用）与空项目 `VerifyP2`（P2，`983423c5`）。
- 均为新建测试数据，非业务账号；未操作任何业务窗口。
- 界面对照截图随 PR 附：双面板 `PAGE-ALPHA`/`PAGE-BETA` 同屏（对应下表 T2 采样）、全部关闭后 "No Panels"（对应 T9）。

## 验收矩阵（实机执行）

采样命令形如 `relayctl --session <file> <op>`；`capturedAt` 为服务端返回的原子捕获时间，界面在相邻秒内保持未动时与其对应；界面变化后均重新取证。

| # | 场景 | 步骤与采样 | 实际结果（脱敏） | 结论 |
|---|---|---|---|---|
| T1 | 双身份同屏+真实页面 | 同项目 Http-A/Http-B 双面板，截屏对照（T2 同刻） | panels：A=`nativeViewId 0 windowId 83 url http://127.0.0.1:8901/a.html`；B=`nativeViewId 1 windowId 83 url …/b.html`；截图 A 面板显示 `PAGE-ALPHA`（蓝）、B 显示 `PAGE-BETA`（粉） | 通过 |
| T2 | state 关联窗口 | `state` capturedAt `2026-10-08T12:15:03Z` | `window.identityIds=[A,B]`、`selectedIdentityId=A`、`focusedIdentityId=null`、`selectionConsistent=true`，与截图一一对应 | 通过 |
| T3 | 选中≠焦点 | 点击 B 的 WebView 内部后 `state` | `selectedIdentityId=A`、`focusedIdentityId=B` | 通过 |
| T4 | 地址栏焦点 | 点入 B 面板 URL 输入框（光标可见）后 `state`/`windows`，capturedAt `12:15:19Z` | `focusedIdentityId=null`；views 两项 `hasKeyboardFocus=false`；selected 仍为 A | 通过 |
| T5 | 嵌入→独立→重嵌 | B detach→查 `windows`/`panel`→关独立窗→复查 | detach：B `state=detached windowId=78`，窗口 `Relay Desk — b494a75b` `identityIds=[B]`，views `viewId1→win78`；重嵌：B 回 `windowId=67 state=embedded nativeViewId=2`（视图重建不复用），窗口 78 消失 | 通过 |
| T6 | 项目切换 | P1(HTTP)→P2 后 `state`/`panels`/`identities`/`workspace` | `project=P2`、`identity/panel=null`、`selectedIdentityId` 残留旧 ID 但 `selectionConsistent=false`、`window.identityIds=[]`；P1 面板 `windowId=null`；`identities`(P2)=[]、显式 P1=[A,B] | 通过 |
| T7 | 工作区归属 | VerifyHTTP 内 Save workspace `Ws-HTTP` → `workspaces --project` 各项目 | `Ws-HTTP`（`06f45e6b`）仅出现在 VerifyHTTP 下，含 A/B 两面板布局；UpgradeE2E/VerifyP2 返回空；保存后 `state.workspaceId=06f45e6b`；切到 P2 后 `workspaceId=null`、`workspace` op `null` | 通过 |
| T8 | 应用失活→激活 | 激活 Finder→重新激活 relay_desk | 失活：`currentWindowId=null`（无 mainWindow 回退）、各窗 `isKey=false`、`focused=null`、`state.window=null`；激活：`currentWindowId=83 isKey=true` | 通过 |
| T9 | 合法无选择 | VerifyHTTP 关闭全部面板（"No Panels"）后 `state`/`panels`，capturedAt `12:16:24Z` | `selectedIdentityId=null`、`focusedIdentityId=null`、`identity/panel/workspaceId=null`、`panels=[]`、`selectionConsistent=true`；P2 中 `identity`/`panel`/`workspace` op 均返回 `null` 不报错 | 通过 |
| T10 | 未知 ID | `--identity`/`--window`/`panel --identity` 给不存在值 | 三处均 `{"code":"not_found"}`，CLI 不猜测其他目标；`window` 不带参数返回 keyWindow | 通过 |
| T11 | 面板/窗口关闭 | B Close panel | `panels` 仅剩 A；`panel --identity B`→`not_found`；views 与 `window.identityIds` 只含 A；旧 `nativeViewId` 不复用 | 通过 |

## 观察记录（如实记录，非缺陷结论）

1. **`layout.detached` 为嵌入快照语义**：`state=detached` 时 `layout.detached` 仍为 `false`——`layout` 是最近一次嵌入布局快照，`state` 字段权威；按 ID 定位不受影响。
2. **系统辅助窗口入清单**：`windows` 含 `windowId=72`（64×64、`isVisible=false`、空标题、无 identities），不影响 `currentWindowId` 判定。
3. **独立窗口标题含 identityId 前缀**：`Relay Desk — b494a75b`，现有实现行为。
4. **SIGTERM 后会话文件残留（仅本次观察）**：`pkill` 后 `automation-<port>.json` 留盘。本次实测同一进程结束后 `relayctl sessions` 返回空列表——其发现逻辑仅做 PID 活性（`kill -0`）过滤，**PID 复用场景未验收**，不能由此推出旧文件永不会被误列；其中 token 对应已关闭端口不可用。是否清扫由后续生命周期切片决定，本切片不扩展。

## 本轮执行的检查

- `flutter analyze --no-pub`：无问题（基线复验，本轮无源码改动）
- `flutter test`：209 项通过（同上）
- relayctl 独立运行：`env -i PATH=/usr/bin:/bin` 查询成功
- 未覆盖项：PID 复用下 sessions 过滤；复杂多窗组合的 AppKit 焦点边界未穷尽；均标记待验收

## 结论

矩阵内场景均实机执行并记录证据，未发现需要修改源码的定位缺陷；本切片无生产代码变更，仅含本文档。结论仅覆盖定位可靠性，不代表页面截图、DOM 或业务能力已验收；最终状态以审查通过为准。
