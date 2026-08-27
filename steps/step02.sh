#!/usr/bin/env bash
# Step 02 — 환경 세팅 인터랙티브 러너
#
#   ./steps/step02.sh            처음부터
#   ./steps/step02.sh --auto     엔터 대기 없이 전부 실행
#   ./steps/step02.sh --keep     끝나고 sandbox 를 끄지 않음
#
# 하나의 터미널에서 설명 → 엔터 → 실행 → 결과 순으로 진행한다.

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

# ─── 출력 도구 ────────────────────────────────────────────────────────────────

if [ -t 1 ]; then
  B=$'\033[1m'; DIM=$'\033[2m'; R=$'\033[0m'
  CY=$'\033[36m'; GR=$'\033[32m'; YE=$'\033[33m'; RD=$'\033[31m'
else
  B=''; DIM=''; R=''; CY=''; GR=''; YE=''; RD=''
fi

STEP_NO=0
TOTAL=12
LOG="$ROOT/.step02/sandbox.log"

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
bad()  { printf '%s✗ %s%s\n' "$RD" "$1" "$R"; }

pause() {
  [ "$AUTO" = 1 ] && return 0
  printf '\n%s─ 엔터를 누르면 실행합니다 ─%s' "$DIM" "$R"
  read -r _ || true
  printf '\n'
}

# 명령을 보여주고 실행한다
run() {
  printf '%s$ %s%s\n\n' "$YE" "$1" "$R"
  eval "$1"
}

die() { bad "$1"; exit 1; }

# ─── 0. 사전 확인 ────────────────────────────────────────────────────────────

printf '%s\n' "$B"
cat <<'BANNER'
 Step 02 — 환경 세팅
 ────────────────────────────────────────────────────────────
 Canton 원장을 띄우고, party 와 user 를 만들고,
 HTTP 로 계약을 생성해 프라이버시와 권한 검사를 확인한다.

 등장 인물
   Citi    토큰화 예금을 발행하는 은행       (party)
   Alice   Citi 의 고객                      (party)
   David   Citi 의 또 다른 고객               (party)

 Step 01 에서 정의한 용어가 실제로 무엇인지 눈으로 본다.
BANNER
printf '%s\n' "$R"

if [ ! -f ./env.sh ]; then
  die "env.sh 가 없습니다. README 의 '시작하기' 를 먼저 진행하세요."
fi
# shellcheck disable=SC1091
source ./env.sh

command -v dpm >/dev/null 2>&1 || die "dpm 을 찾을 수 없습니다. README 의 '시작하기' 를 먼저 진행하세요."

API="http://localhost:7575"
LAPI_PORT=6865
export API

mkdir -p "$ROOT/.step02"

cleanup() {
  if [ "$KEEP" = 1 ]; then
    printf '\n%s sandbox 를 계속 실행 중입니다. 끄려면: pkill -f canton%s\n' "$DIM" "$R"
    return
  fi
  if [ -n "${SANDBOX_PID:-}" ]; then
    printf '\n%s sandbox 종료 중...%s\n' "$DIM" "$R"
    kill "$SANDBOX_PID" 2>/dev/null || true
    pkill -f 'daml-sdk.jar sandbox' 2>/dev/null || true
    pkill -f canton 2>/dev/null || true
  fi
}
trap cleanup EXIT

# ─── 1. 빌드 ─────────────────────────────────────────────────────────────────

title "DAR 빌드"
say "Daml 소스를 컴파일해 DAR 을 만든다."
say "DAR 은 Java 의 .jar 에 해당하는 배포 단위이고, 안에 컴파일된 package(.dalf)와"
say "원본 소스가 함께 들어 있다."
pause

run "dpm build 2>&1 | grep -E 'error|Created'" || die "빌드 실패"

