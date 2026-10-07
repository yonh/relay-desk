# Relay Desk 自动更新 — 执行计划 Spec

版本：v1.5 · 2026-10-08 · 状态：已实现（macOS 全自动；Win/Linux 降级手动）
上游文档：`design/auto-update-discussion.md`（多模型评审记录）
变更记录：v1.1–v1.4 多轮互审（§12–14）；v1.5 真机实测：quarantine→-10810，
helper 改预置 bundle（§5）；更新对话框加当前版本显示；26 测试全绿

---

## 1. 目标与非目标

### 目标
- G1 启动后自动检查 GitHub Releases 最新版本（静默、节流）
- G2 发现新版本弹出对话框：版本号 + 发布说明 +「下载更新 / 稍后 / 跳过此版本」
- G3 设置页提供：自动检查开关、自动下载开关、手动检查按钮、已跳过版本管理
- G4 下载带进度 + 可取消 + SHA-256 完整性校验（对照 API `digest`）
- G5 macOS 全自动安装：退出主程序 → 替换 bundle → 重启，全程保留 App Sandbox
- G6 任何路径下不产生磁盘残留（三层清理）

### 非目标（v1）
- Windows / Linux 自动替换安装（下载校验可用，安装降级为打开目录 / Release 页）
- 断点续传（包体 ~26MB，失败整删重下）
- 差量更新、签名校验（minisign/EdDSA，Sparkle 级安全）
- 预发布通道订阅（prerelease 一律过滤）

---

## 2. 架构

```
lib/
  core/update/
    models.dart            ReleaseAsset / GithubRelease / UpdatePhase / UpdateStatus /
                           versionFromTag / versionFromPackage / isRemoteNewer /
                           isSkipped / selectAsset / hostPlatformToken
    settings_storage.dart  UpdateSettings + UpdateStorage 接口
                           + SharedPreferencesUpdateStorage + MemoryUpdateStorage
  platform/update/
    release_client.dart    ReleaseClient 接口 + GithubReleaseClient (dart:io HttpClient)
    downloader.dart        UpdatePaths / StagedUpdate / UpdateDownloader 接口
                           + HttpUpdateDownloader（下载→校验→解压）
    installer.dart         UpdateInstaller 接口 + MacOSUpdateInstaller（helper .app）
                           + revealStagedUpdate 兜底
  features/update/
    update_controller.dart providers + UpdateSettingsController + UpdateController
    update_ui.dart         UpdateGate / UpdatePromptDialog / UpdateSettingsSection /
                           openExternalUrl
main.dart                  UpdateStorage override + UpdateGate 包裹 Home
settings_dialog.dart       设置弹窗追加 UpdateSettingsSection
```

**注入缝（全部 Provider，测试可替换）**：`updateStorageProvider` ·
`releaseClientProvider` · `updateDownloaderProvider` · `updateInstallerProvider` ·
`updatePathsProvider` · `appVersionReaderProvider` · `quitAppProvider`

---

## 3. 数据契约

### 3.1 SharedPreferences 键

| key | 类型 | 默认 | 语义 |
|---|---|---|---|
| `update.auto_check` | bool | true | 启动后自动静默检查 |
| `update.auto_download` | bool | false | 发现新版后免询问直接下载 |
| `update.skipped_version` | string? | null | 规范化 `X.Y.Z`；`remote ≤ skipped` 不提醒 |
| `update.last_check_ms` | int | 0 | 上次检查 epoch ms（节流源） |
| `update.ready_tag` | string? | null | 已下载+校验+解压完成的 release tag |

### 3.2 GitHub API

- 端点：`GET https://api.github.com/repos/yonh/relay-desk/releases/latest`
- 头：`Accept: application/vnd.github+json`、`User-Agent: relay-desk-updater`
- 使用字段：`tag_name` · `body` · `html_url` · `draft` · `prerelease` ·
  `assets[].name/browser_download_url/size/digest`
