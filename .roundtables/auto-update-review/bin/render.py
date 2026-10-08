#!/usr/bin/env python3
"""渲染圆桌讨论工作区为聊天式 index.html（自包含、无外部依赖）。

用法：
  render.py [--ws <dir>] [--out <file>] [--open]
  render.py --demo [--out <file>] [--open]     # 不依赖工作区，生成示例页预览设计
"""
import datetime
import html
import os
import re
import subprocess
import sys

KIND_LABEL = {"requirements": "需求讨论", "implementation": "实现探索", "free": "自由讨论"}
STATE_LABEL = {
    "opening": "开局陈述中", "discussing": "圆桌交锋中", "synthesizing": "等待总结",
    "done": "已总结", "stopped": "已停止",
}
PALETTE = ["#6ea8fe", "#b18cff", "#4ec9b0", "#e0a55e", "#e06c9f", "#7ed083", "#5ec9e0", "#d0c06a"]
THINK_STYLE = {"high": ("◆ high", "#b18cff"), "medium": ("◐ medium", "#e0a55e"),
               "low": ("○ low", "#8b98ad"), "minimal": ("○ min", "#8b98ad"), "max": ("◆ max", "#f47067")}
esc = html.escape


def flat_yaml(path):
    """读平铺的 key: value 文件（table.yaml / roster/*.yaml）。"""
    out = {}
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.rstrip("\n")
                if not line.strip() or line.lstrip().startswith("#") or line.strip() == "---":
                    continue
                m = re.match(r"^([A-Za-z0-9_]+):\s*(.*)$", line)
                if not m:
                    continue
                v = re.sub(r"\s+#.*$", "", m.group(2)).strip()
                if len(v) >= 2 and v[0] == '"' and v[-1] == '"':
                    v = v[1:-1]
                out[m.group(1)] = v
    except OSError:
        pass
    return out


def split_fm(text):
    """拆 front matter：(dict, body)。"""
    if not text.startswith("---"):
        return {}, text
    end = text.find("\n---", 3)
    if end < 0:
        return {}, text
    fm = {}
    for line in text[3:end].strip().splitlines():
        m = re.match(r"^([A-Za-z0-9_]+):\s*(.*)$", line)
        if m:
            fm[m.group(1)] = m.group(2).strip().strip('"')
    return fm, text[end + 4:].lstrip("\n")


def md(text):
    """小型 markdown → html：fenced code / 标题 / 列表 / 引用 / hr / 表格 / 粗斜体 / 行内码 / 链接。"""
    lines = text.split("\n")
    out, i = [], 0
    in_code = False
    while i < len(lines):
        ln = lines[i]
        if ln.strip().startswith("```"):
            if in_code:
                out.append("</code></pre>")
                in_code = False
            else:
                out.append("<pre><code>")
                in_code = True
            i += 1
            continue
        if in_code:
            out.append(esc(ln) + "\n")
            i += 1
            continue
        s = ln.strip()
        if not s:
            i += 1
            continue
        if re.match(r"^-{3,}$|^\*{3,}$", s):
            out.append("<hr>")
        elif m := re.match(r"^(#{1,4})\s+(.*)$", s):
            lv = len(m.group(1))
            out.append(f"<h{lv}>{inline(m.group(2))}</h{lv}>")
        elif s.startswith("<!--"):
            pass  # 模板注释不渲染
        elif re.match(r"^\|.*\|$", s):
            rows = []
            while i < len(lines) and re.match(r"^\|.*\|$", lines[i].strip()):
                rows.append([c.strip() for c in lines[i].strip().strip("|").split("|")])
                i += 1
            rows = [r for r in rows if not all(re.match(r"^:?-{2,}:?$", c) for c in r)]
            if rows:
                h = "<table><tr>" + "".join(f"<th>{inline(c)}</th>" for c in rows[0]) + "</tr>"
                for r in rows[1:]:
                    h += "<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>"
                out.append(h + "</table>")
            continue
        elif re.match(r"^[-*]\s+", s) or re.match(r"^\d+\.\s+", s) or re.match(r"^-\s+\[[ xX]\]\s+", s):
            tag = "ol" if re.match(r"^\d+\.", s) else "ul"
            out.append(f"<{tag}>")
            while i < len(lines) and re.match(r"^\s*([-*]\s+|\d+\.\s+)", lines[i]):
                item = re.sub(r"^\s*([-*]|\d+\.)\s+", "", lines[i])
                item = re.sub(r"^\[([ xX])\]\s+", lambda m: "☑ " if m.group(1).lower() == "x" else "☐ ", item)
                i += 1
                # 缩进的续行属于当前列表项（非列表 marker），并入本 <li>，
                # 否则续行会断开列表变成孤立 <p>，后续项重新开 <ol> 导致编号回退到 1
                while i < len(lines) and re.match(r"^\s+\S", lines[i]) \
                        and not re.match(r"^\s*([-*]\s+|\d+\.\s+)", lines[i]):
                    item += " " + lines[i].strip()
                    i += 1
                out.append(f"<li>{inline(item)}</li>")
            out.append(f"</{tag}>")
            continue
        elif s.startswith(">"):
            buf = []
            while i < len(lines) and lines[i].strip().startswith(">"):
                buf.append(re.sub(r"^\s*>\s?", "", lines[i]))
                i += 1
            out.append(f"<blockquote>{inline(' '.join(buf))}</blockquote>")
            continue
        else:
            buf = [s]
            while i + 1 < len(lines) and lines[i + 1].strip() and not re.match(
                    r"^\s*(#{1,4}\s|[-*]\s|\d+\.\s|>|```|\||-{3,}$)", lines[i + 1]):
                buf.append(lines[i + 1].strip())
                i += 1
            out.append("<p>" + inline(" ".join(buf)) + "</p>")
        i += 1
    if in_code:
        out.append("</code></pre>")
    return "\n".join(out)


