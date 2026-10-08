# Issue #21 DOM 元素搜索 — 实现与实机验收记录

日期：2026-10-08。切片：`devin/issue21-dom-find`，stacked on `devin/issue20-dom-summary`。

## 实现方案

- 读 op `dom_find`；CLI `dom_find --identity --text|--role|--selector`（恰好一个条件），可选 `--match exact|contains`（默认 contains）、`--name`（role 辅助）、`--frame <label>`。
- **无任意 JS**：条件以 JSON 字符串传给原生，嵌入为 `var __rdQuery = <json>;` 数据字面量 + 固定 `domFindScriptTail`——调用方输入永不进入可执行位置。
- **ref 一致性**：ref = `<frameIndex>.<querySelectorAll('*') 位置>`；dom/find 两探针共用 DFS 帧序+文档序——同一未变文档下 find 的 ref 与 dom 摘要的 ref 指向同一元素（#22 inspect 的解析基础）。
- **返回**：`documentId`（本次探针 nonce）+`matchCount`+有界 `matches`（50：ref/frame/tag/role/label≤80/visible/disabled）+`truncated`。多条如实列出不首挑。
- **text**：可见文本归一化匹配（innerText≤400 的元素），exact/contains；只保留最深匹配（祖先仅因子代命中即丢弃）——返回可直接操作的叶子元素。
- **role**：显式 `role` 属性或标签隐含角色（a→link、button、input 类型映射、标题/列表/表格等）；`name` 按可访问名二次过滤。
- **selector**：原生 `querySelectorAll`，语法错误 →`invalid_selector`(400)；命中元素映射回文档序 ref。
- **frame**：`--frame` 指定帧标签；不存在 →`not_found`，跨源 →`frame_unreachable`(409)；缺省搜所有可达帧。
- 0 命中 →`not_found`(404)；漂移 →`target_changed`(409)；超时 `dom_find_timeout`。只读：无点击/输入/属性写。
- 预算：扫描 2000/候选 400/返回 50，截断如实上报。

## 实机验收（会话 automation-59743）

| 场景 | 实际结果 |
|---|---|
| 真实评审页 text "总结者" | count:1，`0.13 main span '总结者 host'`——最深匹配，祖先未混入 |
| role button | count:6（4 个 P1–P4 卡片按钮+顶部/底部导航按钮），ref/tag/label/visible 齐全 |
| selector h2 | count:43，全部 h2 标题带短标签 |
| frame f0（同源 iframe） | count:1，`1.4 f0 div 'PAGE-ALPHA…'`——帧索引与 dom 输出一致（f0=帧1） |
| frame f1（跨源） | `frame_unreachable` 409 |
| 非法 selector `[[[` | `invalid_selector` 400 |
| 0 命中 | `not_found` 404 |

## 自动测试

- queries dom_find 组 5 项：必需参+单条件约束/条件 JSON 透传+匹配返回+脱敏/0 命中 not_found/invalid_selector+frame_unreachable 区分/target_changed。
- server 读集合 + py 31 项。全量 flutter test 通过、analyze 零问题。

## 如实标注

- text 匹配基于 `innerText`（渲染文本）：CSS `display:none` 内容天然不命中；但 `innerText` 依赖布局，被裁区域不可见文本仍可能命中（visible 字段如实标注）。
- 隐含角色映射是常见子集（非完整 ARIA 规范）；未覆盖角色可用显式 `role` 属性元素或 selector 兜底。
- ref 跨探针一致的前提是"文档未变"——任何 DOM 变更都会移位，`stale_element` 检测是 #22 inspect 的职责。
- 真实 uni-app 业务页未在本机；iframe 场景用夹具验收。
