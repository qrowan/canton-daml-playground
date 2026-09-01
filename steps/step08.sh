#!/usr/bin/env bash
# Step 08 — Reassignment 인터랙티브 러너
#
#   ./steps/step08.sh            처음부터
#   ./steps/step08.sh --auto     엔터 대기 없이 전부 실행
#   ./steps/step08.sh --keep     끝나고 노드를 끄지 않음
#
# Synchronizer 2개 + Participant 2개를 띄우고 Contract 를 원장 사이로 옮긴다.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

AUTO=0
KEEP=0
for a in "$@"; do
  case "$a" in
    --auto) AUTO=1 ;;
    --keep) KEEP=1 ;;
    *) echo "알 수 없는 옵션: $a"; exit 2 ;;
  esac
done

if [ -t 1 ]; then
  B=$'\033[1m'; DIM=$'\033[2m'; R=$'\033[0m'
  CY=$'\033[36m'; GR=$'\033[32m'; YE=$'\033[33m'; RD=$'\033[31m'
else
  B=''; DIM=''; R=''; CY=''; GR=''; YE=''; RD=''
fi

STEP_NO=0
TOTAL=12
WORK="$ROOT/.step08"
LOG="$WORK/canton.log"

CITI_API=http://localhost:5013
GS_API=http://localhost:5033

title() {
  STEP_NO=$((STEP_NO + 1))
  printf '\n%s%s\n' "$CY" "════════════════════════════════════════════════════════════════"
  printf '  [%d/%d] %s%s%s\n' "$STEP_NO" "$TOTAL" "$B" "$1" "$R"
  printf '%s%s%s\n' "$CY" "════════════════════════════════════════════════════════════════" "$R"
}

say()  { printf '%s\n' "$1"; }
note() { printf '%s%s%s\n' "$DIM" "$1" "$R"; }
ok()   { printf '%s✓ %s%s\n' "$GR" "$1" "$R"; }
warn() { printf '%s! %s%s\n' "$YE" "$1" "$R"; }
die()  { printf '%s✗ %s%s\n' "$RD" "$1" "$R"; exit 1; }

pause() {
  [ "$AUTO" = 1 ] && return 0
  printf '\n%s─ 엔터 ─%s' "$DIM" "$R"
  read -r _ || true
  printf '\n'
}

run() { printf '%s$ %s%s\n\n' "$YE" "$1" "$R"; eval "$1"; }

jq_() { python3 -c "import sys,json; d=json.load(sys.stdin); $1"; }

printf '%s\n' "$B"
cat <<'BANNER'
 Step 08 — Reassignment
 ────────────────────────────────────────────────────────────
 Step 06 의 DvP 는 현금과 채권이 같은 원장에 있다고 전제했습니다.
 실무에서는 그렇지 않습니다. 현금은 자금 결제망에, 증권은 예탁결제망에
 있습니다. 서로 다른 원장입니다.

 여기서는 Synchronizer 를 둘 띄웁니다.

   dtcc           현금 원장       Sequencer 5001 / Mediator 5003
   euroclear      증권 원장       Sequencer 5004 / Mediator 5006
   citi           Citi, Alice     Ledger 5011 / JSON 5013
   goldmansachs   GoldmanSachs    Ledger 5031 / JSON 5033

 Daml 코드는 Step 06 의 것을 그대로 씁니다. 한 줄도 고치지 않습니다.
BANNER
printf '%s\n' "$R"

# env.sh 가 있으면 읽습니다. 없어도 됩니다 — PATH 에 dpm 과 java 만 있으면 동작합니다.
# shellcheck disable=SC1091
[ -f ./env.sh ] && source ./env.sh

command -v dpm >/dev/null 2>&1 || die "dpm 을 찾을 수 없습니다.
    설치: https://docs.canton.network/sdks-tools/cli-tools/dpm
    설치 후 PATH 에 추가하세요:  export PATH=\"\$HOME/.dpm/bin:\$PATH\""
java -version >/dev/null 2>&1 || die "JDK 21 이상이 필요합니다.
    JAVA_HOME 을 설정하거나 java 를 PATH 에 두세요."

if [ -z "${CANTON_JAR:-}" ] || [ ! -f "${CANTON_JAR:-}" ]; then
  CANTON_JAR=$(find "${DPM_HOME:-$HOME/.dpm}/cache/components/canton-open-source" \
    -name 'canton-open-source-*.jar' 2>/dev/null | sort -V | tail -1)
fi
[ -n "$CANTON_JAR" ] && [ -f "$CANTON_JAR" ] || die "canton jar 을 찾을 수 없습니다.
    dpm 으로 SDK 를 설치했는지 확인하세요:  dpm install
    또는 직접 지정하세요:  export CANTON_JAR=/path/to/canton-open-source-*.jar"

