# 自动化接口集成验收（Issue #40）

> 验收对象：`feature/relay-desk-automation` 已合入的全部公开调试接口。
> 本报告为**验收执行记录**：环境、命令、实际返回与通过/失败/未覆盖逐项登记。
> 状态：待 Codex 审查。

## 1. 验收基线与产物版本

| 项 | 值 |
|---|---|
| 源码 HEAD | `8d2580756ea230ad60b7da94bef46cf6e652ce8a`（验收分支 `devin/issue40-integration-acceptance` 基于该提交，应用代码与其一致；本 PR 仅新增夹具页与文档） |
| 构建 | `flutter build macos --debug --dart-define=RELAY_DESK_AUTOMATION=true`（debug 包，pid 2339） |
| CLI | 仓库 `tool/relayctl.dart` 同 HEAD 本地编译（无独立版本号；Mach-O arm64，仅链系统库） |
| 会话 | `automation-52047.json`（endpoint+token，token 不入证据） |
| 采样窗口 | R1 2026-10-09 13:43–13:53 UTC；R2（复审补取）14:12–14:13 UTC |
| 环境 | macOS（本机 arm64）；页面服务 `python3 -m http.server 8901 --bind 127.0.0.1 --directory <repo>` |
| 隔离资源 | 项目 `VerifyHTTP`（`bf0a306e`）、身份 `Http-A`（`98205caa`）/`Http-B`（`7f78ffc9`）——通用验收代号，非业务身份 |

案例页面版本固定（`git hash-object` 可复核）：

- 评审页 `.roundtables/auto-update-review/index.html` blob `657628978147e669df9285b052d6ad6677093046`（提交 `bd481da` 之内容）
- 夹具页 `test/fixtures/pages/` 随本 PR 入库提交 `cc35e91`；逐页 blob 见 `design/evidence/issue40-integration/INDEX.md`。复审轮 `media-seek.html` 改为两相位（seek 后暂停→15s 播放），新 blob `907cf7993f8f9742bec68972756bb1c509601400`——改动前的 R1 证据仅证明推进、落点不可独立判读，已按未验证处理并以 R2 重取（见 §4）。

## 2. 基础链路

| 检查 | 命令 | 实际观察 | 结论 |
|---|---|---|---|
| capabilities | `relayctl capabilities` | `protocolVersion:2`；读 op 14 个 + 写 op 2 个（`activate_project`/`open_panel`）；`readOnly:false`，写白名单显式列出 | 通过 |
| 激活项目 | `relayctl activate_project --project bf0a306e…` | `alreadyActive:false`→选中+打开 A 面板；重复调用 `alreadyActive:true`；无效 UUID `not_found`；切走再切回各自选中恢复、`selectionConsistent:true` | 通过 |
| 打开面板（已开） | `relayctl open_panel --identity <B>` | `alreadyOpen:true`/`viewReady:true`/`windowId:37`/`nativeViewId:9`，重复调用幂等无重复面板 | 通过 |
| 打开面板（未开→打开，R2 补取） | UI 关闭 A 面板（panels 恰 1）→ `open_panel --identity <A>` → 再调一次 → `panels` | 首调 `alreadyOpen:false`、`state:openingEmbedded`、`viewReady:false`、`windowId:null`、新 `nativeViewId:10`、`frameSettled:true`；复调 `alreadyOpen:true`、`state:embedded`、`viewReady:true`、`windowId:37`、同 `nativeViewId:10`；`panels` 恰 2（无重复面板） | 通过 |
| 面板/截图一致性 | `panels` + `screenshot --identity A --output …` | A url=评审页（view 8 / win 37）；PNG 550×394、59KB，内容与 DOM 标题「自动更新 Spec 终审」一致 | 通过 |
| 证据 | `case-a-panel.png`、`capabilities.json` 等 | 见 §7 | — |

## 3. 案例 A：仓库真实评审页

页面：`/.roundtables/auto-update-review/index.html`（Http-A 面板地址栏导航加载，操作与接口证据分开记录）。

| 检查 | 实际观察 | 结论 |
|---|---|---|
| DOM 摘要 | `dom` → frame main，52 元素、标题/章节/按钮齐全，`text` 含页面文案 | 通过 |
| 标题定位 | `dom_find --role heading --name 焦点问题` → `matchCount:1`，ref `0.89`（h2, visible） | 通过 |
| 评审按钮 | `dom_find --role button` → 6 个：P1–P4 席位按钮 + `⇧ 顶部`/`⇩ 底部`，均 visible/not disabled | 通过 |
| 重名歧义 | `--name 立场` → `matchCount:8`（立场×5 + 立场更新×3），列表返回不自动选取 | 通过 |
| inspect | 同次 find 的 `0.17`+documentId → tag/role/name/`attrs{class,title}`/rect（x22 y135 w337 h56，`coordinateSpace:frame` 注明不叠加滚动/iframe 偏移）/visible/disabled/focused | 通过 |
| 跨调用失效 | 另一次 `dom_find` 后用旧 documentId+ref inspect → `stale_element`（每次探针调用重打文档 nonce，旧 ref 不静默复用） | 通过（设计行为） |

