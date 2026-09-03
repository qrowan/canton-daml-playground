#!/usr/bin/env bash
# Step 09 — 업그레이드 인터랙티브 러너
#
#   ./steps/step09.sh            처음부터
#   ./steps/step09.sh --auto     엔터 대기 없이 전부 실행
#   ./steps/step09.sh --keep     끝나고 노드를 끄지 않음
#
# 배포된 Template 의 새 버전을 만들고 원장에 올린다. 노드 구성은 Step 05 것을 쓴다.

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
WORK="$ROOT/.step09"
LOG="$WORK/canton.log"

CITI_API=http://localhost:5013
MS_API=http://localhost:5023

V1="$ROOT/upgrade/v1"
V2="$ROOT/upgrade/v2"
DAR1="$V1/.daml/dist/step09-voucher-1.0.0.dar"
DAR2="$V2/.daml/dist/step09-voucher-2.0.0.dar"

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
    print("  cause:", d.get("cause", "")[:220])
else:
    print("  성공  updateId:", d.get("updateId", "")[:24])
'
}

printf '%s\n' "$B"
cat <<'BANNER'
 Step 09 — 업그레이드
 ────────────────────────────────────────────────────────────
 Step 03 에서 확인했습니다. Contract 는 수정되지 않습니다.
 그런데 Template 자체를 고쳐야 하면 어떻게 되는가.

 이미 원장에 수천 건이 살아 있고, 상대 기관은 옛 코드를 돌리고 있습니다.
 전부 멈추고 다시 시작할 수는 없습니다.

 Daml 은 이것을 패키지 버전으로 다룹니다. 여기서는 상품권 Template 에
 유효기간 필드를 추가해 봅니다.

   upgrade/v1     step09-voucher 1.0.0
   upgrade/v2     step09-voucher 2.0.0

 노드 구성은 Step 05 의 것을 그대로 씁니다 — citi, morganstanley,
 그리고 Synchronizer 하나. 이 Step 에서 달라지는 것은 패키지뿐입니다.
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

title "고칠 수 없는 것을 고쳐야 할 때"
say "Step 03 에서 Contract 는 수정되지 않는다고 했습니다. archive 하고 새로 만들"
say "뿐입니다. 그런데 그것은 ${B}같은 Template 안에서${R}의 이야기였습니다."
printf '\n'
say "Template 에 필드를 하나 추가해야 하면 사정이 다릅니다."
cat <<'PROBLEM'

    이미 원장에 있는 것    v1 코드로 만들어진 Contract 수천 건
    상대 기관              아직 v1 만 갖고 있습니다
    바꾸고 싶은 것         필드 하나 추가

PROBLEM
say "Package ID 는 내용의 해시입니다. 한 글자만 고쳐도 완전히 다른 패키지가 되고,"
say "원장에 있는 Contract 는 옛 Package ID 를 가리킨 채 남습니다."
printf '\n'
note "그래서 업그레이드는 '코드를 덮어쓰는 일'이 아니라 '두 버전을 공존시키는 일'입니다."

# ─── 2 ───────────────────────────────────────────────────────────────────────

title "패키지를 둘로 나눈다"
say "업그레이드는 같은 패키지 안에서 일어나지 않습니다. ${B}이름이 같고 버전이 다른"
say "두 패키지${R}가 필요합니다. 그래서 daml.yaml 도 둘입니다."
pause

run "cat upgrade/v1/daml.yaml"
printf '\n'
run "cat upgrade/v2/daml.yaml"

printf '\n'
say "차이는 두 줄입니다."
cat <<'DIFF'

    version:   1.0.0  →  2.0.0
    upgrades:  (없음)  →  ../v1/.daml/dist/step09-voucher-1.0.0.dar

DIFF
say "${B}name 은 같아야 합니다.${R} Daml 은 package name 이 같고 version 이 높은"
say "패키지를 후속 버전으로 봅니다. 이름이 다르면 그냥 남남입니다."
printf '\n'
note "upgrades 는 컴파일러에게 '무엇의 후속인지' 알려줍니다. 이 줄이 있어야"
note "업그레이드 규칙 검사가 돕니다. 비워 두면 검사 없이 그냥 빌드됩니다."
note "저장소 루트의 daml.yaml 과는 별개의 패키지이므로 daml/ 밖에 두었습니다."

