# Issue #40 集成验收证据索引

本目录收录 `design/automation-integration-acceptance.md` 各验收场景的**实际命令返回**（接口内脱敏后原样落盘）。
凭据脱敏由接口内 scrub() 完成；本目录所有 JSON 均不含会话 token、业务域名或真实项目名。

## 版本固定

| 对象 | 固定值 |
|---|---|
| 应用源码 | `8d2580756ea230ad60b7da94bef46cf6e652ce8a`（feature/relay-desk-automation HEAD，验收构建即该提交的工作区） |
| 评审页（案例 A） | `.roundtables/auto-update-review/index.html` blob `657628978147e669df9285b052d6ad6677093046`（提交 `bd481da` 内容） |
| 夹具页目录 | `test/fixtures/pages/` 入库提交 `cc35e91`；本轮修改后 media-seek.html blob `907cf7993f8f9742bec68972756bb1c509601400` |
| relayctl | `build/relayctl/macos-arm64/relayctl`（dart compile exe，与工作区同源构建） |
| 会话 | `automation-52047.json`（endpoint http://127.0.0.1:52047；凭据不入库） |
| 项目/身份 | `bf0a306e-…` VerifyHTTP；`98205caa-…` Http-A(nativeViewId 8/10)；`7f78ffc9-…` Http-B(nativeViewId 9)；windowId 37 |
| 采样批次 | R1 2026-10-09 13:43:24–13:53:16Z；R2（复审补取）14:12:19–14:13:06Z |

## 命令模板

`relayctl <op> [--project <projectId>] [--identity <identityId>] [--ref <f.p> --document-id <nonce>] [--text|--role [+--name]|--selector|--frame|--match <值>] [--output <path>]`
全部命令经 `RELAY_DESK_SESSION=<会话文件路径>` 指向会话；会话文件含 loopback endpoint 与一次性 token（不入库）。

## 场景 → 证据映射

### 基础链路

| 场景 | 命令（参数映射） | 证据文件 | 采样时间 |
|---|---|---|---|
| capabilities | `relayctl capabilities` | `json/capabilities.json` | —（无时间字段） |
| 激活项目 | `relayctl activate_project --project bf0a306e-…` | `json/activate-project.json`（无效 ID `activate-project-badid.json`、幂等 `activate-project-repeat.json`、切回原项 `activate-other.json`） | —（返回无时间字段；执行于 R1 13:43–13:44 窗口） |
| 打开面板（已开幂等） | `relayctl open_panel --identity 98205caa-…` / `7f78ffc9-…` | `json/open-panel-a.json` / `json/open-panel-b.json` | 13:43:24Z |
| 打开面板（未开→打开，R2 补取） | 同命令；前置 UI 关闭 A 面板 | `json/r2-panels-closed.json`（1 面板）→ `json/r2-open-panel-fresh.json`（`alreadyOpen:false`,`state:openingEmbedded`,`viewReady:false`,`nativeViewId:10`）→ `json/r2-open-panel-repeat.json`（`alreadyOpen:true`,`viewReady:true`,同 nativeViewId）→ `json/r2-panels-after.json`（恰 2 面板） | 14:12:19–14:12:25Z |
| 面板清单 | `relayctl panels --project bf0a306e-…` | `json/r2-panels-after.json` | — |

### 案例 A（评审页 Http-A）

| 场景 | 命令 | 证据文件 | 采样时间 |
|---|---|---|---|
| DOM 摘要 | `relayctl dom --identity 98205caa-…` | `json/a-dom.json` | 13:43:49Z |
| 找标题/章节/按钮/重名/P1 | `relayctl dom_find --identity 98205caa-… --text|--role|--name …` | `json/a-find-heading.json` `a-find-buttons.json` `a-find-dup.json` `a-find-p1.json` | 13:43:56–13:44:16Z |
| inspect 章节/P1 | `relayctl dom_inspect --identity 98205caa-… --ref <f.p> --document-id <同次 find 的 documentId>` | `json/a-inspect-heading.json` `a-inspect-p1.json` | 13:44:16Z（inspect 返回无自身时间字段，取同批 find 时间） |
| 截图 | `relayctl screenshot --identity 98205caa-… --output case-a-panel.png` | `json/a-screenshot.json`（返回与 `case-a-panel.png` 对应：byteLength/width/height/nativeViewId 8） | 13:44:23Z |

### 案例 B 媒体（Http-B）

