# Issue #24 — `click` 合成元素点击 实机验收记录

基线：`devin/issue24-click`（stacked on `devin/issue28-reload`，DOM 三 op 已在功能分支）。
实机：pid 10707，debug 构建（`RELAY_DESK_AUTOMATION=true`），会话 `automation-49415.json`，VerifyHTTP（priv=true）Http-A `98205caa`、Http-B `7f78ffc9`；测试页 `build/screenshot-pages/click.html|click-target.html`（本机 8901 静态服务，明确标注的测试夹具，非业务页面）。采样 17:31–17:36 UTC。证据 JSON：`~/Library/Caches/relay-desk/agent-evidence/issue-24/`。

## 机制声明（按 issue 要求如实）

点击 = 固定原生脚本内**一次** `HTMLElement.click()` —— 事件为合成不可信（`isTrusted:false`，应答中显式声明 `mechanism:'synthetic_dom_click'`/`isTrusted:false`）。非真实鼠标输入，无坐标回退；需要可信输入的场景本接口明确不支持。一次调用仅派发一次，超时绝不重放。

## 实机矩阵

| 场景 | 操作 | 观测 | 判定 |
|---|---|---|---|
| 导航型点击 | `dom_find selector:a.btn` 签发 `ref 0.8`+documentId → `click` | `dispatched:true`、`mechanism:synthetic_dom_click`、`isTrusted:false`、`navigationStarted:true`、`navStatus:committed`、`navigationId:nav-…-2`、`finalUrl` 已剥 `?from=click&token=secret9`（响应体零凭据字节）、`canGoBack:true` | 通过 |
| 导航后重新定位 | 上条后 `dom_find text:TARGET REACHED` | `matchCount:1`、新文档 `documentId` 正常签发——旧 ref 体系随文档更换失效，新文档可查询 | 通过 |
| 非导航点击 | 返回 click.html → `dom_find selector:#mutbtn` → `click` | `dispatched:true`、`navigationStarted:false`；随后 `dom_find #msg` 读到 `CLICKED-MUT-h5quo`——页面 onclick 真生效（派发事实 ≠ 宣称业务成功，但业务结果可由 DOM 复核） | 通过 |
| 禁用按钮拒绝 | `dom_find selector:#offbtn`(disabled) → `click` | `not_interactable`(409) "Element is disabled"，未派发 | 通过 |
| 隐藏元素拒绝 | `dom_find selector:button` 含隐藏按钮 ref `0.15` → `click` | `not_interactable`(409) "Element is hidden (attribute or computed ancestor)"——动作时 isHiddenDeep 复核命中 | 通过 |
| 旧引用拒绝 | 第一次导航前签发的 `ref 0.8`+旧 documentId → `click` | `stale_element`(409) "Document changed since the ref was issued"，无静默改指 | 通过 |
| 越界引用 | `ref 0.99`+当前 documentId → `click` | `stale_element`(409) "Document shrank"——签发纪律区分 not_found(未签发) vs stale(已失效) | 通过 |
| 双身份隔离 | Http-A 全部操作期间/之后 | Http-B 面板仍 `review.html`、`loading:false`，无串档 | 通过 |
| 目标可查 | 上述全部结束后 `panels` | 双面板正常枚举 | 通过 |

## 单元测试（11 项，`group('click')`）

参数链（缺参 `invalid_argument`）、`project_not_active`/`panel_not_open`/`no_native_view` 拒绝链、payload 错误映射（`stale_element`→409、`not_interactable` 三种 reason、`click_failed`→500）、派发一次不重放（calls==1）、导航批次归属（committed/started-timeout/他身份事件不误归）、mechanism/isTrusted 字段、脱敏断言。

## 如实边界

- **无坐标回退**即设计本身——未做也不宣称真实输入；`isTrusted` 限制已声明。
- **`frame_unreachable`**：跨源 iframe ref 路径与 dom_inspect 共用 frameDocs 可达性判定，未单独实机构造跨源页面（单元/共享脚本一致）。
- **`panel_busy`/`navigation_in_flight`**：传输锁与在途门禁为既有机制，未在本切片重复实机命中。
- **超时不重放**：`clickNavObserveBudget`（默认 2s，注入可调）仅观察导航是否开始；观察超时如实 `navigationStarted:false`，更晚发生的导航由后续 `panels`/`state`/`dom` 查询复核——应答不承诺"此后必无导航"。
- **`documentId` 语义**：每次 DOM 探测签发新 nonce；ref+documentId 仅在最新探测后有效，find→click 须同批使用（与 dom_inspect 契约一致）。

## 范围外（按 issue 未实现）

真实鼠标/键盘输入（#26）、坐标点击、输入/滚动（#25/#27）、历史导航（#29/#30）、任意 JS——本切片仅 `click`。