- `digest` 形如 `sha256:<hex>`，截取后做下载校验；缺失时跳过校验
- 限流：未认证 60 req/h/IP → 自动检查 6h 节流 + 失败静默
- 资产选择（白名单 token，`selectAsset`）：
  - macOS → 名称含 `macos` 且 `.zip` 结尾（dmg 不自动安装）
  - Windows → `windows` + `.zip`；Linux → `linux` + `.tar.gz`/`.zip`
  - 无匹配 → 对话框降级为「打开下载页面」(`html_url`)

### 3.3 版本语义

- `versionFromTag('v1.0.3') → 1.0.3`；`versionFromPackage('1.0.2+3') → 1.0.2`
- 仅 `remote > current` 才提示；本地领先或相等 → `upToDate`
- draft / prerelease / 无法解析的 tag → `fromJson` 返回 null → 视为无更新
- 跳过：`remote ≤ skippedVersion` → 自动检查静默；**手动检查不受 skipped 限制**
- **发布流程约束（写进 release checklist）**：每次发版必须提升 `X.Y.Z` ——
  `+build` 号不参与远端比较，同 X.Y.Z 重新发版不会触发更新提示
- 资产架构假设：macOS 包为 universal；若未来拆分 arm64/x64 需扩展 `selectAsset`

### 3.4 磁盘布局

`getApplicationSupportDirectory()/updates/<tag>/`

```
  package.zip          下载完成并 rename 的成品包
  package.zip.part     下载中的半截文件（失败/取消即删）
  payload/…X.app       解压产物（ditto -xk，含 .app bundle）
  helper/RelayDeskUpdater.app   运行时生成的安装 helper
  helper.started       helper 存活标记（安装握手）
```

---

## 4. 状态机

```
                 check()                 remote>cur & !skipped
  idle ──────────────────► checking ───────────────────► available ─┐
    ▲                        │                              │       │ autoDownload
    │                        ├─ none/≤cur/skipped ─► upToDate │       ▼
    │                        └─ error ─► failed(check)*   下载更新  downloading
    │                                                       │    (progress 0..1)
    │  dismiss()/skip                                       ▼    cancel→available
    └────────────────────────────── ready ◄── verifying ◄──┘
                                       │ installAndRelaunch
                                       ▼
                                  installing ─► helper 握手成功 ─► exit(0)
                                       └─ 握手失败 ─► failed(install) + open -R 兜底
                                            （同时写 helper.abort 拦截迟到 helper）

  * auto 检查失败 → 回 idle（静默）；manual 失败 → failed(check) 可见
```

- `busy = checking|downloading|verifying|installing`：所有入口先查 busy，防重入
- `readyTag == tag && 暂存 .app 存在` → check 直达 `ready`（不重复下载）
- `download()` 幂等：`readyTag == tag` 且暂存完好 → 直接置 `ready`
- `retry()`：check 失败→手动重查；download 失败→重下（幂等复用暂存）；
  install 失败→回 `ready`（暂存仍有效，不重复下载）
- `dismiss()`（"稍后"）：重置 `lastCheckMs=0` —— 下次启动立即重新检查并再提醒，
  不被 6h 节流吞掉
- `markChecked` 只在 fetch 成功后写入 —— 失败的 auto-check 不消耗节流配额
- autoDownload 弹窗豁免在 **Gate 监听器层**：`available` 且 autoDownload → 不弹，
  下载静默进行，`ready` 时才弹「安装并重启」

---

## 5. 安装握手（macOS 沙盒逃逸，已实测）

> **v1.5 架构变更（真机实测驱动）**：沙盒应用写出的文件会被系统强制加
> `com.apple.quarantine`，且沙盒内不可移除——运行时生成的 helper `.app`
> 被 LaunchServices 拒启（`_LSOpenURLsWithCompletionHandler -10810`）。
> **helper 改为预置在主 bundle 内**：`macos/Runner/RelayDeskUpdater.app`
> 经 Xcode Resources 阶段 `CodeSignOnCopy` 拷入 `Contents/Resources/`，随主包
> 签名/公证 → 无 quarantine → LS 放行。运行时参数全部走 `open --args`
> （pid/root/staged/target/archive），脚本读 `$1..$5`，无任何运行时生成。