# ─── 3 ───────────────────────────────────────────────────────────────────────

title "v1 — 지금 배포되어 있는 코드"
pause

run "cat upgrade/v1/daml/Voucher.daml"

printf '\n'
printf '%s$ cd upgrade/v1 && dpm build%s\n\n' "$YE" "$R"
DAML_PACKAGE="$V1" dpm build 2>&1 | grep -E 'Created|error' || die "v1 빌드 실패"
PKG1=$(dpm inspect-dar "$DAR1" 2>/dev/null | grep -oE '[0-9a-f]{64}' | head -1)
printf '\n'
ok "v1 Package ID = $PKG1"

# ─── 4 ───────────────────────────────────────────────────────────────────────

title "기동 — 그리고 v1 을 양쪽 노드에 올린다"
say "Step 05 의 canton/step05.conf 를 그대로 씁니다. 이번에는 DAR 을 bootstrap 에서"
say "올리지 않고, 러너가 ${B}JSON Ledger API 로${R} 올립니다."
pause

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
nohup java -jar "$CANTON_JAR" daemon \
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
BOB=$(grep   '^BOB='   "$LOG" | tail -1 | cut -d= -f2)
ok "노드 4개 기동"

upload() { # $1=api $2=dar
  curl -s -o /dev/null -w '%{http_code}' -X POST "$1/v2/packages" \
    -H 'Content-Type: application/octet-stream' --data-binary @"$2"
}

printf '\n%s$ POST /v2/packages   (DAR 을 그대로 본문에 싣습니다)%s\n\n' "$YE" "$R"
printf '  citi           HTTP %s\n' "$(upload "$CITI_API" "$DAR1")"
printf '  morganstanley  HTTP %s\n' "$(upload "$MS_API"  "$DAR1")"

printf '\n'
say "Step 05 에서는 bootstrap 콘솔로 올렸습니다. 운영 중인 노드에는 이렇게"
say "Ledger API 로 올립니다. 노드를 멈추지 않습니다."
printf '\n'
note "업로드는 vetting 까지 포함합니다. Step 05 에서 본 그것입니다 —"
note "이 노드가 이 코드로 검증에 참여하겠다고 Topology 에 선언하는 것입니다."

# ─── 헬퍼 ────────────────────────────────────────────────────────────────────

mkuser() { # $1=api $2=id $3=party
  curl -s -X POST "$1/v2/users" -H 'Content-Type: application/json' \
    -d "{\"user\":{\"id\":\"$2\",\"primaryParty\":\"\",\"isDeactivated\":false,\"metadata\":{\"resourceVersion\":\"\",\"annotations\":{}},\"identityProviderId\":\"\"},\"rights\":[{\"kind\":{\"CanActAs\":{\"value\":{\"party\":\"$3\"}}}}]}" >/dev/null
}

submit() { # $1=api $2=userId $3=party $4=commands(json)
  curl -s -X POST "$1/v2/commands/submit-and-wait" -H 'Content-Type: application/json' \
    -d "{\"commands\":$4,\"commandId\":\"s09-$RANDOM$RANDOM\",\"userId\":\"$2\",\"actAs\":[\"$3\"],\"readAs\":[]}"
}

acs() { # $1=api $2=party
  local off
  off=$(curl -s "$1/v2/state/ledger-end" | jq_ 'print(d["offset"])')
  curl -s -X POST "$1/v2/state/active-contracts" -H 'Content-Type: application/json' \
    -d "{\"filter\":{\"filtersByParty\":{\"$2\":{\"cumulative\":[{\"identifierFilter\":{\"WildcardFilter\":{\"value\":{\"includeCreatedEventBlob\":false}}}}]}}},\"verbose\":false,\"activeAtOffset\":$off}"
}

# 어느 버전으로 저장되어 있는지까지 보여줍니다.
show() { # $1=api $2=party
  acs "$1" "$2" | PKG1="$PKG1" PKG2="${PKG2:-}" jq_ '
import os
ver = {os.environ["PKG1"]: "v1", os.environ.get("PKG2", "-"): "v2"}
if not d:
    print("    (없음)")
for e in d:
    c = e["contractEntry"]["JsActiveContract"]["createdEvent"]
    a = c["createArgument"]
    rp = c.get("representativePackageId", "")
    v = ver.get(rp, rp[:8])
    exp = a.get("expiresAt")
    text = exp if exp is not None else ("(v1 에 없는 필드)" if v == "v1" else "None")
    print("    %-4s %-16s amount=%-8s expiresAt=%s" % (
        v, c["contractId"][:14],
        a.get("amount", "?").rstrip("0").rstrip("."), text))
'
}