def inline(t):
    t = esc(t)
    t = re.sub(r"`([^`]+)`", r"<code>\1</code>", t)
    t = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", t)
    t = re.sub(r"(?<!\w)\*([^*\n]+)\*(?!\w)", r"<em>\1</em>", t)
    t = re.sub(r"\[([^\]]+)\]\((https?://[^)\s]+)\)", r'<a href="\2" target="_blank" rel="noopener">\1</a>', t)
    return t


def load_workspace(ws):
    cfg = flat_yaml(os.path.join(ws, "table.yaml"))
    participants = cfg.get("participants", "").split()
    seats = []
    for idx, p in enumerate(participants):
        roster = flat_yaml(os.path.join(ws, "roster", f"{p}.yaml"))
        seats.append({
            "id": p,
            "via": cfg.get(f"via_{p}", "manual"),
            "model": roster.get("model") or cfg.get(f"model_{p}", "") or "default",
            "thinking": roster.get("thinking") or cfg.get(f"thinking_{p}", ""),
            "persona": cfg.get(f"persona_{p}", ""),
            "joined": bool(roster),
            "color": PALETTE[idx % len(PALETTE)],
        })

    events = []  # (round_no:int, kind, payload)
    topic = ""
    tpath = os.path.join(ws, "TOPIC.md")
    if os.path.exists(tpath):
        with open(tpath, encoding="utf-8") as f:
            tfm, tbody = split_fm(f.read())
        topic = tbody.strip()
        title = tfm.get("title") or cfg.get("title", "")
    else:
        title = cfg.get("title", "")
    mtime = lambda p: datetime.datetime.fromtimestamp(os.path.getmtime(p))

    human = None
    hpath = os.path.join(ws, "HUMAN.md")
    if os.path.exists(hpath):
        with open(hpath, encoding="utf-8") as f:
            human = (f.read().strip(), mtime(hpath))

    max_rounds = int(cfg.get("max_rounds") or 2)
    speeches = []  # (round, seat_id, stance, body, mtime)
    rdir = os.path.join(ws, "rounds")
    if os.path.isdir(rdir):
        for rd in sorted(os.listdir(rdir)):
            if not re.match(r"^r\d+$", rd):
                continue
            for fn in sorted(os.listdir(os.path.join(rdir, rd))):
                m = re.match(r"^speech-(P\d+)\.md$", fn)
                if not m:
                    continue
                fp = os.path.join(rdir, rd, fn)
                with open(fp, encoding="utf-8") as f:
                    fm, body = split_fm(f.read())
                speeches.append({"round": int(rd[1:]), "seat": m.group(1),
                                 "stance": fm.get("stance", ""), "body": body.strip(), "ts": mtime(fp)})

    synthesis = None
    spath = os.path.join(ws, "SYNTHESIS.md")
    if os.path.exists(spath):
        with open(spath, encoding="utf-8") as f:
            sfm, sbody = split_fm(f.read())
        synthesis = {"body": sbody.strip(), "ts": mtime(spath), "by": sfm.get("synthesizer", "R0")}

    # 状态推导（与 status.sh 一致）
    if os.path.exists(os.path.join(ws, "STOP")):
        state, cur_round, pending = "stopped", -1, []
    elif synthesis:
        state, cur_round, pending = "done", -1, []
    elif os.path.exists(os.path.join(ws, "SYNTHESIZE")):
        state, cur_round, pending = "synthesizing", -1, []
    else:
        state, cur_round, pending = "synthesizing", -1, []
        have = {(s["round"], s["seat"]) for s in speeches}
        for i in range(max_rounds + 1):
            miss = [p for p in participants if (i, p) not in have]
            if miss:
                cur_round, pending = i, miss
                state = "opening" if i == 0 else "discussing"
                break

    return {"cfg": cfg, "title": title, "kind": cfg.get("kind", "free"),
            "mode": cfg.get("mode", "orchestrated"), "seats": seats,
            "max_rounds": max_rounds, "synthesizer": cfg.get("synthesizer", "host"),
            "state": state, "cur_round": cur_round, "pending": pending,
            "topic": topic, "human": human, "speeches": speeches,
            "synthesis": synthesis}


