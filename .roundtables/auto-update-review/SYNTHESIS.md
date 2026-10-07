---
synthesizer: R0
date: 2026-10-07
---

# 圆桌总结：自动更新 Spec 终审

## 结论（TL;DR）

1. **代码可随 v1.0.3 发布**（共识，P1/P2/P3/P4 一致）——三轮审查共发现 17 项
   真实缺陷全部修复，`buildHelperScript` 不变量已由 8 条字符串断言钉入 CI。
2. **干净机器 + 公证产物握手实测是发布流程硬闸门**（共识，r1 三席确认）——
   非代码 blocker，而是打 tag 前的强制 checklist 项。P4 的关键论据：实测可能
   击穿的不是"失败模式安全"（四席只读过代码，公证链路是共同盲区）。
3. **失败路径已收敛到已知边界**：SIGKILL/断电可留 `.relay-backup`（无 journal，
   人工恢复命令已入 checklist）；其余退出路径由 `trap cleanup EXIT` 自愈。

## 共识

- 第二轮修复（abort 文件、kill -0 复检、payload 迁移、Gate 豁免、retry→ready、
  dismiss 节流、dismiss/markChecked 时机、下载超时、对话框单例）逐条对码成立
  （P1/P2/P3/P4@r0 交叉核验）。
- 失败模式安全不等于可以跳过实测——P3@r1 指出这是自我循环论证，实测验证的
  正是失败模式是否真的安全。
- AC20–AC24 现码已满足，但必须有测试钉住防止"条文-行号"漂移（P4@r1，已落实为
  8 条 helper 脚本不变量断言）。

## 分歧与取舍

| 分歧点 | 各方立场 | 取舍 |
|---|---|---|
| R1 pgrep 单检查点是否充分 | P1/P2: 充分 / **P4: TOCTOU——检查点在 ditto 前，破坏点在 ditto 后** | P4 胜：加第二检查点（ditto 后、`rm -rf $BACKUP` 前），命中即回滚而非破坏 |
| 干净机实测定位 | P2: 不构成硬阻塞 / P3/P4: 发布流程硬闸门（非代码 blocker） | 采纳 P3/P4：强制 checklist 项，区分"代码质量裁决"与"发布流程裁决" |
| 成功路径 `rm -rf $BACKUP` 时机 | P3: open 前删备份，open 失败则无法回退 | 已修：`open "$TARGET" && rm -rf "$BACKUP"` |
| autoDownload 下载失败是否弹窗 | 产品取舍 | 不修：settings 状态行可见（P4@r1 接受收口） |

## 各席独特洞见

- **P4**：pgrep TOCTOU 错位（唯一真正的席位间实质分歧，且判胜）；spec 处置表
  选择性记录问题——"已修"措辞会让下轮读者停止追查，比低危 bug 更危险。已推动
  §14 改为「代码实际覆盖 + 残余窗口」两列式 + 补齐未处置留痕表。
- **P3**：mkdir 锁与 pgrep 守卫是两层独立防线（并发 vs 运行实例），不可互替；
  自匹配边界分析确认 pgrep 无误伤自身风险。
- **P1**：OWN_LOCK 守卫防"安静退出的第二 helper 误删第一 helper 的锁"——并发
  语义细节核验；pgrep 子串误伤场景（别名路径副本）建议 aborted 文件留诊断，
  已落实（`instance-running`/`instance-running-late` 等）。
- **P2**：r0 提出 R1–R5 五连击（R2 为误报，其余全部落实）；r1 因上游端点连续
  5 次故障未能发言，其 r0 贡献与本场问题已由三席裁决覆盖。

## 建议行动项

- [x] pgrep 双检查点（早查 fail-fast + 晚查防 ditto 窗口内重开）
- [x] `open && rm -rf $BACKUP` 延迟删备份
- [x] `helper.aborted` 写入命中原因（可诊断）
- [x] `buildHelperScript` @visibleForTesting + 8 条不变量断言
- [x] spec v1.4：处置表改两列式 + 未处置/已知遗留清单（每条有归宿）
- [ ] **发布前**：干净机 + 公证产物实测（成功路径 + 8s 超时回退 + 杀 helper
      注入），结果记 release checklist 后才允许 tag
- [ ] release checklist 写 `.relay-backup` 手工恢复命令

## 发言签署

- P1（opencode · fledge-alpha-free · high）：可发布，前提是实测入 checklist
- P2（opencode · ling-3.1-flash-free · high）：r0「有条件可发布」；r1 缺席（端点故障）
- P3（opencode · longcat-2.5-preview-free · high）：代码可发布、实测前不点发布
- P4（opencode · mimo-v2.6-flash-free · high）：文档级必修（spec 措辞+留痕）已满足，
  代码补强已落实——裁决实质转为可发布
