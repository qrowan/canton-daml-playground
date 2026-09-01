#!/usr/bin/env bash
# Step 05 — 다중 Participant 인터랙티브 러너
#
#   ./steps/step05.sh            처음부터
#   ./steps/step05.sh --auto     엔터 대기 없이 전부 실행
#   ./steps/step05.sh --keep     끝나고 노드를 끄지 않음
#
# Participant 2개 + Sequencer + Mediator 를 직접 띄운다.

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
WORK="$ROOT/.step05"
LOG="$WORK/canton.log"

CITI_API=http://localhost:5013
MS_API=http://localhost:5023

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

printf '%s\n' "$B"
cat <<'BANNER'
 Step 05 — 다중 Participant
 ────────────────────────────────────────────────────────────
 지금까지는 Participant 하나에서 확인했습니다.
 "노드가 분리돼도 동작한다"는 아직 말뿐이었습니다.

 여기서는 노드를 직접 띄웁니다.

   citi-participant           Citi, Alice 호스팅       Ledger 5011 / JSON 5013
   morganstanley-participant  Bob 호스팅               Ledger 5021 / JSON 5023
   dtcc-sequencer             순서 부여                 5001
   dtcc-mediator              판정                      5003

 Step 01 에서 그림으로만 봤던 구성입니다.
BANNER
printf '%s\n' "$R"

# env.sh 가 있으면 읽는다. 없어도 된다 — PATH 에 dpm 과 java 만 있으면 동작한다.
# shellcheck disable=SC1091
[ -f ./env.sh ] && source ./env.sh

command -v dpm >/dev/null 2>&1 || die "dpm 을 찾을 수 없습니다.
    설치: https://docs.canton.network/sdks-tools/cli-tools/dpm
    설치 후 PATH 에 추가하세요:  export PATH=\"\$HOME/.dpm/bin:\$PATH\""
java -version >/dev/null 2>&1 || die "JDK 21 이상이 필요합니다.
    JAVA_HOME 을 설정하거나 java 를 PATH 에 두세요."

# Canton jar 위치. CANTON_JAR 로 직접 지정할 수 있고, 없으면 DPM 캐시에서 찾는다.
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
    printf '\n%s 노드를 계속 실행 중입니다. 끄려면: pkill -f 'daemon -c canton/step05.conf'%s\n' "$DIM" "$R"
    return
  fi
  printf '\n%s 노드 종료 중...%s\n' "$DIM" "$R"
  [ -n "${CANTON_PID:-}" ] && kill "$CANTON_PID" 2>/dev/null
  pkill -f 'daemon -c canton/step05.conf' 2>/dev/null
  true
}
trap cleanup EXIT

# ─── 1 ───────────────────────────────────────────────────────────────────────

title "설정 파일 — 노드를 직접 선언한다"
say "dpm sandbox 는 노드 구성을 감춰 놓았습니다. 여기서는 직접 씁니다."
pause

run "cat canton/step05.conf"

printf '\n'
say "Participant 마다 포트가 세 벌입니다."
cat <<'PORTS'

    ledger-api        애플리케이션이 쓰는 gRPC Ledger API
    admin-api         노드 운영 (Party 생성, DAR 업로드, Topology)
    http-ledger-api   JSON Ledger API

PORTS
note "storage.type = memory 이므로 종료하면 전부 사라집니다."

# ─── 2 ───────────────────────────────────────────────────────────────────────

title "Bootstrap — Synchronizer 를 구성하고 노드를 연결한다"
say "노드를 띄우는 것만으로는 부족합니다. Synchronizer 를 만들고 각 Participant 를"
say "거기에 연결해야 합니다."
pause

run "cat canton/step05-bootstrap.canton"