def seat_chip(s):
    think = THINK_STYLE.get(s["thinking"], (s["thinking"], "#8b98ad")) if s["thinking"] else None
    chips = f'<span class="chip tool">{esc(s["via"])}</span><span class="chip model">{esc(s["model"])}</span>'
    if think:
        chips += f'<span class="chip think" style="color:{think[1]};border-color:{think[1]}55">{esc(think[0])}</span>'
    if s["persona"]:
        chips += f'<span class="chip persona">{esc(s["persona"])}</span>'
    dot = "●" if s["joined"] else "○"
    return (f'<button class="seat" data-seat="{s["id"]}" style="--c:{s["color"]}" '
            f'title="点击只看 {s["id"]} 的发言；再点一次取消">'
            f'<span class="seat-av">{s["id"]}</span>'
            f'<span class="seat-meta"><b>{s["id"]}</b><i class="join" data-on="{str(s["joined"]).lower()}">{dot}</i></span>'
            f'<span class="seat-chips">{chips}</span></button>')


def render(data, out_path):
    cfg = data["cfg"]
    seats = {s["id"]: s for s in data["seats"]}
    seat_order = [s["id"] for s in data["seats"]]
    state = data["state"]
    live = state not in ("done", "stopped")

    parts = []
    # 议题卡
    if data["topic"]:
        parts.append(f'<div class="card topic"><div class="card-tag">◈ 议题 · TOPIC</div>'
                     f'<div class="md">{md(data["topic"])}</div></div>')
    # 人类指令卡
    if data["human"]:
        parts.append(f'<div class="card human"><div class="card-tag">◉ 人类 · HUMAN.md（最高优先级）</div>'
                     f'<div class="md">{md(data["human"][0])}</div>'
                     f'<div class="ts">{data["human"][1]:%m-%d %H:%M}</div></div>')

    # 按轮渲染
    by_round = {}
    for s in data["speeches"]:
        by_round.setdefault(s["round"], []).append(s)
    rounds_to_show = sorted(set(by_round) | ({data["cur_round"]} if data["cur_round"] >= 0 else set()))
    for r in rounds_to_show:
        label = "开局陈述 · 盲答" if r == 0 else f"第 {r} 轮 · 圆桌交锋"
        parts.append(f'<div class="round-div"><span>{label}</span></div>')
        rows = sorted(by_round.get(r, []), key=lambda s: (s["ts"], s["seat"]))
        for s in rows:
            seat = seats.get(s["seat"], {"id": s["seat"], "via": "?", "model": "?", "thinking": "",
                                         "persona": "", "color": "#8b98ad"})
            think = THINK_STYLE.get(seat["thinking"], (seat["thinking"], "#8b98ad")) if seat["thinking"] else None
            chips = f'<span class="chip tool">{esc(seat["via"])}</span><span class="chip model">{esc(seat["model"])}</span>'
            if think:
                chips += f'<span class="chip think" style="color:{think[1]};border-color:{think[1]}55">{esc(think[0])}</span>'
            if seat["persona"]:
                chips += f'<span class="chip persona">{esc(seat["persona"])}</span>'
            stance = f'<div class="stance">{esc(s["stance"])}</div>' if s["stance"] else ""
            parts.append(
                f'<div class="msg from-{s["seat"]}" data-seat="{s["seat"]}">'
                f'<div class="av" style="--c:{seat["color"]}">{s["seat"]}</div>'
                f'<div class="bubble"><div class="head">'
                f'<b style="color:{seat["color"]}">{s["seat"]}</b>{chips}'
                f'<span class="ts">{s["ts"]:%m-%d %H:%M}</span></div>'
                f'{stance}<div class="md">{md(s["body"])}</div></div></div>')
        # 本轮未发言席位占位
        if r == data["cur_round"]:
            for p in data["pending"]:
                seat = seats.get(p, {"color": "#8b98ad", "via": "?", "model": "?", "thinking": "", "persona": ""})
                parts.append(
                    f'<div class="msg ghost" data-seat="{p}">'
                    f'<div class="av" style="--c:{seat["color"]}">{p}</div>'
                    f'<div class="bubble pending"><i>思考中 · 尚未发言</i></div></div>')

    if state == "synthesizing":
        who = "主持人" if data["synthesizer"] == "host" else data["synthesizer"]
        parts.append(f'<div class="round-div"><span>总结</span></div>'
                     f'<div class="card synth pending"><div class="card-tag">◎ {esc(who)} 正在综合全部发言…</div></div>')
    if data["synthesis"]:
        sy = data["synthesis"]
        who = "主持人 R0" if sy["by"] in ("R0", "host") else f'{sy["by"]}'
        parts.append(f'<div class="round-div"><span>主持人总结</span></div>'
                     f'<div class="card synth"><div class="card-tag">◎ {esc(who)} · SYNTHESIS</div>'
                     f'<div class="md">{md(sy["body"])}</div>'
                     f'<div class="ts">{sy["ts"]:%m-%d %H:%M}</div></div>')
    if state == "stopped":
        parts.append('<div class="round-div"><span>已停止（STOP）</span></div>')

    refresh = '<meta http-equiv="refresh" content="30">' if live else ""
    seats_html = "".join(seat_chip(s) for s in data["seats"])
    status_cls = {"done": "ok", "synthesizing": "warn", "stopped": "mut"}.get(state, "live")
    state_txt = STATE_LABEL.get(state, state)
    kind_txt = KIND_LABEL.get(data["kind"], data["kind"])
    now = datetime.datetime.now()

    return TEMPLATE.format(
        title=esc(data["title"] or "圆桌讨论"), refresh=refresh,
        kind=esc(kind_txt), mode=esc(data["mode"]), state_cls=status_cls, state=esc(state_txt),
        rounds=data["max_rounds"], synth=esc(data["synthesizer"]),
        n_seats=len(data["seats"]), seats=seats_html,
        chat="\n".join(parts), now=f"{now:%Y-%m-%d %H:%M}",
        legend="开局盲答 → 多轮交锋 → 总结",
        wsname=esc(cfg.get("slug", "")))


