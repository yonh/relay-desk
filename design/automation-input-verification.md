# Issue #25 — `input` 表单填写 实机验收记录

基线：`devin/issue25-input`（stacked on `devin/issue24-click`）。
实机：pid 12586，debug 构建（`RELAY_DESK_AUTOMATION=true`），会话 `automation-52952.json`，VerifyHTTP Http-A `98205caa`；测试页 `build/screenshot-pages/input.html`（本机 8901，标注的测试夹具，非业务页面）。采样 17:39–17:41 UTC。证据 JSON：`~/Library/Caches/relay-desk/agent-evidence/issue-25/`。

## 机制声明（按 issue 要求如实）

写入 = 固定原生脚本内调用**原型 `value` setter** + 派发真实冒泡 `input` 与 `change` 事件（`mechanism:'prototype_setter_and_events'`）——Vue/uni-app/React 受控模型经事件更新，单纯 `el.value = v` 不会触达。内容绝不回显/记录：应答仅 `valueLength` + `eventsFired` + `mode`。不自动提交表单、不发回车、不勾协议框——业务提交是另一个显式动作（`click`）。第一版可编辑集：text/search/url/email/password/tel/number 的 INPUT + TEXTAREA。

## 实机矩阵

| 场景 | 操作 | 观测 | 判定 |
|---|---|---|---|
| 搜索框写入 | `dom_find #q` → `input --text hello-world` | `dispatched:true`、`mechanism:prototype_setter_and_events`、`mode:replace`、`valueLength:11`、`eventsFired:[input,change]`、应答无 `hello-world` 字节、`navigationStarted:false` | 通过 |
| 受控模型更新 | 同上后 `dom_find #model` | `label:"model=hello-world"`——页面 input 事件处理器执行，模型真实更新（非仅 DOM value） | 通过 |
| 中文/特殊字符 | `input #cn --text 你好世界·résumé ★` | `dispatched`、`valueLength:13`（UTF-16 计） | 通过 |
| append 语义 | `input #cn --text +追加 --mode append` | `mode:append`、`valueLength:16`（13+3 拼接） | 通过 |
| textarea + change | `input #ta --text textarea-body` | 页面 change 处理器写 `#log`=`CHANGE-FIRED:13`——change 事件真实触发 | 通过 |
| readonly 拒绝 | `input #ro(readonly)` | `not_interactable`(409) "Element is readonly"，未写入 | 通过 |
| disabled 拒绝 | `input #dis(disabled)` | `not_interactable`(409) "Element is disabled" | 通过 |
| 非可编辑类型 | `input #chk(checkbox)` | `not_interactable`(409) "not an editable input/textarea of a v1 type"——不静默写其他元素 | 通过 |
| 隐藏元素 | `input #hid(display:none 容器内)` | `not_interactable`(409) "Element is hidden" | 通过 |
| 密码字段 | `input #pw(password)` | `dispatched`、`valueLength:1`；`dom_inspect #pw` 属性白名单仅 `{id,type}`——value 不回显也不在后续 DOM 输出泄露 | 通过 |
| 旧引用拒绝 | `input` 旧 nonce 的 `ref 0.7` | `stale_element`(409) "Document changed since the ref was issued; re-probe" | 通过 |

## 单元测试（9 项，`group('input')`）

参数校验（缺 identityId/ref/documentId/text、非法 mode→400）、`panel_not_open`、`not_interactable`→409 不重试（calls==1）、机制字段+不回显断言（响应体无提交文本；query 以 JSON 数据送达）、append 透传、写后导航上报+脱敏 finalUrl、他身份事件不归因、`dom_input_failed`→500、`stale_element`→409。

## 如实边界

- **`frame_unreachable`** 路径与 click 共用 frameDocs 可达性判定，未单独构造跨源页。
- **写后导航观察**沿用 `_armClickNavigation` + `clickNavObserveBudget`(2s)；本切片页面未触发导航，`navigationStarted:false` 属正常路径（单元测试覆盖上报）。
- **类型之外的可编辑集**（checkbox/radio/file/range/button、contenteditable、select）一律 `not_interactable`——按设计拒绝，未尝试写入。
- **业务提交不在本 op**：submit/回车/勾选由调用方显式 `click`（或后续键盘 op #26）。
- **docnonce 每次探测新签**：find→input 须同批使用（与 DOM ops 契约一致）。

## 范围外（按 issue 未实现）

键盘输入（#26）、滚动（#27）、历史导航（#29/#30）、真实可信输入、任意 JS——仅 `input`。