mkdir -p "$WORK"

cleanup() {
  if [ "$KEEP" = 1 ]; then
    printf '\n%s 노드를 계속 실행 중입니다. 끄려면: pkill -f '\''daemon -c canton/step08.conf'\''%s\n' "$DIM" "$R"
    return
  fi
  printf '\n%s 노드 종료 중...%s\n' "$DIM" "$R"
  [ -n "${CANTON_PID:-}" ] && kill "$CANTON_PID" 2>/dev/null
  pkill -f 'daemon -c canton/step08.conf' 2>/dev/null
  true
}
trap cleanup EXIT

# ─── 1 ───────────────────────────────────────────────────────────────────────

title "원장이 둘이다"
say "Step 05 의 설정에서 Sequencer 와 Mediator 가 한 벌 더 늘었습니다."
pause

run "cat canton/step08.conf"

printf '\n'
say "Sequencer + Mediator 한 벌이 Synchronizer 하나입니다. 두 벌이므로"
say "${B}독립적인 원장이 두 개${R}입니다."
printf '\n'
note "Participant 는 Step 05 와 같이 둘입니다. Morgan Stanley 자리에 GoldmanSachs 가"
note "들어온 것은 다루는 자산이 채권이기 때문이고, 구조는 같습니다. 이 Step 에서"
note "실제로 달라지는 변수는 Synchronizer 의 개수 하나뿐입니다."

# ─── 2 ───────────────────────────────────────────────────────────────────────

title "Bootstrap — 양쪽에 연결하고, 다중 원장을 켠다"
pause

run "cat canton/step08-bootstrap.canton"

printf '\n'
say "세 가지가 Step 05 와 다릅니다."
cat <<'DIFF'

    1. bootstrap.synchronizer 를 두 번 부릅니다
    2. Participant 마다 connect_local 을 두 번 부릅니다
    3. synchronizer_trust_certificates.propose 로 feature flag 를 켭니다

DIFF
say "${B}세 번째가 이 Step 의 전제입니다.${R} 여러 원장에 걸친 동작은 기본이 아니라"
say "Participant 가 명시적으로 켜야 하는 기능이고, 그 사실이 Topology 에"
say "기록됩니다 — Participant 가 Synchronizer 에 제출하는 가입 증서"
say "(SynchronizerTrustCertificate) 에 붙습니다."
printf '\n'
note "켜지 않으면 이 뒤의 모든 동작이 MULTI_SYNCHRONIZER_IS_NOT_ENABLED 로 거부됩니다."
note "Party 도 원장마다 따로 등록해야 합니다. parties.enable 이 두 번씩 불립니다."

# ─── 3 ───────────────────────────────────────────────────────────────────────

title "기동"
pause

