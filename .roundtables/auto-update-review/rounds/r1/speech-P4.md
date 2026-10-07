---
participant: P4
round: r1
stance: 维持「需修改后才能发布」，但范围已收窄——我 r0 的 4 项 blocker 全部对码核验通过、R1–R5 亦成立；剩余的是 1 项 spec 措辞必须改（R1 实为「部分缓解」而非「已修」）+ 1 项一行级代码补强 + AC20–24 补测试
---

## 交锋

- re: P2 —— **concur（裁决问题①）**：干净机 + 公证产物实测**不是代码门，但是发布流程的硬闸门**，且必须在打正式 tag 之前完成，不是发完再补。理由要补一层 P2 没说的：P2 把"最坏是 UX 降级"当作不构成硬阻塞的依据，这只覆盖了**握手超时类**失败（8s → abort → failed + 访达，落点确实安全）；但实测真正可能失败的是另一类——**Gatekeeper/公证链路拒绝运行时生成的 helper**，那一类的落点不是 UX 降级，而是"macOS 全自动安装路径整体不可用"，直接击穿 TOPIC 的唯一必须成立约束，且代码无解、只能改流程。所以实测是硬闸门的原因不是失败模式安全，而是**它的失败可能落在本轮所有席位都没审过的盲区（我们四席全部只读代码，没审公证链路）**。据此我建议实测要在 RC 产物上跑、覆盖成功路径 + 8s 超时回退 + 一条"杀 helper 中途"注入，结果记入 release checklist 后才允许 tag。
- re: P2 —— **dissent（裁决问题②，R1 处置不充分）**：pgrep 的位置放错了，它是 TOCTOU。核验代码：pgrep 在 installer.dart:191-195（`sleep 1` 之后），而**真正不可逆的破坏点**是 :208 的 `rm -rf "$BACKUP"`（删除旧 bundle），两者之间隔着 :203 `mv TARGET→BACKUP` 与 :206 整个 `ditto` 复制（0.3–1.5s，大包可达 3s）。pgrep 只能挡住"检查那一刻已在运行"的实例，**挡不住"检查之后启动"的实例**——用户在 app 退出后约 1s～4s 之间点开 Dock 图标，新进程以旧 bundle 启动 → mv 把它的 bundle 挪到 BACKUP → ditto 写新包 → :208 把**正在运行的进程的 bundle** 删掉。这正是 P2 自己定义的失败模式，且新窗口（≈ mv+ditto）不比原来的 ~1.2s 更窄。最小修复：在 :208 `rm -rf "$BACKUP"` 紧前再查一次 `pgrep`，命中则放弃本次更新并回滚（此时 BACKUP=旧包、TARGET=新包，`rm -rf "$TARGET" && mv "$BACKUP" "$TARGET"` 即还原，旧实例句柄不受影响），约 5 行。:191 的早查保留作 fail-fast。
- re: P1 —— **dissent**：据 LOG.md 22:29:20 记载，P1 判"R1 pgrep 充分"。我不同意，理由同上（检查点与破坏点之间隔着 ditto）。这一条恰好是本轮唯一的**席位间实质分歧**，请主持人在 SYNTHESIS 里显式保留为分歧项而不是归并成共识。
- re: P3 —— **build**：P3 r0 第 5 条"成功路径 `rm -rf "$BACKUP"` 在 `open "$TARGET"` 之前，open 失败则备份已删、无法回退"——我核验 installer.dart:208-209 **顺序未变，此条未修**，且 spec §13 的处置表里也没有它。它不是 blocker（ditto 已成功、新包完整，"回滚"针对的损坏场景并未发生；真正的风险是新版本本身起不来），同意 P3 自评的次级严重度，但**必须在 spec 留痕**，不能因为不在表里就等于被处理。同时指出表的反向遗漏：P1 的 B3（`helper.aborted` 残留未清）**实现已修**（installer.dart:79-81 每次 attempt 开头连删 marker/abort/aborted），表里同样没记。一正一反两条说明 §13 是**选择性记录**——终审文档的处置表必须每条发现都有归宿（含"不修 + 理由"），否则下轮读者无法从表判断"我的发现是否被处理"。

## 立场更新

- **裁决不变（需修改后可发布），但"必须修"的清单重新界定**：我 r0 提的 B1–B4 全部对码核验通过，**不再是我方的必修项**。剩余必修只有 1 项且是文档级：spec §14 把 R1 写成"已修"，实际是"部分缓解（检查点错位）"——终审产出物就是这份 spec 的可信度，措辞与代码覆盖面不符比代码里多个低危 bug 更危险，因为它会让后续审查者基于"已修"二字停止追查。代码级补强（R1 第二检查点，5 行）与 AC20–24 补测试列为强烈建议、不阻塞。
- **修正 r0 的一处自我判断**：我当初把 B4 拆成"写 abort 前复检 marker" + "mkdir 原子锁" + "唯一脚本名"三重修复，其中第一重在看到 installer.dart:125-127 的 deadline 后复检后，我认为**是必要的、且已落地**——此处我原话里"~100ms 窗口"的担心已被正确关闭，不需要再补。三重都到位，无冗余。
- **接受 autoDownload 下载失败静默的产品裁决**（spec §13 末条 / AC24 后半）：设置页状态行可见，不额外弹窗。我 r0 抛的第 3 问就此收口，不再作为待决项。

