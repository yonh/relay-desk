# 真实调试案例验收记录（Issue #13）

用已交付的「定位 + 指定身份截图」只读链路，对仓库内一个正在开发的本地页面
做一次完整的「发现 → 取证 → 修复 → 复核」调试循环，验收该链路对代码验收
的实际帮助。

## 版本固定

| 对象 | 固定标识 |
|---|---|
| 应用源树（debug 构建） | `feature/relay-desk-automation` @ `6013f17`（`flutter build macos --debug --dart-define=RELAY_DESK_AUTOMATION=true`，构建即提交内容） |
| 旧页面（修复前） | git blob `6ab36edd76840c03e37acba5c69732a53bba569e`（`6013f17:.roundtables/auto-update-review/index.html`），导出为 `build/screenshot-pages/review-old.html`，`git hash-object` 复核一致 |
| 修复后页面 | 重生成 `index.html`，blob `657628978147e669df9285b052d6ad6677093046`，复制为 `build/screenshot-pages/review.html`（两文件 hash 一致） |
| 生成器 | `.roundtables/auto-update-review/bin/render.py`（修复提交见本 PR） |
| 取证会话 | `automation-49983.json`，隔离 debug 实例（第三轮统一取证；前两轮会话 `60170`/`64330` 的完整返回未持久化，相关 PNG 已由本轮同条件重取替换） |

## 案例登记（页面/现象/复现/预期/仓库）

| 项 | 内容 |
|---|---|
| 页面 | `.roundtables/auto-update-review/index.html`，经 `python3 -m http.server 8901` 以 `/review.html`（修复版）与 `/review-old.html`（git blob 旧页）提供 |
| 现象 | 列表被拆碎：`<ol>` 每项重开，结论列表显示 1/1/1；`<ul>`/checkbox 项在句子中间被截断，续行渲染成无 bullet 的孤立段落（旧页 `</ol>+<p>` 5 处、`</ul>+<p>` 9 处） |
| 复现 | 固定复现——静态 HTML 即含拆分结构，任何视口打开都可见 |
| 预期 | 结论列表编号 1/2/3 连续；续行归属原列表项 |
| 仓库 | yonh/relay-desk（页面与其生成器 `bin/render.py` 同库） |

根因：`bin/render.py` 列表循环只消费 marker 行，**缩进续行**（markdown 里
列表项的续段）打断列表 → 续行落入段落分支成 `<p>` → 下一项重开 `<ol>`
编号回退到 1。

## 取证过程与命令

VerifyHTTP 项目 + Http-B 身份载入评审页，Http-A 作为防串对照。

```bash
R=build/relayctl/macos-arm64/relayctl
S=~/Library/Containers/com.example.relayDesk/Data/Library/Application\ Support/com.example.relayDesk/automation/automation-49983.json
$R --session "$S" panels --project bf0a306e-b7db-469d-95fb-7e0e039b4913
$R --session "$S" screenshot --identity 7f78ffc9-a39f-491e-b886-c9d3491ee503 \
   --output design/evidence/debug-case-2026-10-08/<file>.png
```

### 实际返回（脱敏，本轮持久化）

`panels`（切页前，B 在 `/review.html`）：

```json
{ "ok": true, "data": { "panels": [
  { "identityId": "98205caa-ac31-46a0-b257-907a4c27702e", "identityName": "Http-A",
    "state": "embedded", "url": "http://127.0.0.1:8901/a.html", "loading": false,
    "selected": true, "nativeViewId": 0, "windowId": 37, "hasKeyboardFocus": false,
    "layout": {"x":40,"y":40,"width":480,"height":360,"detached":false,"minimized":false} },
  { "identityId": "7f78ffc9-a39f-491e-b886-c9d3491ee503", "identityName": "Http-B",
    "state": "embedded", "url": "http://127.0.0.1:8901/review.html", "loading": false,
    "selected": false, "nativeViewId": 1, "windowId": 37, "hasKeyboardFocus": false,
    "layout": {"x":70,"y":70,"width":480,"height":360,"detached":false,"minimized":false} }
]}}
```

B 地址栏切到 `/review-old.html` 后 `panels`（页面切换后重新定位）：

```text
Http-A http://127.0.0.1:8901/a.html        view 0 win 37
Http-B http://127.0.0.1:8901/review-old.html view 1 win 37
```

B 切回 `/review.html` 后 `panels`：同绑定恢复（view1/win37，URL 回写
`review.html`）。两次切换中 `identityId`/`nativeViewId`/`windowId` 绑定不变，
URL 字段如实跟随导航。

`screenshot` 实际返回（before-numbered 为例，其余同构）：

