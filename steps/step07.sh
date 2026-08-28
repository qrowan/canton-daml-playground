#!/usr/bin/env bash
# Step 07 — 공시와 감사 인터랙티브 러너
#
#   ./steps/step07.sh            처음부터
#   ./steps/step07.sh --auto     엔터 대기 없이 전부 실행

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
TOTAL=9
SRC="daml/Step07/Disclosure.daml"
TST="daml/Step07/DisclosureTest.daml"
OUT="$ROOT/.step07/test.out"

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
  line=$(grep "Step07/DisclosureTest.daml:${name}:" "$OUT" 2>/dev/null | head -1)
  if [ -n "$line" ]; then
    printf '  %s✓%s %-32s %s\n' "$GR" "$R" "$name" "${line#*: }"
  else
    printf '  %s✗%s %-32s (결과 없음)\n' "$RD" "$R" "$name"
  fi
}

printf '%s\n' "$B"
cat <<'BANNER'
 Step 07 — 공시와 감사
 ────────────────────────────────────────────────────────────
 지금까지 프라이버시는 늘 "안 보인다" 쪽이었습니다.
 이번에는 반대입니다 — 보여야 하는 것을 어떻게 보이게 하는가.

   Citi       발행 은행
   Alice      Citi 의 고객
   Bob        이체 상대
   SEC        감독기관. 상시 공시 대상
   Auditor    외부 감사인. 필요할 때만 공시
   David      제3자. 아무것도 못 봄
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
mkdir -p "$ROOT/.step07"

# ─── 1 ───────────────────────────────────────────────────────────────────────

title "문제 — SEC 는 당사자가 아닙니다"
say "SEC 는 Citi 가 발행하는 모든 예금을 감독해야 합니다."
say "그런데 SEC 는 예금 계약의 Signatory 가 아닙니다. 당사자가 아니기 때문입니다."
printf '\n'
say "Step 02 에서 David 가 Alice 의 예금을 못 본 것과 같은 상황입니다."
say "Stakeholder 가 아니면 데이터가 도달하지 않습니다."
pause

cat <<'ROLES'
    Signatory    동의가 필요하다      계약 성립에 서명이 필요
    Observer     보여준다             권한은 없고 가시성만
    Controller   행사할 수 있다        특정 Choice 를 실행

ROLES
say "${B}Observer 가 이 문제를 풉니다.${R} 서명 없이 가시성만 줍니다."

# ─── 2 ───────────────────────────────────────────────────────────────────────

title "Template 에 Observer 를 박습니다"
pause

show "$SRC" "^template RegulatedDeposit" 11

printf '\n'
say "regulator 를 필드로 갖고 observer 로 선언합니다."
printf '\n'
say "${B}이 Template 으로 만든 모든 Contract 는 처음부터 SEC 에게 보입니다.${R}"
note "Observer 는 Stakeholder 에 포함되므로 그 Contract 가 SEC 의 Participant 에도"
note "전달되고, 확인 프로토콜에서 Informee 가 됩니다."

# ─── 3 ───────────────────────────────────────────────────────────────────────

title "공시는 설계 시점에 결정됩니다"
pause

cat <<'DESIGN'
    나중에 "이 거래는 공시하고 저 거래는 감추자" 를 할 수 없습니다.
    감추려면 다른 Template 을 써야 합니다.

    Solidity        이벤트를 나중에 끄고 켤 수 있다
    Daml            Template 이 공시 범위를 확정한다

DESIGN
warn "규제 대상 자산의 Template 설계는 공시 범위를 확정하는 일입니다."
say "법무·컴플라이언스가 관여해야 하는 지점이고, 개발자가 혼자 정할 것이 아닙니다."

# ─── 4 ───────────────────────────────────────────────────────────────────────

title "Observer 는 권한을 주지 않습니다"
say "SEC 는 모든 예금을 봅니다. 그런데 아무것도 못 합니다."
pause

show "$TST" "^testRegulatorCannotTransfer" 8

printf '\n'
say "이체시킬 수도, archive 할 수도 없습니다. ${B}Choice 가 없기 때문입니다.${R}"
printf '\n'
note "Step 04 에서 제안을 Observer 가 본다고 수락할 수 있는 게 아니었던 것과"
note "같은 원리입니다. 볼 수 있는 것과 할 수 있는 것은 별개입니다."

# ─── 5 ───────────────────────────────────────────────────────────────────────

title "개입하게 하려면 Choice 로 명시합니다"
say "감독기관이 동결까지 할 수 있어야 한다면, 그 권한을 Choice 로 써 줘야 합니다."
pause

