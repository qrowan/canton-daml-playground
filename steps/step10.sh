#!/usr/bin/env bash
# Step 10 — 애플리케이션 연동 인터랙티브 러너
#
#   ./steps/step10.sh            처음부터
#   ./steps/step10.sh --auto     엔터 대기 없이 전부 실행
#   ./steps/step10.sh --keep     끝나고 노드를 끄지 않음
#
# 원장을 따라가는 애플리케이션을 40줄로 만들어 본다. 노드 구성은 Step 05 것을 쓴다.

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
TOTAL=11
WORK="$ROOT/.step10"
LOG="$WORK/canton.log"
SYNC="$WORK/ledger_sync.py"
STATE="$WORK/state.json"

API=http://localhost:5013

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

result() {
  jq_ '
if d.get("code"):
    print("  실패  " + d["code"])
    print("  cause:", d.get("cause", "")[:220])
else:
    print("  성공  updateId:", d.get("updateId", "")[:24])
'
}

printf '%s\n' "$B"
cat <<'BANNER'
 Step 10 — 애플리케이션 연동
 ────────────────────────────────────────────────────────────
 지금까지는 원장에 무엇을 쓸 수 있는지를 다뤘습니다. 이번에는
 그 위에 애플리케이션을 올립니다.

 애플리케이션은 원장의 현재 상태를 알아야 합니다. 잔액 화면을 그리려면
 매번 전부 조회할 수는 없고, 어딘가에 복제본을 두고 변경분만 따라가야
 합니다.

 그 복제본이 원장과 어긋나지 않게 하는 것이 이 Step 의 주제입니다.
 빠짐도 중복도 없이 따라가는 방법은 정해져 있습니다.
BANNER
printf '%s\n' "$R"

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
rm -f "$STATE"

cleanup() {
  if [ "$KEEP" = 1 ]; then
    printf '\n%s 노드를 계속 실행 중입니다. 끄려면: pkill -f '\''daemon -c canton/step05.conf'\''%s\n' "$DIM" "$R"
    return
  fi
  printf '\n%s 노드 종료 중...%s\n' "$DIM" "$R"
  [ -n "${CANTON_PID:-}" ] && kill "$CANTON_PID" 2>/dev/null
  pkill -f 'daemon -c canton/step05.conf' 2>/dev/null
  true
}
trap cleanup EXIT

# ─── 1 ───────────────────────────────────────────────────────────────────────

title "애플리케이션은 원장을 따라가야 합니다"
say "화면 하나를 그릴 때마다 원장 전체를 조회할 수는 없습니다. 애플리케이션은"
say "자기 쪽에 상태를 두고 변경분만 받아 갱신합니다."
printf '\n'
say "여기서 두 가지가 어긋날 수 있습니다."
cat <<'PROBLEM'

    빠짐     구독을 시작하기 전에 일어난 거래를 놓칩니다
    중복     이미 반영한 거래를 다시 받아 두 번 적용합니다

PROBLEM
say "둘 다 잔액이 틀리는 결과로 이어집니다. Canton 은 이것을 ${B}offset${R} 하나로"
say "해결합니다."

# ─── 2 ───────────────────────────────────────────────────────────────────────

title "기동"
say "Step 05 의 canton/step05.conf 를 그대로 씁니다. Daml 은 Step 04 의 Deposit 을"
say "씁니다."
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
    pkill -f 'daemon -c canton/'"
fi

CITI=$(grep  '^CITI='  "$LOG" | tail -1 | cut -d= -f2)
ALICE=$(grep '^ALICE=' "$LOG" | tail -1 | cut -d= -f2)
ok "노드 4개 기동"

PKG=$(dpm inspect-dar "$DAR" 2>/dev/null | grep -oE '[0-9a-f]{64}' | head -1)
DEP="$PKG:Step04.Deposit:Deposit"

curl -s -X POST "$API/v2/users" -H 'Content-Type: application/json' \
  -d "{\"user\":{\"id\":\"app\",\"primaryParty\":\"\",\"isDeactivated\":false,\"metadata\":{\"resourceVersion\":\"\",\"annotations\":{}},\"identityProviderId\":\"\"},\"rights\":[{\"kind\":{\"CanActAs\":{\"value\":{\"party\":\"$CITI\"}}}},{\"kind\":{\"CanActAs\":{\"value\":{\"party\":\"$ALICE\"}}}}]}" >/dev/null