def demo_data():
    seats = [
        {"id": "P1", "via": "codex", "model": "gpt-5.2-codex", "thinking": "high",
         "persona": "架构务实派", "joined": True, "color": PALETTE[0]},
        {"id": "P2", "via": "claude", "model": "claude-opus-4.6", "thinking": "high",
         "persona": "风险质疑者", "joined": True, "color": PALETTE[1]},
        {"id": "P3", "via": "opencode", "model": "openai/gpt-5", "thinking": "medium",
         "persona": "数据一致性", "joined": True, "color": PALETTE[2]},
        {"id": "P4", "via": "devin", "model": "swe-2-max", "thinking": "medium",
         "persona": "落地执行", "joined": False, "color": PALETTE[3]},
    ]
    t0 = datetime.datetime.now() - datetime.timedelta(minutes=42)
    speeches = [
        {"round": 0, "seat": "P1", "stance": "用文件系统做状态机，不要引入数据库",
         "body": "## 立场\n圆桌讨论应该复用「文件即状态」的模式：每个席位只写自己的发言文件，主持人只负责派发与总结。\n\n## 论点\n- `rounds/rN/speech-Pk.md` 天然支持并行写入与增量可见，不需要消息队列\n- 盲答开局能保住各模型的独立判断，这正是 fusion 面板的价值来源\n- 渲染层（HTML）与协议层（markdown 文件）解耦，任何工具都能接入\n\n## 风险与盲点\n- 无锁并发下两个席位同时写同名文件会互相覆盖——靠席位 ID 入文件名规避\n\n## 抛给圆桌的问题\n- 讨论轮要不要允许引用对方原文？引用格式怎么定？", "ts": t0},
        {"round": 0, "seat": "P2", "stance": "先定义收敛标准，否则讨论会无限发散",
         "body": "## 立场\n支持这个方向，但「讨论什么时候结束」必须先于「怎么讨论」定下来。\n\n## 论点\n- 没有收敛条件的圆桌容易变成观点陈列：建议 `max_rounds` + `SYNTHESIZE` 文件双保险\n- 总结的署名与签署机制要写进协议，否则分歧会被粉饰成共识\n- 每个席位必须有 `verdict` 等价物——哪怕是「一句话最终立场」\n\n## 风险与盲点\n- 高 thinking 等级的席位延迟会拖慢整轮：需要考虑超时与降级策略\n\n## 抛给圆桌的问题\n- 人类中途插话的优先级和格式是什么？", "ts": t0 + datetime.timedelta(minutes=3)},
        {"round": 0, "seat": "P3", "stance": "席位配置要声明式，模型和 thinking 等级写进 table.yaml",
         "body": "## 立场\n席位 = tool + model + thinking + persona，必须声明式可复查。\n\n## 论点\n- `via_Pk` / `model_Pk` / `thinking_Pk` 平铺在 table.yaml，一行一席一眼可查\n- join.sh 握手登记实际运行的工具与模型，和配置不一致时给出席位冲突\n- opencode 没有默认模型，必须强制 `model_Pk: provider/model`\n\n## 风险与盲点\n- 不同 CLI 的 thinking 参数语义不对齐：codex 有 `-c model_reasoning_effort`，opencode 是 `--variant`，claude 走环境变量——映射层要兜底到提示词\n\n## 抛给圆桌的问题\n- manual 席位（人类自己粘提示词）算不算正式席位？", "ts": t0 + datetime.timedelta(minutes=5)},
        {"round": 0, "seat": "P4", "stance": "页面即监控：每轮结束就重渲染 index.html",
         "body": "## 立场\n聊天式 HTML 不只是产出物，也是运行中的监控面板。\n\n## 论点\n- 每派发完一轮就 `render.py`，用户随时刷新看进度\n- 未发言席位渲染成「思考中」占位气泡，状态一目了然\n- meta refresh 让进行中页面自动刷新，结束后移除\n\n## 风险与盲点\n- 渲染脚本不能依赖外部资源，必须自包含单文件\n\n## 抛给圆桌的问题\n- 页面要不要支持按席位过滤发言？", "ts": t0 + datetime.timedelta(minutes=7)},
        {"round": 1, "seat": "P1", "stance": "接受收敛双保险，引用格式定为 Pk@rN",
         "body": "## 交锋\n- re: P2 —— concur：`max_rounds` + `SYNTHESIZE` 双保险合理，人类随时能收尾\n- re: P3 —— build：thinking 映射兜底到提示词是对的，CLI 参数只是加速器\n- re: P4 —— concur：过滤功能保留，实现成本极低\n\n## 立场更新\n同意在 SYNTHESIS.md 里加「发言签署」节——每席一句话最终立场。\n\n## 新观点\n- 引用格式统一为 `Pk@rN`（如 `P2@r1`），可追溯且零解析成本", "ts": t0 + datetime.timedelta(minutes=15)},
        {"round": 1, "seat": "P2", "stance": "维持判断；补充 human 指令的优先级",
         "body": "## 交锋\n- re: P1 —— concur：`Pk@rN` 引用格式够用\n- re: P3 —— dissent：manual 席位不该是二等公民，提示词打印出来让人粘贴即可，协议上完全等价\n\n## 立场更新\n维持 r0 立场。\n\n## 新观点\n- `HUMAN.md` 应是最高优先级输入，每回合开头必读；`STOP` 文件存在即全员退出——这两条要写进协议硬约束", "ts": t0 + datetime.timedelta(minutes=18)},
        {"round": 1, "seat": "P3", "stance": "同意 manual 等价席位；补充渲染降级",
         "body": "## 交锋\n- re: P2 —— concur：manual 席位协议等价，只差在调度方式\n- re: P4 —— build：render.py 纯 python3 标准库，不装依赖；YAML 只解析平铺 key: value\n\n## 立场更新\n同意 P2：manual 是正式席位。\n\n## 新观点\n- python3 不可用时 degrade 为只看 markdown 文件，协议不受影响——渲染层是可选的", "ts": t0 + datetime.timedelta(minutes=21)},
        {"round": 1, "seat": "P4", "stance": "全部接受；补一个失败处理条款",
         "body": "## 交锋\n- re: P1 —— concur\n- re: P2 —— concur：HUMAN.md + STOP 进硬约束\n- re: P3 —— concur：渲染层可选\n\n## 立场更新\n维持 r0 立场。\n\n## 新观点\n- 派发失败处理：同一回合失败两次即停止并向人类汇报，不无限重试", "ts": t0 + datetime.timedelta(minutes=24)},
    ]
    synthesis = {
        "by": "R0", "ts": t0 + datetime.timedelta(minutes=35),
        "body": """# 圆桌总结：为 CLI 会话工具增加圆桌讨论功能

## 结论（TL;DR）
1. 采用「文件系统即状态机」架构 —— **共识**
2. 收敛条件 = max_rounds 耗尽 或 SYNTHESIZE 文件 或人类 STOP —— **共识**
3. 席位声明式配置（tool+model+thinking+persona），manual 席位协议等价 —— **共识**

## 共识
- 开局盲答保独立性，讨论轮可见历史（P1@r0, P2@r1）
- 引用格式 `Pk@rN`；HUMAN.md 最高优先级，STOP 即停（P1@r1, P2@r1）
- 渲染层与协议层解耦，render.py 单文件自包含（P4@r0, P3@r1）

## 分歧与取舍

| 分歧点 | 各方立场 | 取舍建议 |
|---|---|---|
| thinking 参数映射 | P1: CLI 原生参数优先 / P3: 提示词兜底 | 双管齐下：CLI 有就用，无则提示词 |
| 席位过滤功能 | P4: 要 / P1: 可选 | 保留，成本极低 |

## 各席独特洞见
- P2: 总结署名签署机制，防止分歧被粉饰成共识
- P3: 无默认模型的 CLI 必须强制 `provider/model` 显式配置

## 建议行动项
- [ ] 实现 init.sh / status.sh / dispatch.sh / prompt.sh / wait.sh / join.sh / log.sh
- [ ] 实现 render.py（含 --demo 预览）
- [ ] 在真实议题上跑一场四席位圆桌验证端到端

## 发言签署
- P1（codex · gpt-5.2-codex · high）：文件状态机 + 盲答开局是正确骨架
- P2（claude · claude-opus-4.6 · high）：收敛与签署先于流程
- P3（opencode · openai/gpt-5 · medium）：声明式席位 + 握手核对
- P4（devin · swe-2-max · medium）：页面即监控，渲染层必须可选"""}
    return {"cfg": {"slug": "demo", "title": "为 CLI 会话工具增加圆桌讨论功能",
                    "kind": "implementation", "mode": "orchestrated",
                    "synthesizer": "host"},
            "title": "为 CLI 会话工具增加圆桌讨论功能", "kind": "implementation",
            "mode": "orchestrated", "seats": seats, "max_rounds": 2,
            "synthesizer": "host", "state": "done", "cur_round": -1, "pending": [],
            "topic": "## 背景\n本地已有 claude / codex / opencode / devin 四家 CLI。需要一个把议题 fan-out 给多模型、再综合结论的「圆桌」能力（类 fusion 面板）。\n\n## 讨论目标\n1. 确定讨论协议与状态机\n2. 确定席位配置与 thinking 等级映射\n3. 确定聊天式原型页的形态\n\n## 焦点问题\n1. 讨论如何收敛？\n2. 席位间如何引用与交锋？\n3. 页面渲染边界在哪？",
            "human": None, "speeches": speeches, "synthesis": synthesis}


