# 验收测试页（夹具）

这些页面是**测试夹具**，仅用于验收 Relay Desk 公开调试接口的行为，不代表真实业务页面。
启动方式（仓库根目录执行）：

```bash
python3 -m http.server 8901 --bind 127.0.0.1 --directory .
```

- 夹具地址：`http://127.0.0.1:8901/test/fixtures/pages/<page>.html`
- 真实评审页（案例 A）：`http://127.0.0.1:8901/.roundtables/auto-update-review/index.html`

本表记录**测试页预期**；接口实际观察值以验收报告为准。

## 媒体场景

| 页面 | 预设场景 | 预期接口观察 |
|---|---|---|
| `media.html` | 播放中 + 暂停(0s) + 坏源 + 无源 + 同源 iframe + data: iframe + 跨源 iframe | playing 推进；paused@0；坏源/无源可区分；跨源帧 `reachable:false` |
| `media-frame.html` / `media-frame2.html` | 同源嵌套 iframe（两层） | 分层标签 `f*.f*` 内出现媒体项 |
| `media-seek.html` | 页面自身 seek 至 20s 后**暂停**（t<15s 落点保持）；t≥15s 起静音播放 | 阶段一采样 `paused:true` 且 currentTime≈20s（落点可独立判断）；阶段二 `paused:false` 且 >20s 推进 |
| `media-many.html` | 40 个 `<video>`（探针上限 32） | `skipped.media>0`，前 32 项 |
| `no-media.html` | 无媒体元素 | `media:[]` / 无媒体可区分输出 |

## 异常场景

| 页面 | 预设场景 | 预期接口观察 |
|---|---|---|
| `errs.html` + `errs-frame.html` | 主文档同步 error、未处理 Promise、对象 rejection；iframe error | `error`/`unhandledrejection` 两种 kind；帧级归集 |
| `errs-flood.html` | 230 个 error（环形上限 200） | `overflow=30`，保留最新 200 条 |
| `errs-reload.html` | `?batch=N` 驱动的导航批次：batch=0 文档抛 `batch-0-error`，15s 后 `location.search='?batch=1'` 导航；batch=1 文档抛 `batch-1-error` | 导航前后 `bufferId` 不同，旧批次不带入新缓冲 |
| `errs-creds.html` | 合成凭据：短/长 quoted、bare key=、含 userinfo+query 的 URL、Bearer、对象 secret | 全量 `<redacted>` / URL 仅 origin+pathname；长值按 `<redacted>` 后不泄露任何片段 |
| 双身份隔离 | 仅 A 页抛错 | B 的 errors 缓冲无 A 的记录 |

## DOM 边界场景

| 页面 | 预设场景 | 预期接口观察 |
|---|---|---|
| `hidden.html` | CSS/属性隐藏祖先、隐藏 span、可见控件 | 隐藏元素不输出文本/属性，计 `skipped.hidden` |
| `dom-frame.html` | 同源 + 跨源 iframe 混排 | 跨源帧 `reachable:false`，帧序 DFS |
| `dom-frames-mixed.html` | 隐藏 iframe 位于可见 iframe 之前 | 隐藏帧不入列；可见帧标签按 DOM 位次（f1/f3），三 op 一致 |
| `dom-mutate.html` | 15s 后移除 `#victim`（`#victim2` 滑入其位置）并追加新元素 | 被占位的已签发 ref → `stale_element`；位置现为未签发元素 → `not_found` |
| `dom-reload-once.html` | 15s 后同 URL 重载一次（sessionStorage flag 防循环） | 旧 documentId/ref → `stale_element` |
| `dom-many-frames.html` | 20 个同源 iframe（上限 16） | `framesTruncated>0`；显式 `--frame` 超范围 → `frame_out_of_scope` |
| `dom-many-cands.html` | 500 个同文本链接（find 上限 400） | `candTruncated:true` + `complete:false` |
| `a.html` / `b.html` | 纯色标记页 PAGE-ALPHA / PAGE-BETA | 截图与 DOM 标题对应 |

## 无状态输出区分

- 不可达帧：`reachable:false` + `reason`
- 缓冲未安装：`installed:false`（当前同源文档均由探针安装，主要见于不可达帧）
- 无媒体 / 无错误记录：`media:[]`、`errors:[]` + `count:0`
- 截断：`truncated` / `skipped.*` / `*Truncated` 字段
- 失效 ref：`stale_element`；未签发 ref：`not_found`

注：`v.mp4`（90s，≈1.1MB）与 `a.wav`（6s）为本地媒体源；`media-seek.html` 依赖 v.mp4 时长 ≥20s。