find_cid() { # $1=api $2=party $3=amount 접두
  local i cid
  for i in $(seq 1 30); do
    cid=$(acs "$1" "$2" | jq_ "
cs=[e['contractEntry']['JsActiveContract']['createdEvent'] for e in d if 'JsActiveContract' in e['contractEntry']]
cs=[c for c in cs if c['createArgument'].get('amount','').startswith('$3')]
print(cs[0]['contractId'] if cs else '')" 2>/dev/null)
    [ -n "$cid" ] && { printf '%s' "$cid"; return 0; }
    sleep 1
  done
  return 1
}

mkuser "$CITI_API" citi-app  "$CITI"
mkuser "$CITI_API" alice-web "$ALICE"
mkuser "$MS_API"   bob-web   "$BOB"

# ─── 5 ───────────────────────────────────────────────────────────────────────

title "v1 로 상품권을 발행한다"
say "Citi 가 Alice 와 Bob 에게 각각 발행합니다. Bob 은 morganstanley 노드에"
say "있지만 상품권은 발행사 단독 서명이므로 한 Transaction 으로 됩니다."
pause

VT1="$PKG1:Voucher:Voucher"

printf '%s$ Alice 앞으로 50%s\n\n' "$YE" "$R"
submit "$CITI_API" citi-app "$CITI" \
  "[{\"CreateCommand\":{\"templateId\":\"$VT1\",\"createArguments\":{\"issuer\":\"$CITI\",\"owner\":\"$ALICE\",\"amount\":\"50.0\"}}}]" | result

printf '\n%s$ Bob 앞으로 70%s\n\n' "$YE" "$R"
submit "$CITI_API" citi-app "$CITI" \
  "[{\"CreateCommand\":{\"templateId\":\"$VT1\",\"createArguments\":{\"issuer\":\"$CITI\",\"owner\":\"$BOB\",\"amount\":\"70.0\"}}}]" | result

OLD_CID=$(find_cid "$CITI_API" "$ALICE" 50) || die "Alice 의 상품권을 찾지 못했습니다"

printf '\n%s$ Alice 시점%s\n\n' "$YE" "$R"
show "$CITI_API" "$ALICE"

printf '\n'
say "${B}expiresAt 필드가 아예 없습니다.${R} v1 Template 에 그런 필드가 없기"
say "때문입니다. 이것이 잠시 뒤 업그레이드의 대상이 됩니다."

# ─── 6 ───────────────────────────────────────────────────────────────────────

title "v2 — 유효기간을 붙인다"
pause

run "sed -n '/^module/,\$p' upgrade/v2/daml/Voucher.daml"

printf '\n'
say "v1 에서 바꾼 것은 셋입니다."
cat <<'CHANGES'

    expiresAt : Optional Time     새 필드. Optional 이고 맨 뒤
    Redeem                        만료 검사를 넣었습니다
    SetExpiry                     새 Choice

CHANGES
printf '%s$ cd upgrade/v2 && dpm build%s\n\n' "$YE" "$R"
DAML_PACKAGE="$V2" dpm build 2>&1 | grep -E 'Created|error' || die "v2 빌드 실패"
PKG2=$(dpm inspect-dar "$DAR2" 2>/dev/null | grep -oE '[0-9a-f]{64}' | head -1)
printf '\n'
ok "v2 Package ID = $PKG2"
printf '\n'
say "v1 과 ${B}완전히 다른 Package ID${R} 입니다. 같은 이름의 다음 버전이라는 사실은"
say "ID 가 아니라 패키지 안에 적힌 name 과 version 이 말해 줍니다."

# ─── 7 ───────────────────────────────────────────────────────────────────────

title "컴파일러가 막는 것"
say "upgrades 를 적어 두면 v2 를 빌드할 때 규칙 검사가 돕니다. 실제로 어겨 봅니다."
pause

BROKEN="$WORK/broken"
rm -rf "$BROKEN"; mkdir -p "$BROKEN/daml"
sed 's|\.\./v1/|../../upgrade/v1/|' "$V2/daml.yaml" > "$BROKEN/daml.yaml"

break_it() { # $1=설명   stdin=Voucher.daml 내용
  cat > "$BROKEN/daml/Voucher.daml"
  printf '\n%s── %s%s\n' "$B" "$1" "$R"
  DAML_PACKAGE="$BROKEN" dpm build 2>&1 \
    | sed 's/\x1b\[[0-9;]*m//g' \
    | grep -iE 'error type checking|^ +(The|Field|Choice)' | head -4 \
    | sed 's/^/    /'
}

BODY='  where
    signatory issuer
    observer owner
    choice Redeem : ()
      controller owner
      do pure ()'

break_it "새 필드를 Optional 이 아니게" <<EOF
module Voucher where
template Voucher
  with
    issuer : Party
    owner : Party
    amount : Decimal
    expiresAt : Time
$BODY
EOF

break_it "새 필드를 중간에 끼워넣기" <<EOF
module Voucher where
template Voucher
  with
    issuer : Party
    expiresAt : Optional Time
    owner : Party
    amount : Decimal
$BODY
EOF

break_it "기존 필드 제거" <<EOF
module Voucher where
template Voucher
  with
    issuer : Party
    owner : Party
$BODY
EOF

break_it "기존 필드 타입 변경" <<EOF
module Voucher where
template Voucher
  with
    issuer : Party
    owner : Party
    amount : Int
$BODY
EOF

break_it "Choice 제거" <<EOF
module Voucher where
template Voucher
  with
    issuer : Party
    owner : Party
    amount : Decimal
  where
    signatory issuer
    observer owner
EOF

printf '\n'
say "규칙은 하나로 정리됩니다 — ${B}원장에 저장된 v1 payload 를 v2 타입으로 읽을 수"
say "있어야 합니다.${R} 필드를 빼거나 타입을 바꾸거나 순서를 흔들면 못 읽습니다."
printf '\n'
say "그런데 ${B}막히지 않는 것${R}도 있습니다."
pause

cat > "$BROKEN/daml/Voucher.daml" <<'EOF'
module Voucher where
template Voucher
  with
    issuer : Party
    owner : Party
    amount : Decimal
    expiresAt : Optional Time
  where
    signatory issuer, owner
    observer owner
    ensure amount > 0.0
    choice Redeem : ()
      controller owner
      do pure ()
EOF
printf '\n%s── signatory 에 owner 를 추가하기%s\n' "$B" "$R"
DAML_PACKAGE="$BROKEN" dpm build 2>&1 | sed 's/\x1b\[[0-9;]*m//g' \
  | grep -iE 'changed the definition|Werror=upgraded|^Created' | head -3 | sed 's/^/    /'

printf '\n'
warn "에러가 아니라 경고입니다. DAR 이 만들어집니다."
printf '\n'
say "컴파일러는 타입은 검사하지만 ${B}표현식의 의미는 검사하지 못합니다.${R}"
say "signatory·observer·ensure 를 바꾸면 옛 Contract 의 서명자가 소급해서"
say "달라지는데도 경고로 끝납니다."
printf '\n'
note "-Werror=upgraded-template-expression-changed 로 에러로 올릴 수 있습니다."
note "실무 패키지라면 켜 두는 편이 낫습니다."
rm -rf "$BROKEN"

# ─── 8 ───────────────────────────────────────────────────────────────────────

title "v2 를 올린다 — 우선 citi 에만"
say "일부러 한쪽에만 올립니다. 11단계에서 이 상태가 무엇을 뜻하는지 봅니다."
pause

printf '%s$ POST %s/v2/packages   (v2)%s\n\n' "$YE" "$CITI_API" "$R"
printf '  citi           HTTP %s\n' "$(upload "$CITI_API" "$DAR2")"
printf '  morganstanley  올리지 않습니다\n'
sleep 3

printf '\n'
say "노드를 멈추지 않았고, 원장에 있던 Contract 도 그대로입니다."
printf '\n'
printf '%s$ Alice 시점%s\n\n' "$YE" "$R"
show "$CITI_API" "$ALICE"
printf '\n'
say "${B}v1 로 저장된 채 그대로입니다.${R} 새 버전을 올렸다고 기존 Contract 가"
say "다시 쓰이지 않습니다. 원장은 그대로 두고 코드만 하나 더 생긴 것입니다."

# ─── 9 ───────────────────────────────────────────────────────────────────────

title "v1 시절 Contract 를 v2 코드로 다룬다"
say "Alice 의 상품권은 v1 으로 만들어졌습니다. v2 에만 있는 SetExpiry 를"
say "그 Contract 에 행사해 봅니다."
pause

VT2="$PKG2:Voucher:Voucher"

printf '%s$ exercise SetExpiry  (templateId = v2)%s\n\n' "$YE" "$R"
submit "$CITI_API" citi-app "$CITI" \
  "[{\"ExerciseCommand\":{\"templateId\":\"$VT2\",\"contractId\":\"$OLD_CID\",\"choice\":\"SetExpiry\",\"choiceArgument\":{\"deadline\":\"2030-01-01T00:00:00Z\"}}}]" | result

sleep 2
printf '\n%s$ Alice 시점%s\n\n' "$YE" "$R"
show "$CITI_API" "$ALICE"

printf '\n'
ok "v1 으로 만들어진 Contract 를 v2 코드가 읽고, v2 로 다시 만들었습니다"
printf '\n'
say "읽는 순간 없던 필드는 ${B}None${R} 으로 채워집니다. 원장에 저장된 값이 바뀐 게"
say "아니라, 읽을 때 v2 타입으로 번역된 것입니다."
printf '\n'
say "여기에 설계 함정이 하나 있습니다."
cat <<'TRAP'

    v2 의 Redeem
      case expiresAt of
        None -> pure ()                       ← v1 시절 Contract 는 여기로 온다
        Some deadline -> assertMsg ...

TRAP
note "None 을 '만료됨' 으로 다뤘다면 v1 시절 Contract 는 전부 사용 불가가 됩니다."
note "새 필드의 None 을 어떻게 다룰지가 옛 Contract 의 운명을 정합니다."
note "컴파일러는 여기까지 봐 주지 않습니다."

# ─── 10 ──────────────────────────────────────────────────────────────────────

title "버전을 고정할 것인가, 맡길 것인가"
say "지금까지는 templateId 에 Package ID 를 직접 적었습니다. 다른 방법이 있습니다."
pause

cat <<'REF'

    Package ID 고정     "5e4405c8...:Voucher:Voucher"
                        그 버전으로만 실행합니다

    package name 참조   "#step09-voucher:Voucher:Voucher"
                        참여자 전원이 가진 것 중 가장 높은 버전으로 풀립니다

REF
printf '%s$ Alice 앞으로 #step09-voucher 로 발행%s\n\n' "$YE" "$R"
submit "$CITI_API" citi-app "$CITI" \
  "[{\"CreateCommand\":{\"templateId\":\"#step09-voucher:Voucher:Voucher\",\"createArguments\":{\"issuer\":\"$CITI\",\"owner\":\"$ALICE\",\"amount\":\"11.0\"}}}]" | result

sleep 2
printf '\n%s$ Alice 시점%s\n\n' "$YE" "$R"
show "$CITI_API" "$ALICE"

printf '\n'
ok "v2 로 풀렸습니다. Alice 는 citi 노드에 있고 citi 는 v2 를 갖고 있습니다"

# ─── 11 ──────────────────────────────────────────────────────────────────────

title "혼자서는 업그레이드할 수 없습니다"
say "같은 명령을 Bob 앞으로 보냅니다. Bob 은 morganstanley 노드에 있고 그 노드는"
say "아직 v2 가 없습니다."
pause

printf '%s$ Bob 앞으로 #step09-voucher 로 발행 — 같은 명령입니다%s\n\n' "$YE" "$R"
submit "$CITI_API" citi-app "$CITI" \
  "[{\"CreateCommand\":{\"templateId\":\"#step09-voucher:Voucher:Voucher\",\"createArguments\":{\"issuer\":\"$CITI\",\"owner\":\"$BOB\",\"amount\":\"22.0\"}}}]" | result

sleep 2
printf '\n%s$ Bob 시점 (morganstanley 노드)%s\n\n' "$YE" "$R"
show "$MS_API" "$BOB"

printf '\n'
say "${B}같은 명령인데 v1 으로 풀렸습니다.${R} Canton 이 참여자 전원의 vetting 상태를"
say "보고 ${B}모두가 가진 가장 높은 버전${R}을 고른 것입니다."
pause

printf '%s$ Bob 앞으로 v2 를 못박아서 발행%s\n\n' "$YE" "$R"
submit "$CITI_API" citi-app "$CITI" \
  "[{\"CreateCommand\":{\"templateId\":\"$VT2\",\"createArguments\":{\"issuer\":\"$CITI\",\"owner\":\"$BOB\",\"amount\":\"33.0\",\"expiresAt\":null}}}]" | result

printf '\n'
warn "거부되었습니다. 상대 노드가 모르는 코드로는 거래가 성립하지 않습니다."
printf '\n'
say "이제 morganstanley 에도 올립니다."
pause

printf '%s$ POST %s/v2/packages   (v2)%s\n\n' "$YE" "$MS_API" "$R"
printf '  morganstanley  HTTP %s\n' "$(upload "$MS_API" "$DAR2")"
sleep 5

printf '\n%s$ Bob 앞으로 다시 #step09-voucher 로 발행%s\n\n' "$YE" "$R"
submit "$CITI_API" citi-app "$CITI" \
  "[{\"CreateCommand\":{\"templateId\":\"#step09-voucher:Voucher:Voucher\",\"createArguments\":{\"issuer\":\"$CITI\",\"owner\":\"$BOB\",\"amount\":\"44.0\"}}}]" | result

sleep 2
printf '\n%s$ Bob 시점%s\n\n' "$YE" "$R"
show "$MS_API" "$BOB"

printf '\n'
ok "이번에는 v2 로 풀렸습니다"
printf '\n'
say "${B}업그레이드는 배포가 아니라 합의입니다.${R} 내 노드에 올리는 것만으로는"
say "아무 일도 일어나지 않고, 거래 상대가 올려야 그 버전이 쓰이기 시작합니다."
printf '\n'
note "그래서 #package-name 참조가 실무의 기본값입니다. 참여자들이 각자의 속도로"
note "올려도 거래는 계속되고, 전원이 올린 시점부터 자동으로 새 버전이 쓰입니다."
note "Package ID 를 못박으면 그 조율을 직접 해야 합니다."

# ─── 12 ──────────────────────────────────────────────────────────────────────

title "확인한 것"
cat <<SUMMARY

  Package ID         내용의 해시입니다. 한 글자만 고쳐도 다른 패키지입니다
  업그레이드의 정체     덮어쓰기가 아니라 두 버전의 공존입니다
  같은 name, 높은 version  이것이 후속 버전의 정의입니다
  upgrades:          컴파일러에게 무엇의 후속인지 알려 규칙 검사를 켭니다
  바꿔도 되는 것       맨 뒤에 Optional 필드 추가, Choice 추가
  막히는 것           필드 제거·타입 변경·순서 변경·필수 필드 추가·Choice 제거
  막히지 않는 것       signatory·observer·ensure 변경은 경고에 그칩니다
  옛 Contract        원장에 그대로 남고, 읽을 때 새 타입으로 번역됩니다
  None 처리          새 필드의 None 을 어떻게 다룰지가 옛 Contract 를 살리고 죽입니다
  #package-name      참여자 전원이 가진 가장 높은 버전으로 풀립니다
  vetting            상대가 올리기 전에는 새 버전이 쓰이지 않습니다

  ${B}확인하지 못한 것${R}

  버전을 되돌리는 경우 (v2 로 만든 Contract 를 v1 코드로 읽기)
  Interface 를 쓴 버전 분리
  multi-package.yaml 로 여러 패키지를 한 번에 빌드하기

  ${B}다음${R}  Step 10 — 애플리케이션 연동. offset 과 ACS 스냅샷으로 원장을
        따라가는 애플리케이션을 만듭니다.

SUMMARY

if [ "$KEEP" = 1 ]; then
  say "노드가 계속 실행 중입니다."
  note "  export CITI='$CITI'"
  note "  export ALICE='$ALICE'"
  note "  export BOB='$BOB'"
  note "  export PKG1=$PKG1"
  note "  export PKG2=$PKG2"
  note "  citi JSON API          $CITI_API"
  note "  morganstanley JSON API $MS_API"
else
  say "노드를 종료합니다. 인메모리이므로 Party·User·Contract 가 모두 사라집니다."
  note "계속 살려두려면: ./steps/step09.sh --keep"
fi