# ─── 헬퍼 ────────────────────────────────────────────────────────────────────

submit() { # $1=commandId $2=commands(json)
  curl -s -X POST "$API/v2/commands/submit-and-wait" -H 'Content-Type: application/json' \
    -d "{\"commands\":$2,\"commandId\":\"$1\",\"userId\":\"app\",\"actAs\":[\"$CITI\",\"$ALICE\"],\"readAs\":[]}"
}

deposit_cmd() { # $1=amount
  printf '[{"CreateCommand":{"templateId":"%s","createArguments":{"bank":"%s","owner":"%s","amount":"%s"}}}]' \
    "$DEP" "$CITI" "$ALICE" "$1"
}

ledger_end() { curl -s "$API/v2/state/ledger-end" | jq_ 'print(d["offset"])'; }

sync() { python3 "$SYNC" "$API" "$ALICE" "$STATE" "$@"; }

# 애플리케이션 쪽 코드를 파일로 남깁니다. 이 Step 에서 계속 이것을 부릅니다.
cat > "$SYNC" <<'PYEOF'
"""원장을 따라가는 최소 애플리케이션.

  snapshot   현재 ACS 를 통째로 받아 복제본을 만든다. 기준 offset 을 함께 저장한다
  catchup    저장된 offset 다음부터 업데이트를 받아 복제본에 적용한다
  show       복제본을 출력한다
  verify     복제본과 원장을 대조한다
"""
import json, sys, urllib.request

API, PARTY, STATE, CMD = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

