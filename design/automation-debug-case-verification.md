# 真实调试案例验收记录（Issue #13）

用已交付的「定位 + 指定身份截图」只读链路，对仓库内一个正在开发的本地页面
做一次完整的「发现 → 取证 → 修复 → 复核」调试循环，验收该链路对代码验收
的实际帮助。

证据源码树：`feature/relay-desk-automation` @ `6013f17`（构建即提交内容）。
截图时间均为 UTC。案例页面为 `.roundtables/auto-update-review/index.html`
（仓库内圆桌评审工具生成的真实页面），由本机 `python3 -m http.server 8901`
提供，缺陷与修复均属本仓库，修复由开发代理在同一任务内完成。

## 案例登记（页面/现象/复现/预期/仓库）

| 项 | 内容 |
|---|---|
| 页面 | `.roundtables/auto-update-review/index.html`，经 `http://127.0.0.1:8901/review.html` 提供（同源旧版对照 `review-old.html` = `git show HEAD:` 提交版） |
| 现象 | 列表被拆碎：`<ol>` 每项重开，结论列表显示 1/1/1；`<ul>`/checkbox 项在句子中间被截断，续行渲染成无 bullet 的孤立段落（页面内 `</ol>+<p>` 5 处、`</ul>+<p>` 9 处） |
| 复现 | 固定复现——静态 HTML 即含拆分结构，任何视口打开都可见 |
| 预期 | 结论列表编号 1/2/3 连续；续行归属原列表项 |
| 仓库 | yonh/relay-desk（页面与其生成器 `bin/render.py` 同库） |

根因：`bin/render.py` 列表循环只吃 marker 行，**缩进续行**（markdown 里
列表项的续段）打断列表 → 续行落入段落分支成 `<p>` → 下一项重开 `<ol>`
编号回退到 1。

## 取证过程与命令

隔离 debug 实例：`flutter build macos --debug --dart-define=RELAY_DESK_AUTOMATION=true`
（源树 `6013f17`），会话 `automation-60170.json`。VerifyHTTP 项目 +
Http-B 身份载入评审页，Http-A 作为防串对照。

```bash
R=build/relayctl/macos-arm64/relayctl
S=~/Library/Containers/com.example.relayDesk/Data/Library/Application\ Support/com.example.relayDesk/automation/automation-60170.json
$R --session "$S" projects
$R --session "$S" identities --project bf0a306e-b7db-469d-95fb-7e0e039b4913
$R --session "$S" panels --project bf0a306e-b7db-469d-95fb-7e0e039b4913
$R --session "$S" screenshot --identity 7f78ffc9-a39f-491e-b886-c9d3491ee503 \
   --output design/evidence/debug-case-2026-10-08/<file>.png
```

定位返回（脱敏节选，B 面板）：

```json
{ "identityId": "7f78ffc9-…", "projectId": "bf0a306e-…", "identityName": "Http-B",
  "state": "embedded", "url": "http://127.0.0.1:8901/review.html",
  "nativeViewId": 2, "windowId": 47, "hasKeyboardFocus": true }
```

## 证据（修复前 → 修复后，同身份同视口）

**编号列表**：`before-numbered-list.png`（17:24:48Z，`review-old.html`，
550×394，`结论` 下连续两项均显示「1.」，续行孤立）→
`after-numbered-list.png`（17:25:24Z，`review.html`，550×394，
编号 2/3 正确、续行并入项内）。

**checkbox 截断**：`before-review-defect.png`（17:20:10Z，550×394，
`☐ 发布前：干净机+公证产物实测（成功路径 + 8s 超时回退 + 杀 helper`
后接无 bullet 孤儿段「注入），结果记 release checklist 后才允许 tag」）→
`after-review-fixed.png`（17:22:17Z，550×394，同区现为一条完整项）。

**同类缺陷旁证**：`before-orphan-2.png`（17:23:41Z，550×394，
`共识` 段两处孤儿段落）。

人工观看结论：修复前 1/1/1 编号与孤儿段落稳定复现且截图可证；
修复后同视口编号连续、续行归位。

## 修复

`.roundtables/auto-update-review/bin/render.py`：列表 item 之后吸收
「缩进且非 marker」的续行并入同一 `<li>`（CommonMark 续行语义），
重生成 `index.html`（`</ol>+<p>`/`</ul>+<p>` 计数 5+9 → 0+0）。

## 该链路实际省去的人工步骤

- **定位**：panels/state 一次查询直接给出 identityId↔nativeViewId↔windowId
  绑定与 URL，免开 devtool/手工比对窗口；显式 `--identity` 选择，双身份
  同屏不会串（A 面板全程未被影响）。
- **取证**：`screenshot` 单命令产出 PNG + capturedAt + 尺寸 + 源 URL 元数据，
  前后两版页面共 4 张对照图，无需手动框选/拼接。
- **复核**：同 selector 重复截图即得同条件对照，旧版页面（`git show` 提交版）
  与修复版在同一身份上交替取证。

## 截图能证与不能证（未验收项）

- **能证（已验收）**：页面渲染缺陷的存在与消失；编号/缩进等布局结果；
  取图身份与窗口归属正确。
- **不能证（未验收）**：缺陷 HTML 由 `render.py` 生成这一归因——截图只到
  渲染结果，生成器根因靠源码阅读得出（`</ol>+<p>` 计数为文本佐证，非截图）。
- **未验证**：截图未覆盖修复是否引入新的排版副作用（其他圆桌页未重渲染
  对比）；页面 JS 交互（seat 过滤）未测。
- **工具缺口（如实记录，不扩）**：面板截图只到当前视口，定位缺陷区域需
  人工滚动页面到位——无 scroll/navigate 能力；修复后取「同条件」截图依赖
  手动复现滚动位置，精度约为屏幕级。

## 遗留

- Issue 留言登记步骤需要 issue 写权限（本会话无），案例登记信息以本文档
  为准，可由仓库持有人在 issue #13 下转贴。
- `review-old.html` 为 `git show` 导出的提交版旧页，非现场伪造。
