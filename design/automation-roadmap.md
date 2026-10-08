# Relay Desk 代码验收与调试接口规划

## 决策与当前迭代

目标：让 Agent 可靠找到对应身份的窗口和页面，取得可核对的页面证据，验证是否帮助实际调试。
采用应用内接口和独立 CLI 复用现有宿主。完成本轮真实调试验收后停止默认扩展；新增能力由实际问题决定。
当前迭代 P0 只交付元数据读取：当前/全部项目、身份、面板、原生窗口、已保存工作区，以及能力清单。
下一阶段优先验收定位并提供指定面板截图；页面文字无法从截图判断时再增加有限 DOM 摘要。
任意脚本执行、导航、点击、日志与网络采集不列入当前任务。
分支：`feature/relay-desk-automation`；已合入线上 `main` 的 `7026cd1`（PR #9），自动升级代码保持原逻辑。

| 方案 | 与现有实现的关系 | 适用场景 | 本项目决策 |
|---|---|---|---|
| 浏览器插件 | 需要新增扩展宿主、身份关联及能力适配；Chrome debugger 绑定 Chrome 协议 | 控制已有 Chrome/Edge 等浏览器标签页 | 后续接入外部浏览器时考虑 |
| 应用内服务 + CLI | 直接复用 Riverpod、数据库和自定义 WKWebView 插件 | 多身份验收、明确窗口定位、批量获取证据 | 首选 |
| MCP | 可包装同一协议 | 未来确有工具接入需求时评估 | 暂无开发任务 |
| Safari Web Inspector | 利用 WKWebView 的官方 inspection 接口 | 断点、源码、WebKit 深层网络与性能诊断 | 保留人工诊断入口 |