1. 主程序定位 `<bundle>/Contents/Resources/RelayDeskUpdater.app`（不存在则
   判 hand-off 失败，走 reveal 兜底）
2. `/usr/bin/open -n <helper> --args $pid $root $stagedApp $target $archive`
   —— LaunchServices 在沙盒外 spawn helper（argv 传参已实测可用）
3. 主程序轮询 `<root>/helper.started`（**8s** 超时，超时后**再复检一次**
   marker 防边界竞态）→ 出现则 `exit(0)`；未出现 → 写入 `helper.abort` +
   `open -R` 兜底 + failed(install)（主程序保持运行）
4. helper 脚本（参数全来自 argv，脚本本体为仓库内静态文件
   `macos/Runner/RelayDeskUpdater.app/Contents/MacOS/updater`）：
   - `touch marker` → 循环 ≤120s 等 `kill -0 $PARENT` 失败（期间见 `helper.abort`
     提前退出）→ **循环结束复检：父进程仍存活 或 出现 abort 文件 →
     `touch helper.aborted` + exit 1，绝不替换运行中的 app**
   - `pgrep -f "$TARGET/Contents/MacOS/"` 检查任意运行实例（防 1s 窗口内
     手动重开）；命中写 `instance-running` 留档退出
   - `mkdir helper.lock` 原子锁：双 helper 并发时仅一个进入 swap 区
   - 旧 bundle 存在时 `mv → .relay-backup` **必须成功**，失败即 abort —— 否则
     ditto 会把新旧合并成损坏包
   - `ditto 新.app → 原位`
   - **ditto 成功后、`rm -rf $BACKUP` 前第二道 pgrep**（TOCTOU：覆盖整个
     ditto 窗口内重开的实例）→ 命中回滚并写 `instance-running-late`
   - 成功：`xattr -dr com.apple.quarantine` → 删 payload+zip+marker+abort+lock
     → `open "$TARGET" && rm -rf "$BACKUP"`（open 失败时备份留存手工恢复）
   - 失败：**先** `mv payload → ~/Downloads/RelayDesk-<tag>`（抢在重启旧版的
     L2 清扫之前移出暂存区）→ `rm -rf 残缺 TARGET` 后 `mv 备份回滚`（防嵌套/
     ENOTEMPTY）→ `open` 重启旧版 → `open -R` 展示 Downloads 里的包
   - `trap cleanup EXIT`：BACKUP 在而 TARGET 缺失 → mv 回滚（覆盖 mv 与 ditto
     之间被杀、显式回滚语句自身失败两类）；OWN_LOCK 守卫防第二 helper
     误删第一 helper 的锁
5. helper bundle 在主包内随版本走，无运行时残留；staging 目录由 L2 清扫

---

## 6. 清理策略（三层）

| 层 | 时机 | 动作 |
|---|---|---|
| L1 | helper 安装成功后 | `rm -rf` backup、payload、zip、marker |
| L2 | 每次启动 `_sweepStaging` | 删除 `updates/` 下所有 ≠ readyTag 的目录；readyTag 版本 ≤ 当前版本（已消费）→ 一并删除并清 pref |
| L3 | 下载失败/取消/校验失败 | 即时删 `.part`；未产生完整 archive 时删半个 payload |

另：`skipVersion(tag)` 时若 `readyTag == tag` → 删暂存 + 清 pref；
`check()` 发现 `readyTag ≠ latest tag` → 删旧暂存。

---

## 7. UI 契约

### 7.1 更新对话框（UpdatePromptDialog，barrierDismissible:false，单例/会话每 tag 一次）

| phase | 内容 | 按钮 |
|---|---|---|
| available | 标题`发现新版本 vX.Y.Z`、资产体积、发布说明（滚动）、无资产提示 | 跳过此版本 · 稍后 · 下载更新 / 打开下载页面 |
| downloading | 进度条（未知总长→indeterminate）+ 百分比 | 取消下载 |
| verifying / installing | spinner + 文案 | — |
| ready | `更新已就绪` + 说明文案 | 跳过此版本 · 稍后 · 安装并重启 |
| failed | 错误文本 | 完成 · 重试 |