## 4. 案例 B：媒体场景

Http-B 逐页导航（UI 操作），`relayctl media --identity 7f78ffc9…` 采样。

| 场景（夹具预期） | 实际观察 | 结论 |
|---|---|---|
| 播放推进（`media.html` v-play） | `paused:false`，currentTime>0 持续增长 | 通过 |
| 暂停在零秒（v-pause） | `paused:true`，`currentTime:0`，readyState 4 | 通过 |
| 坏源（v-broken→missing.mp4） | readyState 0，`error.code:4`（SRC_NOT_SUPPORTED） | 通过 |
| 无源（v-nosrc） | readyState 0，无 error——与坏源可区分 | 通过 |
| 音频暂停（a-pause） | `tag:"audio"`，paused@0 | 通过 |
| 同源嵌套 iframe | f0（media-frame）与 f0.f0（media-frame2）`reachable:true`，分层标签正确 | 通过 |
| data: iframe | `reachable:false`，url 记为 `%3Copaque-url%3E`（脱敏） | 通过 |
| 跨源 iframe（example.com） | `reachable:false`，`reason:unavailable` | 通过 |
| 预设起点 20s（`media-seek.html`，R1 旧夹具 seek 后即播） | `currentTime:25.22`→`29.30`——仅证明推进；落点须依赖「已播放约5s」推测，**按未验证处理**（R1 证据保留于 `b-media-seek-1/2.json`） | 未验证（R1） |
| 预设起点 20s（R2 新夹具两相位：seek 后暂停→15s 播放） | 相位一采样 `paused:true`、`currentTime:20`、`seeking:false`——暂停锁定值即落点，可独立判读；相位二 `paused:false`、`currentTime:32.34` 推进 | 通过 |
| 预算截断（`media-many.html`，40 个 video，上限 32） | `mediaCount:40`、返回 32 条、`mediaSkipped:8`、顶层 `truncated:true` | 通过 |
| 无媒体（`no-media.html`） | `media:[]`、`mediaCount:0` | 通过 |

## 5. 案例 B：异常场景

`relayctl errors --identity …`。

| 场景（夹具预期） | 实际观察 | 结论 |
|---|---|---|
| 同步 error（errs.html） | `kind:error`，`Error: main-boom`，source=页面路径 | 通过 |
| 未处理 Promise | `kind:unhandledrejection` ×2（Error rejection 取 message；对象 rejection 记 `[object Object]`，内部字段不读取） | 通过 |
| iframe 错误 | f0 独立 `bufferId`，`frame-boom` 归集到对应帧 | 通过 |
| 环形溢出（errs-flood，230>200） | `count:200`、`overflow:30`，保留 flood-30…flood-229 最新段 | 通过 |
| 导航批次（errs-reload，`location.search='?batch=1'` query 变化导航，非同 URL reload） | 导航前 `bufferId bn7dft195ne-…` 含 `batch-0-error`；导航后新 `bufferId b8f0346nfgxy-…` 仅含 `batch-1-error`——旧批次不带入新文档 | 通过 |
| 身份隔离 | Http-A（评审页）`installed:true`、`count:0`，B 的全部错误未出现在 A | 通过 |
| 凭据脱敏（errs-creds，全合成） | 短 quoted `"password":"123"`→`<redacted>`；长 600 字符 token→`<redacted>`；`api_key=abc123XYZ`→`<redacted>`；`https://user:pw@example.com/p?q=1&token=…`→`https://example.com/p`；`Bearer …`→`Bearer <redacted>`；对象 secret→`[object Object]`。原文逐字节 grep：8/8 标记零泄漏 | 通过 |
| 未安装监听/不可达输出 | dom-frame 页跨源帧：`reachable:false`、`installed:false`、`reason:unavailable`；无错误页面 `installed:true`+`count:0` | 通过 |

## 6. 案例 B：DOM 边界

