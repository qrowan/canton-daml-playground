#!/usr/bin/env bash
# Step 03 — 첫 계약 인터랙티브 러너
#
#   ./steps/step03.sh            처음부터
#   ./steps/step03.sh --auto     엔터 대기 없이 전부 실행
#
# Sandbox 를 띄우지 않는다. daml test 의 인메모리 엔진으로 빠르게 돈다.

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
SRC="daml/Step03/Deposit.daml"
TST="daml/Step03/DepositTest.daml"
OUT="$ROOT/.step03/test.out"

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

# 파일의 특정 구간을 보여준다: show <파일> <시작패턴> <줄수>
show() {
  local f="$1" pat="$2" n="$3"
  local start
  start=$(grep -n -- "$pat" "$f" | head -1 | cut -d: -f1)
  [ -n "$start" ] || { warn "구간을 찾지 못했습니다: $pat"; return; }
  printf '%s%s:%s%s\n' "$DIM" "$f" "$start" "$R"
  sed -n "${start},$((start + n - 1))p" "$f" | sed 's/^/    /'
}

# 테스트 결과에서 한 스크립트의 상태를 뽑는다
result() {
  local name="$1"
  local line
  line=$(grep "Step03/DepositTest.daml:${name}:" "$OUT" 2>/dev/null | head -1)
  if [ -n "$line" ]; then
    printf '  %s✓%s %-28s %s\n' "$GR" "$R" "$name" "${line#*: }"
  else
    printf '  %s✗%s %-28s (결과 없음)\n' "$RD" "$R" "$name"
  fi
}

printf '%s\n' "$B"
cat <<'BANNER'
 Step 03 — 첫 계약
 ────────────────────────────────────────────────────────────
 Deposit 템플릿에 choice 를 추가하고, daml test 로 검증한다.
 Daml 문법과 권한 계산 규칙을 코드로 익힌다.

 Step 02 는 원장을 관찰했다. 여기서는 코드를 쓴다.
BANNER
printf '%s\n' "$R"

[ -f ./env.sh ] || die "env.sh 가 없습니다. README 의 '세팅' 절을 먼저 진행하세요."
# shellcheck disable=SC1091
source ./env.sh
command -v daml >/dev/null 2>&1 || die "daml 을 찾을 수 없습니다."
mkdir -p "$ROOT/.step03"

# ─── 1 ───────────────────────────────────────────────────────────────────────

title "template — 계약의 설계도"
say "필드는 with 블록, 규칙은 where 블록에 쓴다."
pause

show "$SRC" "^template Deposit" 9

printf '\n'
say "${B}signatory bank, owner${R} — 둘 다 동의해야 성립한다."
say "Step 02 에서 Citi 권한만으로 제출했을 때 거부된 이유가 이 한 줄이다."
printf '\n'
say "${B}ensure amount > 0.0${R} — 원장에 기록되기 전 항상 검사되는 불변식."
note "template 에 선언되지 않은 것은 존재하지 않는다. onlyOwner 로 막는 게 아니라"
note "애초에 그런 행위가 없다."

# ─── 2 ───────────────────────────────────────────────────────────────────────

title "choice — 계약에 할 수 있는 일"
say "계약의 상태를 바꾸는 유일한 수단이다."
pause

show "$SRC" "choice Withdraw" 13

printf '\n'
say "구조는 이렇다."
cat <<'SYNTAX'

    choice <이름> : <반환 타입>
      with
        <인자> : <타입>        행사할 때 넘기는 값
      controller <party>       이 choice 를 행사할 수 있는 party
      do
        <본문>

SYNTAX
say "${B}controller 는 signatory 와 별개다.${R} signatory 가 아닌 party 도"
say "controller 가 될 수 있다. Step 04 에서 그 형태가 나온다."

# ─── 3 ───────────────────────────────────────────────────────────────────────

title "계약은 수정되지 않는다"
say "Withdraw 는 amount 필드를 줄이는 것처럼 보이지만 그렇지 않다."
say "기존 계약을 소비(archive)하고 새 금액의 계약을 만든다."
pause

