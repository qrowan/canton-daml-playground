#!/usr/bin/env bash
# Step 06 — DvP 인터랙티브 러너
#
#   ./steps/step06.sh            처음부터
#   ./steps/step06.sh --auto     엔터 대기 없이 전부 실행

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
TOTAL=10
SRC="daml/Step06/Dvp.daml"
TST="daml/Step06/DvpTest.daml"
OUT="$ROOT/.step06/test.out"

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
  local f="$1" pat="$2" n="$3" start
  start=$(grep -n -- "$pat" "$f" | head -1 | cut -d: -f1)
  [ -n "$start" ] || { warn "구간을 찾지 못했습니다: $pat"; return; }
  printf '%s%s:%s%s\n' "$DIM" "$f" "$start" "$R"
  sed -n "${start},$((start + n - 1))p" "$f" | sed 's/^/    /'
}

result() {
  local name="$1" line
  line=$(grep "Step06/DvpTest.daml:${name}:" "$OUT" 2>/dev/null | head -1)
  if [ -n "$line" ]; then
    printf '  %s✓%s %-32s %s\n' "$GR" "$R" "$name" "${line#*: }"
  else
    printf '  %s✗%s %-32s (결과 없음)\n' "$RD" "$R" "$name"
  fi
}

printf '%s\n' "$B"
cat <<'BANNER'
 Step 06 — DvP
 ────────────────────────────────────────────────────────────
 Bob 이 채권을 팔고 Alice 가 현금을 지급합니다.
 두 이전이 하나의 Transaction 안에서 일어나야 합니다.

   Citi           현금 발행
   GoldmanSachs   채권 발행
   Bob            채권 보유. 매도자
   Alice          현금 보유. 매수자

 Step 03 에서 남겨둔 질문에 답하는 단계이기도 합니다.
BANNER
printf '%s\n' "$R"

[ -f ./env.sh ] || die "env.sh 가 없습니다."
# shellcheck disable=SC1091
source ./env.sh
command -v daml >/dev/null 2>&1 || die "daml 을 찾을 수 없습니다."
mkdir -p "$ROOT/.step06"

# ─── 1 ───────────────────────────────────────────────────────────────────────

title "왜 원자성이 필요한가"
pause

cat <<'RISK'
    나눠서 하면

      TX 1   Bob 이 채권을 Alice 에게 이전
      TX 2   Alice 가 현금을 Bob 에게 이전      ← 여기서 멈추면 Bob 만 손해

RISK
say "이것을 ${B}결제 리스크(principal risk)${R} 라고 합니다."
say "현실 금융은 중앙청산소나 에스크로를 두어 막습니다."
printf '\n'
say "Daml 은 두 이전을 한 Transaction 에 담아 ${B}구조적으로 없앱니다.${R}"
note "전부 성공하거나 전부 실패합니다. 중간 상태가 존재하지 않습니다."

# ─── 2 ───────────────────────────────────────────────────────────────────────

title "Step 03 의 연습문제 5번"
say "Step 03 에서 Transfer 가 실패했을 때 이런 질문을 남겼습니다."
printf '\n'
cat <<'Q'
    "controller 를 owner, newOwner 로 바꾸면 되지 않나?
     이것이 옳은 해결인가?"

Q
pause

show "$SRC" "choice CashTransfer" 6

printf '\n'
say "답은 ${B}그 자체로는 해결이 아니지만, DvP 에서는 바로 그것이 필요하다${R} 입니다."
printf '\n'
say "이렇게 두면 이 Choice 는 ${B}양쪽 권한이 모두 있는 Transaction 안에서만${R}"
say "행사할 수 있습니다. Alice 혼자서는 못 씁니다."
printf '\n'
note "즉 '단독으로는 불가, 합의된 결제 안에서는 가능' 이라는 조건을"
note "타입 수준에서 표현한 것입니다."

# ─── 3 ───────────────────────────────────────────────────────────────────────

title "제안 — 채권이 잠긴다"
pause

show "$SRC" "choice ProposeDvp" 9

printf '\n'
say "ProposeDvp 가 원본 Bond 를 ${B}소비${R}합니다. 제안이 살아있는 동안 Bob 의 ACS 에"
say "채권이 없고, 그래서 같은 채권을 두 번 팔 수 없습니다."
printf '\n'
warn "이것은 결제 리스크가 아니라 유동성 제약입니다."
say "Alice 의 현금은 움직인 적이 없고 Bob 은 언제든 Cancel 로 회수할 수 있습니다."

# ─── 4 ───────────────────────────────────────────────────────────────────────

title "결제 — 두 다리가 한 Transaction 에"
pause

show "$SRC" "choice Settle" 13

printf '\n'
say "채권은 ${B}직접 create${R}, 현금은 ${B}중첩 exercise${R} 입니다."
say "왜 다른지는 다음 단계에서 봅니다."

# ─── 5 ───────────────────────────────────────────────────────────────────────

title "권한이 어떻게 흐르는가"
pause

cat <<'AUTH'
    Settle 을 행사하는 시점

      DvpProposal 의 signatory = GoldmanSachs, Bob
      Settle 의 controller     = Alice
      ─────────────────────────────────────────
      이 지점의 권한            = GoldmanSachs, Bob, Alice


    채권 다리 — 직접 create

      만들려는 Bond 의 signatory = GoldmanSachs, Alice        → 충족


    현금 다리 — 중첩 exercise

      exercise cashCid CashTransfer
        controller = Alice, Bob
          → 둘 다 현재 권한에 있으므로 행사 가능

        그 안의 권한 = [Cash 의 signatory] + [controller]
                     = (Citi, Alice) + (Alice, Bob)
                     = Citi, Alice, Bob

        만들려는 Cash 의 signatory = Citi, Bob                 → 충족