```json
{ "ok": true, "data": {
  "identityId": "7f78ffc9-a39f-491e-b886-c9d3491ee503",
  "projectId": "bf0a306e-b7db-469d-95fb-7e0e039b4913",
  "nativeViewId": 1, "windowId": 37,
  "capturedAt": "2026-10-08T18:38:59.268002Z",
  "format": "png", "width": 550, "height": 394,
  "url": "http://127.0.0.1:8901/review-old.html",
  "outputPath": "…/design/evidence/debug-case-2026-10-08/before-numbered-list.png",
  "byteLength": 97305 }}
```

## 证据（修复前 → 修复后，同身份同视口，UTC）

| 图 | capturedAt | URL | 内容 |
|---|---|---|---|
| `before-numbered-list.png` | 18:38:59Z | review-old.html | `结论` 连续两项均显示「1.」，续行孤立 |
| `after-numbered-list.png` | 18:38:00Z | review.html | 同区编号 1/2/3 正确、续行并入项内 |
| `before-review-defect.png` | 18:39:43Z | review-old.html | checkbox 项「…杀 helper」截断 + 孤儿段「注入），结果记 release checklist 后才允许 tag」 |
| `after-review-fixed.png` | 18:40:30Z | review.html | 同区为一条完整项 |
| `before-orphan-2.png` | 18:38:39Z | review-old.html | `共识` 段两处孤儿段落旁证 |

人工观看结论：修复前 1/1/1 编号与孤儿段落稳定复现且截图可证；
修复后同视口编号连续、续行归位。

### 重生成附带差异（如实披露）

`index.html` 重生成不仅改变列表结构：speech 源文件 mtime 已统一为
`10-07 23:13`，渲染按 mtime 排序 → 发言顺序由旧页的
`P1,P3,P4,P2,P1,P3,P4` 变为 `P1,P2,P3,P4,P1,P3,P4`（P2 r0 发言前移），
且所有发言时间戳塌缩为 `23:13`。故图片结论**仅限于列表结构与编号**，
不暗示整页唯一变量是渲染器修复；发言顺序/时间戳差异是重生成副作用。
无需为本次验收重构生成器的 mtime 逻辑。

## 修复

`.roundtables/auto-update-review/bin/render.py`：列表 item 之后仅合并
「缩进且非块起始」的**纯文本续行**入同一 `<li>`（本解析器的简化规则，
非完整 CommonMark）：遇到已支持的块起始——fence ```` ``` ````、标题 `#`、
引用 `>`、表格 `|`、分隔线 `---`/`***`、HTML 注释、新列表项——即停止吸收，
保持原有块级渲染（列表内 fence 示例回归验证：`pre/code` 不再被吞入 item）。
重生成 `index.html`（`</ol>+<p>`/`</ul>+<p>` 计数 5+9 → 0+0）。

## 该链路实际省去的人工步骤

- **定位**：`panels` 一次查询直接给出 identityId↔nativeViewId↔windowId
  绑定与 URL，免开 devtool/手工比对窗口；显式 `--identity` 选择，双身份
  同屏不串（A 面板全程 `/a.html` 未受影响）。
- **取证**：`screenshot` 单命令产出 PNG + capturedAt + 尺寸 + 源 URL 元数据，
  前后两版页面共 5 张对照图，无需手动框选/拼接。
- **复核**：同 selector 重复截图即得同条件对照；页面切换（review ↔
  review-old）后 `panels` 重新定位确认绑定不变、URL 跟随。

## 截图能证与不能证（未验收项）

- **能证（已验收）**：页面渲染缺陷的存在与消失；编号/缩进等布局结果；
  取图身份与窗口归属正确；页面切换后目标绑定闭环。
- **不能证（未验收）**：缺陷 HTML 由 `render.py` 生成这一归因——截图只到
  渲染结果，生成器根因靠源码阅读得出（`</ol>+<p>` 计数为文本佐证，非截图）。
- **未验证**：截图未覆盖修复是否引入新的排版副作用（其他圆桌页未重渲染
  对比）；页面 JS 交互（seat 过滤）未测。
- **历史缺失（如实标注）**：前两轮会话（`60170`/`64330`）的完整 panels/
  screenshot 返回未持久化，无法回验；本表所列返回与 PNG 全部来自第三轮
  统一取证（会话 `49983`、view1/win37），可追溯一致。
- **工具缺口（如实记录，不扩）**：面板截图只到当前视口，定位缺陷区域需
  人工滚动页面到位——无 scroll/navigate 能力；取「同条件」对照依赖
  手动复现滚动位置，精度约为屏幕级。

## 遗留

- Issue 留言登记步骤需要 issue 写权限（本会话无），案例登记信息以本文档
  为准，可由仓库持有人在 issue #13 下转贴。
- `review-old.html` 为 `git show 6013f17:` 导出的固定 blob 旧页（hash 复核
  一致），非现场伪造。
