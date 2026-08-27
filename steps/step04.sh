#!/usr/bin/env bash
# Step 04 — 두 당사자 (propose/accept) 인터랙티브 러너
#
#   ./steps/step04.sh            처음부터
#   ./steps/step04.sh --auto     엔터 대기 없이 전부 실행
#
# Sandbox 를 띄우지 않는다. dpm test 의 인메모리 엔진으로 진행한다.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

AUTO=0
for a in "$@"; do
  case "$a" in
    --auto) AUTO=1 ;;
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
PREV="daml/Step03/Deposit.daml"
SRC="daml/Step04/Deposit.daml"
TST="daml/Step04/DepositTest.daml"
OUT="$ROOT/.step04/test.out"

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

show() {
  local f="$1" pat="$2" n="$3"
  local start
  start=$(grep -n -- "$pat" "$f" | head -1 | cut -d: -f1)
  [ -n "$start" ] || { warn "구간을 찾지 못했습니다: $pat"; return; }
  printf '%s%s:%s%s\n' "$DIM" "$f" "$start" "$R"
  sed -n "${start},$((start + n - 1))p" "$f" | sed 's/^/    /'
}

result() {
  local name="$1" line
  line=$(grep "Step04/DepositTest.daml:${name}:" "$OUT" 2>/dev/null | head -1)
  if [ -n "$line" ]; then
    printf '  %s✓%s %-30s %s\n' "$GR" "$R" "$name" "${line#*: }"
  else
    printf '  %s✗%s %-30s (결과 없음)\n' "$RD" "$R" "$name"
  fi
}

printf '%s\n' "$B"
cat <<'BANNER'
 Step 04 — 두 당사자
 ────────────────────────────────────────────────────────────
 Step 03 에서 Transfer 가 실패했다. 그리고 발행도 사실은
 submit [Citi, Alice] 라는 편법에 기대고 있었다.

 두 문제의 원인은 같다 — 한 트랜잭션에 두 party 의 권한이 필요한데
 participant 는 자기가 호스팅하는 party 의 권한만 행사할 수 있다.

 해법은 권한을 두 트랜잭션으로 나누는 것이다. propose / accept.
BANNER
printf '%s\n' "$R"

[ -f ./env.sh ] || die "env.sh 가 없습니다. README 의 '시작하기' 를 먼저 진행하세요."
# shellcheck disable=SC1091
source ./env.sh
command -v dpm >/dev/null 2>&1 || die "dpm 을 찾을 수 없습니다. README 의 '시작하기' 를 먼저 진행하세요."
mkdir -p "$ROOT/.step04"

# ─── 1 ───────────────────────────────────────────────────────────────────────

title "복습 — Step 03 의 Transfer 는 왜 실패했는가"
pause

show "$PREV" "choice Transfer" 7

printf '\n'
cat <<'CALC'
      signatory  = Citi, Alice
      controller = Alice
      ─────────────────────────
      권한        = Citi, Alice

      만들려는 계약의 signatory = Citi, Bob
                                        ↑ Bob 의 권한이 없다

CALC
say "Bob 은 아직 아무것도 서명하지 않았다. 서명 없이 남의 계약 당사자로"
say "만들 수는 없다."

# ─── 2 ───────────────────────────────────────────────────────────────────────

title "발행도 사실 편법이었다"
say "Step 03 의 테스트는 이렇게 발행했다."
pause

cat <<'OLD'
    submit [Citi, Alice] do
      createCmd Deposit with bank = citi, owner = alice, amount = 100.0

OLD
warn "두 party 의 권한을 동시에 쓰는 것이다."
say "participant 는 ${B}자기가 호스팅하는 party 의 권한만${R} 행사할 수 있다."
printf '\n'
cat <<'HOSTING'
    같은 노드           citi-participant { Citi, Alice }
                        → actAs [Citi, Alice] 가능

    다른 노드           citi-participant { Citi }
                        morganstanley-participant { Bob }
                        → 어느 쪽도 두 권한을 동시에 갖지 못함

HOSTING
say "Step 02 에서 통했던 이유는 sandbox 가 노드 하나였기 때문이다."
note "Alice 가 Bob 같은 타행 고객이었다면 그 코드는 실제 환경에서 동작하지 않는다."

