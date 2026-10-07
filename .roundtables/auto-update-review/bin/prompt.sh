#!/usr/bin/env bash
# 生成某席位的接入提示词（粘贴到另一个会话，或交给 dispatch.sh）。
# 用法：prompt.sh <R0|Pk> [--oneshot|--loop] [--note "附加说明"]
#   --oneshot 只做一个回合就退出（orchestrated 模式默认）；--loop 做完用 wait.sh 等下一回合（peer 模式默认）
#   提示词内容按 status.sh 推导的当前状态生成（开局盲答 / 第N轮讨论 / 总结）。
set -uo pipefail
WS="$(cd "$(dirname "$0")/.." && pwd)"
cd "$WS"
ROLE=${1:-}; [ -n "$ROLE" ] || { sed -n '2,5s/^# *//p' "$0" >&2; exit 2; }
shift
STYLE=""; NOTE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --oneshot) STYLE=oneshot; shift ;;
    --loop)    STYLE=loop; shift ;;
    --note)    NOTE=$2; shift 2 ;;
    *) echo "未知参数 $1" >&2; exit 2 ;;
  esac
done

cfg() { sed -n "s/^$1:[[:space:]]*//p" table.yaml | tail -n1 | sed -e 's/[[:space:]]#.*$//' -e 's/^"\(.*\)"$/\1/' -e 's/[[:space:]]*$//'; }
MODE=$(cfg mode); TITLE=$(cfg title); KIND=$(cfg kind); SYNTH=$(cfg synthesizer); PARTICIPANTS=$(cfg participants)
[ -z "$STYLE" ] && { [ "$MODE" = orchestrated ] && STYLE=oneshot || STYLE=loop; }

# 讨论类型视角：给每席的发言定焦
case "$KIND" in
  requirements)   LENS="讨论目标是把需求谈透：用户价值、边界与非目标、验收口径、遗漏场景、风险假设。" ;;
  implementation) LENS="讨论目标是把实现谈透：架构选型、数据流、关键接口、风险与回滚、分步落地路径。" ;;
  *)              LENS="围绕议题自由交锋：观点要具体、可辩护、可落地。" ;;
esac

if [ "$ROLE" = R0 ]; then
  cat <<EOF
你是圆桌讨论的 R0（主持人/调度者）。议题：$TITLE
圆桌工作区（绝对路径）：$WS
如果你的环境里有名为 roundtable 的技能，先调用它；否则按下面执行。

