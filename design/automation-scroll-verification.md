# Issue #27 — `scroll` 滚动定位 实机验收记录

基线：`devin/issue27-scroll`（stacked on `devin/issue26-keyboard`）。
实机：debug 构建（`RELAY_DESK_AUTOMATION=true`），会话 `automation-60061.json`，VerifyHTTP Http-A `98205caa`；测试页 `build/screenshot-pages/scroll.html`+`scroll-inner.html`（本机 8901，标注测试夹具，含长页面、sticky header、嵌套滚动容器、同源 iframe）。采样 18:05–18:12 UTC。证据 JSON：`~/Library/Caches/relay-desk/agent-evidence/issue-27/`。

## 机制声明（按 issue 要求如实）

滚动 = 固定原生脚本内 DOM 滚动（`scrollIntoView`/`scrollBy`/`scrollTo`，`behavior:'auto'` 瞬时——无动画等待条件，返回即最终位置）。单位一律 CSS px（`unit:'css-pixel'`）。不触发任意脚本、不猜桌面坐标、不自动点击/截图（截图是既有独立 op）。`into_view` 的前后度量落在**帧文档的 scrollingElement**（目标元素自身 scrollTop 恒不变），`delta`/`position` 落在所选容器——如实区分文档 vs 嵌套容器 vs 同源 iframe。

## 实机矩阵

| 场景 | 操作 | 观测 | 判定 |
|---|---|---|---|
| 文档增量 | `scroll --document-id D --mode delta --dy 400` | `container:document`、`before.top:0→after.top:400`、`movedY:400`、`unit:css-pixel` | 通过 |
| 边界钳制 | `--dy 19999` | `movedY:806`（页面截断）、`after.top=maxTop:2896`、`atBottom:true` | 通过 |
| 越界拒绝 | `--dy 99999` | `invalid_argument`(400) "|v| <= 20000 CSS px" | 通过 |
| 元素滚入视野 | `scroll --ref 0.16`（#evidence）| `container:document`、`movedY:2090`、`target.rect.y≈0`、`visibleInViewport:true`、无遮挡 | 通过 |
| 嵌套容器 | `scroll --ref 0.9(#nest) --mode delta --dy 700` | `container:element`、`containerTag:div`、`movedY:700`——滚动的是元素容器非主页面 | 通过 |
| 同源 iframe 滚入 | `--ref 1.8(#inner-bottom)`（frame f0）| iframe 文档滚 `movedY:388`、目标可见、`frame:f0` | 通过 |
| iframe 文档增量 | `--document-id D:1 --mode delta --dy 300` | `frame:f0` doc `movedY:196`、`after.top:584`、`atBottom:true`——iframe 文档按 documentId 帧索引滚动 | 通过 |
| 绝对位置 | `--mode position --x 0 --y 0` | `movedY:-1476`、`after.top:0`、`atTop:true` | 通过 |
| 旧引用 | `scroll` 旧 nonce | `stale_element`(409) | 通过 |

## 单元测试（8 项，`group('scroll')`）

参数校验（缺参/`into_view` 缺 ref/非法 mode→400）、`panel_not_open`、无 ref delta→文档容器、into_view 目标 rect+可见+遮挡字段、元素容器 ref 透传、`stale_element`→409、越界 `invalid_argument`→400、`dom_scroll_failed`→500。

## 如实边界

- **遮挡检测已实现但实机未命中**：`elementFromPoint` 遮挡上报存在（单元测试覆盖 `occludedBy` 字段）；本夹具 sticky header 60px、目标元素均 ≥180px，中心点未落入遮挡区——如实标注。
- **滚动动画**：固定 `behavior:'auto'` 瞬时滚动，无等待条件；页面自带 CSS `scroll-behavior:smooth` 场景下的行为未验（如实声明）。
- **位置语义**：rect 为帧视口相对 CSS px（坐标空间注明 `frame`），iframe 内目标不合成主页面坐标偏移。

## 范围外（按 issue 未实现）

鼠标滚轮事件、拖拽滚动条、自动截图组合（`scroll`+`screenshot` 由调用方串接）、历史导航（#29/#30）——仅 `scroll`。