cat <<'DIAGRAM'
    Solidity     deposit.amount -= 30       주소 그대로, 값만 변경

    Daml         archive(cid1)              cid1 은 무효가 되고
                 create Deposit{70.0}       cid2 가 새로 생긴다
                 ← 하나의 원자적 트랜잭션

DIAGRAM
say "그래서 계약 ID 가 매번 바뀌고, 원장에 모든 변경 이력이 남는다."
note "실무 함의: 계약 ID 를 외부 시스템에 저장해두면 곧 무효가 된다."
note "조회는 query 로 다시 하는 것이 원칙이다."

# ─── 4 ───────────────────────────────────────────────────────────────────────

title "consuming 과 nonconsuming"
say "choice 는 기본이 consuming 이다. 행사되면 계약이 사라진다."
say "소비하지 않으려면 nonconsuming 을 앞에 붙인다."
pause

show "$SRC" "nonconsuming choice ShowBalance" 4

printf '\n'
say "잔액 조회처럼 상태를 바꾸지 않는 행위에 쓴다."
note "다만 Daml Script 나 API 로 그냥 query 하면 될 일을 choice 로 만들 필요는 없다."
note "nonconsuming 이 정말 필요한 것은 계약을 유지하면서 다른 계약을 만들 때다."

# ─── 5 ───────────────────────────────────────────────────────────────────────

title "권한은 어떻게 계산되는가"
say "choice 를 행사하면 권한이 이렇게 합쳐진다."
printf '\n'
cat <<'AUTH'
    [그 계약의 signatory]  +  [choice 의 controller]

AUTH
pause

show "$SRC" "choice AddInterest" 8

printf '\n'
cat <<'CALC'
    AddInterest 의 경우

      signatory  = Citi, Alice
      controller = Citi
      ─────────────────────────
      권한        = Citi, Alice

      만들려는 계약의 signatory = Citi, Alice   → 충족

CALC
say "${B}Citi 혼자 행사했는데 Alice 서명이 필요한 계약이 만들어진다.${R}"
printf '\n'
say "이것이 중요한 함의를 갖는다 — ${B}계약에 서명한다는 것은 그 template 에 선언된"
say "모든 choice 에 동의한다는 뜻${R}이다. Alice 는 Deposit 을 수락한 시점에"
say "'Citi 가 이자를 붙일 수 있다'에 이미 동의했다. 매번 다시 묻지 않는다."
printf '\n'
note "현실의 계약과 같다. 약관에 서명하면 그 조항이 발동할 때마다 다시 서명하지 않는다."

# ─── 6 ───────────────────────────────────────────────────────────────────────

title "테스트 — Daml Script"
say "daml test 는 인메모리 엔진으로 스크립트를 실행한다."
say "빠르지만 Canton 이 아니다. Sequencer·Mediator·확인 프로토콜이 없다."
printf '\n'
say "로직 검증은 여기서 빠르게, 원장 동작 확인은 Step 02 의 러너로."
pause

show "$TST" "^testPartialWithdraw" 15

printf '\n'
note "submitMustFail 은 '반드시 거부되어야 함'을 검증한다."
note "성공 경로만큼 실패 경로를 테스트하는 것이 권한 모델에서는 특히 중요하다."

# ─── 7 ───────────────────────────────────────────────────────────────────────

title "실행"
say "전체 테스트를 돌린다."
pause

printf '%s$ daml test%s\n\n' "$YE" "$R"
daml test --no-legacy-assistant-warning > "$OUT" 2>&1
TEST_EXIT=$?

PASSED=$(grep -c ': ok,' "$OUT" 2>/dev/null || echo 0)
if [ "$TEST_EXIT" != 0 ]; then
  tail -30 "$OUT"
  die "테스트 실패"
fi

for t in testIssue testBankAloneCannotIssue testOwnerAloneCannotIssue \
         testEnsureRejectsZero testShowBalance testPartialWithdraw \
         testFullWithdraw testWithdrawTooMuch testBankAddsInterest \
         testOwnerCannotAddInterest testTransferFails; do
  result "$t"