| 场景（夹具预期） | 实际观察 | 结论 |
|---|---|---|
| CSS/属性隐藏（hidden.html） | `dom` 仅返回可见元素；`SECRET-SPAN/SECRET-LINK/SECRET-HIDDEN-BTN` 原始串 grep 零泄漏；`--text SECRET`→`not_found`；`--selector a` 命中隐藏链接时仅回 `{ref,tag,hidden:true,…}` 白名单（label:null） | 通过 |
| 帧遍历+不可达（dom-frame.html） | DFS：main→f0(a)→f1(example.com `reachable:false`)→f2(b)；不可达帧保留序号占位 | 通过 |
| 隐藏 iframe 前置（dom-frames-mixed） | 隐藏 f0/f2 不入列；`frames[]` 有两套编号——`label` 按 DOM 位次（f1=b.html、f3=a.html），`index` 为枚举序（1/2，隐藏不占位）；`--frame` 按 label 选择，元素 ref 前缀用 index：`--frame f1`→`1.4`、`--frame f3`→`2.4`；隐藏位次 `--frame f0`/`f2`→`not_found`（"No frame matches the given label"，R2 补取 `r2-find-frame0/2-hidden.json`） | 通过 |
| 元素移除/替换（dom-mutate，15s 后） | 变前 find 发 `0.6`(VICTIM-BTN)/`0.7`(VICTIM-BTN2)；变后 `0.6`→`stale_element`（位置现为已签发的 victim2）；`0.7`→`not_found`（"Position was never issued as a ref"，替换元素不静默接管 ref） | 通过 |
| 同 URL reload（dom-reload-once，`location.reload()`） | 重载后旧 documentId+ref → `stale_element`（"Document changed since the ref was issued"）——新文档中相同按钮不被误指 | 通过 |
| 显式 frame 超预算（dom-many-frames，20 iframe > 16） | `dom` 枚举 16 帧（main+f0–f14）、`skipped.frames:5`、`truncated:true`；`--frame f19`→`frame_out_of_scope`；`--frame f14`（界内末位 label）可解析可扫描：`--selector a`→`matchCount:0`（a.html 无链接，`complete:false` 因帧清单截断不敢断言为零），`--text ALPHA`→`matchCount:1` ref `15.4`（index 15=label f14，R2 补取） | 通过 |
| 候选截断（dom-many-cands，500 link > 400） | `matchCount:400`、返回前 50、`complete:false`、`countIsLowerBound:true`、`truncated:true` | 通过 |

## 7. 证据清单

入库证据 `design/evidence/issue40-integration/`：

- `INDEX.md`——逐场景「命令模板+参数映射→证据文件→采样时间→定位字段」映射与版本固定表
- `json/`——52 个命令实际返回（308KB，接口内脱敏原样落盘；错误返回无时间字段者以同批采样窗口标注）
- `case-a-panel.png`（59KB，评审页面板，对应 `json/a-screenshot.json` 返回）、`case-b-panel.png`（6KB，夹具页面板，对应 `json/b-screenshot.json`）

报告与证据均已脱敏：无 token、无业务域名、项目/身份均为通用验收代号；errs-creds 的 8 个合成凭据标记在证据文件内逐字节 grep 零泄漏。

## 8. 恢复与隔离复核

- 故障/超限返回（`frame_out_of_scope`、`not_found`、`stale_element`）后，同一目标再次 `dom`/`dom_find`/`errors` 均正常返回——探针调用间无状态污染。
- A/B 双身份并行：B 的所有错误/媒体/DOM 数据不出现在 A 的返回中，无串档。

## 9. 通过/失败/未覆盖

- **通过**：§2 全部（含 R2 补取 open_panel 未开→打开路径）、§3 全部、§4（media-seek 经 R2 两相位夹具重取后通过）、§5 全部、§6 全部、§8 全部。
- **失败**：无。
- **曾标未验证后补齐**：media-seek R1 落点判读不足 → R2 夹具改两相位重取通过；`--frame f0/f2` 隐藏位次 R1 未留证 → R2 补取 not_found；open_panel 未开→打开路径 R1 仅 alreadyOpen → R2 补取全路径。
- **未覆盖 / 如实边界**：
  - 夹具 iframe `src` 绝对路径问题为夹具自身缺陷（首轮验证发现 404），已改相对路径修正；非接口缺陷。
  - 元素替换后旧位置观察为 `not_found`（位置现占未签发元素）而文档级替换为 `stale_element`——两种失效语义已在 §6 如实记录，属设计区分而非缺陷。
  - 页面准备动作（导航、媒体起点、错误注入）由夹具自身脚本与应用地址栏完成，均如实标注；当前接口无 `navigate`/输入/滚动操作——缺口沿 #23–#30 推进，不把桌面外挂操作计为公开能力。
  - 媒体"预设起点"验证的是接口采样行为；不代表外部业务系统历史进度恢复（issue 结论边界）。
  - Windows/Linux 未验收（接口本阶段仅 macOS）。
  - 评审页 iframe 内 rect 的滚动/iframe 偏移叠加：inspect 已注明 `coordinateSpace:frame` 不叠加，未做跨 frame 坐标合成验证。

## 10. 结论

`8d25807` 基线上的全部已交付接口（capabilities/state/projects/identities/panels/windows/workspaces、screenshot、media、errors、dom/dom_find/dom_inspect、activate_project、open_panel）在真实评审页与覆盖边界夹具上按预期工作：定位字段真实、写操作幂等且受限、DOM 三 op 链与失效语义正确、媒体/异常采样字段可区分、脱敏边界成立、故障后目标可再查、双身份无串档。建议按 issue 清单逐项确认后关闭 #40。
