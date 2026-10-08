# Relay Desk 代码验收与调试接口规划

## 决策与当前迭代

采用应用内控制服务作为唯一能力入口，CLI 首先接入，MCP 后续复用同一协议。
当前迭代 P0 只交付元数据读取：当前/全部项目、身份、面板、原生窗口、已保存工作区，以及能力清单。
页面 DOM、截图、脚本执行、导航、点击、日志与网络采集进入后续迭代。
分支：`feature/relay-desk-automation`；已合入线上 `main` 的 `7026cd1`（PR #9），自动升级代码保持原逻辑。

| 方案 | 与现有实现的关系 | 适用场景 | 本项目决策 |
|---|---|---|---|
| 浏览器插件 | 需要新增扩展宿主、身份关联及能力适配；Chrome debugger 绑定 Chrome 协议 | 控制已有 Chrome/Edge 等浏览器标签页 | 后续接入外部浏览器时考虑 |
| 应用内服务 + CLI | 直接复用 Riverpod、数据库和自定义 WKWebView 插件 | 多身份验收、明确窗口定位、批量获取证据 | 首选 |
| MCP | 包装相同查询和操作契约，不新增业务实现 | 代理工具发现、结构化调用、截图返回 | CLI 稳定后追加 |
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

没有当前选择是合法状态：单项返回 null，列表返回空数组。显式指定不存在的 ID 返回 not_found/404。
单项值保留名称包装，例如 `data: {"project": null}`、`data: {"window": {"windowId": 1}}`；`state` 内字段直接嵌入对象。
当前窗口严格使用原生采样的 currentWindowId；应用未激活时为 null，即使 AppKit 窗口仍保留 isKey 标记。
参数类型错误返回 invalid_argument/400；不支持的 op 返回 unsupported_operation/400。
P0 whitelist 在 transport 与 query 层均限制读取操作；eval、navigate、reload、click 等请求不能进入执行路径。

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
| P0a.2 下一步 | 应用内接口开关与包内 CLI | 设置页显式开关默认关闭；按开关启动/关闭服务与清理会话；发布版补 network.server entitlement；生命周期与现有 dispatch 共用；Developer ID 签名/公证纳入分发 | 发布版手动启用可查询，关闭后端口/会话消失；不重启现有浏览身份；全新 Mac 可按签名分发安装 |
| P0b | 设备预设、宿主能力、布局诊断 | device presets + probe；标注预设是 UA/尺寸模拟而非真实设备 | 输出与 UI 配置一致；不宣称模拟了真实触摸/网络环境 |
| P1a | DOM 摘要、同源 frame 清单 | 固定读取脚本、返回有限可见文本/控件/frames，脱敏输入值；同源 framePath 明确定位 | 嵌套 web-view 读取、选择器歧义、跨域不可访问、文档切换失效 |
| P1b | 面板/窗口截图 | WKWebView.takeSnapshot 与 AppKit 截图分别实现；说明捕获范围、尺度、媒体画面限制 | 所选身份与图片绑定，独立窗口/嵌入窗口一致 |
| P2a | 导航、刷新、前进后退 | 走 WorkspaceController，不绕开状态机；命令 accepted 与页面 loaded 分开；带 generation | 导航失败/目标销毁/项目切换均返回明确结果 |
| P2b | 点击、填写、滚动、键盘 | 原生事件与 DOM 合成事件分为能力，标明 user gesture；限定身份/frame/元素，多匹配报错 | 不误点另一个身份；媒体自动播放与权限行为按真实输入验证 |
| P3a | 控制台与异常 | document-start 注入 console/error/unhandledrejection 捕获，原生附 frame/navigation/sequence，环形缓冲 | 刷新前后的首条错误保留，重复事件去重、重入防护 |
| P3b | 网络摘要 | fetch/XHR 元数据 + Performance；不默认读取正文/认证头，声明非全量抓包 | 请求开始/结束/失败关联；遗漏的导航、worker、HLS 明确标注 |
| P3c | 深层调试 | Safari Inspector 官方入口；如需要完整协议再评估 WebKit inspector 适配或 Chromium 后端 | 断点、性能、所有 frame/network 与已有 profile 能力分别验收 |
| P4 | 可重放验收用例 | 保存步骤、状态条件、容差、身份绑定、截图/日志证据及结果；等待条件替代固定 sleep | 修复前失败/修复后通过，失败证据可定位哪一身份/哪一步 |
| P5 | MCP | 与 CLI 共享同一 dispatch；能力清单生成工具 schema；图片直接返回 | MCP 与 CLI 对同一操作结果一致 |

每个切片只实现一种可观察结果，审查通过再派下一个切片。
普通 DOM 点击不能当成真实鼠标验收；截图不能单独证明后台礼品领取成功。
播放器续播验收要观察历史位置、实际播放位置、有限尝试次数，使用时间容差；
观看时长与播放位置分别读取，礼品资格以服务端记录为证据。
角色验收以真实业务身份验证，浏览器身份名称仅是定位标签。

## 委派安排与完成边界

- Codex：架构、接口契约、切片提示词、分支、差异审查、集成与验证。
- Devin：P0 Dart 查询逻辑与测试，再实现原生窗口查询及接入；每轮文件白名单明确。
- OpenCode：使用 `opencode/space-bunny-free`，先 CLI 与离线协议测试，再编写使用技能；HTTP session 执行。
- 同时写入的路径互不重叠；代理不提交、不改分支、不清理他方改动，不操作现有业务浏览器。
- P0 完成报告区分：已实现源码、自动检查通过、开发构建通过、真实运行态已验收。
  发布版能力不因开发版检查通过而被宣称已经可用；P1+ 仍为规划。

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
- 真实 AppKit 焦点、项目切换、独立窗口及业务行为仍待运行态验收；正式签名、公证、发布版开关和包内 CLI 未实现。

### 下一切片：P0a.2a 设置页控制服务

线上代理先完成已有 P0 的真实运行态验收，再实现 macOS 设置页显式开关，默认关闭，复用现有只读 dispatch。
启用后显示真实服务状态；关闭或退出应停止监听并清理该实例会话；重新启用更换凭据，旧凭据失效。
覆盖快速开关、启动中关闭、重复启用和启动失败，不能留下重复服务，也不能刷新页面、重建身份或重启应用。
验证 release 沙盒配置实际可用，Windows/Linux 本切片标记未支持。
此切片暂不包含包内 CLI、DOM、截图、输入、网络采集或 MCP。

开发代理负责实现并提供提交与验证证据；Codex 负责审核。
保持 `feature/relay-desk-automation`，每个切片独立提交并等待审查；不直接合并 main 或发布版本。