TEMPLATE = """<!doctype html>
<html lang="zh-CN"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} · 圆桌讨论</title>{refresh}
<style>
:root{{--bg:#0b0e13;--panel:#131824;--panel2:#1a2130;--line:#232b3a;--fg:#dbe2ee;--mut:#7f8ca3;--acc:#6ea8fe;--gold:#e0b36a}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--fg);font:14px/1.75 -apple-system,"SF Pro","PingFang SC","Segoe UI",sans-serif}}
code,pre,.model{{font-family:"SF Mono",Menlo,Consolas,monospace}}
.topbar{{position:sticky;top:0;z-index:10;background:rgba(11,14,19,.92);backdrop-filter:blur(10px);border-bottom:1px solid var(--line);padding:14px 22px}}
.topbar h1{{margin:0;font-size:16px;font-weight:650}}
.meta{{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-top:8px}}
.pill{{font-size:12px;padding:2px 10px;border-radius:99px;border:1px solid var(--line);color:var(--mut)}}
.pill.kind{{color:var(--acc);border-color:#6ea8fe44;background:#6ea8fe14}}
.pill.live{{color:#6ea8fe;border-color:#6ea8fe66;box-shadow:0 0 0 3px #6ea8fe14}}
.pill.ok{{color:#7ed083;border-color:#7ed08355}}
.pill.warn{{color:#e0a55e;border-color:#e0a55e55}}
.pill.mut{{color:var(--mut)}}
.legend{{color:var(--mut);font-size:12px}}
.seats{{display:flex;gap:10px;flex-wrap:wrap;padding:14px 22px;border-bottom:1px solid var(--line)}}
.seat{{--c:#8b98ad;display:flex;gap:10px;align-items:center;background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:8px 14px;cursor:pointer;color:var(--fg);text-align:left;transition:.15s}}
.seat:hover{{border-color:var(--c)}}
.seat.on{{border-color:var(--c);box-shadow:0 0 0 2px color-mix(in srgb,var(--c) 30%,transparent)}}
.seat-av{{width:32px;height:32px;border-radius:50%;background:color-mix(in srgb,var(--c) 22%,var(--panel));color:var(--c);display:flex;align-items:center;justify-content:center;font-weight:700;font-size:12px;border:1px solid color-mix(in srgb,var(--c) 45%,transparent)}}
.seat-meta{{display:flex;flex-direction:column;line-height:1.3}}
.seat-meta b{{font-size:13px}}
.join{{font-style:normal;font-size:10px;color:var(--mut)}}
.join[data-on=true]{{color:#7ed083}}
.seat-chips{{display:flex;gap:4px;flex-wrap:wrap;max-width:240px}}
.chip{{font-size:11px;padding:1px 8px;border-radius:6px;border:1px solid var(--line);color:var(--mut);white-space:nowrap}}
.chip.tool{{color:var(--fg);background:#ffffff0d}}
.chip.persona{{color:var(--gold);border-color:#e0b36a44}}
.chat{{max-width:900px;margin:0 auto;padding:26px 22px 120px}}
.card{{background:var(--panel);border:1px solid var(--line);border-radius:14px;padding:16px 18px;margin:14px 0}}
.card-tag{{font-size:12px;font-weight:650;color:var(--acc);margin-bottom:8px;letter-spacing:.4px}}
.topic{{border-left:3px solid var(--acc)}}
.human{{border-left:3px solid #7ed083}}
.human .card-tag{{color:#7ed083}}
.synth{{border:1px solid #e0b36a55;background:linear-gradient(180deg,#1c1a12 0%,var(--panel) 30%)}}
.synth .card-tag{{color:var(--gold)}}
.synth.pending{{opacity:.6;font-style:italic}}
.round-div{{display:flex;align-items:center;gap:14px;margin:30px 0 16px;color:var(--mut);font-size:12px;letter-spacing:1px}}
.round-div::before,.round-div::after{{content:"";flex:1;height:1px;background:var(--line)}}
.msg{{display:flex;gap:12px;margin:14px 0;transition:opacity .15s}}
.av{{--c:#8b98ad;flex:none;width:38px;height:38px;border-radius:50%;background:color-mix(in srgb,var(--c) 20%,var(--panel));color:var(--c);display:flex;align-items:center;justify-content:center;font-weight:700;font-size:12px;border:1px solid color-mix(in srgb,var(--c) 45%,transparent)}}
.bubble{{flex:1;min-width:0;background:var(--panel);border:1px solid var(--line);border-radius:4px 14px 14px 14px;padding:11px 15px}}
.bubble.pending{{border-style:dashed;color:var(--mut);text-align:center;padding:8px}}
.head{{display:flex;gap:6px;align-items:center;flex-wrap:wrap;margin-bottom:5px}}
.head b{{font-size:13px}}
.ts{{margin-left:auto;font-size:11px;color:var(--mut)}}
.stance{{font-size:12.5px;color:var(--gold);font-style:italic;margin-bottom:6px;padding-left:8px;border-left:2px solid #e0b36a55}}
.md p{{margin:.45em 0}}
.md h1,.md h2{{font-size:15px;margin:.8em 0 .35em}}
.md h3,.md h4{{font-size:13.5px;margin:.7em 0 .3em}}
.md ul,.md ol{{margin:.4em 0;padding-left:1.5em}}
.md li{{margin:.15em 0}}
.md code{{background:#ffffff12;padding:1px 5px;border-radius:5px;font-size:12.5px}}
.md pre{{background:#0a0d12;border:1px solid var(--line);border-radius:8px;padding:10px 12px;overflow-x:auto;font-size:12.5px}}
.md pre code{{background:none;padding:0}}
.md blockquote{{border-left:3px solid var(--line);margin:.5em 0;padding:2px 12px;color:var(--mut)}}
.md table{{border-collapse:collapse;margin:.6em 0;font-size:13px}}
.md th,.md td{{border:1px solid var(--line);padding:5px 10px;text-align:left}}
.md th{{background:var(--panel2)}}
.md hr{{border:none;border-top:1px solid var(--line);margin:.8em 0}}
.md a{{color:var(--acc)}}
.toolbar{{position:fixed;right:18px;bottom:18px;display:flex;gap:6px;z-index:20}}
.toolbar button{{background:var(--panel2);border:1px solid var(--line);color:var(--mut);border-radius:8px;padding:6px 10px;font-size:12px;cursor:pointer}}
.toolbar button:hover{{color:var(--fg);border-color:var(--mut)}}
</style></head>
<body data-ws="{wsname}">
<header class="topbar">
  <h1>{title}</h1>
  <div class="meta">
    <span class="pill kind">{kind}</span>
    <span class="pill">{mode}</span>
    <span class="pill">讨论轮 ×{rounds}</span>
    <span class="pill">总结者 {synth}</span>
    <span class="pill {state_cls}">{state}</span>
    <span class="legend">{legend} · {n_seats} 席 · 生成于 {now}</span>
  </div>
</header>
<section class="seats">{seats}</section>
<main class="chat">
{chat}
</main>
<div class="toolbar"><button onclick="top_()">⇧ 顶部</button><button onclick="bot()">⇩ 底部</button></div>
<script>
document.querySelectorAll('.seat').forEach(b=>b.addEventListener('click',()=>{{
  const p=b.dataset.seat, cur=document.body.dataset.focus;
  document.querySelectorAll('.seat').forEach(x=>x.classList.remove('on'));
  if(cur===p){{delete document.body.dataset.focus;
    document.querySelectorAll('.msg').forEach(m=>m.style.opacity='');return}}
  document.body.dataset.focus=p; b.classList.add('on');
  document.querySelectorAll('.msg').forEach(m=>{{
    m.style.opacity = (!m.dataset.seat||m.dataset.seat===p) ? '' : '.18';
  }});
}}));
function top_(){{scrollTo({{top:0,behavior:'smooth'}})}}
function bot(){{scrollTo({{top:document.body.scrollHeight,behavior:'smooth'}})}}
</script>
</body></html>
"""


def main():
    args = sys.argv[1:]
    demo = "--demo" in args
    do_open = "--open" in args
    ws = os.getcwd()
    out = None
    i = 0
    while i < len(args):
        if args[i] == "--ws":
            ws = args[i + 1]; i += 2
        elif args[i] == "--out":
            out = args[i + 1]; i += 2
        else:
            i += 1
    if demo:
        data = demo_data()
        out = out or os.path.join(os.getcwd(), "roundtable-demo.html")
    else:
        if not os.path.exists(os.path.join(ws, "table.yaml")):
            sys.exit(f"不是圆桌工作区（缺 table.yaml）: {ws}")
        data = load_workspace(ws)
        out = out or os.path.join(ws, "index.html")
    html_out = render(data, out)
    with open(out, "w", encoding="utf-8") as f:
        f.write(html_out)
    print(f"已生成: {out}")
    print(f"  议题: {data['title']}   状态: {STATE_LABEL.get(data['state'], data['state'])}   席位: {len(data['seats'])}   发言: {len(data['speeches'])}")
    if do_open:
        subprocess.run(["open", out] if sys.platform == "darwin" else ["xdg-open", out], check=False)


if __name__ == "__main__":
    main()
