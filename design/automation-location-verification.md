# 真实定位验收记录（Issue #10）

日期：2026-10-08
执行：线上 Devin 会话，独立 macOS debug 实例（`--dart-define=RELAY_DESK_AUTOMATION=true`）
基线：`feature/relay-desk-automation` @ `cfa36ac`；分支 `devin/issue-10-location-verify`
环境：macOS（Devin VM），debug 构建 `build/macos/Build/Products/Debug/relay_desk.app`
测试数据：项目 `UpgradeE2E`（P1，id `4e990d7d`）、`VerifyP2`（P2，id `983423c5`）；身份 `Verify-A`（`6d683554`）、`Verify-B`（`b494a75b`），均为本项目新建测试身份，非业务账号。
查询工具：仓库编译产物 `build/relayctl/macos-arm64/relayctl`（`env -i` 最小环境可运行）。
说明：面板 URL `https://a/`、`https://b/` 为不可达测试地址，页面空白属预期；所有查询均通过 `POST /v1/command` + Bearer 凭据，未接触业务窗口。

## 验收矩阵结果

| 场景 | 步骤 | 预期 | 实际 | 结论 |
|---|---|---|---|---|
| 双身份同屏 | 同项目开 A/B 两面板后 `panels`/`state` | 各 ID 独立、映射真实 | A：`identityId=6d683554 nativeViewId=0 windowId=67 selected=true`；B：`b494a75b nativeViewId=1 windowId=67 selected=false`；按 ID 查询互不串扰 | 通过 |
| 选中与焦点不同 | 点击 B 的 WebView 内部 | 两字段分离 | `selectedIdentityId=6d683554`（A）而 `focusedIdentityId=b494a75b`（B），互不冒充 | 通过 |
| 侧栏/地址栏焦点 | 选中 A 后焦点在侧栏/创建对话框 | focused 不伪装为选中 | `focusedIdentityId=null`、各 view `hasKeyboardFocus=false`，`selectedIdentityId=A` 保持不变 | 通过 |
| 嵌入→独立→重嵌 | B 点 detach → 关独立窗口 | 映射随展示方式变化 | detach 后 B：`state=detached windowId=78 nativeViewId=1`；windows 出现 `windowId=78 title="Relay Desk — b494a75b" identityIds=[B]`，views 同步 `viewId=1→win78`；重嵌后 B 回 `windowId=67 state=embedded nativeViewId=2`（原生视图重建，非复用），窗口 78 从清单消失 | 通过 |
| 项目切换 | P1 选中 A → 切到 P2 | 旧选择不错归属 | `state.project=P2`，`identity/panel=null`，`selectedIdentityId` 仍记录 A 但 `selectionConsistent=false`；`window.identityIds=[]`；`panels` 中 A/B `windowId=null`（后台项目无活跃窗口）；`identities`(P2)=[]、(P1)=[A,B] | 通过 |
| 应用失活→激活 | 激活 Finder → 重新激活 | 失活不回退 mainWindow | 失活：`currentWindowId=null`、`mainWindowId=null`、各窗口 `isKey=false`、`focusedIdentityId=null`、`state.window=null`；激活：`currentWindowId=67 isKey=true` | 通过 |
| 无选择与未知 ID | `--identity`/`--window`/`--identity`(panel) 给不存在值 | not_found，不猜目标 | 三处均 `{"code":"not_found"}`；`window` 不带参数返回 keyWindow（67），无 mainWindow 回退 | 通过 |
| 面板/窗口关闭 | B 点 Close panel | 清单不留伪活跃目标 | `panels` 仅剩 A；`panel --identity B` → `not_found`；`views` 与 `window.identityIds` 均只含 A；B 的 `nativeViewId` 被回收（A 新视图为 3） | 通过 |

## 观察记录（非缺陷，如实记录）

1. **`layout.detached` 字段滞后**：面板 `state=detached` 时其 `layout.detached` 仍为 `false`。`layout` 对象携带的是嵌入态布局快照，`state` 字段才是权威状态；按 ID 定位不受影响。建议后续在文档或序列化中注明 `layout` 为"最近一次嵌入布局"，避免下游误读。
2. **系统辅助窗口进入清单**：`windows` 含 `windowId=72`（64×64、`isVisible=false`、空标题、无 identities），为宿主自身的辅助 NSWindow，不影响 `currentWindowId` 判定。如后续需要可讨论是否过滤不可见空窗口，本切片不改动。
3. **独立窗口标题暴露 identityId 前缀**：`Relay Desk — b494a75b`。属现有实现行为，便于人工对照；是否改用身份名称另行决策。
4. **SIGTERM 后会话文件残留（实测影响）**：`pkill` 应用后 `automation-<port>.json` 仍在磁盘上（dispose 未执行删除）。实测 `relayctl sessions` 按 pid 活性过滤，返回空列表——残留文件不会被当作活会话；其中 token 对应已关闭端口，无可用性。实际影响=磁盘残留一个失效凭据文件，需后续生命周期切片决定是否清扫，不在本切片扩展。

## 本轮执行的检查

- `flutter analyze --no-pub`：无问题（任务前基线复验）
- `flutter test`：209 项全部通过（任务前基线复验，本轮无源码改动）
- relayctl 独立运行：`env -i PATH=/usr/bin:/bin` 下 `capabilities`/查询成功
- 未运行项：无（本切片验收全部实机完成）

## 结论

8/8 场景实机验证通过，未发现需要修改源码的定位缺陷；本切片无生产代码变更，仅新增本验收记录。结论仅覆盖定位可靠性，不代表页面截图、DOM 或业务能力已验收。
