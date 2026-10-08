---
participant: P2
round: r0
stance: 第二轮修复逐项对码成立，未发现 blocker；裁决为「有条件可发布」——唯一发布闸门是 spec §8 自列的干净机/公证产物握手实测，R1–R5 低危项 follow-up 不阻塞。
---

## 立场

修复成立、可以收口，但「可发布」附一个硬前提：v1.0.3 发布前必须在干净机器 + 正式公证产物上实测一次完整握手链路（成功路径 + 8s 超时回退路径）。helper 链路目前只在开发机实测过（spec §8 自认），而它是全方案唯一不可回退的环节；其余失败路径（超时、swap 失败、下载损坏）在代码里都有安全落点。另有 R1–R5 五项低危 hardening 建议 follow-up，不阻塞发布。

## 论点

- 第二轮修复逐条对码确认落实：`helper.abort` 拦截迟到 helper（installer.dart:120-122,158,165-168）、循环后 `kill -0` 复检（installer.dart:162-168）、swap 失败 payload 移出暂存区（installer.dart:183-187）、Gate 层 autoDownload 豁免（update_ui.dart:57-59）、retry→ready 复用暂存（update_controller.dart:324-326）、dismiss 重置节流（update_controller.dart:308-315）、markChecked 仅在 fetch 成功后（update_controller.dart:156-158）、连接 30s/分块 60s 超时（downloader.dart:93-111）、对话框单例守卫（update_ui.dart:75-87）。
- 隐性不变量成立：ABORT 被 helper 以 0.2s 间隔轮询，因此「8s marker 超时 → 用户点重试」不会产生双 helper 竞争——迟到 helper 在 0.2s 内即退出。这是第二轮未明说、但代码里真实成立的关键安全性，也是我认为方案可收口的核心理由。
- 状态机与实现一致：busy 单飞、readyTag 短路、download 幂等、retry 三分支、dismiss 相位限定均符合 §4；verifying 相位在校验完成后才置位属文案级偏差，§12 已澄清。autoDownload/retry/dismiss 三条修复路径无新矛盾。
- AC1–AC19 覆盖第二轮全部高风险项；清理三层与代码一致（downloader.dart:139-155 finally 清理、update_controller.dart:387-408 L2 清扫）。

## 风险与盲点

- R1（中低危·换机重开竞态）：helper 只复检原 PID（installer.dart:165）。用户在 app 退出后 ~1.2s 窗口内手动重开，新 PID 存活而 swap 照常进行，成功分支 `rm -rf "$BACKUP"` 会删除正在运行实例的 bundle。最小修复：swap 前 `pgrep -f` 检测运行中实例，命中则 stand down。概率极低，但违背「绝不替换运行中 app」的本轮核心不变量。
- R2（低危）：`mv "$TARGET" "$BACKUP"` 返回值未检查（installer.dart:172）。mv 失败而 ditto 成功会产生新旧混合 bundle。最小修复：mv 失败即 `touch helper.aborted` + exit 1。
- R3（低危）：helper 若在 mv 成功后、ditto 前崩溃，`.relay-backup` 残留而原 app 消失，无自愈。建议启动时检测 `$TARGET.relay-backup` 并还原。
- R4（低危）：`GithubRelease.fromJson` 只过滤 API prerelease 布尔，不过滤 semver prerelease tag（models.dart:53-57）——`v1.1.0-rc.1` 若作为正式 release 发布，会提示更新到 RC。
- R5（低危）：解压失败时 payload 不清理（downloader.dart:150 的条件为 `!archive.exists()`），重下时 ditto 合并残留文件。
- 干净机 + 公证产物握手未实测（spec §8 自列）——唯一真正的发布闸门。

## 抛给圆桌的问题

- R1 的 pgrep 守卫：进 v1.0.3 还是 follow-up？我倾向 follow-up（概率极低、失败模式可恢复），但若其他席位认为它直接违背本轮核心不变量，应升级为 blocker。
- 干净机实测若在发布前无法完成，裁决是否降为「需修改后才能发布」？我的看法：失败模式安全（8s 超时 → abort → failed(install) + 访达展示），最坏是 UX 降级而非数据丢失，故不构成硬阻塞——请各席裁决。