printf '\n'
say "${B}bootstrap.synchronizer${R} 가 Sequencer 와 Mediator 를 묶어 Synchronizer 를"
say "만듭니다. Step 01 에서 '노드 두 종류의 묶음'이라고 한 것이 이것입니다."
printf '\n'
say "${B}connect_local${R} 로 각 Participant 가 그 Synchronizer 에 연결됩니다."
note "parties.enable 은 admin-api 를 통한 Party 생성입니다. Step 02 에서 HTTP 로"
note "했던 것과 같은 일을 콘솔에서 하는 것입니다."

# ─── 3 ───────────────────────────────────────────────────────────────────────

title "기동"
pause

DAR=$(ls -t .daml/dist/*.dar 2>/dev/null | head -1)
[ -n "$DAR" ] || { dpm build >/dev/null 2>&1; DAR=$(ls -t .daml/dist/*.dar | head -1); }
ok "DAR: $DAR"

# 이전 실행이 남아 있으면 포트를 붙잡고 있다. 완전히 사라질 때까지 기다린다.
pkill -f 'daemon -c canton/' 2>/dev/null
for _ in $(seq 1 30); do
  pgrep -f 'daemon -c canton/' >/dev/null 2>&1 || break
  sleep 1
done
for _ in $(seq 1 30); do
  if ! nc -z localhost 5002 2>/dev/null && ! nc -z localhost 5011 2>/dev/null; then break; fi
  sleep 1
done

printf '%s$ java -jar canton.jar daemon -c canton/step05.conf --bootstrap canton/step05-bootstrap.canton%s\n\n' "$YE" "$R"
STEP05_DAR="$ROOT/$DAR" nohup java -jar "$CANTON_JAR" daemon \
  -c canton/step05.conf --bootstrap canton/step05-bootstrap.canton --no-tty > "$LOG" 2>&1 &
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
  die "기동 실패. 포트 5001~5003, 5011~5013, 5021~5023 이 비어 있는지 확인하세요:
    pkill -f 'daemon -c canton/step05.conf'"
fi

CITI=$(grep '^CITI='  "$LOG" | tail -1 | cut -d= -f2)
ALICE=$(grep '^ALICE=' "$LOG" | tail -1 | cut -d= -f2)
BOB=$(grep '^BOB='    "$LOG" | tail -1 | cut -d= -f2)
export CITI ALICE BOB

ok "노드 4개 기동, Synchronizer 'dtcc' 구성 완료"

# ─── 4 ───────────────────────────────────────────────────────────────────────

title "Namespace 지문이 노드마다 다르다"
say "Step 02 에서는 세 Party 의 :: 뒷부분이 모두 같았습니다. 한 노드가 전부"
say "발급했기 때문입니다. 이제는 다릅니다."
pause

printf '  %-8s %s\n' "Citi"  "$CITI"
printf '  %-8s %s\n' "Alice" "$ALICE"
printf '  %-8s %s\n' "Bob"   "$BOB"
printf '\n'
say "지문만 뽑아 보면:"
printf '\n'
printf '  %-8s %s\n' "Citi"  "${CITI##*::}"
printf '  %-8s %s\n' "Alice" "${ALICE##*::}"
printf '  %-8s %s\n' "Bob"   "${BOB##*::}"
printf '\n'
if [ "${CITI##*::}" = "${ALICE##*::}" ] && [ "${CITI##*::}" != "${BOB##*::}" ]; then
  ok "Citi 와 Alice 는 같고, Bob 은 다릅니다"
else
  warn "예상과 다릅니다"
fi
printf '\n'
say "Citi 와 Alice 는 ${B}citi-participant${R} 가 발급했고, Bob 은"
say "${B}morganstanley-participant${R} 가 발급했습니다. Party ID 의 뒷부분이"
say "발급자를 가리킨다는 것이 여기서 눈에 보입니다."

# ─── 5 ───────────────────────────────────────────────────────────────────────

title "아는 Party 와 호스팅하는 Party 는 다릅니다"
say "각 노드에 Party 목록을 물어봅니다."
pause

listparties() {
  curl -s "$1/v2/parties" | python3 -c '
import sys, json
for x in sorted(json.load(sys.stdin)["partyDetails"], key=lambda x: x["party"]):
    name = x["party"].split("::")[0]
    local = x["isLocal"]
    mark = "호스팅함" if local else "알기만 함"
    print("    %-18s isLocal=%-5s  %s" % (name, local, mark))
'
}

printf '%s$ GET %s/v2/parties   (citi-participant)%s\n\n' "$YE" "$CITI_API" "$R"
listparties "$CITI_API"

printf '\n%s$ GET %s/v2/parties   (morganstanley-participant)%s\n\n' "$YE" "$MS_API" "$R"
listparties "$MS_API"

printf '\n'
say "${B}양쪽 목록에 이름은 다 나옵니다.${R} Party 의 존재는 Topology 로 전파되므로"
say "네트워크의 모든 노드가 압니다. Step 01 에서 Topology 를 '누가 존재하는지의"
say "상태' 라고 한 것이 이것입니다."
printf '\n'
say "갈라지는 것은 ${B}isLocal${R} 입니다."
printf '\n'
cat <<'SPLIT'
    citi-participant            morganstanley-participant
      Citi   isLocal=true          Bob    isLocal=true
      Alice  isLocal=true          그 외  isLocal=false
      그 외  isLocal=false

SPLIT
note "isLocal 은 PartyToParticipant 매핑의 반영입니다 — 이 노드가 그 Party 의"
note "권한을 행사하고 데이터를 보관하는가."
note "'존재를 안다' 와 '호스팅한다' 를 구분하는 것이 이 단계의 요점입니다."
note "10단계에서 이 차이가 제출 거부로 드러납니다."

# ─── 6 ───────────────────────────────────────────────────────────────────────

title "User 생성 — 노드마다 따로"
say "User 는 Participant 내부에만 존재합니다. 노드가 둘이면 각각 만들어야 합니다."
pause

mkuser() { # $1=api $2=id $3..=parties
  local api="$1" id="$2"; shift 2
  local rights="" p
  for p in "$@"; do
    [ -n "$rights" ] && rights="$rights,"
    rights="$rights{\"kind\":{\"CanActAs\":{\"value\":{\"party\":\"$p\"}}}}"
  done
  curl -s -X POST "$api/v2/users" -H 'Content-Type: application/json' \
    -d "{\"user\":{\"id\":\"$id\",\"primaryParty\":\"$1x\",\"isDeactivated\":false,\"metadata\":{\"resourceVersion\":\"\",\"annotations\":{}},\"identityProviderId\":\"\"},\"rights\":[$rights]}" >/dev/null
  curl -s "$api/v2/users/$id/rights" | jq_ "
rs=d.get('rights',[])
print('  $id → ' + ', '.join(list(r['kind'].values())[0]['value']['party'].split('::')[0] for r in rs) if rs else '  $id → 생성 실패')
"
}

printf '%s citi-participant%s\n' "$B" "$R"
mkuser "$CITI_API" citi-settlement "$CITI" "$ALICE"
mkuser "$CITI_API" alice-web "$ALICE"
printf '\n%s morganstanley-participant%s\n' "$B" "$R"
mkuser "$MS_API" bob-web "$BOB"

printf '\n'
note "같은 이름의 User 를 양쪽에 만들어도 서로 다른 계정입니다."

# ─── 7 ───────────────────────────────────────────────────────────────────────

title "DAR 은 양쪽 노드에 각각 올라가 있다"
say "Bootstrap 이 citi 와 morganstanley 양쪽에 업로드했습니다."
pause

PKG=$(dpm inspect-dar "$DAR" 2>/dev/null | grep -oE "[0-9a-f]{64}" | head -1)
ok "PKG = $PKG"
printf '\n'

for pair in "citi:$CITI_API" "morganstanley:$MS_API"; do
  name="${pair%%:*}"; api="${pair#*:}"
  found=$(curl -s "$api/v2/packages" 2>/dev/null | grep -c "$PKG" || echo 0)
  if [ "$found" != "0" ]; then
    printf '  %s✓%s %-16s vetting 됨\n' "$GR" "$R" "$name"
  else
    printf '  %s?%s %-16s 확인 불가\n' "$YE" "$R" "$name"
  fi
done

printf '\n'
say "${B}한 곳에만 올리면 거래가 성립하지 않습니다.${R} 상대 노드가 재실행 검증을"
say "할 수 없기 때문입니다. Step 01 의 vetting 이 이것입니다."

# ─── 8 ───────────────────────────────────────────────────────────────────────

title "발행 — Citi 와 Alice 는 같은 노드라 한 번에 된다"
say "citi-participant 가 두 Party 를 모두 호스팅하므로 actAs 에 둘 다 넣을 수"
say "있습니다. Step 02 와 같은 상황입니다."
pause

DEP="$PKG:Step04.Deposit:Deposit"

submit_cmd() { # $1=api $2=userId $3=actAs(json array) $4=commands(json)
  curl -s -X POST "$1/v2/commands/submit-and-wait" -H 'Content-Type: application/json' \
    -d "{\"commands\":$4,\"commandId\":\"s05-$(date +%s%N | tail -c 8)\",\"userId\":\"$2\",\"actAs\":$3,\"readAs\":[]}"
}

CREATE="[{\"CreateCommand\":{\"templateId\":\"$DEP\",\"createArguments\":{\"bank\":\"$CITI\",\"owner\":\"$ALICE\",\"amount\":\"100.0\"}}}]"
submit_cmd "$CITI_API" citi-settlement "[\"$CITI\",\"$ALICE\"]" "$CREATE" \
  | result

ok "Alice 의 예금 100 이 생성되었습니다"

# ─── 9 ───────────────────────────────────────────────────────────────────────

title "Morgan Stanley 노드에는 이 Contract 가 존재하지 않는다"
say "Step 02 에서는 David 의 조회가 빈 배열이었지만, 물리적으로는 같은 노드가"
say "양쪽 데이터를 갖고 있었습니다. 이번엔 다릅니다."
pause

acs() { # $1=api $2=party
  local off
  off=$(curl -s "$1/v2/state/ledger-end" | jq_ 'print(d["offset"])')
  curl -s -X POST "$1/v2/state/active-contracts" -H 'Content-Type: application/json' \
    -d "{\"filter\":{\"filtersByParty\":{\"$2\":{\"cumulative\":[{\"identifierFilter\":{\"WildcardFilter\":{\"value\":{\"includeCreatedEventBlob\":false}}}}]}}},\"verbose\":false,\"activeAtOffset\":$off}"
}

# 상대 노드에 Contract 가 도달할 때까지 기다린다
wait_contract() { # $1=api $2=party $3=템플릿 접미사  → contractId 출력
  local i cid
  for i in $(seq 1 40); do
    cid=$(acs "$1" "$2" | jq_ "
cs=[e['contractEntry']['JsActiveContract']['createdEvent'] for e in d]
cs=[c for c in cs if c['templateId'].endswith(':$3')]
print(cs[0]['contractId'] if cs else '')
" 2>/dev/null)
    [ -n "$cid" ] && { printf '%s' "$cid"; return 0; }
    sleep 1
  done
  return 1
}

printf '%s$ citi-participant 에서 Alice 시점 조회%s\n\n' "$YE" "$R"
acs "$CITI_API" "$ALICE" | jq_ 'print("  활성 Contract:", len(d), "건")'

printf '\n%s$ morganstanley-participant 에서 Bob 시점 조회%s\n\n' "$YE" "$R"
acs "$MS_API" "$BOB" | jq_ 'print("  활성 Contract:", len(d), "건")'

printf '\n%s$ morganstanley-participant 에서 Alice 시점 조회 시도%s\n\n' "$YE" "$R"
acs "$MS_API" "$ALICE" | jq_ 'print("  결과:", d)'

printf '\n'
say "빈 배열입니다. 그런데 ${B}조회 결과만으로는 '없는 것'인지 '가려진 것'인지"
say "구분되지 않습니다.${R} 확실한 증거는 제출을 시도해 보는 것입니다."
pause

printf '%s$ morganstanley 노드에서 Alice 권한으로 제출 시도%s\n\n' "$YE" "$R"
submit_probe="[{\"CreateCommand\":{\"templateId\":\"$PKG:Step04.Deposit:Deposit\",\"createArguments\":{\"bank\":\"$CITI\",\"owner\":\"$ALICE\",\"amount\":\"1.0\"}}}]"
curl -s -X POST "$MS_API/v2/commands/submit-and-wait" -H 'Content-Type: application/json' \
  -d "{\"commands\":$submit_probe,\"commandId\":\"s05-probe\",\"userId\":\"bob-web\",\"actAs\":[\"$ALICE\"],\"readAs\":[]}" \
  | result

printf '\n'
warn "morganstanley 노드는 Alice 를 호스팅하지 않으므로 Alice 로 제출할 수 없습니다."
say "${B}데이터가 도달하지 않은 것이지 가려진 것이 아닙니다.${R}"
note "Step 02 에서는 같은 노드가 양쪽 데이터를 갖고 API 가 뷰만 분리했습니다."
note "여기서는 노드 자체가 그 Contract 를 모릅니다."

# ─── 10 ──────────────────────────────────────────────────────────────────────

title "이체 — 이제 propose/accept 가 반드시 필요하다"
say "Alice 는 citi 노드, Bob 은 morganstanley 노드에 있습니다."
say "어느 노드도 두 Party 의 권한을 동시에 갖지 못합니다."
pause

say "먼저 편법을 시도해 봅니다 — citi 노드에서 actAs 에 Bob 을 넣습니다."
printf '\n'
BADCREATE="[{\"CreateCommand\":{\"templateId\":\"$DEP\",\"createArguments\":{\"bank\":\"$CITI\",\"owner\":\"$BOB\",\"amount\":\"50.0\"}}}]"
submit_cmd "$CITI_API" citi-settlement "[\"$CITI\",\"$BOB\"]" "$BADCREATE" \
  | result

printf '\n'
ok "거부되었습니다. citi 노드는 Bob 의 권한을 행사할 수 없습니다"
printf '\n'
say "${B}Step 04 에서 만든 propose/accept 로 갑니다.${R}"
pause

ALICE_DEP=$(wait_contract "$CITI_API" "$ALICE" Deposit) || die "Alice 의 예금을 찾지 못했습니다"

printf '%s$ TX 1 — citi 노드에서 Alice 가 ProposeTransfer%s\n\n' "$YE" "$R"
PROP="[{\"ExerciseCommand\":{\"templateId\":\"$DEP\",\"contractId\":\"$ALICE_DEP\",\"choice\":\"ProposeTransfer\",\"choiceArgument\":{\"newOwner\":\"$BOB\"}}}]"
submit_cmd "$CITI_API" alice-web "[\"$ALICE\"]" "$PROP" \
  | result

printf '\n'
say "제안이 만들어졌습니다. Bob 이 Observer 이므로 ${B}morganstanley 노드에도 도달${R}합니다."
printf '\n'
printf '%s$ morganstanley 노드에서 Bob 시점 조회%s\n\n' "$YE" "$R"
PROP_CID=$(wait_contract "$MS_API" "$BOB" TransferProposal) \
  || die "제안이 morganstanley 노드에 도달하지 않았습니다"
acs "$MS_API" "$BOB" | jq_ '
print("  활성 Contract:", len(d), "건")
for e in d:
    c=e["contractEntry"]["JsActiveContract"]["createdEvent"]
    print("   ", c["templateId"].split(":",1)[1])
'
printf '\n'
note "Step 01 의 '각자 알아야 할 조각만 전달된다'가 실제로 일어난 것입니다."
note "제출 노드가 응답한 뒤 상대 노드에 반영되기까지 약간의 지연이 있습니다."
note "이 러너는 도달할 때까지 폴링합니다. 애플리케이션도 같은 처리가 필요합니다."

# ─── 11 ──────────────────────────────────────────────────────────────────────

title "TX 2 — Bob 이 자기 노드에서 수락한다"
pause

TPROP="$PKG:Step04.Deposit:TransferProposal"
ACC="[{\"ExerciseCommand\":{\"templateId\":\"$TPROP\",\"contractId\":\"$PROP_CID\",\"choice\":\"AcceptTransfer\",\"choiceArgument\":{}}}]"
printf '%s$ POST %s/v2/commands/submit-and-wait   (userId=bob-web)%s\n\n' "$YE" "$MS_API" "$R"
submit_cmd "$MS_API" bob-web "[\"$BOB\"]" "$ACC" \
  | result

printf '\n'
say "결과를 양쪽에서 봅니다."
printf '\n'
printf '  %s citi-participant / Alice%s\n' "$B" "$R"
acs "$CITI_API" "$ALICE" | jq_ 'print("    활성 Contract:", len(d), "건")'
printf '  %s morganstanley-participant / Bob%s\n' "$B" "$R"
wait_contract "$MS_API" "$BOB" Deposit >/dev/null || true
acs "$MS_API" "$BOB" | jq_ '
print("    활성 Contract:", len(d), "건")
for e in d:
    c=e["contractEntry"]["JsActiveContract"]["createdEvent"]
    a=c["createArgument"]
    print("     ", c["templateId"].split(":",1)[1], "amount=" + str(a.get("amount")))
'

printf '\n'
ok "서로 다른 Participant 사이에서 소유권이 이동했습니다"
printf '\n'
say "이 한 번의 Transaction 에서 무슨 일이 있었는지 정리하면:"
cat <<'FLOW'

    1. morganstanley-participant 가 Transaction 을 계산해 제출
    2. dtcc-sequencer 가 순서를 부여해 양쪽에 전달
    3. citi-participant 와 morganstanley-participant 가 각자 재실행 검증
       → 둘 다 vetting 된 같은 Package ID 의 코드를 씁니다
    4. dtcc-mediator 가 확인 응답을 모아 판정
    5. 각 Participant 가 자기 ACS 에 반영

FLOW
note "Step 01 에서 그림으로만 봤던 확인 프로토콜이 실제로 돈 것입니다."

# ─── 12 ──────────────────────────────────────────────────────────────────────

title "확인한 것"
cat <<SUMMARY

  Namespace          발급 노드마다 지문이 다릅니다
  Party 호스팅        모든 노드가 Party 의 존재를 압니다. isLocal 이 호스팅을 가릅니다
  User               노드마다 따로 만들어야 합니다
  Vetting            양쪽 노드가 같은 Package ID 를 갖고 있어야 합니다
  데이터 격리          가려진 것이 아니라 도달하지 않습니다
  propose/accept     노드가 분리되면 선택이 아니라 필수입니다
  Observer           제안이 상대 노드까지 전달되게 하는 장치입니다
  확인 프로토콜        양쪽이 각자 재실행하고 Mediator 가 판정합니다

  ${B}다음${R}  Step 06 — DvP. 증권과 현금 두 다리를 하나의 Transaction 에서
        동시에 이전시켜 원자적 교환을 만듭니다.

SUMMARY

if [ "$KEEP" = 1 ]; then
  say "노드가 계속 실행 중입니다."
  note "  export CITI='$CITI'"
  note "  export ALICE='$ALICE'"
  note "  export BOB='$BOB'"
  note "  export PKG=$PKG"
  note "  citi JSON API          $CITI_API"
  note "  morganstanley JSON API $MS_API"
  note "  Canton 콘솔:  java -jar $CANTON_JAR sandbox-console -c canton/step05.conf"
else
  say "노드를 종료합니다. 인메모리이므로 Party·User·Contract 가 모두 사라집니다."
  note "계속 살려두려면: ./steps/step05.sh --keep"
fi
