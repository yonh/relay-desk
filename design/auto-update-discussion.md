# 自动更新功能 — 多模型设计评审记录

日期：2026-10-07
参与评审：fledge-alpha、ling-3.1-flash、longcat-2.5-preview、mimo-v2.6-flash（经 opencode 调用）+ Devin 综合

## 需求（原始简报）

通过 GitHub Releases 实现应用内自动更新：

1. 启动时自动检查更新（release tag `vX.Y.Z` vs pubspec `1.0.2+3`，semver 比较）
2. 发现新版本弹提示：版本号、发布说明、「立即更新 / 稍后 / 跳过此版本」
3. 设置页开关：自动检查、自动下载更新包
4. 带进度下载 + SHA-256 校验（GitHub API `digest` 字段）
5. 安装更新并重启
6. 装完删除下载文件，防止占用磁盘

核心难点：macOS **App Sandbox 已启用**，沙盒子进程继承沙盒 → 无法写
`/Applications` 替换自身 bundle。

## 各模型立场

### fledge-alpha —— 移除沙盒 + detached script
- 个人分发不走 App Store，沙盒换不来额外保护；直接删 `app-sandbox` 最简可靠
- 半自动 dmg 拖拽是退步，只能做 fallback
- 补充：`If-Modified-Since`/ETag 缓解 60 req/h 限流；公司 NAT 下尤其注意
- 脚本需 `xattr -dr com.apple.quarantine`；运行中不能覆盖自身，必须 detached + 等 pid

### ling-3.1-flash —— 移除沙盒 + detached script（备选 Sparkle 2）
- `open` 只能绕过沙盒启动进程，替代不了"复制文件"这一步——此点后被 Devin 修正
  （LaunchServices 在沙盒外 spawn 目标进程，helper 可做复制）
- 建议保留旧版本备份可回滚；脚本必须 `ProcessStartMode.detached`
- 提到 Sparkle 2（EdDSA 签名、差量更新）是更稳的现成方案
- 状态机建议 `.part` 落盘 rename；校验失败即删文件；「稍后」建议存 snoozedUntil 时间戳

### longcat-2.5-preview —— 保留沙盒 + open 半自动
- 改 entitlement 影响签名/公证链路，macOS 14+ 对未沙盒自替换有 TCC 限制
- 路径：解压到 Application Support → `open -n` 新 app → 提示用户移动到 /Applications
- 提醒：sandbox temp 会被系统清理，下载目录应放 Application Support 下固定目录
- 补充风险：磁盘空间预检查、文件锁防并发下载

### mimo-v2.6-flash —— 保留沙盒，两级安装
- 沙盒下 `open` dmg 半自动；检测到未沙盒（dev build）才走脚本全自动
- 命名匹配用**白名单正则**而非模糊 contains；匹配不到资产时降级打开 release 页
- 校验失败必须删文件并禁止进入 install 态；下载支持 Range 但 302 后签名 URL 会过期，
  v1 不做断点续传
- `autoDownload` 默认关；`autoCheck` 默认开

## 最终采纳方案（Devin 综合）

**保留沙盒 + 运行时生成 helper `.app` 经 `open` 启动执行替换** —— 第三条路：

- 不改 entitlement/签名/公证链路（回应 longcat/mimo 的担忧）
- 又能实现真正全自动（回应 fledge/ling 的全自动诉求）：`/usr/bin/open` 经
  LaunchServices 在沙盒外启动进程，生成的 `RelayDeskUpdater.app`（含 bash 脚本）
  可做文件替换。已实测：`open -n` 启动 helper 约 900ms，swap 脚本（备份→ditto→
  xattr→open→清理）验证通过
- helper 启动失败降级：`open -R` 在访达中展示已解压的新 app + 状态置 failed

### 定稿要点

- **版本**：`pub_semver` 比较 X.Y.Z；tag 去 `v` 前缀；pubspec `+build` 剥离；
  prerelease/draft 过滤；本地版本 ≥ 远端不提示
- **资产**：macOS 取 `*macos*.zip`（白名单 contains 匹配）；无资产时降级打开
  `html_url` release 页
- **状态机**：`idle → checking → upToDate/available → downloading(progress)
  → verifying → ready → installing`；`failed(stage,error)`；单 Notifier 互斥；
  下载写 `.part` 完成 rename
- **跳过语义**：持久化 `skippedVersion`（`remote ≤ skipped` 静默，更高版本恢复）；
  「稍后」不持久化，下次启动再提醒
- **持久化**：`update.auto_check`(默认开)/`update.auto_download`(默认关)/
  `update.skipped_version`/`update.last_check_ms`/`update.ready_tag`
- **清理三层**：① helper 成功后删 zip+解压目录+marker ② 启动时扫
  `Application Support/updates/` 删除非 readyTag 及已消费的暂存 ③ `.part`
  半截文件即时删
- **节流**：自动检查 6h 一次；手动检查不限且忽略 skipped；检查失败自动静默、
  手动才报错
- **续传**：v1 不做（26MB，失败整删重下）
- **未覆盖**：Windows/Linux 自动安装（下载校验可用，安装降级为打开目录）
