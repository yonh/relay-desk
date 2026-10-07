#!/usr/bin/env bash
# 从工作区文件推导圆桌状态（唯一的状态来源）。用法：status.sh [--porcelain]
#
# 状态机：
#   stopped       存在 STOP
#   done          存在 SYNTHESIS.md
#   synthesizing  存在 SYNTHESIZE（人类要求提前收尾），或 rounds/r0..r<max> 全部到齐
#   opening       rounds/r0/ 有嘉宾缺发言（盲答轮）
#   discussing    rounds/rN/（N≥1）有嘉宾缺发言，round=N
set -uo pipefail
WS="$(cd "$(dirname "$0")/.." && pwd)"
cd "$WS"
PORCELAIN=0; [ "${1:-}" = "--porcelain" ] && PORCELAIN=1

cfg() { sed -n "s/^$1:[[:space:]]*//p" table.yaml | tail -n1 | sed -e 's/[[:space:]]#.*$//' -e 's/^"\(.*\)"$/\1/' -e 's/[[:space:]]*$//'; }

MODE=$(cfg mode); PARTICIPANTS=$(cfg participants); MAX=$(cfg max_rounds); TITLE=$(cfg title)
KIND=$(cfg kind); SYNTH=$(cfg synthesizer)
: "${MAX:=2}"; : "${SYNTH:=host}"; : "${KIND:=free}"

STATE=""; ROUND=-1; NEXT_ROLE="-"; NEXT_ACTION=""; PENDING=""; HINT=""; DETAIL=""

if [ -f STOP ]; then
  STATE=stopped; NEXT_ACTION="stop"; HINT="存在 STOP：所有席位退出，不再写入。"
elif [ -f SYNTHESIS.md ]; then
  STATE=done; NEXT_ACTION="none"; HINT="已总结：SYNTHESIS.md"
elif [ -f SYNTHESIZE ]; then
  STATE=synthesizing; NEXT_ROLE=$SYNTH; NEXT_ACTION="synthesize"
  HINT="存在 SYNTHESIZE：人类要求提前收尾，由 ${SYNTH} 就已有发言写 SYNTHESIS.md"
else
  i=0
  while [ "$i" -le "$MAX" ]; do
    RD="rounds/r$i"; MISS=""
    for p in $PARTICIPANTS; do
      [ -f "$RD/speech-$p.md" ] || MISS="$MISS $p"
    done
    if [ -n "$MISS" ]; then ROUND=$i; PENDING="${MISS# }"; break; fi
    DETAIL="$DETAIL
  r$i: 到齐（$(ls "$RD"/speech-*.md 2>/dev/null | wc -l | tr -d ' ') 席发言）"
    i=$((i + 1))
  done
  if [ "$ROUND" = -1 ]; then
    STATE=synthesizing; NEXT_ROLE=$SYNTH; NEXT_ACTION="synthesize"
    HINT="全部轮次完成：由 ${SYNTH} 写 SYNTHESIS.md（模板 templates/SYNTHESIS.md）"
  elif [ "$ROUND" = 0 ]; then
    STATE=opening; NEXT_ROLE=participants; NEXT_ACTION="speak:r0"
    HINT="待嘉宾各自盲答写 rounds/r0/speech-<Pk>.md（互不可见；模板 templates/speech.md）"
  else
    STATE=discussing; NEXT_ROLE=participants; NEXT_ACTION="speak:r$ROUND"
    HINT="待嘉宾先读 rounds/r0..r$((ROUND - 1))/ 全部发言，再写 rounds/r$ROUND/speech-<Pk>.md（禁读本轮他人文件）"
  fi
fi

HUMAN=0; [ -f HUMAN.md ] && HUMAN=1

# 就位登记（roster/Pk.yaml，由 bin/join.sh 写入）
ROSTER=""; JOINED=""; MISSING=""
EXPECTED="$PARTICIPANTS"; [ "$MODE" = orchestrated ] && EXPECTED="R0 $EXPECTED"
for r in $EXPECTED; do
  if [ -f "roster/$r.yaml" ]; then
    JOINED="$JOINED $r"
    t=$(sed -n 's/^thinking:[[:space:]]*//p' "roster/$r.yaml")
    ROSTER="$ROSTER
  $r: $(sed -n 's/^tool:[[:space:]]*//p' "roster/$r.yaml") / $(sed -n 's/^model:[[:space:]]*//p' "roster/$r.yaml")${t:+ / $t}（$(sed -n 's/^joined:[[:space:]]*//p' "roster/$r.yaml")）"
  else
    MISSING="$MISSING $r"
  fi
done
JOINED="${JOINED# }"; MISSING="${MISSING# }"

if [ "$PORCELAIN" = 1 ]; then
  printf 'state=%s\nround=%s\nnext_role=%s\nnext_action=%s\npending=%s\nmode=%s\nkind=%s\nparticipants=%s\nmax_rounds=%s\nsynthesizer=%s\nhuman=%s\njoined=%s\nmissing=%s\n' \
    "$STATE" "$ROUND" "$NEXT_ROLE" "$NEXT_ACTION" "$PENDING" "$MODE" "$KIND" "$PARTICIPANTS" "$MAX" "$SYNTH" "$HUMAN" "$JOINED" "$MISSING"
  exit 0
fi

echo "圆桌工作区: $WS"
echo "议题: $TITLE"
echo "类型: $KIND   模式: $MODE   嘉宾: $PARTICIPANTS   讨论轮数: $MAX   总结者: $SYNTH"
echo "状态: $STATE${ROUND:+, 当前轮 r$ROUND}"
if [ -n "$ROSTER" ]; then echo "已就位:$ROSTER"; fi
[ -n "$MISSING" ] && echo "未就位: ${MISSING}（各席位先运行 bin/join.sh <Pk> --tool … --model …）"
[ -n "$DETAIL" ] && echo "已完成轮次:$DETAIL"
echo
echo "下一步: [$NEXT_ROLE] $NEXT_ACTION${PENDING:+   待发言: $PENDING}"
echo "        $HINT"
[ "$HUMAN" = 1 ] && echo "HUMAN.md 存在：所有席位下一回合必读。"
exit 0