### 7.2 设置区块（UpdateSettingsSection）

- 自动检查 Switch（`update-auto-check`）· 自动下载 Switch（`update-auto-download`）
- 已跳过行：`已跳过版本 X` + 清除
- 检查行：`检查更新` 按钮（busy 置灰）+ 状态行（checking/upToDate/`vX 查看`/
  下载中/校验中/安装中/失败）

### 7.3 l10n（en + zh 全量新增 22 keys，见 app_en.arb/app_zh.arb `update*`）

---

## 8. 边界与风控

- **GitHub 限流**：60 req/h → 6h 节流；auto 失败静默回 idle
- **网络重定向**：下载 302 → CDN，`HttpClient.followRedirects` 默认跟随
- **并发**：state.busy 单飞；UpdateGate 每 tag 每会话仅弹一次
- **helper 失败**：8s marker 超时 → 写 `helper.abort` + `open -R` 兜底 + failed(install)
- **替换失败**（无写权限）：helper 回滚 `.relay-backup` + 重启旧版 + payload 移到 `~/Downloads` 展示
- **Gatekeeper**：HTTP 直连下载无 quarantine；装后仍 `xattr -dr` 双保险
- **校验缺失**：`digest` 为空 → 跳过校验放行（GitHub 目前总是提供）
- **校验强度边界**：sha256 只防下载损坏——digest 与下载包同源自 API 响应，
  若 API 元数据被篡改则 digest 同步被换；真正防伪需发布端签名（列入后续候选），
  spec 不宣称"已签名校验"
- **会话内重复弹窗**：`_promptedTags` 记录；「稍后」当次不再弹，重启后恢复提醒
- **对话框单例**：模块级 `_updatePromptOpen` 守卫，设置页"查看"与 Gate 不叠加
- **下载挂起**：连接 30s 超时 + 分块 60s stall 超时，不会永久卡在 downloading
- **安装位置**：不假设 `/Applications` —— `runningAppBundle` 解析可执行文件
  向上找 `.app`，任意位置原位替换；无写权限 → helper 回滚 + Downloads 兜底
- **多 .app 包**：payload 内取递归首个 `*.app`（release 包约定单 app）
- **隐私**：仅访问 api.github.com/objects.githubusercontent.com，无遥测
- **已知未验**：helper 的 `open` 启动与 Gatekeeper 行为只在开发机实测过，
  干净机器 + 正式公证产物上的握手链路需随下个 release 实测复核

---

## 9. 验收标准（AC）

- AC1 远端 `vX.Y.Z` > 本地 → `available`，对话框出现且每 tag 每会话一次
- AC2 远端 ≤ 本地 / draft / prerelease / 坏 tag → `upToDate`，不弹窗
- AC3 设 `skippedVersion=X` 后远端 `≤X` 自动检查静默、`>X` 提醒、手动检查仍提醒
- AC4 autoDownload=true 时 check 后直达 `ready`，无中间弹窗阻塞
- AC5 下载进度连续回调；取消 → `available` 且无 `.part` 残留
- AC6 sha256 不匹配 → failed(download) + 文件删除
- AC7 install 握手成功 → `exit(0)`；helper 完成替换+重启+删负载
- AC8 helper 未启动 → failed(install) + 访达展示新 app；旧 app 原样可回滚
- AC9 更新后首次启动：暂存目录（含 helper）被清扫、readyTag 清除
- AC10 开关/跳过/readyTag 写入 SharedPreferences，重启后保留
- AC11 设置页两个 Switch、检查按钮、跳过行、状态行齐全（中英双语）
- AC12 helper 等待超时（主进程仍存活）→ `helper.aborted` 退出，**不替换**
- AC13 `helper.abort` 文件存在 → 迟到的 helper 放弃 swap
- AC14 swap 失败 → 备份回滚 + 旧版重启 + payload 移入 `~/Downloads/` 不被 L2 误删
- AC15 autoDownload → `available` 不弹窗，直达 `ready` 时才提示安装
- AC16 install 失败后 retry → 回 `ready` 复用暂存，不重新下载
- AC17 「稍后」→ `lastCheckMs` 清零，下次启动重新检查并提醒
- AC18 下载连接 >30s / 分块间隔 >60s → 中止并归入 failed(download)
- AC19 重复触发 `showUpdatePrompt` 不产生叠加对话框
- AC20 verifying/installing/checking/idle/upToDate 阶段对话框无按钮
  （skipVersion 受 busy 守卫，安装中不可跳过）