DAR=$(ls -t .daml/dist/*.dar 2>/dev/null | head -1)
[ -n "$DAR" ] || { dpm build >/dev/null 2>&1; DAR=$(ls -t .daml/dist/*.dar | head -1); }
ok "DAR: $DAR"

pkill -f 'daemon -c canton/' 2>/dev/null
for _ in $(seq 1 30); do
  pgrep -f 'daemon -c canton/' >/dev/null 2>&1 || break
  sleep 1
done
for _ in $(seq 1 30); do
  if ! nc -z localhost 5002 2>/dev/null && ! nc -z localhost 5011 2>/dev/null; then break; fi
  sleep 1
done

printf '%s$ java -jar canton.jar daemon -c canton/step08.conf --bootstrap canton/step08-bootstrap.canton%s\n\n' "$YE" "$R"
STEP08_DAR="$ROOT/$DAR" nohup java -jar "$CANTON_JAR" daemon \
  -c canton/step08.conf --bootstrap canton/step08-bootstrap.canton --no-tty > "$LOG" 2>&1 &
CANTON_PID=$!

printf '기동 대기'
READY=0
for _ in $(seq 1 120); do
  if grep -q "=== READY ===" "$LOG" 2>/dev/null; then READY=1; break; fi
  if grep -q "Bootstrap script terminated" "$LOG" 2>/dev/null; then break; fi
  printf '.'
  sleep 2
done
printf '\n'
if [ "$READY" != 1 ]; then
  grep -iE "Failed to bind|Address already in use" "$LOG" | head -3
  tail -15 "$LOG"
  die "기동 실패. 포트 5001~5006, 5011~5013, 5031~5033 이 비어 있는지 확인하세요:
    pkill -f 'daemon -c canton/'"
fi

DTCC=$(grep  '^DTCC='      "$LOG" | tail -1 | cut -d= -f2)
EURO=$(grep  '^EUROCLEAR=' "$LOG" | tail -1 | cut -d= -f2)
CITI=$(grep  '^CITI='      "$LOG" | tail -1 | cut -d= -f2)
ALICE=$(grep '^ALICE='     "$LOG" | tail -1 | cut -d= -f2)
GS=$(grep    '^GS='        "$LOG" | tail -1 | cut -d= -f2)
EXCL=$(grep  '^EXCLUSIVITY=' "$LOG" | tail -1 | cut -d= -f2)

ok "노드 6개 기동, Synchronizer 2개 구성 완료"
printf '\n'
printf '  %-12s %s\n' "dtcc"      "$DTCC"
printf '  %-12s %s\n' "euroclear" "$EURO"
printf '\n'
note "Synchronizer ID 도 Party ID 처럼 이름::지문 꼴입니다. 지문은 그 원장을"
note "만든 키에서 나옵니다."

# ─── 헬퍼 ────────────────────────────────────────────────────────────────────

mkuser() { # $1=api $2=id $3..=parties
  local api="$1" id="$2"; shift 2
  local rights="" p
  for p in "$@"; do
    [ -n "$rights" ] && rights="$rights,"
    rights="$rights{\"kind\":{\"CanActAs\":{\"value\":{\"party\":\"$p\"}}}}"
  done
  curl -s -X POST "$api/v2/users" -H 'Content-Type: application/json' \
    -d "{\"user\":{\"id\":\"$id\",\"primaryParty\":\"\",\"isDeactivated\":false,\"metadata\":{\"resourceVersion\":\"\",\"annotations\":{}},\"identityProviderId\":\"\"},\"rights\":[$rights]}" >/dev/null
}

submit() { # $1=api $2=userId $3=actAs(json) $4=commands(json) $5=synchronizerId
  curl -s -X POST "$1/v2/commands/submit-and-wait" -H 'Content-Type: application/json' \
    -d "{\"commands\":$4,\"commandId\":\"s08-$RANDOM$RANDOM\",\"userId\":\"$2\",\"actAs\":$3,\"readAs\":[],\"synchronizerId\":\"$5\"}"
}

# 응답 하나를 사람이 읽을 수 있게 출력합니다. 성공 응답에는 code 필드가 없습니다.
result() {
  jq_ '
if d.get("code"):
    print("  실패  " + d["code"])
    print("  cause:", d.get("cause", "")[:200])
else:
    print("  성공  updateId:", d.get("updateId", "")[:24])
'
}

acs() { # $1=api $2=party
  local off
  off=$(curl -s "$1/v2/state/ledger-end" | jq_ 'print(d["offset"])')
  curl -s -X POST "$1/v2/state/active-contracts" -H 'Content-Type: application/json' \
    -d "{\"filter\":{\"filtersByParty\":{\"$2\":{\"cumulative\":[{\"identifierFilter\":{\"WildcardFilter\":{\"value\":{\"includeCreatedEventBlob\":false}}}}]}}},\"verbose\":false,\"activeAtOffset\":$off}"
}

# ACS 를 사람이 읽을 수 있게 출력한다. 활성이 아닌 항목도 그대로 보여준다.
show() { # $1=api $2=party
  acs "$1" "$2" | jq_ '
import unicodedata
STATE = {"JsActiveContract": "활성", "JsIncompleteUnassigned": "이동중", "JsIncompleteAssigned": "붙이는중"}
def pad(t, w):
    n = sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in t)
    return t + " " * max(0, w - n)
if not d:
    print("    (없음)")
for e in d:
    kind = list(e["contractEntry"])[0]
    v = e["contractEntry"][kind]
    ce = v.get("createdEvent", {})
    tpl = ce.get("templateId", "?").split(":")[-1]
    ue = v.get("unassignedEvent")
    if ue:
        where = ue["source"].split("::")[0] + " → " + ue["target"].split("::")[0]
    else:
        where = v.get("synchronizerId", "").split("::")[0] or "-"
    print("    %s %s %s %s" % (pad(STATE.get(kind, kind), 8), pad(tpl, 14), pad(where, 22), ce.get("contractId", "")[:16]))
'
}

# 템플릿 이름으로 활성 Contract ID 를 찾는다. 도달할 때까지 기다린다.
wait_cid() { # $1=api $2=party $3=템플릿 접미사
  local i cid
  for i in $(seq 1 40); do
    cid=$(acs "$1" "$2" | jq_ "
cs=[e['contractEntry']['JsActiveContract']['createdEvent'] for e in d if 'JsActiveContract' in e['contractEntry']]
cs=[c for c in cs if c['templateId'].endswith(':$3')]
cs.sort(key=lambda c: c['offset'])
print(cs[-1]['contractId'] if cs else '')
" 2>/dev/null)
    [ -n "$cid" ] && { printf '%s' "$cid"; return 0; }
    sleep 1
  done
  return 1
}

# 특정 Contract ID 의 현재 상태를 "상태/원장" 으로 돌려준다. 없으면 빈 문자열.
cid_state() { # $1=api $2=party $3=contractId
  acs "$1" "$2" | jq_ "
out = ''
for e in d:
    k = list(e['contractEntry'])[0]
    v = e['contractEntry'][k]
    if v.get('createdEvent', {}).get('contractId', '') == '$3':
        out = k + '/' + (v.get('synchronizerId') or v.get('unassignedEvent', {}).get('target', '')).split('::')[0]
print(out)
"
}

# Reassignment 제출. 응답에 이벤트가 실리도록 eventFormat 을 함께 보낸다.
reassign() { # $1=api $2=userId $3=submitter $4=command(json)
  curl -s -X POST "$1/v2/commands/submit-and-wait-for-reassignment" -H 'Content-Type: application/json' \
    -d "{\"reassignmentCommands\":{\"workflowId\":\"\",\"userId\":\"$2\",\"commandId\":\"r08-$RANDOM$RANDOM\",\"submitter\":\"$3\",\"submissionId\":\"\",\"commands\":[$4]},\"eventFormat\":{\"filtersByParty\":{\"$3\":{\"cumulative\":[{\"identifierFilter\":{\"WildcardFilter\":{\"value\":{\"includeCreatedEventBlob\":false}}}}]}},\"verbose\":false}}"
}

# 이벤트가 {"JsUnassignedEvent": {...}} 로도, 한 겹 더 싸여서도 옵니다.
pick() { python3 -c "
import sys, json
d = json.load(sys.stdin)
key = '$1'
ev = d.get('reassignment', {}).get('events', [])
hit = [e[key] for e in ev if key in e]
hit = [h.get('value', h) for h in hit]
e = hit[0] if hit else None
$2
"; }

PKG=$(dpm inspect-dar "$DAR" 2>/dev/null | grep -oE "[0-9a-f]{64}" | head -1)
CASH="$PKG:Step06.Dvp:Cash"
BOND="$PKG:Step06.Dvp:Bond"
PROPT="$PKG:Step06.Dvp:DvpProposal"

mkuser "$CITI_API" citi-settlement "$CITI" "$ALICE"
mkuser "$CITI_API" alice-web "$ALICE"
mkuser "$GS_API"   gs-desk     "$GS"

# ─── 4 ───────────────────────────────────────────────────────────────────────

title "발행 — 자산마다 원장이 다르다"
say "현금은 dtcc 에, 채권은 euroclear 에 발행합니다. 제출할 때 synchronizerId 를"
say "지정하면 그 원장에서 실행됩니다."
pause

printf '%s$ Citi + Alice → Cash 1000  (synchronizerId = dtcc)%s\n\n' "$YE" "$R"
submit "$CITI_API" citi-settlement "[\"$CITI\",\"$ALICE\"]" \
  "[{\"CreateCommand\":{\"templateId\":\"$CASH\",\"createArguments\":{\"bank\":\"$CITI\",\"owner\":\"$ALICE\",\"amount\":\"1000.0\"}}}]" "$DTCC" \
  | result

printf '\n%s$ GoldmanSachs → Bond 10  (synchronizerId = euroclear)%s\n\n' "$YE" "$R"
submit "$GS_API" gs-desk "[\"$GS\"]" \
  "[{\"CreateCommand\":{\"templateId\":\"$BOND\",\"createArguments\":{\"issuer\":\"$GS\",\"owner\":\"$GS\",\"isin\":\"US912810TM09\",\"quantity\":\"10.0\"}}}]" "$EURO" \
  | result

CASH_CID=$(wait_cid "$CITI_API" "$ALICE" Cash) || die "현금을 찾지 못했습니다"
BOND_CID=$(wait_cid "$GS_API"   "$GS"    Bond) || die "채권을 찾지 못했습니다"

printf '\n'
ok "발행 완료"
printf '\n'
note "채권의 issuer 와 owner 가 둘 다 GoldmanSachs 입니다. signatory 가 한 party 로"
note "합쳐지므로 혼자서 만들 수 있습니다 — 발행사가 자기 앞으로 찍어 두는 것입니다."

# ─── 5 ───────────────────────────────────────────────────────────────────────

title "Contract 는 한 Synchronizer 에 배정된다"
say "ACS 항목에는 그 Contract 가 어느 원장에 있는지가 함께 실려 옵니다."
pause

printf '%s$ citi-participant / Alice 시점%s\n\n' "$YE" "$R"
show "$CITI_API" "$ALICE"

printf '\n%s$ goldmansachs-participant / GoldmanSachs 시점%s\n\n' "$YE" "$R"
show "$GS_API" "$GS"

printf '\n'
say "${B}Contract 는 어느 한 원장에 속합니다.${R} 두 원장에 동시에 있을 수 없고,"
say "그래서 한 Transaction 이 두 원장의 Contract 를 함께 쓸 수도 없습니다."
printf '\n'
note "Transaction 은 Sequencer 하나가 순서를 부여하고 Mediator 하나가 판정합니다."
note "원장이 다르면 그 둘이 다르므로, 하나의 확인 프로토콜로 묶이지 않습니다."

# ─── 6 ───────────────────────────────────────────────────────────────────────

title "결제 제안 — 채권 원장에서"
say "GoldmanSachs 가 Alice 에게 채권 10 을 1000 에 팔겠다고 제안합니다."
say "채권이 euroclear 에 있으므로 제안도 euroclear 에서 만들어집니다."
pause

printf '%s$ ProposeDvp  (buyer=Alice, price=1000)%s\n\n' "$YE" "$R"
submit "$GS_API" gs-desk "[\"$GS\"]" \
  "[{\"ExerciseCommand\":{\"templateId\":\"$BOND\",\"contractId\":\"$BOND_CID\",\"choice\":\"ProposeDvp\",\"choiceArgument\":{\"buyer\":\"$ALICE\",\"price\":\"1000.0\"}}}]" "$EURO" \
  | result

PROP_CID=$(wait_cid "$CITI_API" "$ALICE" DvpProposal) || die "제안이 도달하지 않았습니다"

printf '\n%s$ Alice 시점%s\n\n' "$YE" "$R"
show "$CITI_API" "$ALICE"

printf '\n'
say "Alice 는 두 원장의 Contract 를 하나의 목록으로 봅니다. 하지만 ${B}현금은 dtcc,"
say "제안은 euroclear${R} 입니다. 결제하려면 둘을 한 원장에 모아야 합니다."

# ─── 7 ───────────────────────────────────────────────────────────────────────

title "Unassign — 현금을 원장에서 떼어낸다"
say "Reassignment 는 두 단계입니다. 먼저 원본 원장에서 떼어냅니다."
pause

printf '%s$ POST %s/v2/commands/submit-and-wait-for-reassignment%s\n' "$YE" "$CITI_API" "$R"
printf '%s    UnassignCommand  source=dtcc  target=euroclear%s\n\n' "$YE" "$R"

UNRESP=$(reassign "$CITI_API" alice-web "$ALICE" \
  "{\"command\":{\"UnassignCommand\":{\"value\":{\"contractId\":\"$CASH_CID\",\"source\":\"$DTCC\",\"target\":\"$EURO\"}}}}")

RID=$(printf '%s' "$UNRESP" | pick JsUnassignedEvent "print(e['reassignmentId'] if e else '')")
printf '%s' "$UNRESP" | pick JsUnassignedEvent "
if e:
    print('  reassignmentId       ', e['reassignmentId'][:32])
    print('  reassignmentCounter  ', e['reassignmentCounter'])
    print('  assignmentExclusivity', e.get('assignmentExclusivity', '-'))
else:
    print('  code:', d.get('code', '?'), d.get('cause', '')[:150])
"
[ -n "$RID" ] || die "unassign 에 실패했습니다"

printf '\n%s$ Alice 시점%s\n\n' "$YE" "$R"
show "$CITI_API" "$ALICE"

printf '\n'
say "현금의 상태가 ${B}이동중${R} 으로 바뀌었습니다. dtcc 에서 떨어져 나왔지만"
say "아직 euroclear 에 붙지 않았습니다."
printf '\n'
say "${B}이 구간에는 기한이 있습니다.${R} assignmentExclusivity 까지는 제출자만"
say "붙일 수 있고, 그 시각이 지나면 ${B}Participant 가 알아서 붙입니다${R} —"
say "자동 assign (automatic assignment) 입니다. 제출자가 사라져도 자산이"
say "갇히지 않게 하는 장치입니다."
printf '\n'
note "기본값은 15초입니다. 그대로 두면 이 화면을 읽는 사이에 자동으로 붙어 버려서,"
note "이 러너는 step08-bootstrap.canton 에서 assignmentExclusivityTimeout 을"
note "${EXCL:-10분} 으로 늘려 두었습니다. Synchronizer 의 동적 파라미터입니다."
note "reassignmentCounter 는 이 Contract 가 몇 번 옮겨졌는지 세는 값입니다."

# ─── 8 ───────────────────────────────────────────────────────────────────────

title "이동중에는 쓸 수 없습니다"
say "지금 결제를 시도하면 어떻게 되는지 봅니다."
pause

printf '%s$ Settle 시도  (cashCid = 이동중인 현금)%s\n\n' "$YE" "$R"
TRY=$(submit "$CITI_API" alice-web "[\"$ALICE\"]" \
  "[{\"ExerciseCommand\":{\"templateId\":\"$PROPT\",\"contractId\":\"$PROP_CID\",\"choice\":\"Settle\",\"choiceArgument\":{\"cashCid\":\"$CASH_CID\"}}}]" "$EURO")
printf '%s' "$TRY" | result
TRY_CODE=$(printf '%s' "$TRY" | jq_ 'print(d.get("code",""))')

printf '\n'
if [ -n "$TRY_CODE" ]; then
  warn "거부되었습니다."
  printf '\n'
  say "${B}Reassignment 는 원자적이지 않습니다.${R} unassign 과 assign 사이에 자산이"
  say "어느 원장에서도 쓸 수 없는 구간이 존재합니다."
  printf '\n'
  note "Contract 가 사라진 것은 아닙니다. 어느 원장에도 붙어 있지 않을 뿐입니다."
  note "애플리케이션은 이 구간을 '이동중'으로 다뤄야 합니다. Step 04 의 제안 구간과"
  note "같은 종류의 문제이고, 여기서는 Daml 이 아니라 Canton 이 만드는 구간입니다."
else
  warn "예상과 달리 성공했습니다."
  printf '\n'
  say "assignmentExclusivity 가 이미 지나서 Canton 이 현금을 euroclear 에 붙인"
  say "뒤였습니다. 결제가 그대로 진행되었습니다."
  printf '\n'
  note "보여주려던 것은 '이동중에는 쓸 수 없다' 였습니다. 7단계 직후에 바로 이"
  note "단계를 실행하면 거부되는 것을 볼 수 있습니다."
  note "다음 두 단계는 이미 끝난 일을 다시 시도하므로 실패로 표시됩니다."
fi

# ─── 9 ───────────────────────────────────────────────────────────────────────

title "Assign — 반대편 원장에 붙인다"
pause

printf '%s$ AssignCommand  reassignmentId=%s...%s\n\n' "$YE" "${RID:0:20}" "$R"
reassign "$CITI_API" alice-web "$ALICE" \
  "{\"command\":{\"AssignCommand\":{\"value\":{\"reassignmentId\":\"$RID\",\"source\":\"$DTCC\",\"target\":\"$EURO\"}}}}" \
  | pick JsAssignmentEvent "
if e:
    print('  target              ', e['target'].split('::')[0])
    print('  reassignmentCounter ', e['reassignmentCounter'])
    print('  contractId          ', e['createdEvent']['contractId'][:16])
else:
    print('  code:', d.get('code', '?'), d.get('cause', '')[:150])
"

printf '\n%s$ Alice 시점%s\n\n' "$YE" "$R"
show "$CITI_API" "$ALICE"

printf '\n'
say "원래 Contract ID: ${DIM}${CASH_CID:0:16}${R}"
printf '\n'
CASH_STATE=$(cid_state "$CITI_API" "$ALICE" "$CASH_CID")
case "$CASH_STATE" in
  JsActiveContract/euroclear) ok "같은 Contract ID 가 euroclear 에서 활성입니다" ;;
  "")                         warn "그 Contract 가 Alice 의 목록에 없습니다 (이미 소비되었습니다: $CASH_STATE)" ;;
  *)                          warn "예상과 다릅니다: $CASH_STATE" ;;
esac
printf '\n'
say "${B}Reassignment 는 소유권 이전이 아닙니다.${R} 새 Contract 를 만들지 않고,"
say "같은 Contract 를 다른 원장으로 옮깁니다. bank·owner·amount 는 그대로입니다."
printf '\n'
note "Step 03 의 '계약은 수정되지 않는다' 와 헷갈리기 쉽습니다. 거기서는 내용이"
note "바뀌므로 archive + create 였습니다. 여기서는 내용이 그대로이므로 같은"
note "Contract 가 유지됩니다. 바뀌는 것은 어느 원장이 이 Contract 를 관리하는가입니다."

# ─── 10 ──────────────────────────────────────────────────────────────────────

title "결제"
say "두 자산이 euroclear 에 모였습니다. 이제 Step 06 의 Settle 이 그대로 됩니다."
pause

printf '%s$ Settle  (synchronizerId = euroclear)%s\n\n' "$YE" "$R"
SET1=$(submit "$CITI_API" alice-web "[\"$ALICE\"]" \
  "[{\"ExerciseCommand\":{\"templateId\":\"$PROPT\",\"contractId\":\"$PROP_CID\",\"choice\":\"Settle\",\"choiceArgument\":{\"cashCid\":\"$CASH_CID\"}}}]" "$EURO")
printf '%s' "$SET1" | result
SET1_CODE=$(printf '%s' "$SET1" | jq_ 'print(d.get("code",""))')

wait_cid "$CITI_API" "$ALICE" Bond >/dev/null || true
printf '\n%s Alice%s\n' "$B" "$R"
show "$CITI_API" "$ALICE"
printf '\n%s GoldmanSachs%s\n' "$B" "$R"
show "$GS_API" "$GS"

printf '\n'
if [ -z "$SET1_CODE" ]; then
  ok "채권은 Alice 에게, 현금은 GoldmanSachs 에게 — 한 Transaction 에서"
else
  warn "결제가 거부되었습니다 ($SET1_CODE). 8단계에서 이미 결제가 끝났다면 정상입니다"
fi
printf '\n'
note "Daml 코드는 Step 06 과 완전히 같습니다. 원장이 둘이라는 사실은 Daml 에"
note "나타나지 않습니다. Template 에 Synchronizer 를 적는 자리가 없습니다."

# ─── 11 ──────────────────────────────────────────────────────────────────────

title "자동 재배정 (automatic reassignment) — 호출 3번이 1번으로"
say "방금 결제까지 오는 데 애플리케이션은 API 를 ${B}세 번${R} 불렀습니다."
say "  1) unassign   2) assign   3) Settle"
printf '\n'
say "Alice 를 호스팅하는 Participant 가 앞의 둘을 대신 해 줍니다. 이번에는"
say "아무것도 옮기지 않고 ${B}Settle 한 번만${R} 불러 봅니다."
pause

printf '%s$ Cash 500 on dtcc / Bond 5 on euroclear / ProposeDvp 500%s\n\n' "$YE" "$R"
submit "$CITI_API" citi-settlement "[\"$CITI\",\"$ALICE\"]" \
  "[{\"CreateCommand\":{\"templateId\":\"$CASH\",\"createArguments\":{\"bank\":\"$CITI\",\"owner\":\"$ALICE\",\"amount\":\"500.0\"}}}]" "$DTCC" >/dev/null
submit "$GS_API" gs-desk "[\"$GS\"]" \
  "[{\"CreateCommand\":{\"templateId\":\"$BOND\",\"createArguments\":{\"issuer\":\"$GS\",\"owner\":\"$GS\",\"isin\":\"US912810TN81\",\"quantity\":\"5.0\"}}}]" "$EURO" >/dev/null

CASH2=$(wait_cid "$CITI_API" "$ALICE" Cash) || die "두 번째 현금을 찾지 못했습니다"
BOND2=$(wait_cid "$GS_API"   "$GS"    Bond) || die "두 번째 채권을 찾지 못했습니다"

submit "$GS_API" gs-desk "[\"$GS\"]" \
  "[{\"ExerciseCommand\":{\"templateId\":\"$BOND\",\"contractId\":\"$BOND2\",\"choice\":\"ProposeDvp\",\"choiceArgument\":{\"buyer\":\"$ALICE\",\"price\":\"500.0\"}}}]" "$EURO" >/dev/null
PROP2=$(wait_cid "$CITI_API" "$ALICE" DvpProposal) || die "두 번째 제안이 도달하지 않았습니다"

printf '  현금  dtcc       %s\n' "${CASH2:0:16}"
printf '  제안  euroclear  %s\n' "${PROP2:0:16}"

printf '\n%s$ Settle — unassign/assign 없이 그대로%s\n\n' "$YE" "$R"
SET2=$(submit "$CITI_API" alice-web "[\"$ALICE\"]" \
  "[{\"ExerciseCommand\":{\"templateId\":\"$PROPT\",\"contractId\":\"$PROP2\",\"choice\":\"Settle\",\"choiceArgument\":{\"cashCid\":\"$CASH2\"}}}]" "$EURO")
printf '%s' "$SET2" | result
SET2_CODE=$(printf '%s' "$SET2" | jq_ 'print(d.get("code",""))')

sleep 2
printf '\n%s GoldmanSachs%s\n' "$B" "$R"
show "$GS_API" "$GS"

printf '\n'
if [ -z "$SET2_CODE" ]; then
  ok "성공했습니다. Participant 가 현금을 euroclear 로 옮긴 뒤 결제했습니다"
else
  warn "거부되었습니다: $SET2_CODE"
fi
printf '\n'
note "목록에 Bond 가 둘 보이는 것은 GoldmanSachs 가 발행사이기 때문입니다."
note "issuer 는 signatory 이므로 Alice 에게 넘어간 채권도 계속 보입니다 — Step 07 의"
note "가시성 이야기가 그대로 적용됩니다."
printf '\n'
say "이것이 ${B}자동 재배정 (automatic reassignment)${R} 입니다. 필요한 Contract 가"
say "다른 원장에 있으면 Participant 가 먼저 옮기고 Transaction 을 실행합니다."
printf '\n'
say "${B}전후 비교${R}"
cat <<'CMP'

                       수동 (7~10단계)                  자동 (이 단계)
    ─────────────────────────────────────────────────────────────────────
    앱의 API 호출       3번                             1번

      1              submit-and-wait-for-reassignment  ─┐
                       UnassignCommand                  │  Participant 가
      2              submit-and-wait-for-reassignment   │  대신 제출합니다
                       AssignCommand                   ─┘
      3              submit-and-wait                   submit-and-wait
                       Settle                            Settle

    원장 update        3개                             3개   ← 같습니다
    commandId          3개 (서로 다름)                  1개 (셋 다 같음)
    이동중 구간         있음                             있음   ← 없어지지 않습니다
    원자성              없음                             없음   ← 여전히 3개 Transaction

CMP
say "줄어드는 것은 ${B}앱과 Participant 사이의 왕복${R} 뿐입니다. 원장 쪽에서는"
say "아무것도 줄지 않습니다 — unassign, assign, Settle 이 그대로 세 번 일어납니다."
printf '\n'
note "앱이 reassignmentId 를 받아 두었다가 다음 호출에 넘길 필요가 없어지고, 어느"
note "Contract 가 어느 원장에 있는지 앱이 알 필요도 없어집니다. 그 두 가지가 자동"
note "재배정이 없애 주는 전부입니다."
printf '\n'
say "그렇다면 수동 Reassignment 는 왜 쓰는가:"
cat <<'WHY'

    결제 원장을 고르고 싶을 때     원장마다 수수료·규제·운영 주체가 다릅니다
    미리 옮겨 두고 싶을 때         결제 시점의 지연을 줄입니다
    이동 자체가 업무일 때          예탁 이관은 그 자체로 하나의 처리입니다

WHY
note "자동이든 수동이든 실행되는 것은 같은 unassign/assign 입니다. 제출자도 Alice 그대로고,"
note "Alice 가 그 한 번의 command 로 이미 준 권한을 쓰는 것입니다. 새 권한은 생기지 않습니다."

# ─── 12 ──────────────────────────────────────────────────────────────────────

title "확인한 것"
cat <<SUMMARY

  Synchronizer       Sequencer + Mediator 한 벌이 독립된 원장 하나입니다
  Contract 의 배정     모든 Contract 는 정확히 한 원장에 속합니다
  Transaction 의 범위  한 Transaction 은 한 원장 안에서 실행됩니다
  Reassignment       unassign / assign 두 단계로 원장 사이를 옮깁니다
  Contract ID        Reassignment 로 바뀌지 않습니다. 소유권 이전이 아닙니다
  원자성              Reassignment 는 원자적이지 않습니다. 이동중 구간이 있습니다
  자동 재배정          automatic reassignment. 앱의 호출만 3번에서 1번으로 줄입니다
                     원장 update 3개와 이동중 구간은 그대로입니다
  opt-in             다중 원장은 Participant 가 켜야 하고 Topology 에 남습니다

  ${B}확인하지 못한 것${R}

  Synchronizer 마다 다른 신뢰 구성 (참가자·수수료·프로토콜 버전)
  Reassignment 가 상대 Participant 의 연결에 막히는 경우
  원장 사이의 시간·순서 관계

SUMMARY

if [ "$KEEP" = 1 ]; then
  say "노드가 계속 실행 중입니다."
  note "  export DTCC='$DTCC'"
  note "  export EURO='$EURO'"
  note "  export CITI='$CITI'"
  note "  export ALICE='$ALICE'"
  note "  export GS='$GS'"
  note "  export PKG=$PKG"
  note "  citi JSON API          $CITI_API"
  note "  goldmansachs JSON API  $GS_API"
else
  say "노드를 종료합니다. 인메모리이므로 Party·User·Contract 가 모두 사라집니다."
  note "계속 살려두려면: ./steps/step08.sh --keep"
fi