## 新观点

- **R1 与 R3 的覆盖面和 spec 记载恰好相反**（这是我要强调的元问题）：R1 在 spec §14 记为"已修"，代码实际只修了一半（错位的 TOCTOU）；R3 在 spec 里只记了"mv 与 ditto 之间被杀"这一种触发，代码实际更广——`trap cleanup EXIT`（installer.dart:172-179）的条件是"BACKUP 存在且 TARGET 缺失"，因此它**同时覆盖了显式回滚语句自身失败**的场景（:221 `rm -rf "$TARGET" && mv "$BACKUP" "$TARGET"` 若 mv 失败 → TARGET 缺失、BACKUP 还在 → EXIT trap 兜底还原）。一窄一宽，说明 §14 的处置表是按"复述修复意图"写的，不是按"代码实际覆盖面"核验过的。建议终审表格统一改为「代码实际覆盖 + 残余窗口」两列。
- **AC20–AC24 五条新增 AC 零自动化覆盖**：test/features/update_test.dart 共 17 `test(` + 1 `testWidgets(` = 18 项（与 §10 标题相符），但 grep 全文没有任何 `UpdatePromptDialog` / actions 断言，widget 测试只有 1 个且是 `UpdateSettingsSection`；controller 侧 `asset` 断言只测了 `isNotNull`（:273），AC24 的 `autoDl && asset==null` 分支无覆盖；AC21/22/23 是 shell 行为，§10 的"实机验证"只列了 AC7/AC8。结果是新增的 5 条 AC 全靠人工审查背书。**落地建议（零成本）**：`_script()` 是 `static String` 纯函数，标 `@visibleForTesting` 后可写 5 条字符串断言锁住不变量——`rm -rf "$TARGET" && mv` 必须出现在回滚分支、`pgrep` 必须出现在 `rm -rf "$BACKUP"` 之前、`mkdir "$LOCK"` 必须早于 `mv TARGET`、失败分支 `mv payload` 行号小于 `open` 行号、每 attempt 路径含时间戳。这把 AC21/22/23 从"人眼维护"变成"CI 回归防线"，比补 widget 测试更值。
- **spec §13 缺一个「未采纳 / 已知遗留」小节**（§12 有，§13/§14 没有）：直接后果就是上面 P1-B3 / P3-成功路径两条的"一漏记一漏修"。建议 §14 表格后补一节，逐条列"不修 + 理由 + 谁主张"，包括：PID 复用 <1s（我 r0 主动降权）、换包中途断电留 `.relay-backup`、成功路径备份先删（P3 主张延迟删除、本轮接受不修）。

## 风险与盲点

- **我的全部结论仍是静态逐行读 + 时序推演，没有实机注入**。R1 的 ditto 耗时是按 SSD 常规包体估的 0.3–1.5s，若实际更快，窗口更窄但不为零；这不影响"检查点错位"的定性，只影响量级。
- **pgrep 的反向风险（false positive）**：`pgrep -f "$TARGET/Contents/MacOS/"` 会匹配任何完整命令行含该路径的进程。运行中的 relay_desk 是目标；但用户在终端里 `ls`/`cat` 该路径、或开发者跑 `codesign -v` 也会命中 → 该次更新以 `helper.aborted` 失败，用户看到 failed(install) + 访达展示、可重试。方向安全但**是静默的**，排查时容易误判成"更新老是失败"。建议 aborted 分支把 pgrep 命中写进 helper.aborted 文件内容（一行），让现场可诊断。
- **trap 覆盖不到 SIGKILL / 断电**：`trap … EXIT` 不捕获 SIGKILL，`kill -9` 或掉电仍可能留下"TARGET 缺失 + BACKUP 在"且无人还原的状态。这是 spec §14 已承认的无 journal 边界，我同意不修，但 release checklist 的手工恢复说明要**同时写明 `mv /Applications/RelayDesk.app.relay-backup /Applications/RelayDesk.app`** 这条命令本身。
- **失败分支 `open "$TARGET"` 的成败完全不检查**（installer.dart:225）：回滚成功但旧版也起不来时，用户只看到访达里有 payload。属已知降级，不新提 blocker，但别把它写进"AC14 旧版重启"的验收叙述里当作已验证。

## 抛给圆桌的问题

1. 给 P1：你据以判"R1 充分"的是哪一行？若你也看到了 :191 与 :208 之间隔着 `ditto`，请说明为何认为窗口可接受；若没看到，我这条 dissent 是否足以把 R1 从"已修"改回"需补第二检查点"？
2. 给全体：我主张**文档级修正（§14 措辞 + §13/§14 补未处置留痕）是本轮唯一的发布 blocker**，代码补强一律降为建议。有谁认为"spec 措辞与代码不符"不构成阻塞、可以先发后改？请给出"下轮读者会被『已修』误导"之外的反方收益。
3. 给 P2/P3：`_script()` 加 `@visibleForTesting` + 字符串断言锁 AC21/22/23，你们认为是净收益还是过度耦合 shell 文本？若反对，替代的回归防线是什么——现在这三条是零测试的。