# ─── 3 ───────────────────────────────────────────────────────────────────────

title "해법 — 권한을 시간적으로 분리한다"
say "한 트랜잭션에 모을 수 없다면 두 트랜잭션으로 나눈다."
pause

cat <<'PATTERN'
    [TX 1]  제안자가 자기 권한만으로 제안 계약을 만든다

              signatory 제안자
              observer  상대방          ← 상대가 볼 수 있게

    [TX 2]  상대가 그 제안의 choice 를 행사한다

              권한 = [제안의 signatory] + [choice 의 controller]
                   =      제안자        +      상대방

              → 이 합쳐진 권한으로 목표 계약을 만든다

PATTERN
say "${B}두 시점에 나뉘어 있던 동의가 두 번째 트랜잭션에서 결합된다.${R}"
note "Daml 계약의 절반 이상이 이 패턴으로 되어 있다."

# ─── 4 ───────────────────────────────────────────────────────────────────────

title "발행 제안 — DepositProposal"
pause

show "$SRC" "^template DepositProposal" 20

printf '\n'
cat <<'CALC2'
    TX 1   Citi 가 혼자 제안을 만든다
             signatory = Citi 뿐 → Citi 권한만으로 생성 가능

    TX 2   Alice 가 AcceptDeposit 을 행사한다
             권한 = [Citi] + [Alice] = Citi, Alice
             만들려는 Deposit 의 signatory = Citi, Alice   → 충족

CALC2
say "${B}observer 가 여기서 처음 필요해진다.${R}"
say "제안의 signatory 는 Citi 뿐이다. Alice 는 서명하지 않았으므로 signatory 가"
say "아니다. 그런데 제안을 ${B}볼 수 없으면 수락할 수도 없다.${R}"
printf '\n'
note "observer 는 가시성만 준다. 수락 권한은 choice 의 controller 가 준다."
note "이 둘을 혼동하지 말 것 — observer 라고 아무 choice 나 행사할 수 있는 게 아니다."

# ─── 5 ───────────────────────────────────────────────────────────────────────

title "이체 제안 — ProposeTransfer / TransferProposal"
pause

show "$SRC" "choice ProposeTransfer" 8
printf '\n'
show "$SRC" "^template TransferProposal" 9

printf '\n'
cat <<'CALC3'
    TX 1   Alice 가 ProposeTransfer 를 행사
             권한 = [Citi, Alice] + [Alice] = Citi, Alice
             만들려는 TransferProposal 의 signatory = Citi, Alice   → 충족
             ← 원본 Deposit 은 여기서 소비된다

    TX 2   Bob 이 AcceptTransfer 를 행사
             권한 = [Citi, Alice] + [Bob] = Citi, Alice, Bob
             만들려는 Deposit 의 signatory = Citi, Bob            → 충족

CALC3
say "TX 2 에서 Alice 의 권한이 어디서 왔는지 주목할 것 —"
say "Alice 는 그 트랜잭션을 제출하지도 않았다. ${B}제안 계약의 signatory 로 남아있던"
say "Alice 의 동의가 그대로 실린 것${R}이다."

# ─── 6 ───────────────────────────────────────────────────────────────────────

title "거절과 철회는 반드시 되돌려야 한다"
say "ProposeTransfer 는 원본 Deposit 을 소비한다."
say "제안이 살아있는 동안 ${B}예금 계약은 존재하지 않는다.${R}"
pause

show "$SRC" "choice RejectTransfer" 9

printf '\n'
say "거절·철회 시 새 Deposit 을 만들어 돌려주지 않으면 ${B}예금이 사라진다.${R}"
say "deposit.owner 는 원 소유자 그대로이므로 create 만 하면 원상복구된다."
printf '\n'
warn "흔한 버그다. Reject 를 pure () 로 두면 자산이 증발한다."
note "반면 발행 제안(DepositProposal)은 아무것도 소비하지 않았으므로"
note "RejectDeposit 은 pure () 가 맞다. 되돌릴 것이 없다."

# ─── 7 ───────────────────────────────────────────────────────────────────────

title "테스트 — submit [a, b] 가 하나도 없다"
say "Step 04 의 테스트는 모든 발행과 이체를 각자 자기 권한으로만 제출한다."
say "participant 가 분리된 실제 환경에서도 그대로 동작하는 형태다."
pause

