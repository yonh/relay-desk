---
title: "自动更新 Spec 终审（第二轮修复后）"
slug: auto-update-review
created: 2026-10-07
---

# 自动更新 Spec 终审（第二轮修复后）

## 背景

Relay Desk（Flutter macOS 桌面应用，App Sandbox 启用）已实现基于 GitHub
Releases 的应用内自动更新。此前已做过两轮评审：第一轮定方案（保留沙盒 +
运行时生成 helper .app 经 `open` 逃逸执行替换），第二轮互审发现约 15 项
缺陷（含"helper 等满 120s 无条件替换运行中 app""swap 失败 payload 被清扫
误删"等高危项），已全部修复并回写 spec v1.1。

本次圆桌是**终审**：确认修复是否成立、是否引入新问题、是否可以收口发布。

## 讨论目标

1. 验证第二轮修复的正确性（重点：helper 脚本时序与中止语义）
2. 找出仍存在的 blocker 级缺陷（如果有，按严重度给出）
3. 给出"可发布 / 需修改后才能发布"的明确裁决

## 约束

- 不引入 Sparkle 等第三方更新框架；不改动 app-sandbox entitlement
- macOS 全自动为唯一必须成立的安装路径；Win/Linux 降级可接受
- 已写代码即现状，评审对象是 spec + 实现，不是重新设计

## 上下文入口

- `design/auto-update-spec.md` —— 待终审的 spec v1.1（必读）
- `design/auto-update-discussion.md` —— 第一轮评审记录
- `lib/platform/update/installer.dart` —— helper 生成与替换脚本（重点审）
- `lib/platform/update/downloader.dart` —— 下载/校验/解压
- `lib/features/update/update_controller.dart` —— 状态机
- `lib/features/update/update_ui.dart` —— 弹窗与设置区块
- `lib/core/update/` —— 模型与持久化

## 焦点问题

1. §5 安装握手在修复后是否还有"替换运行中 app / 丢失暂存 / 无法回滚"
   的时序漏洞？（逐行审 helper 脚本）
2. 状态机（§4）与实现是否一致？autoDownload、retry、dismiss 三条修复
   路径是否有遗漏或新矛盾？
3. AC1–AC19 是否覆盖第二轮发现的全部风险？还缺哪条验收？
4. 给出裁决：当前实现可否随 v1.0.3 发布？若否，列出必须修的项。

## 产出要求

结论逐条对应焦点问题；分歧标注席位与理由，不粉饰成共识；
blocker 级问题必须给出最小修复建议。中文，控制在两屏内。