def post(path, body):
    req = urllib.request.Request(API + path, method="POST",
                                 data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        return json.load(e)

def get(path):
    with urllib.request.urlopen(API + path) as r:
        return json.load(r)

FILTER = {"filtersByParty": {PARTY: {"cumulative": [
    {"identifierFilter": {"WildcardFilter": {"value": {"includeCreatedEventBlob": False}}}}]}},
    "verbose": False}

def ledger_end():
    return get("/v2/state/ledger-end")["offset"]

def acs_at(offset):
    rows = post("/v2/state/active-contracts",
                {"filter": FILTER, "verbose": False, "activeAtOffset": offset})
    out = {}
    for e in rows:
        entry = e["contractEntry"]
        if "JsActiveContract" not in entry:
            continue                                  # 이동 중 등은 활성이 아니다
        c = entry["JsActiveContract"]["createdEvent"]
        out[c["contractId"]] = c["createArgument"]["amount"]
    return out

def update_at(offset):
    d = post("/v2/updates/update-by-offset", {"offset": offset, "updateFormat": {
        "includeTransactions": {"eventFormat": FILTER,
                                "transactionShape": "TRANSACTION_SHAPE_ACS_DELTA"}}})
    if "code" in d:
        return None                                   # 그 offset 에 우리 몫이 없다
    u = d["update"]
    v = u[list(u)[0]]
    return v.get("value", v)

def load():
    with open(STATE) as f:
        return json.load(f)

def save(s):
    with open(STATE, "w") as f:
        json.dump(s, f, indent=2)

if CMD == "snapshot":
    off = ledger_end()                                # 먼저 기준점을 고정하고
    save({"offset": off, "contracts": acs_at(off)})   # 그 시점의 상태를 받는다
    print(f"snapshot  offset={off}  contracts={len(acs_at(off))}")

elif CMD == "catchup":
    s = load()
    frm, to = s["offset"] + 1, ledger_end()           # 저장한 다음 칸부터
    applied = 0
    for off in range(frm, to + 1):
        u = update_at(off)
        if u is None:
            continue
        for e in u.get("events", []):
            kind = list(e)[0]
            ev = e[kind]
            ev = ev.get("value", ev)
            if kind.endswith("ArchivedEvent"):
                s["contracts"].pop(ev["contractId"], None)
            elif kind.endswith("CreatedEvent"):
                s["contracts"][ev["contractId"]] = ev["createArgument"]["amount"]
            applied += 1
        print(f"  off {off:>3}  {u.get('updateId','')[:16]}  events={len(u.get('events', []))}")
    s["offset"] = to                                  # 어디까지 반영했는지 남긴다
    save(s)
    print(f"catchup   {frm}..{to}  적용 {applied}건  contracts={len(s['contracts'])}")

elif CMD == "show":
    s = load()
    print(f"  복제본 offset = {s['offset']}")
    for cid, amt in sorted(s["contracts"].items(), key=lambda kv: float(kv[1])):
        print(f"    {cid[:14]}  {float(amt):>10,.2f}")
    total = sum(float(v) for v in s["contracts"].values())
    print(f"    합계{'':<10} {total:>12,.2f}")   # 한글은 두 칸을 차지한다

elif CMD == "verify":
    s = load()
    live = acs_at(s["offset"])                        # 같은 offset 기준으로 대조한다
    if live == s["contracts"]:
        print(f"  일치  {len(live)}건")
    else:
        print(f"  불일치  복제본 {len(s['contracts'])}건 / 원장 {len(live)}건")
        for cid in set(live) ^ set(s["contracts"]):
            print(f"    차이 {cid[:14]}")
        sys.exit(1)
PYEOF

# ─── 3 ───────────────────────────────────────────────────────────────────────

title "offset — 원장의 위치"
say "원장에 무언가 일어날 때마다 번호가 하나씩 올라갑니다. 그 번호가 offset 입니다."
pause

run "curl -s $API/v2/state/ledger-end"
printf '\n\n'

say "이 번호는 ${B}이 Participant 가 본 원장의 끝${R}을 가리킵니다. 애플리케이션이"
say "어디까지 반영했는지 기록해 두는 자리이기도 합니다."
printf '\n'
note "offset 은 Participant 마다 다릅니다. 각자 받은 것만 세기 때문입니다."
note "Step 05 에서 두 노드가 서로 다른 것을 본다고 한 것이 여기에도 적용됩니다."

# ─── 4 ───────────────────────────────────────────────────────────────────────

title "예금 3건을 만들고 스냅샷을 뜹니다"
pause

printf '%s$ 예금 10 / 20 / 30 생성%s\n\n' "$YE" "$R"
for amt in 10.0 20.0 30.0; do
  submit "seed-$amt" "$(deposit_cmd $amt)" | result
done

sleep 2
printf '\n%s$ python3 ledger_sync.py … snapshot%s\n\n' "$YE" "$R"
sync snapshot | sed 's/^/  /'
printf '\n'
sync show

printf '\n'
say "${B}스냅샷과 offset 은 한 쌍입니다.${R} 코드에서 순서가 중요합니다."
cat <<'ORDER'

    off = ledger_end()          ← 먼저 기준점을 고정하고
    acs = acs_at(off)           ← 그 시점의 상태를 받는다

ORDER
note "반대로 하면 — 상태를 먼저 받고 나중에 offset 을 읽으면 — 그 사이에 일어난"
note "거래를 두 번 적용하게 됩니다. activeAtOffset 을 지정하는 이유입니다."

# ─── 5 ───────────────────────────────────────────────────────────────────────

title "스냅샷 이후에 원장이 움직입니다"
say "애플리케이션이 잠깐 다른 일을 하는 동안 예금 2건이 더 생기고, 1건에서"
say "인출이 일어납니다."
pause

printf '%s$ 예금 40 / 50 생성%s\n\n' "$YE" "$R"
submit "more-40" "$(deposit_cmd 40.0)" | result
submit "more-50" "$(deposit_cmd 50.0)" | result

sleep 2
CID20=$(curl -s -X POST "$API/v2/state/active-contracts" -H 'Content-Type: application/json' \
  -d "{\"filter\":{\"filtersByParty\":{\"$ALICE\":{\"cumulative\":[{\"identifierFilter\":{\"WildcardFilter\":{\"value\":{\"includeCreatedEventBlob\":false}}}}]}}},\"verbose\":false,\"activeAtOffset\":$(ledger_end)}" \
  | jq_ '
cs=[e["contractEntry"]["JsActiveContract"]["createdEvent"] for e in d if "JsActiveContract" in e["contractEntry"]]
cs=[c for c in cs if c["createArgument"]["amount"].startswith("20.")]
print(cs[0]["contractId"] if cs else "")')

printf '\n%s$ 20 짜리 예금에서 3 인출%s\n\n' "$YE" "$R"
submit "wd-3" "[{\"ExerciseCommand\":{\"templateId\":\"$DEP\",\"contractId\":\"$CID20\",\"choice\":\"Withdraw\",\"choiceArgument\":{\"requested\":\"3.0\"}}}]" | result

sleep 2
printf '\n'
say "복제본은 아직 모릅니다."
printf '\n'
sync show
printf '\n'
printf '  원장의 현재 offset = %s\n' "$(ledger_end)"

# ─── 6 ───────────────────────────────────────────────────────────────────────

title "따라잡기 — 저장한 offset 다음부터"
say "복제본에 적힌 offset 다음 칸부터 원장 끝까지 훑어 적용합니다."
pause

printf '%s$ python3 ledger_sync.py … catchup%s\n\n' "$YE" "$R"
sync catchup | sed 's/^/  /'

printf '\n'
sync show

printf '\n'
say "인출이 들어간 자리를 보면 ${B}20 이 사라지고 17 이 생겼습니다.${R}"
say "Step 03 의 '계약은 수정되지 않는다' 가 그대로 업데이트에 나타난 것입니다."
printf '\n'
cat <<'EVENTS'

    한 Transaction 안에서
      ArchivedEvent   20 짜리 Contract 를 소비
      CreatedEvent    17 짜리 Contract 를 생성

EVENTS
note "애플리케이션이 하는 일은 이 두 가지뿐입니다 — Archived 면 지우고,"
note "Created 면 넣습니다. 40줄짜리 ledger_sync.py 의 전부가 그것입니다."

# ─── 7 ───────────────────────────────────────────────────────────────────────

title "검증 — 복제본과 원장이 같은가"
say "복제본에 적힌 offset 을 기준으로 원장에 다시 물어 대조합니다."
pause

printf '%s$ python3 ledger_sync.py … verify%s\n\n' "$YE" "$R"
if sync verify; then
  printf '\n'
  ok "스냅샷 + 업데이트 재생 = 현재 상태"
else
  printf '\n'
  die "복제본이 원장과 어긋났습니다"
fi

printf '\n'
say "${B}이것이 원장 연동의 전부입니다.${R} 스냅샷을 한 번 뜨고, 그 다음부터는"
say "업데이트만 받아 적용합니다. 다시 전체 조회할 일이 없습니다."

# ─── 8 ───────────────────────────────────────────────────────────────────────

title "재시작 — 저장한 offset 이 있으면 이어붙입니다"
say "애플리케이션이 죽었다가 살아나는 상황입니다. 그 사이 원장은 계속 움직입니다."
pause

printf '%s$ 애플리케이션이 내려간 동안 예금 60 생성%s\n\n' "$YE" "$R"
submit "while-down" "$(deposit_cmd 60.0)" | result
sleep 2

printf '\n'
say "다시 올라왔습니다. 복제본 파일이 남아 있으므로 스냅샷을 다시 뜨지 않습니다."
printf '\n'
run "cat $WORK/state.json | head -6"
printf '\n'
printf '%s$ python3 ledger_sync.py … catchup%s\n\n' "$YE" "$R"
sync catchup | sed 's/^/  /'
printf '\n'
sync show
printf '\n'
printf '%s$ verify%s\n\n' "$YE" "$R"
sync verify

printf '\n'
ok "빠진 것도 두 번 적용된 것도 없습니다"
printf '\n'
note "복제본과 offset 을 같은 트랜잭션으로 저장하는 것이 중요합니다. 상태만 쓰고"
note "offset 을 못 쓴 채 죽으면 재시작 때 같은 업데이트를 다시 적용합니다."
note "그래서 실무에서는 두 값을 같은 DB 트랜잭션에 넣습니다."

# ─── 9 ───────────────────────────────────────────────────────────────────────

title "쓰기 쪽 — 같은 명령을 두 번 보내면"
say "읽기만 문제가 아닙니다. 제출한 뒤 응답을 못 받으면 애플리케이션은 다시"
say "보내야 할지 판단해야 합니다."
pause

printf '%s$ commandId 를 그대로 두고 재제출%s\n\n' "$YE" "$R"
submit "more-40" "$(deposit_cmd 40.0)" | result

printf '\n'
ok "거부되었습니다. 예금 40 이 두 개 생기지 않았습니다"
printf '\n'
say "${B}commandId 가 중복 제거의 열쇠입니다.${R} 같은 userId·actAs·commandId 로"
say "다시 제출하면 원장이 걸러 냅니다."
printf '\n'
cat <<'RETRY'

    응답을 못 받았을 때
      같은 commandId 로 재시도       안전합니다. 두 번 실행되지 않습니다
      새 commandId 로 재시도         위험합니다. 두 번 실행될 수 있습니다

RETRY
note "commandId 는 애플리케이션이 정합니다. 주문번호처럼 업무상 의미가 있는 값을"
note "쓰면 재시도 판단이 쉬워집니다."
note "중복 제거에는 기한이 있습니다. 그 기간이 지나면 같은 commandId 도 통과합니다."

# ─── 10 ──────────────────────────────────────────────────────────────────────

title "애플리케이션이 저장하면 안 되는 것"
pause

sync show

printf '\n'
say "복제본의 키는 ${B}Contract ID${R} 입니다. 그런데 인출 한 번에 20 짜리 ID 가"
say "사라지고 17 짜리 ID 가 새로 생겼습니다."
printf '\n'
cat <<'IDS'

    Contract ID     매 변경마다 바뀝니다. 외부 시스템의 키로 쓰면 안 됩니다
    offset          애플리케이션이 저장해야 하는 값입니다
    commandId       애플리케이션이 만들고 저장해야 하는 값입니다

IDS
say "업무 키가 필요하면 ${B}Template 필드로 직접 넣어야 합니다${R} — 계좌번호,"
say "주문번호 같은 것을 계약 내용에 담아 두고 그것으로 찾습니다."
printf '\n'
note "Step 03 에서 '계약 ID 를 외부 시스템에 저장하면 곧 무효가 된다' 고 한 것이"
note "여기서 실제 문제로 드러납니다."

# ─── 11 ──────────────────────────────────────────────────────────────────────

title "확인한 것"
cat <<SUMMARY

  offset             원장의 위치. 애플리케이션이 어디까지 반영했는지의 기준입니다
  스냅샷과 offset      한 쌍입니다. 먼저 offset 을 고정하고 그 시점의 ACS 를 받습니다
  따라잡기            저장한 offset 다음 칸부터 원장 끝까지 적용합니다
  적용 규칙           Archived 면 지우고 Created 면 넣습니다. 그것이 전부입니다
  재시작              offset 이 남아 있으면 스냅샷을 다시 뜨지 않습니다
  저장 원자성          상태와 offset 을 같은 트랜잭션에 씁니다
  commandId          같은 값으로 재시도하면 중복 실행되지 않습니다
  Contract ID        외부 키로 쓰면 안 됩니다. 업무 키는 Template 필드에 둡니다

  ${B}확인하지 못한 것${R}

  스트리밍 구독 — 이 러너는 offset 을 하나씩 조회했습니다. 실제 애플리케이션은
  gRPC 스트림이나 JSON API 의 WebSocket 으로 밀어 받습니다. 받은 뒤 적용하는
  규칙은 같습니다
  여러 Party 를 한 애플리케이션이 따라가는 경우
  ACS 가 큰 경우의 분할 조회

SUMMARY

if [ "$KEEP" = 1 ]; then
  say "노드가 계속 실행 중입니다."
  note "  export CITI='$CITI'"
  note "  export ALICE='$ALICE'"
  note "  export PKG=$PKG"
  note "  JSON API      $API"
  note "  동기화 코드    $SYNC"
  note "  복제본        $STATE"
else
  say "노드를 종료합니다. 인메모리이므로 Party·User·Contract 가 모두 사라집니다."
  note "계속 살려두려면: ./steps/step10.sh --keep"
fi