AUTH
say "${B}Citi 는 이 Transaction 에 아무 행위도 하지 않았는데 권한이 실렸습니다.${R}"
printf '\n'
say "Cash Contract 의 signatory 로서 이미 동의해 둔 것이, Choice 를 통해"
say "흘러온 것입니다."
printf '\n'
note "발행자가 결제 시점에 온라인일 필요가 없는 이유입니다."
note "Step 03 의 AddInterest 에서 본 것과 같은 원리가, 여기서는 중첩된 exercise 를"
note "통해 두 단계로 흐릅니다."

# ─── 6 ───────────────────────────────────────────────────────────────────────

title "테스트"
say "13개 중 8개가 submitMustFail 입니다."
pause

show "$TST" "^testWrongAmountFails" 18

printf '\n'
note "금액이 다르면 Settle 전체가 실패합니다. 채권도 현금도 움직이지 않습니다."
note "'채권만 넘어가고 현금은 안 오는' 상태가 존재할 수 없습니다."

# ─── 7 ───────────────────────────────────────────────────────────────────────

title "실행"
pause

printf '%s$ daml test%s\n\n' "$YE" "$R"
daml test --no-legacy-assistant-warning > "$OUT" 2>&1
[ $? = 0 ] || { tail -30 "$OUT"; die "테스트 실패"; }

printf '  %s단독 이전 차단%s\n' "$B" "$R"
for t in testAliceCannotMoveCashAlone testBobCannotMoveBondAlone; do result "$t"; done
printf '\n  %s정상 결제%s\n' "$B" "$R"
for t in testSettle testSettleIsSingleTransaction; do result "$t"; done
printf '\n  %s잠금%s\n' "$B" "$R"
for t in testBondLockedDuringProposal testCannotDoubleSell; do result "$t"; done
printf '\n  %s원자성%s\n' "$B" "$R"
for t in testWrongAmountFails testStaleCashFails testOthersCashFails; do result "$t"; done
printf '\n  %s권한%s\n' "$B" "$R"
for t in testStrangerCannotSettle testStrangerCannotCancel; do result "$t"; done
printf '\n  %s되돌리기%s\n' "$B" "$R"
for t in testRejectReturnsBond testCancelReturnsBond; do result "$t"; done

printf '\n'
ok "Step 06 테스트 13개 통과 (전체 $(grep -c ': ok,' "$OUT") 개)"

# ─── 8 ───────────────────────────────────────────────────────────────────────

title "결제 전후 상태"
pause

cat <<'STATE'
    발행 후        Bob    Bond{10}                 Alice  Cash{100}

    제안 후        Bob    (없음)                    Alice  Cash{100}
                          DvpProposal{Bond, Alice, 100}     ← 채권만 잠김

    결제 후        Bob    Cash{100}                Alice  Bond{10}

STATE
say "testSettleIsSingleTransaction 이 이 표를 그대로 검증합니다."
printf '\n'
warn "현금은 잠기지 않습니다."
say "Alice 의 현금은 Settle 시점에 지정됩니다. 그 사이 Alice 가 그 현금을 다른 데"
say "쓰면 Settle 이 실패합니다 — testStaleCashFails 가 그것입니다."
printf '\n'
note "실패로 끝나므로 안전하지만 Bob 은 헛수고합니다. 양쪽을 다 잠그려면 현금 쪽에도"
note "제안 절차가 필요하고, 그러면 3단계 워크플로가 됩니다."

# ─── 9 ───────────────────────────────────────────────────────────────────────

title "직접 해보기"
cat <<'TRY'

  1. CashTransfer 의 controller 를 owner 만으로 되돌린다.
     Settle 이 어떻게 깨지는가? 에러가 무엇을 요구하는가?

  2. Settle 에서 현금 다리를 exercise 대신 직접 create 로 바꾼다.
       create cash with owner = bond.owner
     왜 실패하는가? 권한 계산을 직접 해볼 것.

  3. 금액 검사를 == 에서 >= 로 바꾼다.
     testWrongAmountFails 는 통과하지만 새 문제가 생긴다. 거스름돈은?

  4. DvpProposal 에서 observer buyer 를 지운다.
     Alice 가 Settle 을 행사할 수 있는가?

  5. ProposeDvp 가 Bond 를 소비하지 않게 (nonconsuming) 바꾼다.
     testCannotDoubleSell 이 어떻게 되는가?

TRY
pause

# ─── 10 ──────────────────────────────────────────────────────────────────────

title "확인한 것"
cat <<SUMMARY

  원자적 DvP          두 이전이 한 Transaction. 결제 리스크가 구조적으로 없다
  controller 둘        양쪽 권한이 있는 Transaction 안에서만 행사 가능
  중첩 exercise        Contract 의 signatory 권한을 끌어오는 수단
  발행자 오프라인       Citi 는 행위하지 않았지만 권한이 실린다
  잠금                제안이 원본을 소비해 이중 매도를 막는다
  한쪽만 잠긴다         현금은 결제 시점에 지정되므로 실패 가능성이 남는다

  ${B}필요 없어진 것${R}  에스크로, 중앙청산소, HTLC, 순차 결제와 롤백 로직

  ${B}다음${R}  Step 07 — 공시와 감사. Observer 로 감독기관에 거래를 공시하고,
        누가 무엇을 볼 수 있는지를 설계로 통제합니다.

SUMMARY
