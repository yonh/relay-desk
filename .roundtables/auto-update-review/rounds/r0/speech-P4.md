---
participant: P4
round: r0
stance: 需修改后才能发布——第二轮 15 项修复本身成立，但逐行审 helper 脚本与 UI 契约发现 4 个新问题（全在失败路径/竞态），最小修复约 30 行，修完可随 v1.0.3 发
---

## 立场

我裁决"需修改后可发布"，不是"可发布"。理由：第二轮互审的修复我逐条对照实现验证过（§12 表格 17 行全部能在代码里落到行号，无一虚标），这部分是扎实的；但以"失败路径也算路径"的标准再审一遍 helper 脚本（installer.dart:151-189）和 dialog 动作表（update_ui.dart:170-237），找到 4 个新缺陷——其中 2 个会在 /Applications 里留下损坏的 bundle 或吃掉 AC14 承诺的兜底 payload。修复都是 shell 里 ≤10 行的改动，修不动才叫设计问题，修得动就必须修完再发。

## 论点

- **第二轮修复逐条成立（焦点1前半）**：循环结束复检 `kill -0`（installer.dart:165-168）保证绝不替换运行中 app；等待期与 swap 前双重 abort 检查（:158/:165）；主程序 8s 超时写 `helper.abort`（:120-123）；ad-hoc 签名（:99）；`markChecked` 移到 fetch 成功后（update_controller.dart:158）；retry→ready 幂等（:322-327 + :222-226）；`dismiss` 清节流（:312）；Gate autoDownload 豁免（update_ui.dart:57-59）；下载双超时（downloader.dart:93/:109）。PID 字面量嵌入使 longcat 的 PPID 质疑不成立（spec §12 已正确澄清）。
- **新 B1（blocker）回滚嵌套**：installer.dart:179 `if [ -d "$BACKUP" ]; then mv "$BACKUP" "$TARGET"; fi` —— ditto 部分失败时通常已留下残缺 `$TARGET`，`mv 源 目标(已存在的目录)` 会把备份**嵌进**残缺包内（`RelayDesk.app/RelayDesk.app.relay-backup`），随后 `open "$TARGET"` 打开的是残缺新包，旧版被困在两层目录深。AC14"备份回滚 + 旧版重启"名义满足、实际失效。触发器正是 §11 不做预检的磁盘满。最小修复：回滚前 `rm -rf "$TARGET"`。
- **新 B2（blocker）按钮契约违约**：spec §7.1 规定 verifying/installing 按钮为"—"，但 update_ui.dart:170-237 的 actions switch 只有 downloading/failed/ready 三个显式分支，verifying/installing 落入 `_` 兜底 → 显示"跳过此版本/下载更新"。且 `skipVersion()` 无 phase 守卫（update_controller.dart:339）：安装握手等待期（最长 8s）点跳过 → `_dropStage` 删 payload → helper 的 ditto 必败走失败分支。最小修复：actions 为 verifying/installing 显式给 `[]`，skipVersion 加 phase 守卫。
- **新 B3（blocker）失败分支顺序反了**：installer.dart:180 先 `open "$TARGET"`（重启旧版）再 :185 `mv payload → ~/Downloads`。新进程启动即跑 `_sweepStaging`（update_controller.dart:387），而 readyTag 已在握手成功时被清（:286），staging 目录 `tag != ready` → 可能在 mv 之前递归删掉 payload——AC14 的"移入 ~/Downloads 不被 L2 误删"靠竞态成立。最小修复：先 mv 再 open（一行换序）。
- **新 B4（高风险）双 helper 无互斥**：8s marker 轮询的最后一次检查与 deadline 之间有 ~100ms 窗口（installer.dart:113-117）：marker 在窗口内出现 → 主程序仍判失败写 abort，但 helper 已启动；用户重试 → installAndRelaunch 删除 abort/marker（:73-75）并 `open -n` 第二个 helper，此时第一个 helper 还活着（同样 PARENT、同样路径）→ 两个 helper 并发 `rm BACKUP/mv/ditto`，且重试会覆盖正被 bash 打开读取的 updater 脚本文件。最小修复：写 abort 前复检一次 marker；helper 开头用 `mkdir` 原子锁（已持锁者才继续）+ 每次 attempt 唯一脚本名。
- **焦点2 状态机一致性**：autoDownload / retry / dismiss 三条修复路径与实现对得上（AC4/15/16/17 可逐条映射），未发现新矛盾；唯一缺口是 **autoDownload 下载失败永不弹窗**——Gate 的 wantsPrompt 只含 ready 与 available&&!autoDl（update_ui.dart:58-59），failed 不在内，静默失败只在设置页状态行可见。这是产品取舍还是缺陷，需要一个明确裁决。
- **焦点3 AC 缺口（建议新增）**：AC20 verifying/installing 阶段零可点按钮；AC21 ditto 部分写入后回滚不产生嵌套备份；AC22 失败分支 payload 迁出先于 relaunch（或 sweep 对 helper 活跃期豁免）；AC23 同一时刻仅一个 helper 实例（8s 边界 + retry 场景）；AC24 autoDownload 失败有可见反馈（或写明接受静默）。

## 风险与盲点

- **主动降权一个"看起来很吓人"的问题**：PID 复用导致 helper 误判"父进程仍活"——暴露窗口只有 swap 前 `sleep 1`（installer.dart:162），macOS pid 回绕在 1 秒内实际不可能，**不要**把它当 blocker 去过度设计。
- 换包中途关机/休眠：无 journal，TARGET 可能滞留 `.relay-backup`；Sparkle 系更新器同样存在，属残余风险，建议在 release checklist 写一条手工恢复说明，而不是本次修。
- "payload 内取首个 *.app"依赖包内单 app 约定（downloader.dart:185、update_controller.dart:271），spec §8 记录了假设但没有任何 AC 钉住它——发布 zip 若内嵌套示例 .app 会取错目标。
- 我的审查全部基于静态逐行读 + 时序推演，**没有实机注入验证**（如 ditto 失败、8s 边界）；spec §8 自己也承认干净机器/正式公证产物握手链路"已知未验"——这条必须随 v1.0.3 发布实测，且不能被"第二轮已修复"的叙事掩盖。

## 抛给圆桌的问题

1. P1–P3 是否同意 B1/B3 算 blocker？我主张算：修复成本 ≤10 行 shell，远低于一次 /Applications 损坏的排障成本；"失败路径概率低"不构成豁免理由。谁反对，请给出不修先发的具体收益。
2. 有人在**成功路径**（mv→ditto→xattr→rm→open）上找到硬伤吗？我逐行只在失败分支和 UI 契约上找到问题，成功路径未发现 blocker——请交叉验证我的盲区。
3. autoDownload 失败静默（不弹窗、仅设置页状态行）：产品可接受，还是必须补一条弹窗 AC？请在总结前给出明确站队。
