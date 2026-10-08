---
participant: P3
round: r0
stance: 第二轮修复整体成立，但 ditto 部分失败后回滚路径有 blocker 级缺陷，需修复后方可随 v1.0.3 发布。
---

## 立场

第二轮互审的 15 项修复在 spec v1.1 与实现中基本落实，helper 脚本的时序与中止语义（循环结束复检 `kill -0` + abort 文件双重检查）逻辑闭环，主程序 8s 超时写 abort 的修复也成立。但逐行审 helper 脚本后发现一个 **blocker 级缺陷**：ditto 部分失败时回滚 `mv "$BACKUP" "$TARGET"` 会因目标目录非空而失败，导致用户得到损坏 app 且旧版无法恢复。此项修复后方可发布。

## 论点

- **helper 时序修复成立**（installer.dart:157-168）：等待循环 600×0.2s=120s，每轮检查 `$ABORT` 与 `kill -0`；循环结束后 `sleep 1` 再复检，父进程存活或 abort 存在 → `touch helper.aborted` + exit 1。复检逻辑正确，覆盖了"等满 120s 无条件替换"的原始缺陷。
- **主程序超时写 abort 修复成立**（installer.dart:118-123）：8s marker 超时后写 `helper.abort`，迟到 helper 在等待循环首次检查即发现 abort 并 exit 0，不会 swap 运行中 app。竞争窗口分析：helper 在超时前 touch marker → 主程序检测到 → exit(0) → helper 正常 swap；helper 在超时后启动 → 检查 abort → 放弃。两条路径均安全。
- **retry → ready 修复成立**（update_controller.dart:324-326）：install 失败直接置 `ready`，`download()` 幂等短路（readyTag == tag 且暂存完好 → 直接置 ready），不重复下载。
- **Blocker：ditto 部分失败后回滚失败**（installer.dart:179）：`mv "$BACKUP" "$TARGET"` 在 ditto 复制到一半失败时会失败——ditto 失败时 `$TARGET` 已存在且为非空部分目录，`mv`（rename）到非空目录返回 `ENOTEMPTY`。此时旧版无法回滚，用户得到损坏 app 且无法启动。触发条件：磁盘满、权限问题、I/O 错误。修复：回滚前先 `rm -rf "$TARGET"` 再 `mv "$BACKUP" "$TARGET"`。
- **成功路径备份删除时机**（installer.dart:175）：`rm -rf "$BACKUP"` 在 `open "$TARGET"` 之前执行。若 `open` 失败（新 app 无法启动），备份已删，用户无法回滚。建议延迟删除或保留至下次启动。

## 风险与盲点

- **PID reuse**：主进程 `exit(0)` 后 PID 被系统回收复用，helper 复检 `kill -0 $PARENT` 误判父进程存活 → 放弃 swap（假阴性，安全但更新失败）。概率极低，可记录为已知边界。
- **autoDownload + 无资产时 Gate 不弹窗**（update_ui.dart:57-59）：`available` 且 `autoDl=true` 时不弹，用户无法从对话框点"打开下载页面"。可从设置页"查看"进入，属可接受降级，但 spec AC4 未覆盖此边界。
- **`mv "$TARGET" "$BACKUP" 2>/dev/null` 失败时静默继续**（installer.dart:172）：若 mv 失败（权限），`$TARGET` 仍存在，后续 `ditto` 会覆盖运行中 app。应改为 mv 失败时 exit 1。
- **已知未验**（spec §8）：干净机器 + 正式公证产物上的 helper 握手链路需实测复核，开发机实测不能代表所有环境。

## 抛给圆桌的问题

- ditto 部分失败场景下，是否有比"先 `rm -rf "$TARGET"` 再 `mv "$BACKUP" "$TARGET"`"更稳健的回滚策略（如先 rename TARGET 到临时名再删）？
- 成功路径是否应延迟删除 `.relay-backup`（如保留到下次启动 L2 清扫）以覆盖 `open` 失败场景？
