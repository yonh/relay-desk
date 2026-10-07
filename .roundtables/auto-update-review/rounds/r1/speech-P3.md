---
participant: P3
round: r1
stance: R1–R5 修复全部核验成立，代码层面无 blocker；干净机实测是发布流程硬闸门（非代码 blocker），裁决"代码可发布、实测前不点发布"
---

## 立场

R1–R5 五项修复逐条对码核验，全部成立且落点正确。代码层面我不再持 blocker——r0 我提的 ditto 回滚嵌套（installer.dart:220-222 `rm -rf "$TARGET" && mv "$BACKUP" "$TARGET"`）已修，P4 的 B1–B4 也全部落实。裁决：**代码可随 v1.0.3 发布，但发布动作以干净机实测完成为硬前提**。这个"硬前提"是流程闸门，不是代码缺陷——两者必须分开，否则会用"失败模式安全"自我循环论证来跳过验证。

## 交锋

- re: P2 —— concur + dissent —— R1–R5 逐条核验成立：R1 `pgrep -f "$TARGET/Contents/MacOS/"`（installer.dart:191-192）、R3 `trap cleanup EXIT`（:172-179）、R4 `version.isPreRelease`（models.dart:59）、R5 解压失败清 payload（downloader.dart:150）均落点正确。但**不同意 P2"干净机实测不构成硬阻塞"**：P2 的论证"失败模式安全 → 不构成硬阻塞"是自我指涉——实测验证的正是失败模式是否真的安全，不能用待验证的结论来论证不需要验证。失败模式安全是代码质量判断，硬闸门是发布流程判断，二者不矛盾。
- re: P4 —— concur + build —— P4@r0 的 B1–B4 全部落实：B1 回滚嵌套（installer.dart:220-222）、B2 按钮契约（update_ui.dart:242 `_ => const []`）+ skipVersion busy 守卫（update_controller.dart:342）、B3 失败分支顺序（installer.dart:213-225 先 mv payload 再 open）、B4 双 helper 互斥（installer.dart:198 mkdir 锁 + :68-73 唯一脚本名 + :127 8s 后复检 marker）。补充 P4 未明说的互补关系：B4 的 mkdir 锁与 P2 的 R1 pgrep 守卫是**两层独立防线**——pgrep 防"swap 运行中 app"，mkdir 锁防"双 helper 并发 swap"，二者不可互替。
- re: P1 —— concur + build —— P1@r0 B1（autoDownload ∩ asset==null 静默死角）已修（update_ui.dart:60-62 `(!autoDl || next.asset == null)`），同意 blocker 定级。但 P1 自己提到的"autoDownload 下载失败静默"（failed 不在 wantsPrompt）**仍未修**——update_ui.dart:60-62 只含 ready 与 available&&(!autoDl||asset==null)，failed 阶段不弹窗。settings 状态行可见性我确认可行（failed 状态本就在 settings 渲染），但 Gate 层无提示，建议至少记入 §11 known limitation 并补一条 AC。

## 立场更新

维持 r0 立场"修复成立、可发布"，但**收回 r0 的 blocker 定级**——r0 我判 ditto 回滚嵌套为 blocker，该项已修（installer.dart:220-222），当前代码无我持有的 blocker。同时**修正 r0 对干净机实测的表述**：r0 我写"需实测复核"，r1 明确为"发布流程硬闸门"——实测未完成前不点发布按钮，但代码质量裁决不因此降级。

## 风险与盲点

- **pgrep 自匹配边界**（核验 R1 时的二阶检查）：helper 的 bash 进程命令行是 `/bin/bash /path/to/updater`，不含 `$TARGET/Contents/MacOS/`，不会自匹配；pgrep 排除自身；执行 pgrep 的父 shell 命令行不随脚本内容改变。无自匹配风险。pgrep pattern 中 `.` 是 ERE 通配符会匹配任意字符，但只导致更宽匹配（安全方向），不会漏。
- **pgrep TOCTOU 窗口**：pgrep 通过后、mv 前用户启动 app 的窗口为毫秒级，且此时主进程已退出、用户手动重开需时间，可接受。
- **trap cleanup 的 SIGKILL 盲区**：`trap cleanup EXIT` 覆盖 TERM/INT 等可捕获信号，但 SIGKILL/断电无法捕获——此时 `.relay-backup` 残留而 TARGET 缺失，无自愈。spec §14 已正确记录为已知边界，release checklist 应写一条手工恢复说明。
- **成功路径 backup 删除时机**（installer.dart:208-209）：`rm -rf "$BACKUP"` 仍在 `open "$TARGET"` 之前。open 失败时备份已删，用户无法回滚。r0 我提过，未修，严重度次之——但建议至少把 backup 保留至下次启动 L2 清扫，一行改动。
- **autoDownload 下载失败静默**：failed 阶段 Gate 不弹窗（update_ui.dart:60-62），仅 settings 状态行可见。P1 建议"低频提示或记 known limitation"，当前两者皆未做。

## 抛给圆桌的问题

1. 干净机实测若发现 8s 超时路径行为与预期不符（如 LaunchServices 延迟超 8s），裁决是否立即降级为"需修改后才能发布"？我主张是——实测是唯一能证伪"失败模式安全"的手段。
2. 成功路径 backup 删除时机（open 失败即丢备份）是否随 v1.0.3 修？我倾向修（一行改动、消除最后一个"旧版不可恢复"路径），但若各席认为 open 概率极低可接受，我同意记 known limitation。
3. autoDownload 下载失败静默：补一条 Gate 低频提示 AC，还是记 §11 known limitation？请明确站队。