- AC21 ditto 半失败回滚不产生嵌套备份（先 `rm -rf` 残缺 target 再 mv）
- AC22 失败分支 payload 迁出 ~/Downloads 先于旧版重启（不被 L2 竞态删除）
- AC23 同一时刻至多一个 helper 进入 swap（mkdir 锁 + 8s 边界复检 +
  每次尝试唯一 bundle 名）
- AC24 autoDownload 且 asset==null 时 `available` 仍弹窗（降级打开下载页）；
  autoDownload 下载失败在设置页状态行可见（接受不额外弹窗）

## 10. 测试映射（test/features/update_test.dart，26 项全绿）

- 纯函数：tag/package 解析、比较、skip 边界、资产选择 → AC2/AC3
- fromJson：digest 解析、draft/prerelease/坏 tag → AC2
- Controller：available/upToDate/节流、skip 静默 vs 手动、autoDownload 直达 ready、
  download→ready→install→quit、失败归类 stage、cancel、skip 清暂存、
  就绪暂存续用、auto 静默/manual 报错 → AC1/AC3/AC4/AC5/AC6/AC10
- Widget：设置区块开关持久化 + 检查按钮 → AC11
- 实机验证（本次会话）：helper.app 经 `open` 启动成功（marker ~900ms）；
  swap 脚本备份→替换→清理链路通过 → AC7/AC8

## 11. 后续候选（不在本次范围）

- Sparkle 2 迁移（签名+差量）· Windows/Linux 自动安装 · ETag/304 ·
  断点续传 · 磁盘空间预检 · 发布说明 Markdown 渲染 · beta 通道开关 ·
  多实例并发文件锁 · 发布端包签名（minisign/EdDSA）

---

## 12. 第二轮互审 → 修复落实（v1.1）

| 审查发现（来源） | 处置 |
|---|---|
| helper 等满 120s 无条件替换运行中 app（fledge, mimo） | 循环结束复检 `kill -0`，存活 → `helper.aborted` 退出 |
| marker 超时后 helper 仍 swap，状态矛盾（fledge, mimo） | 主程序失败路径写 `helper.abort`；helper 等待期与 swap 前都检查 |
| helper 未签名 Gatekeeper 风险（longcat） | `codesign --force --sign -` ad-hoc 签名；干净机器实测列入已知未验 |
| swap 失败 payload 被 L2 清扫误删（mimo） | 失败时 `mv payload → ~/Downloads/RelayDesk-<tag>` 再 reveal |
| swap 失败用户会话消失（mimo） | 回滚备份后 `open` 重启旧版 |
| autoDownload 下 `available` 瞬态仍弹窗与 AC4 矛盾（mimo） | Gate 监听器按 autoDownload 豁免 `available` 弹窗 |
| install 失败 retry 回 available 重复下载（longcat, fledge） | retry → `ready`；`download()` 幂等短路 |
| 「稍后」与 6h 节流语义冲突（mimo） | `dismiss()` 重置 `lastCheckMs` |
| auto check 失败消耗节流配额（mimo） | `markChecked` 移至 fetch 成功后 |
| 下载无超时锁死 busy（mimo） | 连接 30s + 分块 stall 60s 超时 |
| 对话框可被叠加打开（mimo） | `_updatePromptOpen` 单例守卫 |
| 同 X.Y.Z 重新发版不提示（longcat） | §3.3 发布流程约束：每次发版必升 X.Y.Z |
| 资产未分架构（longcat） | §3.3 记录 universal 假设，拆架构时扩展 selectAsset |
| app 不在 /Applications（longcat） | §8 记录"原位替换、不假设路径"语义 |
| ETag/304、磁盘预检、多实例锁、Sparkle | 明确列入 §11 后续候选 |
| digest 不防伪（fledge） | §8 写明校验强度边界，不宣称签名校验 |
| UpdateStage.verify 与 phase 归属含糊（mimo） | verify 阶段错误归入 download stage，文案以阶段文案区分 |

