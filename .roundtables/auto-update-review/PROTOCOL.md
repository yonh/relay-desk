# 圆桌讨论协议（PROTOCOL）

本目录是一个**圆桌讨论工作区**：多个彼此独立的 agent 会话（席位）围绕 `TOPIC.md` 的议题讨论，主持人收敛出综合结论。会话之间没有共享内存，**文件系统就是唯一的上下文和状态机**。任何席位——不管用什么工具、什么模型——只要读懂本文件，就能入座。

与「多会话评审」的区别：评审是作者+评审者对一份文档把关（有 verdict），圆桌是**对等席位对一个问题交锋**（没有对错裁决），主持人的价值是把多张独立答卷综合成一张地形图——共识、分歧、各席独特洞见。

## 1. 角色

| 角色 ID | 角色 | 职责 | 只能写入 |
|---|---|---|---|
| P1…Pn | 嘉宾 (participant) | 开局盲答；各讨论轮交锋；可被指定为总结者 | `rounds/rN/speech-Pk.md`（仅自己席位）、`roster/Pk.yaml`、`SYNTHESIS.md`（仅当 synthesizer=Pk） |
| R0 | 主持人 (host，仅 orchestrated) | 派发回合、等待、验证推进、渲染页面；synthesizer=host 时写 SYNTHESIS.md | `logs/`、`SYNTHESIS.md`、`HUMAN.md`（代人类转达） |
| H | 人类 | 随时介入 | `HUMAN.md`、`STOP`、`SYNTHESIZE`、`table.yaml`、`TOPIC.md` |

席位 ID 是文件名的一部分，分配后不变。每个席位**只写自己的文件**，从不修改他人文件，从不修改历史轮次。

## 2. 两种模式

- **orchestrated（主持人调度）**：R0 是唯一的时钟。每个回合由 R0 以一次性子进程派发（`bin/dispatch.sh Pk`），子进程完成一个回合即退出。
- **peer（平行讨论）**：没有 R0。每个会话长期存活，用 `bin/wait.sh Pk` 阻塞到自己的回合，做完再等。同轮席位并行发言，互相可见对方已写入的更早轮次发言。

两种模式的文件格式、状态机、结束规则完全相同，区别只在"谁推进时钟"。

## 3. 目录结构

```
<ws>/
├── table.yaml           配置：议题类型、席位卡（via/model/thinking/persona）、轮数、总结者
├── TOPIC.md             议题：背景/讨论目标/焦点问题/上下文入口（发起时写，之后只由人类改）
├── PROTOCOL.md          本文件
├── roster/Pk.yaml       就位登记：每个席位开始前用 bin/join.sh 声明实际工具/模型
├── HUMAN.md             （可选）人类批注，最高优先级，所有席位每回合开始必读
├── STOP                 （可选）存在即停止：所有席位看到后立即退出
├── SYNTHESIZE           （可选）存在即提前收尾：不再开新轮，直接进入总结
├── LOG.md               追加式时间线（bin/log.sh）
├── rounds/r0/           开局陈述轮（盲答，互不可见）
│   └── speech-P1.md …
├── rounds/rN/           第 N 轮交锋（可见全部更早轮次发言）
│   └── speech-Pk.md
├── SYNTHESIS.md         主持人总结；存在即结束
├── index.html           bin/render.py 渲染出的聊天式页面
├── templates/           TOPIC / speech / SYNTHESIS 模板
├── bin/                 status / dispatch / prompt / join / wait / log / render.py
└── logs/                子进程输出（orchestrated 模式）
```

## 4. 状态机

`bin/status.sh` 只从文件推导状态，不依赖任何可变的状态文件。轮次 r0..r<max_rounds>，r0 是开局盲答。