源码依据：`lib/features/workspace/workspace_controller.dart` 管理面板状态；
`lib/platform/webview/macos_profiled_webview_adapter.dart` 持有 identityId→viewId；
`macos/Runner/ProfiledWebViewPlugin.swift` 已有 evaluateJs/callAsync 原生通道。
这表示宿主具备执行基础，不表示现在已经支持 CDP 或自动化调试。
现代 WebKit 有 [WKWebExtensionController](https://developer.apple.com/documentation/webkit/wkwebextensioncontroller)，
这里的选择依据是复用现有宿主成本，而非断言 WKWebView 永远不能支持扩展。
[Chrome debugger](https://developer.chrome.com/docs/extensions/reference/api/debugger) 是 Chrome 调试协议的另一传输方式；
[WebKit inspection](https://webkit.org/blog/13936/enabling-the-inspection-of-web-content-in-apps/) 可按 WebView 启用并从 Safari 检查。

## 领域与事实来源

- Project：数据库项目；“当前项目”来自 `selectedProjectIdProvider`，不假设 controller 内残留的 selectedProjectId 等于界面选择。
- Identity：数据库浏览身份；`sharedSession` 明确为不隔离。身份名称不是唯一键。
- Panel：工作区内一个身份对应的 WebView 面板；嵌入/独立窗口是同一个运行实例的不同展示方式。
- Window：AppKit NSWindow；一个主窗口可承载多个 Panel，独立窗口一般承载一个 Panel。面板和窗口不能混用。
- Workspace：已保存的布局，属于 Project；当前未加载命名布局时 workspaceId 可以为空。
- Selected identity：Flutter UI 选中的面板身份。
- Focused identity：原生 keyWindow 的 firstResponder 实际属于哪个 WKWebView；在地址栏/侧栏获得焦点时可以为空。

UI 选择与原生焦点分别返回。切换项目时如果选中面板仍属于旧项目，当前身份/面板返回 null，并标记 selectionConsistent=false；不把它冒充新项目的身份。
选中身份没有驻留面板时同样标记不一致；当前命名工作区若属于旧项目，workspace/workspaceId 返回 null。
原生窗口信息采样与数据库查询不是跨层原子事务；响应提供 capturedAt，调用方在界面变化后重新获取。

## P0 协议 v1：读取

传输：`POST /v1/command`，JSON 请求，Bearer session token。
运行限定：macOS debug 构建显式 `--dart-define=RELAY_DESK_AUTOMATION=true` 开启。
默认构建与发布版不启动服务；只监听 127.0.0.1 随机端口，session 文件权限 600。
端口和 token 不写入项目仓库。网页 Origin 请求被拒绝；客户端拒绝代理和 HTTP 重定向。

统一响应：

```json
{"ok": true, "data": {"projects": []}}
```

```json
{"ok": false, "error": {"code": "not_found", "message": "Requested identity does not exist"}}
```

| op / CLI | 请求字段 | data 返回 | 默认选择 |
|---|---|---|---|
| capabilities | 无 | protocolVersion, readOnly, engine, operations, limitations | 无 |
| state | 无 | capturedAt, project, identity, panel, window, workspaceId, layoutMode, selectedIdentityId, focusedIdentityId, selectionConsistent | 当前 UI 选择 + 原生焦点 |
| projects | 无 | projects 数组 | 全部数据库项目 |
| project | projectId 可选 | project 对象或 null | 当前 UI 项目 |
| identities | projectId 可选 | projectId, identities 数组 | 当前 UI 项目 |
| identity | identityId 可选 | identity 对象或 null | 当前 UI 选中身份 |
| panels | projectId 可选 | panels 数组 | 所有驻留面板；有 projectId 时过滤 |
| panel | identityId 可选 | panel 对象或 null | 当前 UI 选中面板 |
| windows | 无 | currentWindowId, mainWindowId, windows 数组, views 数组 | 所有应用 NSWindow |
| window | windowId 可选，整数 | window 对象或 null | keyWindow；不回退为 mainWindow |
| workspaces | projectId 可选 | projectId, workspaces 数组 | 当前 UI 项目 |
| workspace | workspaceId 可选 | workspace 对象或 null | 当前命名工作区 |
| screenshot | identityId **必填** | identityId, projectId, nativeViewId, windowId, capturedAt, format, width, height, url, pngBase64 | 无回退；不以名称/选中/焦点代替 |

没有当前选择是合法状态：单项返回 null，列表返回空数组。显式指定不存在的 ID 返回 not_found/404。
单项值保留名称包装，例如 `data: {"project": null}`、`data: {"window": {"windowId": 1}}`；`state` 内字段直接嵌入对象。
当前窗口严格使用原生采样的 currentWindowId；应用未激活时为 null，即使 AppKit 窗口仍保留 isKey 标记。
参数类型错误返回 invalid_argument/400；不支持的 op 返回 unsupported_operation/400。
P0 whitelist 在 transport 与 query 层均限制读取操作；eval、navigate、reload、click 等请求不能进入执行路径。

screenshot 是唯一的二进制读操作：服务端在原生侧将采样绑定到 (viewId, identityId, WebView 实例, 导航代次)，
异步快照完成后复核四项全部未变；任一变化返回 target_changed/409。解码 PNG 超过 16 MiB 拒绝
（snapshot_too_large/500）。身份无活动原生视图返回 no_native_view/409；未知身份 not_found/404；
缺 identityId 是 invalid_argument/400。CLI 的 `--output` 为本地参数，从不发送给应用；CLI 解码
base64 校验 PNG 魔数后才写文件，写失败不留半文件。url 与其他字段一样经 _stripUrl 脱敏。

返回对象：

- project：id, name, targetUrl, allowPrivateNetwork, defaultLayoutMode。
- identity：id, projectId, name, isolationMode, isIsolated, devicePresetId, startPath。
- panel：identityId, projectId, identityName, state, url, loading, selected, devicePresetId, isolationMode, layout, nativeViewId, windowId, hasKeyboardFocus。
- window：windowId, title, isKey, isMain, isVisible, isMiniaturized, bounds, identityIds。
- native views：viewId, identityId, windowId 可为空, hasKeyboardFocus。
- workspace：id, projectId, name, viewportX/Y, zoom, layoutMode, updatedAt, panels 布局。

URL 输出去除 userinfo/query/hash，保留协议、主机、端口与路径；相对 startPath 同样去 query/hash。
元数据接口不返回 Cookie、localStorage、登录 token、数据库密码、页面输入框值或 arbitrary JavaScript。
window.bounds 使用 AppKit 屏幕坐标与点单位；panel.layout 使用工作区布局坐标，不能直接混作 DOM 坐标。

## P0 使用入口

独立 CLI 构建（开发者执行）：

```bash
cd /Users/yonh/workspaces/flutter/relay-desk
bash tool/build_relayctl.sh
```

运行方使用生成的 `relayctl`，无需安装 Python、Dart 或 Flutter。分发步骤见
[relayctl-distribution.md](relayctl-distribution.md)。当前 Mac 架构决定产物，arm64/x64 分别构建。

开发启动（会启动一个应用实例，按实际调试安排执行）：

```bash
cd /Users/yonh/workspaces/flutter/relay-desk
flutter run -d macos --dart-define=RELAY_DESK_AUTOMATION=true
```

查询：

```bash
cd build/relayctl/macos-arm64
./relayctl sessions
./relayctl capabilities
./relayctl state
./relayctl projects
./relayctl identities --project PROJECT_ID
./relayctl panel --identity IDENTITY_ID
./relayctl windows
./relayctl window --window WINDOW_ID
./relayctl screenshot --identity IDENTITY_ID --output /tmp/panel.png
```

Intel Mac 使用 `macos-x64` 目录；解包后的运行方式相同。Python 旧入口暂时保留用于历史对照。
多个开发实例时，通过全局 `--session FILE` 或 `RELAY_DESK_SESSION` 指定 sessions 返回的描述文件路径，
例如 `./relayctl --session FILE state`。不要打印描述文件内的 token。
运行中的普通发布版没有这个接口；本轮编译和离线测试不自动重启或替换它。
使用技能位于 `skills/relay-desk/SKILL.md`，可通过 `$relay-desk` 调用；技能会先探测会话与能力。

## 迭代与验收细节

| 迭代 | 能力 | 实现细节 | 验收信号 |
|---|---|---|---|
| P0a 当前范围 | 项目/身份/面板/窗口/工作区读取 | Dart 查询层注入状态和仓库；Swift 只采样 NSApp.windows、firstResponder 与 view 映射；独立 Dart CLI，Python 保留作协议参考 | 空选择、显式 ID、隔离模式、选中≠焦点、旧项目残留、未知 op、认证均可验证 |
| P0a.1 当前范围 | 独立 CLI 分发 | SDK-only Dart 编译独立 relayctl；脚本生成架构专用二进制、中文说明、校验文件和压缩包，保持现有 JSON 协议 | 运行方无需 Python/Dart/Flutter；架构和实际产物一致；不打包会话凭据 |
| 下一步 1 | 真实定位验收 | 使用现有 CLI 和 macOS debug 接口，核对 identityId、nativeViewId、windowId、选中与焦点 | 项目切换、嵌入/独立窗口、应用失活时返回可核对结果；过期 ID 明确失败 |
| 下一步 2 | 指定面板截图 | 复用 WKWebView 原生截图与同一 dispatch；CLI 保存图片并返回目标、时间、尺寸及结果 | 截图确实属于指定身份，嵌入/独立展示均正确；不存在、销毁或采样失败有明确结果 |
| 按需补充 | 有限 DOM 摘要 | 仅在截图无法判断实际案例时追加固定只读采样；标注 frame、URL 和采样时间 | 标题、可见文字或关键控件状态帮助定位问题；跨域限制和文档切换明确返回，不猜测 |
| 便利项 | 设置页接口开关 | 默认关闭，复用现有服务；启停清理、失败状态、重新启用凭据更新 | 改善开启方式，不能阻塞使用 debug 实例完成核心验收；发布版可用性另行验证 |

截图与 DOM 是只读观察能力，沿用现有身份和面板定位，不建立另一套自动化框架。
截图可能包含页面显示的业务信息，真实验收使用测试账号和测试数据；媒体画面缺失等限制应如实说明。
输入操作、日志采集、全量网络调试、MCP、浏览器插件、可重放用例平台和包内 CLI 分发均无当前开发任务。
每个切片只实现一种可观察结果，审查通过再派下一个切片。
普通 DOM 点击不能当成真实鼠标验收；截图不能单独证明后台礼品领取成功。
播放器续播验收要观察历史位置、实际播放位置、有限尝试次数，使用时间容差；
观看时长与播放位置分别读取，礼品资格以服务端记录为证据。
角色验收以真实业务身份验证，浏览器身份名称仅是定位标签。

## 早期委派安排与完成边界

下列为 P0 实现阶段记录；后续任务执行末尾的“当前任务与审查约束”，不自动启动外部代理或延续旧任务链。

- Codex：架构、接口契约、切片提示词、分支、差异审查、集成与验证。
- Devin：P0 Dart 查询逻辑与测试，再实现原生窗口查询及接入；每轮文件白名单明确。
- OpenCode：使用 `opencode/space-bunny-free`，先 CLI 与离线协议测试，再编写使用技能；HTTP session 执行。
- 同时写入的路径互不重叠；代理不提交、不改分支、不清理他方改动，不操作现有业务浏览器。
- P0 完成报告区分：已实现源码、自动检查通过、开发构建通过、真实运行态已验收。
  发布版能力不因开发版检查通过而被宣称已经可用；本轮范围以末尾任务清单为准。

## 早期验收记录（同步 main 前）

- 独立 CLI 迭代：SDK-only Dart 源码评审与静态分析通过，ARM64 编译/架构检查/帮助运行/分发包校验通过，使用技能已迁移；本迭代未运行真实 HTTP 或业务页面测试。
- 已实现 P0a 12 个只读服务操作及 CLI 本地 sessions 查询，使用技能已安装。
- Codex 独立复跑：查询/传输/原生适配器/工作区控制器 79 项 Flutter 测试，CLI 16 项离线测试，全部通过。
- `flutter analyze --no-pub`：无问题；技能 quick_validate 校验通过；`git diff --check` 通过。
- macOS debug 构建开启 RELAY_DESK_AUTOMATION 编译通过，包括新增 Swift 窗口查询。
- 未启动或替换用户当前应用；真实 AppKit 焦点状态与业务页面尚未运行态验收。
- 后续先验收开发实例的项目切换、选中/焦点不同、嵌入/独立窗口、应用失活，再进入 P0b 或 P1。

## P0 阶段收尾与线上接续（2026-10-08）

- 基础版本：已合入线上 `main` 的 `7026cd1`，本地合并提交为 `e6feb17`。
- 当前切片：12 个只读元数据操作、独立 Dart CLI、使用技能和协议文档；默认发布版接口仍关闭。
- 全量 Flutter 测试 209 项通过；`flutter analyze --no-pub` 无问题。
- 同一套 16 项 CLI 协议用例分别验证 Python 参考入口和编译后的 ARM64 `relayctl`，均通过。
  测试只连接临时 loopback 服务，不访问真实会话或业务页面。夹具使用实际会话的 `version: 1`，支持 HTTP chunked 请求和 JSON charset。
- 独立 CLI 编译、ARM64 架构检查、校验文件及仅含三个文件的归档检查通过；最小系统 PATH 下帮助命令可用。
- `flutter build macos --debug --dart-define=RELAY_DESK_AUTOMATION=true` 编译成功；未启动或替换用户当前应用。

### 真实运行态验收（2026-10-08，Devin 线上环境）

- 默认 debug 构建（不带 define）启动：无 `automation/` 目录、无会话文件、接口未监听；默认关闭成立。
- 显式 `--dart-define=RELAY_DESK_AUTOMATION=true` debug 构建启动：生成 `automation-<port>.json`（chmod 600），会话字段含 endpoint/token/pid。
- 真实 HTTP 验收（独立调试实例，非业务窗口）：`capabilities`/`projects`/`state` 返回真实数据（含真实 NSWindow 清单与项目记录）；无凭据请求 401；非白名单写操作返回 `unsupported_operation`。
- 编译产物 `relayctl`（纯 Dart SDK，仅链系统库）在 `env -i` 最小环境下直接查询运行中的应用成功；构建链可依赖 SDK，产物运行不依赖 Python/Dart/Flutter。
- 仍待验收：真实 AppKit 焦点切换、项目切换、独立窗口及业务行为组合；正式签名、公证、发布版开关和包内 CLI 未实现。

## 当前任务与审查约束（替代早期扩展路线）

### 顺序

1. **定位验收**：先在本地 macOS 独立调试实例核对已有查询，记录实际身份、面板和原生窗口的对应关系。未实际运行的项目标记待验收。
   已执行实机验收（2026-10-08，Issue #10，PR #11）：矩阵场景全部实机取证并记录，待审查；证据见 `design/automation-location-verification.md`。
2. **看到页面**：线上实现指定 identityId 的面板截图，沿用当前 CLI → 应用接口 → 原生 WebView 的链路。返回图片与采样时目标映射、时间、尺寸；目标销毁或页面切换导致证据不一致时明确失败，不能返回其他身份的图片。
   已实现并实机验收（2026-10-08，Issue #12）：嵌入/独立窗口截图、无选择回退、target_changed 竞态复核均通过；待审查。
3. **按需文字采样**：截图不足以回答真实调试问题时，再追加最小 DOM 摘要，限定可见文字和所需控件状态，不提供任意脚本执行接口。
4. **实际案例验收并停止**：用一个可复现页面问题走通定位、取证、分析、修复和前后对照；能力足够后停止扩展，不自动进入下一阶段。

设置页开关是便利项。若代理已有该切片，可以小范围收尾；核心验收先使用已有 debug 显式启用方式，不等待发布、签名、公证或包内 CLI。

### 验收交付

- 双身份页面内容明显不同，按 ID 获取证据不会串身份；名称不作为唯一键。
- 嵌入面板和独立窗口均可定位；项目切换、焦点变化、应用失活结果符合文档。
- 目标不存在、销毁、取证失败或 frame 不可访问时有可辨识结果，不能把缺失证据当成成功。
- 每份证据记录目标与采样时间，发生状态变化时重新获取；不宣称跨层原子快照。
- 至少提供一份实际调试案例：问题现象、定位命令、截图/必要文字、分析结论和修复后的对照。业务数据类结论仍需后端记录支持。

### 分工和纠偏

- 线上代理负责指定面板截图及必要接入；Codex 负责范围规划、差异审核和纠偏。
- 本地并行做真实定位验收及 CLI 协议验证，使用独立分支；共享协议变更先说明，再接入。
- 实现范围只服务“找到窗口、看到页面”。增加独立服务、通用自动化框架、任意执行、点击填写、全量日志网络采集等，需先给出当前案例为什么无法解决的证据，并由用户决定是否扩展。
- 审查发现偏离时，要求缩减提交；已完成观察闭环即停止默认任务链。
- 保持 `feature/relay-desk-automation`，每个切片独立提交并等待审查，不直接合并 main 或发布版本。