DAR=$(ls -t .daml/dist/*.dar 2>/dev/null | head -1)
[ -n "$DAR" ] || die "DAR 을 찾을 수 없습니다"
ok "DAR: $DAR"

# ─── 2. DAR 내부 ─────────────────────────────────────────────────────────────

title "DAR 안에는 무엇이 있는가"
say "package 하나가 .dalf 파일 하나다. 파일명 뒤 64자가 package-id 이고,"
say "그것은 그 .dalf 내용의 SHA-256 해시다."
pause

run "unzip -l '$DAR' | grep -E '\\.dalf' | awk '{print \$4}' | head -4"
printf '\n'
run "unzip -l '$DAR' | grep -E 'Step02/Deposit\\.daml' | awk '{print \$4}'"
note "원본 소스도 들어 있다 — 상대가 준 DAR 을 감사할 수 있는 이유다."

# ─── 3. sandbox 기동 ─────────────────────────────────────────────────────────

title "빈 Canton 원장 기동"
say "dpm sandbox 는 participant + sequencer + mediator 를 한 JVM 에 띄운다."
say "daml.yaml 의 init-script 를 실행하지 않으므로 party 가 하나도 없다."
say ""
note "이 러너는 sandbox 를 백그라운드로 띄우고 로그를 .step02/sandbox.log 에 남긴다."
note "직접 띄우려면: dpm sandbox --json-api-port 7575 --dar $DAR"
pause

pkill -f canton 2>/dev/null || true
sleep 1
nohup dpm sandbox --json-api-port 7575 --dar "$DAR" > "$LOG" 2>&1 &
SANDBOX_PID=$!

printf '기동 대기'
# JSON API 가 뜨는 것과 participant 가 synchronizer 에 연결되는 것은 별개다.
# 연결 전에 party 를 만들려 하면 PARTY_ALLOCATION_WITHOUT_CONNECTED_SYNCHRONIZER 가 난다.
READY=0
for _ in $(seq 1 120); do
  if curl -s -m 2 "$API/v2/version" >/dev/null 2>&1; then
    SYNCS=$(curl -s -m 3 "$API/v2/state/connected-synchronizers" 2>/dev/null || echo '')
    if [ -n "$SYNCS" ] && [ "$SYNCS" != '{"connectedSynchronizers":[]}' ]; then READY=1; break; fi
  fi
  printf '.'
  sleep 2
done
printf '\n'
[ "$READY" = 1 ] || { tail -25 "$LOG"; die "sandbox 기동 실패 (synchronizer 연결 안 됨)"; }
ok "Ledger API :$LAPI_PORT / JSON API :7575"

run "curl -s \$API/v2/state/connected-synchronizers | python3 -m json.tool"
note "participant 가 synchronizer 에 연결되어야 비로소 party 를 만들 수 있다."
note "JSON API 가 응답하는 것만으로는 부족하다."

run "curl -s \$API/v2/version | python3 -c 'import sys,json; print(\"version:\", json.load(sys.stdin)[\"version\"])'"

# ─── 4. 빈 원장 확인 ─────────────────────────────────────────────────────────

title "원장이 비어 있는지 확인"
say "party 목록을 조회한다. sandbox::... 하나만 있어야 한다."
say "그것은 participant 자신의 admin party 이고 업무용 party 가 아니다."
pause

run "curl -s \$API/v2/parties | python3 -c 'import sys,json; print([d[\"party\"] for d in json.load(sys.stdin)[\"partyDetails\"]])'"
printf '\n'
say "user 도 확인한다."
run "curl -s \$API/v2/users | python3 -c 'import sys,json; print([u[\"id\"] for u in json.load(sys.stdin)[\"users\"]])'"
note "participant_admin 은 ParticipantAdmin 권한을 가진 노드 운영 계정이다."
note "어떤 party 도 대리하지 않는다. 다음 두 단계는 이 계정 권한으로 하는 운영 작업이다."

# ─── 5. party 생성 ───────────────────────────────────────────────────────────

title "party 생성 — Citi, Alice, David"
say "Canton 은 party 를 기본 제공하지 않는다. participant 운영자가 발급한다."
say "partyIdHint 로 이름 힌트를 준다."
pause

for hint in Citi Alice David; do
  run "curl -s -X POST \$API/v2/parties -H 'Content-Type: application/json' -d '{\"partyIdHint\":\"$hint\",\"identityProviderId\":\"\"}' | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get(\"partyDetails\",d).get(\"party\", d))'"
done

findparty() {
  curl -s "$API/v2/parties" | python3 -c "
import sys,json
ps=[d['party'] for d in json.load(sys.stdin)['partyDetails'] if d['party'].startswith('$1')]
print(ps[0] if ps else '')
"
}
export CITI=$(findparty Citi)
export ALICE=$(findparty Alice)
export DAVID=$(findparty David)
[ -n "$CITI" ] && [ -n "$ALICE" ] && [ -n "$DAVID" ] || die "party 생성에 실패했습니다. 위 응답을 확인하세요."

printf '\n'
ok "CITI  = $CITI"
ok "ALICE = $ALICE"
ok "DAVID = $DAVID"
printf '\n'
say "${B}주목할 것${R} — 세 party 의 :: 뒷부분이 모두 같다."
run "echo \"\$CITI\" \"\$ALICE\" \"\$DAVID\" | tr ' ' '\\n' | sed 's/.*:://' | sort -u"
note "이것이 namespace fingerprint 이고, 이 party 들을 발급한 키의 지문이다."
note "셋 다 같은 participant 가 발급했으므로 동일하다. Alice 와 David 는 hosted party 이고"
note "자기 키를 갖고 있지 않다."

# ─── 6. user 생성 ────────────────────────────────────────────────────────────

title "user 생성 — API 호출 자격"
say "party 만으로는 커맨드를 제출할 수 없다. 인증이 꺼져 있어도 user 가 필요하다."
say ""
say "  ${B}계약에 이름이 남는 것이 party, 그 party 로 API 를 호출할 자격이 user${R}"
say ""
say "citi-settlement 에는 Citi 와 Alice 두 party 의 CanActAs 를 준다."
say "은행의 백오피스가 자기 명의와 고객 명의를 모두 대리하는 실제 구성이고,"
say "한 user 가 여러 party 를 대리할 수 있음을 보여준다."
pause

mkuser() { # $1=id  $2..=parties
  local id="$1"; shift
  local rights=""
  for p in "$@"; do
    [ -n "$rights" ] && rights="$rights,"
    rights="$rights{\"kind\":{\"CanActAs\":{\"value\":{\"party\":\"$p\"}}}}"
  done
  local body="{\"user\":{\"id\":\"$id\",\"primaryParty\":\"$1\",\"isDeactivated\":false,\"metadata\":{\"resourceVersion\":\"\",\"annotations\":{}},\"identityProviderId\":\"\"},\"rights\":[$rights]}"
  curl -s -X POST "$API/v2/users" -H 'Content-Type: application/json' -d "$body" \
    | python3 -c 'import sys,json; d=json.load(sys.stdin); print("생성:", d["user"]["id"]) if "user" in d else print("실패:", d.get("cause","?")[:100])'
}

printf '%s$ POST /v2/users  (id=citi-settlement, CanActAs Citi + Alice)%s\n\n' "$YE" "$R"
mkuser citi-settlement "$CITI" "$ALICE"
printf '%s$ POST /v2/users  (id=alice-web, CanActAs Alice)%s\n\n' "$YE" "$R"
mkuser alice-web "$ALICE"
printf '%s$ POST /v2/users  (id=david-web, CanActAs David)%s\n\n' "$YE" "$R"
mkuser david-web "$DAVID"

printf '\n'
run "curl -s \$API/v2/users/citi-settlement/rights | python3 -c 'import sys,json; rs=json.load(sys.stdin)[\"rights\"]; [print(\" \", list(r[\"kind\"])[0], \"→\", list(r[\"kind\"].values())[0][\"value\"][\"party\"].split(\"::\")[0]) for r in rs]'"
note "한 user 가 두 party 를 대리한다. party ↔ user 는 N:M 관계다."

# ─── 7. package-id ───────────────────────────────────────────────────────────

title "package-id — 어떤 코드인지 지목하는 해시"
say "트랜잭션은 template 을 package-id 로 지목한다. 코드가 1바이트만 바뀌어도"
say "해시가 달라지므로 누가 몰래 다른 로직으로 바꿔치기할 수 없다."
pause

export PKG=$(dpm inspect-dar "$DAR" 2>/dev/null | grep -oE "[0-9a-f]{64}" | head -1)
ok "PKG = $PKG"
printf '\n'
say "원장에 업로드·vetting 된 것과 같은지 JSON API 로 대조한다."
run "curl -s \$API/v2/packages | grep -c $PKG"
note "일치한다. vetting 은 participant 가 '이 package-id 를 쓰겠다'고 공표하는 것이고,"
note "--dar 로 넘겼으므로 sandbox 가 업로드와 vetting 을 함께 처리했다."

# ─── 8. 권한 부족 실패 ───────────────────────────────────────────────────────

title "Citi 혼자서는 예금을 만들 수 없다"
say "Deposit 의 signatory 는 bank 와 owner 둘이다."
say "Citi 권한만으로 제출하면 Alice 의 동의가 없어 거부된다."
pause

DEP="$PKG:Step02.Deposit:Deposit"
run "curl -s -X POST \$API/v2/commands/submit-and-wait -H 'Content-Type: application/json' -d '{\"commands\":[{\"CreateCommand\":{\"templateId\":\"$DEP\",\"createArguments\":{\"bank\":\"'\$CITI'\",\"owner\":\"'\$ALICE'\",\"amount\":\"100.0\"}}}],\"commandId\":\"s02-fail1\",\"userId\":\"citi-settlement\",\"actAs\":[\"'\$CITI'\"],\"readAs\":[]}' | python3 -c 'import sys,json; d=json.load(sys.stdin); print(\"code :\", d.get(\"code\")); print(\"cause:\", d.get(\"cause\",\"\")[:200])'"
note "DAML_AUTHORIZATION_ERROR. requires authorizers 에 Alice 가 포함되어 있다."

# ─── 9. 양쪽 권한으로 생성 ───────────────────────────────────────────────────

title "Citi + Alice 권한으로 발행"
say "actAs 에 두 party 를 넣는다. 이 participant 가 양쪽을 모두 호스팅하므로 가능하다."
say ""
warn "실제로 Alice 가 다른 은행 고객이라면 불가능하다. 그때는 propose/accept 가 필요하고"
warn "Step 04~05 에서 다룬다."
pause

run "curl -s -X POST \$API/v2/commands/submit-and-wait -H 'Content-Type: application/json' -d '{\"commands\":[{\"CreateCommand\":{\"templateId\":\"$DEP\",\"createArguments\":{\"bank\":\"'\$CITI'\",\"owner\":\"'\$ALICE'\",\"amount\":\"100.0\"}}}],\"commandId\":\"s02-ok\",\"userId\":\"citi-settlement\",\"actAs\":[\"'\$CITI'\",\"'\$ALICE'\"],\"readAs\":[]}' | python3 -m json.tool"
ok "예금 계약이 원장에 기록되었다."

# ─── 10. 조회와 프라이버시 ───────────────────────────────────────────────────

title "조회 — 누가 무엇을 보는가"
say "조회에는 원장 오프셋이 필요하다. 오프셋은 원장의 위치를 가리키는 번호다."
pause

export OFF=$(curl -s "$API/v2/state/ledger-end" | python3 -c "import sys,json;print(json.load(sys.stdin)['offset'])")
ok "offset = $OFF"

acs() {
  curl -s -X POST "$API/v2/state/active-contracts" -H 'Content-Type: application/json' \
    -d "{\"filter\":{\"filtersByParty\":{\"$1\":{\"cumulative\":[{\"identifierFilter\":{\"WildcardFilter\":{\"value\":{\"includeCreatedEventBlob\":false}}}}]}}},\"verbose\":false,\"activeAtOffset\":$OFF}"
}

printf '\n%s$ POST /v2/state/active-contracts  (Alice 시점)%s\n\n' "$YE" "$R"
acs "$ALICE" | python3 -c '
import sys,json
d=json.load(sys.stdin)
for e in d:
    c=e["contractEntry"]["JsActiveContract"]["createdEvent"]
    print("  templateId :", c["templateId"].split(":",1)[1])
    print("  arguments  :", {k:(v.split("::")[0] if isinstance(v,str) and "::" in v else v) for k,v in c["createArgument"].items()})
    print("  signatories:", [s.split("::")[0] for s in c["signatories"]])
print(f"  총 {len(d)}건")
'

printf '\n%s$ POST /v2/state/active-contracts  (David 시점)%s\n\n' "$YE" "$R"
acs "$DAVID" | python3 -c 'import sys,json; d=json.load(sys.stdin); print("  결과:", d, f"→ {len(d)}건")'

printf '\n'
say "${B}David 에게는 아무것도 보이지 않는다.${R} David 는 이 계약의 signatory 도 observer 도"
say "아니므로 stakeholder 가 아니고, 데이터가 전달되지 않는다."
printf '\n'
warn "단 지금은 participant 가 하나다. 물리적으로는 같은 노드가 양쪽 데이터를 갖고 있고"
warn "Ledger API 가 party 단위로 뷰를 분리해 보여주는 것이다. participant 가 서로 다를 때"
warn "비로소 데이터 자체가 도달하지 않는다. Step 05 에서 확인한다."

# ─── 11. 권한 위조 시도 ──────────────────────────────────────────────────────

title "David 가 Alice 명의로 예금을 날조할 수 있는가"
say "createArguments 의 owner 에 Alice 를 쓰고 David 권한으로 제출한다."
pause

run "curl -s -X POST \$API/v2/commands/submit-and-wait -H 'Content-Type: application/json' -d '{\"commands\":[{\"CreateCommand\":{\"templateId\":\"$DEP\",\"createArguments\":{\"bank\":\"'\$CITI'\",\"owner\":\"'\$ALICE'\",\"amount\":\"999.0\"}}}],\"commandId\":\"s02-forge\",\"userId\":\"david-web\",\"actAs\":[\"'\$DAVID'\"],\"readAs\":[]}' | python3 -c 'import sys,json; d=json.load(sys.stdin); print(\"code :\", d.get(\"code\")); print(\"cause:\", d.get(\"cause\",\"\")[:260])'"

printf '\n'
say "${B}세 가지를 확인할 것.${R}"
say "  1. ${B}david-web 이라는 user 이름이 에러에 없다.${R} user 는 'David 를 주장해도 되는가'만"
say "     판정하고 사라졌다. Daml 엔진에는 party 만 도달한다."
say "  2. ${B}requires authorizers${R} — createArguments 에 owner 를 Alice 로 쓴 것이"
say "     Alice 의 권한을 만들어주지 않았다. 권한은 template 의 signatory 선언에서 나온다."
say "  3. 앞의 64자 해시 — 어떤 코드로 검증했는지가 에러에 기록된다."

# ─── 12. 정리 ────────────────────────────────────────────────────────────────

title "확인한 것"
cat <<SUMMARY

  Participant node   테스트를 위한 sandbox 환경에서는 participant + sequencer + mediator 함께 실행
  Party              Citi / Alice / David. :: 뒷부분이 발급 키의 지문
  Hosted party       셋 다 같은 지문 → participant 가 발급 → 자기 키 없음
  User               citi-settlement 하나가 두 party 를 대리 (N:M)
  ParticipantAdmin   party·user 생성은 노드 운영 작업
  DAR / package-id   내용 해시로 코드를 지목
  Signatory          bank + owner 양쪽 동의 → 한쪽만으로는 생성 불가
  ACS                party 시점으로 조회, David 에게는 보이지 않음
  권한 검사          필드에 이름을 쓴 것이 권한이 되지 않음

  ${B}다음${R}  Step 03 — Deposit.daml 의 문법을 읽고, choice 를 추가해
        예금을 이체할 수 있게 만든다.

SUMMARY

if [ "$KEEP" = 1 ]; then
  say "sandbox 가 계속 실행 중이다. 직접 더 만져보려면:"
  note "  export API=http://localhost:7575"
  note "  export CITI='$CITI'"
  note "  export ALICE='$ALICE'"
  note "  export DAVID='$DAVID'"
  note "  export PKG=$PKG"
else
  say "sandbox 를 종료한다. 인메모리이므로 party·user·계약이 모두 사라진다."
  note "다시 실행하면 namespace 지문부터 새로 생성된다."
  note "계속 살려두려면: ./steps/step02.sh --keep"
fi
