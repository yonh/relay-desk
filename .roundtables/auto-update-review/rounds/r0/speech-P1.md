---
participant: P1
round: r0
stance: helper 时序修复总体成立，但 autoDownload 豁免在 Gate 层制造了一个新的静默死角，需修后方可发布
---

## 立场

第二轮修复的主线（复检 kill -0、abort 拦截、payload 移 Downloads、retry 回 ready、dismiss 重置节流、超时、单例弹窗）逐条落实了，helper 脚本的中止语义现在是自洽的：**任何"主进程仍存活/出现 abort"的情况下都不会 swap**，失败方向偏安全（宁可 aborted 也不会替换运行中的 app）。但终审复查发现一条由 autoDownload 弹窗豁免引入的新矛盾，以及 helper 脚本中两处未防护的失败分支。裁决：**修掉 B1 后可随 v1.0.3 发布**，B2/B3 可作为本版 known issue 或一并修掉。

## 论点

- **时序链自洽（re: 焦点 1）**。逐行审 helper：marker→等待循环（abort 见则 exit 0；父进程死则 break）→sleep 1→复检（abort 或父进程存活→`helper.aborted`+exit 1）→swap。主程序 8s 内见 marker 才 exit(0)，否则写 abort 且**保持存活**——"保持存活"这点关键，它保证 helper 复检时 kill -0 必然成功而中止，两侧不可能同时相信对方会管事。PID 以字面量嵌入（`PARENT=$parentPid`），不依赖 PPID，第二轮 longcat 的质疑确实不成立。abort 写入后 helper 的错误方向是退出不替换，安全。
- **B1（blocker）：autoDownload=true 时 Gate 对 `available` 豁免弹窗，但 `check()` 在 `asset == null` 时不会进入 `download()`**——无 `*macos*.zip` 资产时按 spec §3.2 应弹"打开下载页面"降级框，实际永远不会弹，也不会下载，静默卡死在 available。根因是豁免逻辑写在 UI 层而非状态机里。最小修复： Gate 的豁免条件改为 `available && autoDownload && asset != null`；或更干净，把豁免上移到 controller——autoDownload 且 asset==null 时直接 state 置一个"无 mac 资产"的可见态/弹降级框。同源的二阶问题：autoDownload=true 时下载失败（failed(download)）Gate 也不弹（failed 不在 wantsPrompt 里，除非 autoDl false？看代码 failed 不弹），用户对自动下载失败完全无感知——至少 settings 状态行应可见，建议 Gate 对 failed 在 autoDownload 场景下低频提示或明确记 known limitation。
- **B2（should-fix）：helper 脚本未检查 `mv "$TARGET" "$BACKUP"` 是否成功**。若 mv 失败但目标仍存在，`ditto stagedApp "$TARGET"` 会把新包**合并进旧目录**（ditto 对已存在目录是覆盖式合并），得到新旧混杂的损坏 bundle，然后当作成功清理现场——这是个 data-corruption 路径，且无任何日志。最小修复：`mv … || { touch helper.aborted; exit 1; }`，并对 `open "$TARGET"` 的成败也做降级（open 失败时备份仍在，应打日志/保留现场而非把 backup 已删？成功路径删除 backup 前应确认 open 成功——但 open 失败用户可手动启动，严重度次之）。
- **B3（should-fix）：`helper.aborted` 文件从未被清理**。install 重试时 `installAndRelaunch` 只删 marker 和 abort，旧 `helper.aborted` 残留在 readyTag 目录里；虽无人读它，但 L1 清理清单与 spec §5 不符（spec 说删 marker+abort），留档可误导排查。一行 `rm -f` 即可。
- **状态机一致性（re: 焦点 2）**。autoDownload/retry/dismiss 三条路径已自洽：download 失败→retry→available 重下且幂等短路；install 失败→retry 回 ready 复用暂存；dismiss 清节流+回空态；markChecked 后置；verify 错误归 download stage——与 §12 声明一致。一个 UI 闪烁级瑕疵：autoDownload 时 check() 里 `available` 是同步瞬态，settings 状态行可能闪一下"有新版本"，无功能影响。
- **AC 覆盖（re: 焦点 3）**。AC1–AC19 已覆盖第二轮全部发现。缺口：① B1 场景（autoDownload ∩ asset==null）无 AC；② `mv` 失败不混杂（B2）无 AC——建议补「helper 中途失败时原 `.app` 始终可完整启动」作为 AC20；③ 无"open 重启后新版实际运行版本"的验证点（helper 的 open 成功不等于新版起来，spec 承认这是已知未验，可接受但建议在 release checklist 固化干净机器实测一步）。

## 风险与盲点

- PID 复用窗口：helper 等待期 ≤120s，主进程若被 kill 且 PID 被系统迅速复用，helper 会因 kill -0 误判存活而 aborted——方向安全，但用户得重试一次。接受。
- `helper.started` 由 helper 首行 touch，但若用户机器慢到极端，8s 超时→失败→abort，helper 后续启动会看到 abort 退出，一致；但旧 marker 文件在失败路径没被主程序清理（只有 helper 成功路径和下次 install 调用清），留档风险低。
- helper 脚本里 `DEST="$HOME/Downloads/RelayDesk-$tag"` 未 quote tag（GitHub tag 含空格/特殊字符理论可能），`_q()` 只用在固定路径上；tag 进脚本处（`mv payloadDir "$DEST"`）是拼进双引号字符串，可接受但建议统一 `_q`。
- 下载 302 → CDN 后 contentLength 可能为 -1，就关 indeterminate，已处理。
- 沙盒下 helper 写 `.app` 原位置的权限：若 app 装在 `/Applications` 且用户非管理员拖入，ditto 会失败→回滚路径已覆盖（AC14）。OK。

## 抛给圆桌的问题

- 各位是否同意 B1 是 blocker（autoDownload 下资产缺失/下载失败零感知）？认同修复位置应在 Gate 豁免条件还是 controller？
- B2 的 ditto 合并损坏路径：你们是否在实测中复现过 mv 失败分支，是否同意加 `mv` 失败即 abort？
- 「自动下载失败静默化」是否该算新增 issue 进 §11，还是 v1 必修？
