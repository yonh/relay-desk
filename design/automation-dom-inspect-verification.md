# Issue #22 DOM 元素检查 — 实现与实机验收记录

日期：2026-10-08。切片：`devin/issue22-dom-inspect`，stacked on `devin/issue21-dom-find`。

## 实现方案

- 读 op `dom_inspect`；CLI `dom_inspect --identity --ref <f.p> --document-id <id>`（三者必需）——ref 离开签发它的 documentId 没有意义。
- **stale 检测**：dom/dom_find 探针在扫描时给每个被扫元素打 `__rdRef = <frame>.<position>`、给每个文档打 `__rdDocNonce = docNonce`（expando 属性，非 HTML 属性，不污染 DOM 序列化）。inspect 解析 ref → 按共用 DFS 帧序定位文档 → 校验 `doc.__rdDocNonce` 与 `documentId` 的 nonce 段一致、`els[position].__rdRef === ref`。文档重载/重排/元素替换 → `stale_element`(409)，绝不悄悄指向新占位的元素。
- **`stale_element` vs `not_found`**：位置 ≥2000（探针扫描上限，此 ref 不可能被签发过）→ `not_found`(404)；帧索引越界/文档缩小/标记不符 → `stale_element`(409)；跨源帧 → `frame_unreachable`(409)；ref 格式错 → `invalid_argument`(400)。
- **返回字段**：`{ref, frame, frameIndex, tag, role, name, visible, disabled, checked, selected, focused, attrs, rect, documentId}`。`rect.coordinateSpace:'frame'` 显式标注——元素自身帧的视口相对 CSS 像素，不组合滚动/iframe 偏移。
- **只读白名单**：attrs 仅 id/class/type/name/href/src/alt/title/tabindex/target/rel/for/action/method/placeholder + `aria-*`（≤200 字符）；无 values、无 innerHTML、无密码字段。`href`/`src`/`action` 经 `_stripUrl` 脱敏。
- 条件 JSON 数据嵌入，固定脚本，同一 binding+gate+deadline；`dom_inspect_timeout` 兜底。

## 实机验收（会话 automation-64230）

| 场景 | 实际结果 |
|---|---|
| dom_find → inspect `0.17`（评审页 P1 按钮） | tag button / role button / name 'P1 ● opencode…' / visible / attrs{class,title} / rect x22 y191 288×56 frame 空间 / documentId `…:0` |
| 同 ref+docId 未变文档重查 | 幂等返回同元素 |
| Http-A 真实导航（a.html，文档替换） | `stale_element` 409——旧 ref 不再解析 |
| `--ref 0.2500`（从未签发的位置） | `not_found` 404——与 stale 可区分 |
| 跨源帧 ref | `frame_unreachable` 409（#21 同链路验证） |

## 如实标注

- **失败导航边界**（实机观察）：`webView.url` 先行更新为失败目标 URL，但旧 document 存活时标记仍在——inspect 正确解析旧元素；返回的 `url` 反映目标 URL 而非文档实际内容 URL。非缺陷，如实记录。
- 标记是页面 expando（非属性）：页面自身 JS 理论上可读写同名属性；真实页面冲突概率极低，如实标注。
- 帧坐标系为元素自身帧视口相对值；跨帧绝对坐标需要上层组合 iframe 偏移（本切片不做）。
- 文档变更的粒度是"文档对象存活期"：同文档内的局部 DOM 变更（不替换元素）可能不触发 stale——标记匹配即视有效，元素级变化（attrs/rect 实时重取）如实返回当前值。

## 自动测试

- queries dom_inspect 组 4 项：必需参/ref+docId 透传+href 脱敏/stale 与 frame_unreachable 区分/target_changed。server 读集合、py 32 项。flutter test 全绿、analyze 零问题。
