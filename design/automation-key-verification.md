# Issue #26 — `key` 键盘指令 实机验收记录

基线：`devin/issue26-keyboard`（stacked on `devin/issue25-input`）。
实机：debug 构建（`RELAY_DESK_AUTOMATION=true`），会话 `automation-57109.json`，VerifyHTTP Http-A `98205caa`、Http-B `7f78ffc9`；测试页 `build/screenshot-pages/input.html`（本机 8901，标注测试夹具，非业务页面）。采样 17:49–17:52 UTC。证据 JSON：`~/Library/Caches/relay-desk/agent-evidence/issue-26/`。

## 机制声明（按 issue 要求如实）

派发 = 固定原生脚本在**目标元素本身**上派发合成 `KeyboardEvent` 序列（`keydown` [+`keypress` 仅限可打印键与 Enter] + `keyup`）。`mechanism:'synthetic_keyboard_events'`、`isTrusted:false` 均已声明。页面事件处理器可观察；**浏览器原生默认动作不发生**——Tab 不移焦点、Enter 不原生提交表单、不滚动；不触碰 OS/其他应用的全局按键或桌面焦点。键白名单：Enter/Escape/Tab/Backspace/Delete/方向/Home/End/PageUp/PageDown；组合键、修饰键、输入法、自由文本 → `invalid_argument`（明确返回，未支持）。

## 实机矩阵

| 场景 | 操作 | 观测 | 判定 |
|---|---|---|---|
| Enter 可观察 | `dom_find #q` → `key Enter` | `dispatched:true`、`eventsFired:[keydown,keypress,keyup]`、`isTrusted:false`、`keyId:key-…`；页面 keydown 处理器写 `#log`=`KEY-ENTER|code=Enter|keyCode=0|trusted=false`——搜索控件 Enter 行为可观察 | 通过 |
| Escape/Tab/方向 | `key Escape`/`Tab`/`ArrowDown` | 各 `dispatched:true`；非打印键事件集正确为 `[keydown,keyup]`（无 keypress）；`KEY-TAB` 入日志 | 通过 |
| 组合键/未支持键 | `key cmd+q`、`key F5` | `invalid_argument`(400)，消息列出全部支持键并注明 combos/IME unsupported——不发任何事件 | 通过 |
| 隐藏目标 | `key` 指向 hidden 容器内 input | `not_interactable`(409) "Element is hidden" | 通过 |
| 旧引用 | 探测前 ref+旧 nonce | `stale_element`(409) "Document changed since the ref was issued" | 通过 |
| 双身份/OS 焦点 | Http-A 全部操作期间 | Http-B 面板 `review.html` 不变；派发仅限目标元素、无全局焦点移动（机制本身保证） | 通过 |

## 如实边界

- **`keyCode`/`which`/`charCode` 恒为 0**：`KeyboardEvent` init 不可设这些只读旧字段，合成事件如实报 0（页面日志可见 `keyCode=0`）；依赖旧字段的页面须用 `key`/`code`。
- **原生默认动作不发生是机制事实不是缺陷**：Enter 搜索的业务路径必须是页面自己的处理器（真实搜索控件即如此）；纯原生表单提交需 `click` 提交按钮。
- **写后导航观察**沿用 `_armClickNavigation`/`clickNavObserveBudget`(2s)；本页面 Enter 未触发导航，`navigationStarted:false`（单元测试覆盖上报路径）。
- **frame_unreachable/panel_busy** 与 click/input 同路径未单独复验。

## 单元测试（9 项，`group('key')`）

参数校验、白名单外键→`invalid_argument`（含 `cmd+q`/`a`/`F5`/小写 `enter`）、`panel_not_open`、hidden/disabled→`not_interactable` 不重试、`stale_element`→409、机制字段+事件集（Enter 含 keypress、Escape 无）、key 值到达 native query、导航批次+脱敏、`dom_key_failed`→500。

## 范围外（按 issue 未实现）

自由文本键入（用 `input`）、组合键/修饰键/IME、可信输入、OS 级按键、滚动（#27）、历史导航（#29/#30）——仅 `key`。