### 第二轮未采纳 / 已澄清

- longcat「`kill -0 $PPID` 握手不可靠」：**不成立** —— 实现把主进程 PID 以字面量
  嵌入脚本（`PARENT=<pid>`），不依赖 PPID；但由此发现的"超时无条件 swap"
  是真实缺陷，已按上表修复
- ling `snoozedUntil`：维持"稍后=不持久化、重启再提醒"语义，`dismiss`
  重置节流后语义自洽

---

## 13. 第三轮终审 → 修复落实（v1.2，roundtable 圆桌）

终审结论：第二轮修复逐条验证成立；但失败路径仍有 6 个新缺陷，已全部修复。

| 发现（席位） | 处置 |
|---|---|
| autoDownload + asset==null → `available` 被 Gate 豁免后永久静默（P1） | Gate 豁免加 `asset != null` 条件；无资产时正常弹「打开下载页面」 |
| ditto 半失败 → `mv BACKUP TARGET` 对非空目录失败/嵌套（P3, P4） | 回滚前先 `rm -rf` 残缺 target 再 mv |
| `mv TARGET → BACKUP` 失败仍 ditto → 新旧合并损坏（P1, P3） | `mv` 失败即 `helper.aborted` 退出 |
| 失败分支先 `open` 重启再 mv payload → 被 L2 清扫竞态删除（P4） | 顺序对调：先迁 payload 到 ~/Downloads 再重启旧版 |
| verifying/installing 阶段按钮兜底显示「跳过/下载」，握手期点跳过会删 payload（P4） | 非可用阶段 actions=`[]`；`skipVersion` 加 busy 守卫 |
| 8s 边界 marker 晚到 + 重试生成双 helper 并发 swap（P4） | 超时后再复检一次 marker；`mkdir helper.lock` 原子锁；每次尝试唯一 bundle 名 |

### 第三轮裁决与遗留

- **发布裁决**：P1「修 B1 后可发」、P3「修 blocker 后可发」、P4「修 4 项后可发」——
  上表已全部落实，满足三方放行条件
- 接受为已知边界（不阻塞）：PID 复用窗口 <1s（P4 主动降权）；换包中途断电无
  journal 可留 `.relay-backup`（写入 release checklist 恢复说明）；helper 握手在
  干净机器+公证产物上需随 v1.0.3 实测复核
- autoDownload 下载失败不额外弹窗：设置页状态行可见，接受静默（产品取舍）

---

## 14. P2 终审补充 → 修复落实（v1.3）

P2（ling，重派后完成）确认第二轮修复逐条成立并裁决「有条件可发布」，补充
R1–R5；R2 经查已在第三轮修过（其引用行号为旧版），其余四项全部落实：

| P2 发现 | 级别 | 代码实际覆盖 + 残余窗口 |
|---|---|---|
| R1 换机重开竞态：app 退出后窗口内手动重开，新实例运行中仍被 swap | 中低危→已修 | **双检查点**：`sleep 1` 后 + `rm -rf "$BACKUP"` 前各一次 `pgrep -f "$TARGET/Contents/MacOS/"`；晚到命中走 `rm -rf "$TARGET" && mv "$BACKUP" "$TARGET"` 回滚。残余：第二次检查与 rm 之间的毫秒级窗口，不可消除只可收窄 |
| R2 `mv TARGET→BACKUP` 未检查返回值 | 误报（第三轮已修） | `mv … || { aborted; exit 1 }` 在第三轮落地 |
| R3 helper 在 mv 与 ditto 之间被杀 → 只留 `.relay-backup` | 低危→已修 | `trap cleanup EXIT`：`[ -d BACKUP ] && [ ! -d TARGET ]` 时 mv 回滚——实际覆盖面比记载更广，也兜底「显式回滚语句自身失败」；trap 失败时写 `rollback-failed` 留档。SIGKILL/断电不触发 trap，无 journal 已知边界 |
| R4 `v1.1.0-rc.1` 以正式 release 发布会提示升到 RC | 低危→已修 | `fromJson` 过滤 `version.isPreRelease`，测试覆盖 `rc.1`/`beta+2` |
| R5 解压失败留 payload 残留，重下时 ditto 合并 | 低危→已修 | 解压前无条件清空 payload；解压失败/无 .app 时即删。残余（P1 补充）：SIGKILL 留下的「有效 archive + 半成品 payload」在下次重下时被解压前清空覆盖，不可达 |

