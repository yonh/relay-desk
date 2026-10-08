# Issue #32 打开已有身份面板 — 实现与实机验收记录

日期：2026-10-08。环境：macOS（本机 debug 构建，`RELAY_DESK_AUTOMATION=true`）。
实现切片：`devin/issue32-open-panel`，stacked on `devin/issue31-activate-project`（依赖 activate_project；#35 合入后改 base 到 `feature/relay-desk-automation`）。

## 实现方案

- `open_panel` 加入 `automationWriteOperations`（第二个写 op）；capabilities `writeOperations` 同步。
- **显式 `identityId`**：缺参 `invalid_argument`；`identities.getById` 为空 `not_found`(404)。
- **项目门控**：`identity.projectId != readSelectedProjectId()` → `project_not_active`(409)——绝不隐式切换另一个项目；当前项目选择只信 UI provider（与 activate_project 同源）。
- **复用打开路径**：注入 `ensurePanel` = `workspaceControllerProvider.notifier.ensurePanel`——工作区同步所用的同一个控制器方法；指纹/隔离/起始 URL/布局全是 UI 自己的规则，无第二套 WebView 生命周期、不创建身份、不复制 cookie。
- **幂等**：面板已开（非 closed/closing）→ `alreadyOpen:true`，不再调 ensure（不会重复面板、不触发副作用）。
- **就绪诚实**：ensure 后等一帧（`frameSettled`，4s 上限）再读绑定；返回 `panel`（state/loading/url/layout/nativeViewId/hasKeyboardFocus）+ 顶层 `nativeViewId`/`windowId`/`selected`/`hasKeyboardFocus`/`viewReady`。`openingEmbedded`+`nativeViewId` 可并存——视图已注册但状态未转 embedded，`viewReady:false` 如实上报；"打开成功"从不等于"页面就绪"。
- **销毁竞态**：ensure 后面板消失 → `panel_not_active`…`panel_not_open`(409)，可辨识、不静默成功。
- **并发**：传输层按 identityId 锁——同一身份的并发 open_panel 第二个 `panel_busy`(409)。

## 实机验收（会话 automation-50573，全部实际返回）

| 场景 | 实际结果 |
|---|---|
| 激活 VerifyHTTP 后 open Http-A（已开） | `alreadyOpen:true` 零 ensure；完整绑定 `nativeViewId:0 windowId:132 selected:true viewReady:true` |
| 跨项目（Verify-A 属 UpgradeE2E） | `project_not_active`(409)；`state` 仍 VerifyHTTP——无隐式切换 |
| UI 关闭 Http-B 后 open_panel | `alreadyOpen:false`；返回 `state:openingEmbedded nativeViewId:2 viewReady:false`——视图注册中如实上报 |
| 幂等重复 | `alreadyOpen:true viewReady:true`，无重复面板（panels=[A,B] 各一） |
| UI 复核 | Http-B 面板重新出现并加载 review.html（截图实证） |
| 缺 `--identity` | CLI exit 2（双实现一致） |

## 自动测试

- queries open_panel 组 6 项：显式参/not_found/project_not_active 且零 ensure+未切项目/幂等零调用+绑定返回+脱敏/ensure 路径+openingEmbedded+viewReady:false/注册后绑定齐全/消失 →panel_not_open。
- capabilities 写集合断言更新；server 白名单断言更新；relayctl_test.py 30 项。
- 全量 `flutter test` 通过、`flutter analyze` 零问题。

## 如实标注

- 首次打开即时返回恰好落在 `openingEmbedded`（view 已注册、状态未转）——`viewReady:false` 让调用方知道要重查，不冒充就绪；不同机型注册耗时未统计。
- `panel_not_open`（ensure 后消失）仅单测覆盖，实机未构造出身份销毁竞态。
- 独立窗（detached）身份的 open_panel 语义未实机验收——detach 前面板仍在 workspace.panels 中，按 embedded 同路径返回。
- 真实 uni-app 业务身份（南泥湾）不在本机。