done

printf '\n'
ok "$PASSED 개 통과 (setup 헬퍼 포함)"

printf '\n'
say "커버리지 리포트도 함께 나온다."
grep -A 3 "Internal template choices" "$OUT" | sed 's/^/    /'
printf '\n'
note "5개 중 3개만 행사된 것으로 나온다. 나머지 둘은 Transfer 와 Archive 다."
note "Transfer 는 submitMustFail 로만 호출되므로 '행사됨'으로 세지 않는다 — 실제로"
note "성공한 적이 없기 때문이다. Archive 는 이 테스트에서 직접 부르지 않았다."

# ─── 8 ───────────────────────────────────────────────────────────────────────

title "Transfer 는 왜 실패하는가"
say "Alice 가 Bob 에게 예금을 넘기는 choice 를 순진하게 써 보면 이렇다."
pause

show "$SRC" "choice Transfer" 7

printf '\n'
say "컴파일은 된다. 그런데 실행하면 실패한다."
printf '\n'
cat <<'CALC2'
      signatory  = Citi, Alice
      controller = Alice
      ─────────────────────────
      권한        = Citi, Alice

      만들려는 계약의 signatory = Citi, Bob
                                        ↑ Bob 의 권한이 없다

CALC2
say "테스트가 이것을 문서화하고 있다."
show "$TST" "^testTransferFails" 12

printf '\n'
warn "이것은 버그가 아니다."
say "Deposit 은 owner 의 서명이 필요한 계약인데, 아직 아무 관계도 없는 Bob 이"
say "서명했을 리 없다. ${B}남에게 원치 않는 채권·채무를 떠넘길 수 없다${R}는 뜻이고,"
say "Daml 이 의도한 안전장치다."
printf '\n'
note "현실에서도 마찬가지다. 내 예금 계약의 명의를 상대 동의 없이 남에게"
note "넘길 수는 없다."

# ─── 9 ───────────────────────────────────────────────────────────────────────

title "직접 해보기"
cat <<'TRY'

  1. Withdraw 의 assertMsg 를 지우고 daml test 를 다시 돌려 본다.
     testWithdrawTooMuch 가 실패한다. 왜?

  2. AddInterest 의 controller 를 owner 로 바꿔 본다.
     testBankAddsInterest 와 testOwnerCannotAddInterest 중 무엇이 깨지는가?

  3. ensure 줄을 지우고 testEnsureRejectsZero 를 돌려 본다.

  4. ShowBalance 에서 nonconsuming 을 떼어 본다.
     testShowBalance 의 isSome 단정이 왜 깨지는가?

  5. Transfer 의 controller 를 controller owner, newOwner 로 바꿔 본다.
     testTransferFails 가 통과하지 않게 된다. 이것이 옳은 해결인가?
     (힌트: 그러면 트랜잭션을 누가 제출해야 하는가)

TRY
pause

# ─── 10 ──────────────────────────────────────────────────────────────────────

title "확인한 것"
cat <<SUMMARY

  template          with 는 필드, where 는 규칙
  signatory         동의가 필요한 party. 한쪽만으로는 계약을 못 만든다
  ensure            원장 기록 전 항상 검사되는 불변식
  choice            상태를 바꾸는 유일한 수단. 기본은 consuming
  nonconsuming      계약을 소비하지 않는 choice
  controller        그 choice 를 행사할 수 있는 party. signatory 와 별개
  권한 계산          [계약의 signatory] + [choice 의 controller]
  서명의 의미        template 의 모든 choice 에 미리 동의하는 것
  계약 불변성        수정이 아니라 archive + create. 계약 ID 가 바뀐다
  daml test         인메모리 개발 루프. Canton 이 아니다

  ${B}남은 문제${R}  Transfer 가 실패한다. 새 owner 의 권한을 어떻게 얻는가?

  ${B}다음${R}  Step 04 — propose/accept. 두 시점에 나뉜 동의를 하나의
        트랜잭션에서 결합해 이체를 성립시킨다.

SUMMARY