- 发布闸门（P2 提圆桌裁决，r1 三席确认）：干净机器 + 公证产物完整握手实测
  列为 v1.0.3 发布**流程硬闸门**——P4 补的论据：实测可能失败的不是超时类
  （落点安全的 UX 降级），而是 Gatekeeper/公证链路拒绝运行时 helper（落点是
  macOS 自动安装路径整体不可用，代码无解）——恰在四席全部只读代码的盲区。

### r1 交锋落实（v1.4）

| 席位间分歧/发现 | 处置 |
|---|---|
| **P4 dissent P1**：pgrep 在 `sleep 1` 后、`rm -rf $BACKUP` 在 ditto 后，中间隔 0.3–3s，"检查之后启动"的实例挡不住 | **P4 胜**：ditto 成功后、`rm -rf $BACKUP` 前加第二检查点，命中回滚而非破坏；spec R1 行改为双检查点表述 |
| P3：成功路径 `rm -rf $BACKUP` 在 `open` 之前，open 失败丢备份 | 已修：`open "$TARGET" && rm -rf "$BACKUP"`，open 失败时备份留存供手工恢复 |
| P1：pgrep 误伤（别名路径运行/开发工具触碰）静默 abort 难排查 | 已修：abort 原因写入 `helper.aborted` 文件内容（`parent-alive-or-aborted`/`instance-running`/`instance-running-late`/`rollback-failed`） |
| P1：trap cleanup 静默失败无现场 | 已修：回滚 mv 失败写 `rollback-failed` 标记 |
| P4：AC20–24 零自动化覆盖 | 已修：`buildHelperScript` 标 `@visibleForTesting`，8 条字符串断言锁不变量（PID 嵌入、锁先于 swap、mv 失败 abort、双 pgrep、回滚不嵌套、payload 先迁后重启、open 后删备份、trap 自愈） |
| P4：§13 处置表选择性记录（P1-B3 已修未记、P3-open 前删备份未修未记） | 本节已改为「代码实际覆盖 + 残余窗口」两列式；下方补「未处置/已知遗留」清单 |

### 未处置 / 已知遗留（各发现均有归宿）

| 发现 | 状态 | 理由/落点 |
|---|---|---|
| PID 复用窗口 <1s（P4@r0 提出并主动降权） | 不修 | pgrep 守卫已覆盖其主要危害面 |
| SIGKILL/断电中途换包 → `.relay-backup` 残留 | 不修 | 无 journal 边界；release checklist 写手工恢复命令 `mv <app>.relay-backup <app>` |
| 失败分支 `open "$TARGET"` 成败不检查（P4） | 不修 | 已知降级：回滚成功但旧版也起不来时用户看到访达 payload；AC14 验收叙述不含此路径 |
| autoDownload 下载失败 Gate 不弹窗 | 不修（产品裁决） | settings 状态行可见；P4@r1 接受收口 |
| pgrep 子串误伤（别名路径副本运行→abort） | 不修 | 方向安全（宁可不更）；`helper.aborted` 内容已含命中原因可诊断 |
| R5 残余：SIGKILL 留半成品 payload | 不修 | 下次重下解压前无条件清空，不可达 |
| R1 残余：第二检查点与 rm 间毫秒级窗口 | 不修 | TOCTOU 物理下界 |
