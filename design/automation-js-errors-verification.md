# Issue #17 只读页面运行错误 — 实现与实机验收记录

日期：2026-10-08。环境：macOS（本机 debug 构建，`RELAY_DESK_AUTOMATION=true`）。
实现切片：`devin/issue17-js-errors`，base `feature/relay-desk-automation`（含 #16 栈）。

## 实现方案（先于实现说明）

页面内缓冲 + 固定只读读取脚本，沿用 `relayctl → 本地接口 → WKWebView` 链路：

- **注入**：面板创建参数新增 `automationErrorCapture`（`const bool.fromEnvironment('RELAY_DESK_AUTOMATION')`——**必须 const**，非 const 的 `fromEnvironment` 在 JIT 下运行期求值、app 启动不带 define 得 false，实机已踩过）。为 true 时 `registerWebView` 在 config 里加 `WKUserScript`（`atDocumentStart`、`forMainFrameOnly:false`）：每个文档（含同源 iframe）都装 `error` + `unhandledrejection` 监听与 `__relayErrors` 缓冲。只观察不拦截——不调用 `preventDefault`、不改传播。
- **缓冲即生命周期**：缓冲挂在文档 `window` 上——随文档出生记 `collectedAt`/`bufferId`（导航批次标记），随文档销毁/面板关闭自动清零；不存在跨导航串档，也没有"注入前历史"可声称。
- **上限**：每缓冲 200 条，溢出计 `overflow`；`message`≤1024、`source`≤512、`stack`≤4096 字符，截断带标记。非 Error 的 rejection reason 只做 `Object.prototype.toString.call(r)` 类型标记——**绝不序列化业务对象 payload**。
- **读取**：`drainJsErrors` 原生方法与 `sampleMedia` 同一绑定/门控/期限纪律（viewId+identity+实例+窗口+导航代次复核，漂移 `target_changed`；8s 原生 deadline + 9s Dart 兜底 `errors_timeout`）。固定读取脚本 `errorsDrainScript`：读主文档 + 逐层同源 iframe 的缓冲；跨源/不可达标 `reachable:false`、`installed:false`。
- **`installed` 语义**：区分"页面没装监听"（view 创建时 flag 关闭）与"装了但确实没错误"（installed:true、count:0）——绝不把"无法观察"说成"无错误"。
- **查询层 `errors` op**：显式 `identityId` 必需；frame `url` 与每条 `source` 都过 `_stripUrl`（含 opaque scheme 策略）；返回 `sampledAt`/定位字段/`frames[]`。
- relayctl `errors --identity <id>`，Dart/Python 双实现。

## 版本固定

- 源码树：本 PR 顶端提交（实机验收在提交前同一工作区内容上进行）。
- 夹具：`build/screenshot-pages/`（本机 HTTP :8901）：`errs.html`（300ms `throw main-boom`、400ms `Promise.reject(Error)`、500ms `Promise.reject({secret:'BUSINESS-SECRET-MARKER'})` + 同源 iframe `errs-frame.html` 的 `throw frame-boom`）。
- 会话：automation-54250/57673 两次实例，pid 见会话文件；VerifyHTTP 项目 Http-A=`98205caa`（→/errs.html → /errs-frame.html）。

## 实机验收（全部来自实际返回，时间 UTC）

`relayctl errors --identity 98205caa`（21:45:13Z，`viewId 0 / windowId 107`）：

| 场景 | 实际结果 |
|---|---|
| JS 异常 | `kind:"error"`、`message:"Error: main-boom"`、`source:.../errs.html`、`line:5,col:54`、`stack` 截断存储 |
| Promise 未处理拒绝（Error） | `kind:"unhandledrejection"`、`message:"rej-failure"`、`stack` 保留 |
| 拒绝对象 payload | `{secret:'BUSINESS-SECRET-MARKER'}` → **`message:"[object Object]"`**——payload 未出现在响应任何字段（脱敏实机核对） |
| 同源 iframe | `frames[1]` `label:iframe0`、`installed:true`、独立 `bufferId`（`bkyk…`≠主 `brrk…`）、自记 `frame-boom` |
| 缓冲起点 | `collectedAt` 为注入时间（21:45:03.6Z），无注入前历史——如实标记 |
| 导航批次 | 切页 /errs.html→/errs-frame.html：新 `bufferId`（`bmlp…`）、`count:1` 只含新文档的错误，旧条目随旧文档销毁——跨导航零串档 |
| 双身份隔离 | Http-B 的 drain 只返回自身页面缓冲 |

错误路径（单测+实机）：未知 identityId → `not_found`(404)；缺 `--identity` → CLI `exit 2`；无原生视图 → `no_native_view`(409)；`errors_failed`/`errors_timeout`/`target_changed` 各 wire code 独立。

## 自动测试

- `automation_queries_test.dart` errors 组 7 项：显式 ID、not_found、no_native_view、frame+source 双脱敏（SECRET/TOK 标记不落响应）、target_changed→409、failed/timeout→500、畸形 JSON→errors_failed、capabilities 声明。
- `automation_server_test.dart` 白名单加 `errors`；`relayctl_test.py` 27 项（errors 转发 + 必需 identity）。
- `flutter analyze` 零问题。

## 如实标注的未覆盖项

- 缓冲上限路径（>200 条溢出→`overflow` 计数）未实机灌满；字段截断同理（判定在固定脚本内，形状由单测覆盖）。
- `target_changed` 命中沿用 snapshot/media 已验绑定机制，本次未单独构造。
- 只读 drain 不清缓冲——同一文档内重复调用返回相同条目（`bufferId`+`count` 可判增量）；缓冲销毁时机=文档/面板生命周期，无手动 reset API（保持只读语义）。
- `console.error`/`console.warn`、资源加载错误（`error` 事件 capture 阶段的资源错误）、跨源 iframe 内部错误均不采——按 issue 只收 `error`/`unhandledrejection`。