show "$TST" "^propose : Setup" 13

printf '\n'
note "issue 헬퍼가 TX 1 과 TX 2 를 각각 다른 party 로 제출하는 것을 볼 것."

# ─── 8 ───────────────────────────────────────────────────────────────────────

title "실행"
pause

printf '%s$ dpm test%s\n\n' "$YE" "$R"
dpm test > "$OUT" 2>&1
TEST_EXIT=$?
[ "$TEST_EXIT" = 0 ] || { tail -30 "$OUT"; die "테스트 실패"; }

printf '  %s발행%s\n' "$B" "$R"
for t in testIssueViaProposal testProposalVisibleToOwner testRejectIssue \
         testCancelIssue testStrangerCannotAcceptIssue testDirectIssueStillFails; do
  result "$t"
done
printf '\n  %s이체%s\n' "$B" "$R"
for t in testTransferViaProposal testProposalConsumesDeposit testRejectReturnsDeposit \
         testCancelReturnsDeposit testStrangerCannotAccept testCannotTransferToSelf; do
  result "$t"
done

printf '\n'
ok "Step 04 테스트 12개 통과 (전체 $(grep -c ': ok,' "$OUT") 개)"

# ─── 9 ───────────────────────────────────────────────────────────────────────

title "제안이 살아있는 동안의 상태"
say "testProposalConsumesDeposit 이 확인하는 것이다."
pause

show "$TST" "^testProposalConsumesDeposit" 18

printf '\n'
cat <<'STATE'
    발행 후          Deposit{Alice, 100}                     활성 1건

    제안 후          TransferProposal{deposit, Bob}          활성 1건
                     Deposit 은 소비됨                        활성 0건

    수락 후          Deposit{Bob, 100}                        활성 1건
                     TransferProposal 은 소비됨

STATE
warn "중간 상태에서 Alice 의 예금 조회 결과가 빈 배열이다."
say "실무에서는 이 구간을 사용자에게 '이체 대기중'으로 보여줘야 한다."
say "잔액이 0 으로 보이면 안 된다."

# ─── 10 ──────────────────────────────────────────────────────────────────────

title "직접 해보기"
cat <<'TRY'

  1. RejectTransfer 의 본문을 pure () 로 바꾸고 반환 타입을 () 로 맞춘다.
     testRejectReturnsDeposit 이 어떻게 깨지는가? 예금은 어디로 갔는가?

  2. DepositProposal 의 observer 줄을 지운다.
     testIssueViaProposal 이 실패한다. 에러 메시지가 무엇을 말하는가?

  3. AcceptTransfer 의 controller 를 deposit.owner 로 바꾼다.
     Alice 혼자 Bob 에게 예금을 떠넘길 수 있게 되는가? 왜 안 되는가?

  4. TransferProposal 의 signatory 에서 deposit.owner 를 뺀다.
     TX 2 의 권한 계산이 어떻게 달라지는가?

  5. CancelTransfer 의 controller 를 newOwner 로 바꾼다.
     그러면 누가 제안을 철회할 수 있게 되는가? 그것이 옳은가?

TRY
pause

# ─── 11 ──────────────────────────────────────────────────────────────────────

title "확인한 것"
cat <<SUMMARY

  propose/accept     한 트랜잭션에 모을 수 없는 권한을 두 트랜잭션으로 분리
  권한 결합           TX 2 에서 [제안의 signatory] + [controller] 로 합쳐진다
  observer           가시성만 준다. 권한은 controller 가 준다
  제안이 소비한다      이체 제안은 원본을 소비하므로 거절 시 반드시 되돌려야 한다
  중간 상태           제안 구간에는 원본 계약이 존재하지 않는다
  submit [a,b] 제거   각자 자기 권한으로만 제출 — 노드가 분리돼도 동작한다

  ${B}남은 문제${R}  지금까지는 전부 participant 하나에서 확인했다.
              "노드가 분리돼도 동작한다"는 아직 말뿐이다.

  ${B}다음${R}  Step 05 — canton.conf 로 participant 를 2개 띄우고
        Alice 와 Bob 을 서로 다른 노드에 두어 실제로 확인한다.
        여기서 vetting, 토폴로지, 신뢰 경계가 처음 드러난다.

SUMMARY
