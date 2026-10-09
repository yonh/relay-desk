# Issue #20 DOM 页面摘要 — 实现与实机验收记录

日期：2026-10-08。环境：macOS（本机 debug 构建，`RELAY_DESK_AUTOMATION=true`）。
实现切片：`devin/issue20-dom-summary`，stacked on `devin/issue32-open-panel`（#36 合入后改 base 到 `feature/relay-desk-automation`）。

## 实现方案

- 读 op `dom` 入 `automationReadOperations`；capabilities `limitations.dom:true`。CLI `dom --identity`（必需，双实现）。
- **固定探针**：原生只执行 `domProbeScript` 字面量，调用方无法注入任何 JS（与 media/errors 同纪律）。
- **绑定/门控**：(viewId, expectedIdentityId, 实例, 窗口, provisional+commit 代次) 在 evaluateJavaScript 完成时复核——漂移 `target_changed`(409)；`SnapshotCompletionGate`+`deadline` → `dom_timeout`。
- **返回**：`documentId`（探针运行 nonce，`nonce:frameIndex`——同 URL reload 必得新 documentId，旧引用天然失效）/title/url/`frames[]`/`truncated`/`skipped`。
- **元素 ref**：`<frameIndex>.<n>`——本次摘要内的临时引用，非 CSS 路径、不可跨探针复用（为 #21/#22 的元素定位/详情预留）。
- **每文档**：title/url/reachable/elements（tag/role/label≤80字符/href/inputType/name/disabled/tabindex）+ 可见文本摘要（≤24 段、≤480 字符）。
- **安全边界**：inputs 只报 type/name/disabled——`.value` 从不读取（无密码/令牌/输入内容泄漏面）；script/style/noscript/template/canvas/svg/head 全跳过；`hidden`/`aria-hidden` 子树计入 `skipped.hidden`、不采文本。
- **预算**：深度 8、帧 16、元素 300 跨帧共享、标签 80 字符；所有截断经 `truncated`/`skipped{nodes,frames,hidden,textTruncated}` 上报——有界结果不冒充空页面。
- 所有 URL（frame.url、element.href、顶层 url）过 `_stripUrl`（scheme/host/port/path）。

## 实机验收（会话 automation-55249，全部实际返回）

| 场景 | 实际结果 |
|---|---|
| 真实页面（圆桌评审页 Http-B） | title=自动更新 Spec 终审…；52 元素（h1/h2/button 带标签）；text 摘要 480 字符内；`truncated:true` 带 skipped 计数 |
| 加载中页面 | title/els 空、`truncated:false`——加载态与空页如实可辨（不重报） |
| 同源 iframe（dom-frame 夹具） | f0(a.html)/f2(b.html) `reachable:true` 各自 title/elements；跨源 f1(example.com) `reachable:false reason:unavailable` 未越界 |
| href 脱敏 | `/a.html?ref=top#x` → `/a.html`；顶层 url query 剥离 |
| documentId 失效 | 两次连续探针返回不同 docId（`5gvd…`→`nhqv…`→`rbiw…`）——旧引用不可复用 |
| 缺 `--identity` | CLI exit 2（双实现） |

## 自动测试

- queries dom 组 5 项：显式参/not_found+no_native_view/完整返回+href/url 脱敏+嵌套帧+truncated/target_changed 409/坏 JSON dom_failed。
- capabilities `dom:true` + read 集合更新；relayctl_test.py 30 项。
- 全量 `flutter test` 通过、analyze 零问题。

## 如实标注

- 元素集合是"交互相关"白名单（a/button/input/select/textarea/option/summary/label/h1–h4/[role]）——不是全量 DOM；被白名单挡掉的元素计入 skipped.nodes。
- 隐藏判定只查 `hidden` 属性+`aria-hidden`（`display:none` 的 CSS 隐藏未查——getComputedStyle 每节点代价高，已如实记录为覆盖缺口）。
- 文本摘要有界（24 段/480 字符），不适合全文抽取场景。
- 真实 uni-app 业务页面（南泥湾）不在本机；iframe 覆盖用夹具页验收。