0. 先登记身份：bash $WS/bin/join.sh R0 --tool <你的工具> --model <你的模型>
1. 读 $WS/PROTOCOL.md 的 §2、§4，读 $WS/table.yaml 与 $WS/TOPIC.md。
2. 你只写两类文件：logs/ 与结束时的 SYNTHESIS.md（当 synthesizer: host）。绝不替嘉宾发言。
   你的循环是：
   bash $WS/bin/status.sh --porcelain → 按 state 派发：
     opening / discussing（pending 里的所有席位）→ bash $WS/bin/dispatch.sh <Pk Pj …> --wait
     synthesizing 且 synthesizer: host → 自己读全部 rounds/*/speech-*.md 后写 $WS/SYNTHESIS.md（模板 templates/SYNTHESIS.md）
     synthesizing 且 synthesizer: Pk → bash $WS/bin/dispatch.sh <Pk> --wait
   每次状态推进后运行 python3 $WS/bin/render.py 刷新 index.html。
   子进程退出后再 status，确认状态推进；没推进就看 $WS/logs/ 里该席位最新日志的末尾，修正后重派一次，第二次仍失败就停下向人类汇报。
3. state 为 done 时读 $WS/SYNTHESIS.md 向人类汇报：结论、共识、未决分歧、index.html 路径。
EOF
  [ -n "$NOTE" ] && printf '\n附加说明：%s\n' "$NOTE"
  exit 0
fi

printf ' %s ' "$PARTICIPANTS" | grep -q " $ROLE " || { echo "未知席位 ${ROLE}（table.yaml: participants=${PARTICIPANTS}）" >&2; exit 2; }

SNAP=$(bash "$WS/bin/status.sh" --porcelain)
get() { printf '%s\n' "$SNAP" | sed -n "s/^$1=//p"; }
STATE=$(get state); ROUND=$(get round); PENDING=$(get pending)

THINK=$(cfg "thinking_$ROLE"); : "${THINK:=medium}"
PERSONA=$(cfg "persona_$ROLE")
case "$THINK" in
  high)   THINKNOTE="思考等级 high：深入推理后再落笔——考虑边界条件、反例、二阶效应与失败模式。" ;;
  low)    THINKNOTE="思考等级 low：快速作答，直接给要点清单，不展开论证。" ;;
  *)      THINKNOTE="思考等级 medium：正常深度，论点配简要理由。" ;;
esac
[ -n "$PERSONA" ] && PERSONANOTE="你的视角帽子：${PERSONA}。全程戴好这顶帽子，从该视角发言与质疑。" || PERSONANOTE=""

cat <<EOF
你是圆桌讨论的嘉宾 ${ROLE}。议题：$TITLE
圆桌工作区（绝对路径）：$WS
$LENS
$THINKNOTE
$PERSONANOTE
0. 先登记身份（握手）：bash $WS/bin/join.sh $ROLE --tool <你实际运行的工具> --model <你实际的模型名> --thinking $THINK
   若报"席位冲突"，停下来向人类确认，不要 --force。
1. 读 $WS/PROTOCOL.md、$WS/TOPIC.md；若存在 $WS/HUMAN.md 必读（优先级最高）；若存在 $WS/STOP 立即停止。
EOF

case "$STATE" in
  opening)
    cat <<EOF
2. 现在是开局陈述轮（盲答）：独立作答，禁止读 $WS/rounds/ 下任何文件——信息增量来自独立视角。
   按 $WS/templates/speech.md 的格式写 $WS/rounds/r0/speech-$ROLE.md。
EOF
    ;;
  discussing)
    PREV=""; i=0; while [ "$i" -lt "$ROUND" ]; do PREV="$PREV $WS/rounds/r$i/"; i=$((i+1)); done
    cat <<EOF
2. 现在是第 $ROUND 轮讨论：先读$PREV 下全部 speech-*.md（禁止读 $WS/rounds/r$ROUND/ 下其他席位的文件——本轮仍是独立作答）。
   然后写 $WS/rounds/r$ROUND/speech-$ROLE.md：至少点名回应一席（re: Pj，同意/反对/补充并给理由），可修正自己的立场，只写信息增量，不重复已说过的。
   格式同 $WS/templates/speech.md。
EOF
    ;;
  synthesizing)
    [ "$SYNTH" = "$ROLE" ] || { echo "席位 $ROLE 无待做动作（当前状态 $STATE，总结者是 $SYNTH）" >&2; exit 2; }
    cat <<EOF
2. 你是本场圆桌的总结者：读 $WS/rounds/ 下全部 speech-*.md，按 $WS/templates/SYNTHESIS.md 写 $WS/SYNTHESIS.md——
   结论先行，列出共识、分歧与取舍、各席独特洞见、行动项；引用格式 Pk@rN。
EOF
    ;;
  *) echo "席位 $ROLE 当前无待做动作（state=$STATE，pending=${PENDING:-无}）" >&2; exit 2 ;;
esac

cat <<EOF
3. 完成后运行 bash $WS/bin/status.sh 确认状态已推进，然后 bash $WS/bin/log.sh $ROLE "<做了什么>"。
EOF
if [ "$STYLE" = loop ]; then
  cat <<EOF
4. 然后运行 bash $WS/bin/wait.sh $ROLE（阻塞，最多 1 小时；超时就再跑一次）等待下一回合，回到第 1 步，直到 status 显示 done 或 stopped。
EOF
else
  cat <<EOF
4. 只做这一个回合，不等待其他席位；做完即结束，用 3–5 行汇报你写了哪个文件、立场是什么。
EOF
fi
[ -n "$NOTE" ] && printf '\n附加说明：%s\n' "$NOTE"
exit 0
