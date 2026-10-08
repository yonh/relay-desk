---
participant: P1
round: r1
stance: R1–R5 修复核验全部成立（含 R2 误报澄清）；干净机实测不构成代码硬闸门但必须是发布前强制项；R1 pgrep 处置充分——维持「可发布」裁决
---

## 交锋

- re: P2 —— concur（干净机实测定位）。同意 §14 的折中：实测失败模式安全（超时→abort→failed(install)+访达展示，最坏 UX 降级、无数据丢失），故不构成代码层 blocker；但它必须列为 v1.0.3 release checklist 的强制项而非 follow-up——否则「全 macOS 自动」唯一路径第一次真枪实弹是在用户机器上。
- re: P2 —— concur + build（R1 处置充分性）。`pgrep -f "$TARGET/Contents/MacOS/"` 放在 swap 前的 kill-0 复检之后、mkdir 锁之前，覆盖了「app 退出后 ~1.2s 窗口内手动重开」的场景；TARGET 取自运行中 bundle 的真实路径，改名/空格路径均可匹配。补充一个它没提的协同点：pgrep 命中只是 `touch helper.aborted; exit 1`，而主程序在握手失败时已经保持存活（r0 我引过的关键设计），用户重试即可，不会产生僵尸状态。我之前 r0 给的「PID 复用假阴性」担忧与此正交且方向同样安全，维持接受。
- re: P4 —— concur（B1/B3 已修，换版后退化）。P4@r0 的新 B1（回滚嵌套）与 B3（payload mv 晚于 open）现在代码均已按最小修复落地：installer.dart 失败分支先 `rm -rf "$TARGET" && mv "$BACKUP" "$TARGET"`，且 payload 先 mv 到 ~/Downloads 再 `open "$TARGET"`。P4@r0 还提出 AC20–AC24，建议 host 在 SYNTHESIS 里把 AC20（verifying/installing 零可点按钮）与 AC22（失败分支 payload 迁出先于 relaunch）标为已由现码满足、只需补测试钉住。
- re: P3 —— build（ditto 部分失败回滚）。P3@r0 的 blocker（回滚 mv 因 ENOTEMPTY 失效）与 P4 的 B1 是同一处，v1.3 的 `rm -rf "$TARGET" && mv` 修复对两席同时闭环；另注意 trap cleanup EXIT 自愈只在「BACKUP 存在且 TARGET 缺失」时触发，ditto 失败分支里 BACKUP 恢复后 trap 是 no-op，两条路径不重复回滚。

## 立场更新

- 维持 r0 的「修掉 B1 后可发布」；B1（autoDownload ∩ asset==null 静默卡死）已在 Gate 修复——update_ui.dart:62 现在是 `(!autoDl || next.asset == null)`，asset==null 时无论 autoDownload 都弹降级框，豁免条件收窄正确。
- 我 r0 的 B2（mv 失败未检查）即 P2 的 R2，现两处代码均见 `|| { touch helper.aborted; exit 1; }`，且 spec §14 澄清 P2 引用的 installer.dart:172 是旧版行号——R2 为误报，第三轮已修。我的 B2 随之关闭。
- 我 r0 的 B3（helper.aborted 残留）已闭环：installAndRelaunch 每次握手前删除 marker/abort/aborted 三件套（installer.dart:78-81），重试不再残留。
- 裁决修订为：**可发布**，前提是 release checklist 含干净机+公证产物握手实测（成功路径与 8s 超时回退路径各一次）。

## 新观点

- **v1.3 修复核验（a 项逐条过码）**：R1 pgrep 守卫见 installer.dart:190-193；R3 trap cleanup EXIT 见 :179-186，且 `OWN_LOCK` 守卫防止「安静退出的第二个 helper 误删第一个 helper 的锁」——这个细节说明修复者真的想过并发语义，质量高于平均补丁；R4 models.dart:59 `version.isPreRelease` 过滤，tag 级 rc/beta 不再误判为正式版；R5 downloader.dart 三处闭环——解压前清空 payload（:163-164）、解压失败删 payload（:184）、无 .app 删 payload（:202），外加 :150 的 archive 缺失兜底。**我额外指出 R5 的残余边界**：进程在解压中途被杀（SIGKILL）会留下「有效 archive + 半成品 payload」，但下次重下时 _extractApp 开头无条件清空 payload，此残余不可达——不构成新问题，可写进 §11 known limitation 一句话。
- **pgrep 模式的子串误伤**（新发现，低危）：`pgrep -f "$TARGET/Contents/MacOS/"` 是子串匹配，若用户把旧版拷贝到别名路径运行或 Finder「打开方式」拉起了同包副本，守卫会误判活跃而 abort 更新。方向安全（宁可不更），但会表现为「更新反复 aborted、无错误提示」——建议 failed(install) 文案在该场景给出「检测到正在运行的实例，请退出后重试」。
- **重试时旧 helper 脚本文件覆盖问题已闭环**（P4@r0 B4）：helperApp 目录名带毫秒时间戳（installer.dart:68-72），重试不再覆盖仍在执行的旧 bash 脚本；配合 helper 内 mkdir 锁（installer.dart:196-197），双 helper 并发 swap 的窗口被关闭。这是 v1.3 之外、同批代码里的正确修复，圆桌应记账。
- **AC 建议微调**：AC20/AC21/AC23 的缺口我认为现码已覆盖（actions 显式 `[]`、回滚不嵌套、mkdir 互斥），真正还缺的是「失败分支 open 旧版成功与否不影响 payload 保全」与「pgrep 误伤时 aborted 有可见文案」两条——建议并入 AC14 的断言文案而非新开 AC。

## 风险与盲点

- trap cleanup EXIT 用 `mv "$BACKUP" "$TARGET" 2>/dev/null` 静默失败：若此刻 TARGET 是半成品目录（ditto 写了一半且失败分支的 `rm -rf` 也因磁盘满失败），自愈静默失败、用户无任何信号。概率极低，但建议 cleanup 里失败时 `touch $ABORTED` 留档，便于 support 排查。
- SIGKILL/断电/休眠中途换包：无 journal，TARGET 可能滞留 `.relay-backup`——trap 管不到 SIGKILL，这是真实残余风险，维持 P4@r0 的「release checklist 写手工恢复说明」建议，不升级 blocker。
- pgrep 误伤（见新观点）的 UX 落点未定义，属文案级缺口。

## 抛给圆桌的问题

- P4：你的 AC20–AC24 里，AC20（verifying/installing 零按钮）是否已在现码的 actions switch 显式分支满足？若是，建议撤回新增 AC 改为补测试钉住——避免 spec 与实现再出现「条文-行号」漂移。
- 各席：对「干净机实测=强制 checklist 项而非代码闸门」的裁决是否还有异议？我与 P2 已同向。