| 场景 | 命令 | 证据文件 | 采样时间 |
|---|---|---|---|
| 媒体矩阵（推进/暂停0/坏源/无源/嵌套/data:/跨源） | `relayctl media --identity 7f78ffc9-…`（逐页导航后采样） | `json/b-media-matrix.json` | 13:45:26Z |
| seek 落点（R1，原夹具 seek 后即播） | 同命令 | `json/b-media-seek-1.json` `b-media-seek-2.json`（仅证明推进，落点判读不足→R2 重取） | 13:44:51/13:44:55Z |
| seek 落点（R2，新夹具 seek 后暂停→15s 播放） | 同命令 | `json/r2-media-seek-paused.json`（`paused:true`,`currentTime:20`）/ `json/r2-media-seek-playing.json`（`paused:false`,`32.34`） | 14:12:44/14:13:06Z |
| 媒体预算（40>32） | 同命令 | `json/b-media-many.json`（`mediaSkipped:8`） | 13:45:38Z |
| 无媒体 | 同命令 | `json/b-media-none.json`（`media:[]`） | 13:45:49Z |

### 案例 B 异常（Http-B）

| 场景 | 命令 | 证据文件 | 采样时间 |
|---|---|---|---|
| 主文档 error/rejection | `relayctl errors --identity 7f78ffc9-…` | `json/b-errors-main.json` | 13:46:06Z |
| 环形溢出（230>200） | 同命令 | `json/b-errors-flood.json`（`overflow:30`） | 13:46:19Z |
| 导航批次（query 变化） | 同命令（导航前后各一） | `json/b-errors-nav1.json`（bufferId `bn7dft…`，batch-0）/ `json/b-errors-nav2.json`（`b8f034…`，batch-1） | 13:48:31/13:48:49Z |
| 凭据脱敏（合成） | 同命令 | `json/b-errors-creds.json`（8/8 标记 `<redacted>`/origin+path/`[object Object]`） | 13:49:04Z |
| 未安装/不可达 | 同命令 | `json/b-errors-unreachable.json` | 13:53:16Z |
| 身份隔离（A 侧） | `relayctl errors --identity 98205caa-…` | `json/a-errors-empty.json`（`installed:true`,`count:0`） | 13:46:06Z |

### 案例 B DOM 边界（Http-B）

| 场景 | 命令 | 证据文件 | 采样时间 |
|---|---|---|---|
| 隐藏内容 | `relayctl dom --identity 7f78ffc9-…` / `dom_find --text SECRET` / `--selector a` | `json/b-dom-hidden.json` `b-find-secret.json` `b-find-links.json` | 13:49:17–13:49:22Z |
| 帧遍历+不可达 | `relayctl dom --identity …`（dom-frame 页）；`dom_find --selector a`（frame 内链接命中） | `json/b-dom-frames.json` `b-find-frame-links.json` | 13:49:34Z |
| 隐藏 iframe 前置 | `dom`/`dom_find --frame fN` | `json/b-dom-mixed.json` `b-find-frame1.json` `b-find-frame3.json`；隐藏位次 `--frame f0`/`f2`→not_found（R2 补取 `json/r2-find-frame0-hidden.json` `r2-find-frame2-hidden.json`）；超预算 `--frame f19`→frame_out_of_scope `json/b-find-frame19.json` | 13:50:30Z；R2 14:14Z |
| 元素移除/替换 | `dom_find --text VICTIM`（变前）→ `dom_inspect --ref 0.6|0.7`（变后） | `json/b-find-victim.json`（变前 0.6/0.7）`b-find-victims.json` `b-inspect-mutated-06.json`（stale_element）`b-inspect-mutated-07.json`（not_found） | 13:50:42/13:51:37/13:52:09Z |
| 同 URL reload | `dom_inspect --ref <旧> --document-id <旧>` | `json/b-inspect-stale.json` `b-inspect-reload-stale.json` | —（inspect 错误返回无时间字段；执行于 13:51–13:52 窗口） |
| 帧预算（20>16） | `dom` / `dom_find --frame f19|f14` | `json/b-dom-many-frames.json`（16 帧/skipped.frames:5）`b-find-frame19.json`（frame_out_of_scope）；R2 补取：`r2-dom-many-frames.json` `r2-find-frame14.json`（界内 label 可解析可扫描，页面无 `<a>`→matchCount:0+complete:false）`r2-find-frame14-hit.json`（`--text ALPHA`→matchCount:1 ref `15.4`） | 13:52:38Z；R2 14:15Z |
| 候选预算（500>400） | `dom_find --text candidate-link` | `json/b-find-manycands.json`（matchCount 400,complete:false） | 13:52:51Z |
| B 面板截图 | `screenshot --identity 7f78ffc9-… --output case-b-panel.png` | `json/b-screenshot.json` | 13:53:03Z |

## 入库证据文件

- `case-a-panel.png`（59KB，评审页面板，对应 `json/a-screenshot.json` 返回的 outputPath/byteLength）
- `case-b-panel.png`（6KB，夹具页面板，对应 `json/b-screenshot.json`）
- `json/`（52 个命令实际返回，308KB，接口内脱敏）