show "$SRC" "choice Freeze" 6

printf '\n'
cat <<'AUTH'
    signatory  = Citi, Alice
    controller = SEC
    ─────────────────────────
    권한        = Citi, Alice, SEC

    만들려는 Contract 의 signatory = Citi, Alice        → 충족

AUTH
say "SEC 는 Signatory 가 아닌데도 Choice 를 행사합니다."
say "Step 03 에서 본 대로 ${B}Controller 는 Signatory 와 별개${R}이기 때문입니다."
printf '\n'
note "그리고 Alice 는 이 Template 을 수락한 시점에 'SEC 가 동결할 수 있다' 에"
note "이미 동의했습니다. 약관에 서명하는 것과 같습니다."

# ─── 6 ───────────────────────────────────────────────────────────────────────

title "동결이 실제로 막습니다"
pause

show "$SRC" "choice ProposeTransfer" 8

printf '\n'
say "frozen 플래그를 assertMsg 로 검사합니다. 동결 중에는 이체 제안 자체가"
say "만들어지지 않습니다."
note "권한 검사가 아니라 상태 검사입니다. Alice 는 여전히 Controller 이지만"
note "Choice 본문이 거부합니다."

# ─── 7 ───────────────────────────────────────────────────────────────────────

title "선택적 공시 — 필요할 때만 열기"
say "SEC 는 상시 공시입니다. 외부 감사인은 그렇지 않습니다."
pause

show "$SRC" "choice Publish" 6
printf '\n'
show "$SRC" "^template AuditedDeposit" 8

printf '\n'
say "Publish 는 Observer 가 하나 더 있는 새 Contract 를 만듭니다."
printf '\n'
warn "Contract 는 수정되지 않으므로 Observer 를 더하는 것도 archive + create 입니다."
say "Contract ID 가 바뀝니다."
printf '\n'
warn "그리고 공시는 되돌릴 수 없습니다."
say "Unpublish 는 ${B}앞으로 안 보이게${R} 할 뿐 ${B}본 것을 잊게${R} 하지 못합니다."
note "원장은 append-only 이고 상대 노드의 저장소를 우리가 통제하지 않습니다."

# ─── 8 ───────────────────────────────────────────────────────────────────────

title "실행"
pause

printf '%s$ dpm test%s\n\n' "$YE" "$R"
dpm test > "$OUT" 2>&1
[ $? = 0 ] || { tail -30 "$OUT"; die "테스트 실패"; }

printf '  %s상시 공시%s\n' "$B" "$R"
for t in testRegulatorSees testStrangerSeesNothing testRegulatorSeesTransfer; do result "$t"; done
printf '\n  %sObserver 는 권한이 아니다%s\n' "$B" "$R"
for t in testRegulatorCannotTransfer testRegulatorCannotArchive testStrangerCannotFreeze; do result "$t"; done
printf '\n  %s명시된 권한만 행사할 수 있다%s\n' "$B" "$R"
for t in testRegulatorFreezes testFrozenCannotTransfer testUnfreezeRestores testOwnerCannotFreeze; do result "$t"; done
printf '\n  %s선택적 공시%s\n' "$B" "$R"
for t in testAuditorSeesNothingBefore testPublishAddsAuditor testUnpublishHidesFuture; do result "$t"; done

printf '\n'
ok "Step 07 테스트 13개 통과 (전체 $(grep -c ': ok,' "$OUT") 개)"

# ─── 9 ───────────────────────────────────────────────────────────────────────

title "확인한 것"
cat <<SUMMARY

  Observer           서명 없이 가시성만. Stakeholder 에 포함된다
  공시는 설계다        Template 이 공시 범위를 확정한다. 나중에 못 바꾼다
  가시성 ≠ 권한       SEC 는 모든 예금을 보지만 아무것도 못 한다
  개입하려면 Choice   Freeze 처럼 Controller 를 명시해야 행사할 수 있다
  Controller≠Signatory SEC 는 Signatory 가 아닌데도 Choice 를 행사한다
  상태 검사           동결은 권한이 아니라 Choice 본문의 assertMsg 로 막는다
  선택적 공시          Observer 추가도 archive + create. Contract ID 가 바뀐다
  되돌릴 수 없다       Unpublish 는 앞으로만 막는다. 본 것은 지우지 못한다

  ${B}다음${R}  Step 08 — Synchronizer. 여러 Synchronizer 와 Reassignment 로
        Contract 가 원장 사이를 이동하는 것을 다룹니다.

SUMMARY
