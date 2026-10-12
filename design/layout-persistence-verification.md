# Issue #50 验收记录：Canvas 面板布局实时持久化

基线：`main` + `devin/issue50-live-layout`（`fbb31f5`）。debug 构建（`flutter build macos --debug`），VerifyHTTP 项目（Http-A `98205caa` / Http-B `7f78ffc9`），macOS 实机。

## 实现摘要

- 复用 `SavedWorkspaces`/`SavedPanelLayouts` 增加每项目一行保留 `__live__` 工作区（无需 schema 迁移；`getByProject` 排除该保留行，命名工作区不受影响）。落库前按 CHECK 约束 clamp（`x>=0、y>=0、w>=320、h>=240`）。
- 写入触发：`updateBounds(finalCommit)`（拖拽/缩放结束——`finalCommit` 自此有语义）、`setLayoutMode` 重排、`loadWorkspace` 快照、detach/attach 状态切换、`removePanel`（保留关闭面板最后布局）。400ms debounce + 串行写链 + 尾写合并。
- 恢复路径：`restoreProjectLayoutMode` 载入 live 行（布局模式优先 live 行值）；`ensurePanel` 优先持久化布局，回退 `_defaultPanelLayout` 错位排布；`persisted.detached` 在 `registerView` 后按持久化几何重开 detached 窗口（`detach` 支持传入 frame）。
- detached 几何回写：`DetachedWindowController` 增加 `windowDidMove`/`windowDidResize` → `boundsChanged` 事件 → `updateBounds(finalCommit)`。
- 与 `loadWorkspace` 的关系：显式快照恢复 = 把快照布局载入面板并**成为新的 live 布局**（快照立即落库 live 行）；live 持久化 = 恢复实时态。顺序上 `loadWorkspace` 覆盖 live，二者不冲突。

## 实机验收（全过）

| 场景 | 操作 | 结果 |
|---|---|---|
| 拖拽持久化 | Canvas 模式拖 Http-B 至右下 | DB `__live__` 行写入 `188,342 480x360`，布局模式 `canvas` |
| 重启恢复 | quit → relaunch → 选中项目 | B 恢复 188,342；Canvas 模式恢复 |
| 关闭→重开 | 关 Http-A → 项目往返重开 | A 恢复持久化位置（40,40），未重走错位排布 |
| 项目切换往返 | VerifyHTTP → VerifyP2 → VerifyHTTP | 两面板均恢复持久化几何 |
| detached 回写 | detach A → 移动窗口 | DB 更新 `181,0 480x392 detached=1` |
| detached 重启 | quit → relaunch → 选中项目 | detached 窗口按持久化 frame 重开，标题 `Relay Desk — 98205caa` |

单测：`workspace_controller_test` 新增 3 例（saveLive/getLive 往返 + clamp + `getByProject` 排除；restore 加载 + ensurePanel 优先持久化；finalCommit 持久化 + 关→重开恢复），全套 174 项测试绿，`dart analyze` 零告警。

## 已知边界

- `zIndex` 列保留但未引入置顶/置底 UI（issue 允许跳过）。
- detached 窗口几何以原生窗口 frame 存储（含标题栏），与嵌入式面板 canvas 坐标语义不同；恢复路径各自解释同一 `x/y/w/h`。
- 持久化失败静默容错（下次变更重试）；不写凭据、不影响命名工作区列表。