| 状态 | 判定 | 下一步 |
|---|---|---|
| `stopped` | 存在 `STOP` | 所有人退出 |
| `done` | 存在 `SYNTHESIS.md` | — |
| `synthesizing` | 存在 `SYNTHESIZE`，或 r0..r<max> 全部到齐 | synthesizer → 写 `SYNTHESIS.md` |
| `opening` | r0 有席位缺 `speech-Pk.md` | 缺席的 Pk（并行）→ 盲答 `rounds/r0/speech-Pk.md` |
| `discussing` | 最小的未齐轮次为 rN（N≥1） | 缺席的 Pk（并行）→ 读 r0..r(N-1) 全部发言后写 `rounds/rN/speech-Pk.md` |

规则：
- **r0 盲答**：嘉宾禁止读 `rounds/` 下任何文件——独立判断是信息增量的来源。
- **rN 交锋**：嘉宾必须先读 `rounds/r0` 至 `rounds/r(N-1)` 全部发言；禁止读 `rounds/rN/` 下其他席位的文件（本轮仍并行独立作答）。
- 同轮席位并行发言，互不等待；想引用本轮同行观点就等下一轮。
- 人类写 `SYNTHESIZE` 文件（`touch SYNTHESIZE`）→ 不再开新轮，直接总结已有发言。

## 5. 文件格式

### 5.1 发言引用
`Pk@rN`：Pk 在第 N 轮的发言，如 `P2@r1`。交锋与总结都用这个格式引用，可追溯、零解析成本。

### 5.2 `rounds/rN/speech-Pk.md`
front matter（status 与渲染器读取）：

```
---
participant: P1
round: r0
stance: 一句话立场（可选，显示在聊天气泡的名字下方）
---
```

正文段落见 `templates/speech.md`：
- **r0**：立场 / 论点 / 风险与盲点 / 抛给圆桌的问题
- **rN≥1**：交锋 / 立场更新 / 新观点——`交锋`条目格式 `- re: Pj —— concur | dissent | build —— 理由`，至少一条。

### 5.3 `SYNTHESIS.md`
front matter：`synthesizer` / `date`。正文：结论（逐条回答 TOPIC 焦点问题，标注共识度）/ 共识 / 分歧与取舍 / 各席独特洞见 / 建议行动项 / 发言签署（每席一句话最终立场）。模板 `templates/SYNTHESIS.md`。

## 6. 发言质量要求

- 立场先行：第一段就能让人看清你主张什么；`stance:` 一句话写进 front matter。
- 论点可落地：引用 TOPIC.md「上下文入口」的真实材料，避免空泛正确的话。
- 交锋要具体：点名 `re: Pk`，说清 concur/dissent/build 的理由；复述自己的观点不算交锋。
- 只写信息增量：后续轮次不重复已说过的，被说服就写进「立场更新」。
- 戴好 persona 帽子：有视角配置的席位全程从该视角发言与质疑。
- 遵守思考等级：high 深想反例与二阶效应，low 直接给要点。

## 7. 接入握手与每回合前置动作

**入座时一次**：`bash bin/join.sh Pk --tool <工具> --model <模型> --thinking <指定等级>`。席位必须把自报的工具/模型写进 `roster/Pk.yaml`，让其他席位与人类看得见"谁入座了、用的什么模型"。同一席位已被不同工具/模型登记 ⇒ 席位冲突，停下问人类。

**每回合**：
1. 读 `table.yaml`、`TOPIC.md`；若存在 `HUMAN.md` 则读之（其内容优先于一切）；若存在 `STOP` 则退出。
2. `bash bin/status.sh` —— 只做它指出的属于你的动作；不是你的回合就等（peer）或退出（orchestrated）。
3. 完成后再跑一次 `bash bin/status.sh`，确认状态已推进；然后 `bash bin/log.sh Pk "…"`。

## 8. 终止与人工介入

结束条件：`SYNTHESIS.md` 出现；或 `STOP` 出现。

人类可随时：写 `HUMAN.md` 给所有席位下指令；`touch SYNTHESIZE` 提前收尾；`touch STOP` 叫停；编辑 `table.yaml` 调整席位与轮数（新配置下一回合生效）。

主持人可随时运行 `python3 bin/render.py` 把当前进度渲染成 `index.html`——页面既是产出物，也是运行中的监控面板。
