#!/usr/bin/env bash
# Step 11 — External Party 인터랙티브 러너
#
#   ./steps/step11.sh            처음부터
#   ./steps/step11.sh --auto     엔터 대기 없이 전부 실행
#   ./steps/step11.sh --keep     끝나고 노드를 끄지 않음
#
# 자기 키를 쥔 Party 를 온보딩하고, 그 Party 명의로 거래를 성립시킨다.
# 노드 구성은 Step 05 것을, Daml 은 Step 04 의 Deposit 을 그대로 쓴다.

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
WORK="$ROOT/.step11"
LOG="$WORK/canton.log"
WALLET="$WORK/wallet.py"
KEYFILE="$WORK/charlie.key"

BANK_API=http://localhost:5013
BROKER_API=http://localhost:5023

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

post() { # $1=api $2=path $3=body
  curl -s -X POST "$1$2" -H 'Content-Type: application/json' -d "$3"
}

# 응답을 보고 성공/실패를 판단한다. 무조건 성공을 찍지 않는다.
verdict() { # stdin=응답
  jq_ '
if isinstance(d, dict) and d.get("code"):
    print("  실패  " + d["code"])
    c = d.get("cause", "")
    if c: print("  cause:", c[:200])
elif isinstance(d, dict) and d.get("updateId"):
    print("  성공  updateId:", d["updateId"][:24])
else:
    print("  응답 :", json.dumps(d)[:200])
'
}

printf '%s\n' "$B"
cat <<'BANNER'
 Step 11 — External Party
 ────────────────────────────────────────────────────────────
 Step 02 부터 지금까지 모든 거래는 Participant 가 대신 서명했습니다.
 Alice 도 Bob 도 자기 키를 갖고 있지 않습니다. 은행이 만들어 준
 Party 이고, 서명도 은행 노드가 합니다.

 Step 01 에서 그 대비를 이렇게 적어 두었습니다.

     Hosted Party    Participant 가 배신하면 속을 수 있음
     External Party  서명 없이는 불가

 이번에는 그 문장을 실제로 확인합니다. Charlie 가 자기 키를 쥡니다.
BANNER
printf '%s\n' "$R"

# shellcheck disable=SC1091
[ -f ./env.sh ] && source ./env.sh

command -v dpm >/dev/null 2>&1 || die "dpm 을 찾을 수 없습니다.
    설치: https://docs.canton.network/sdks-tools/cli-tools/dpm
    설치 후 PATH 에 추가하세요:  export PATH=\"\$HOME/.dpm/bin:\$PATH\""
java -version >/dev/null 2>&1 || die "JDK 21 이상이 필요합니다.
    JAVA_HOME 을 설정하거나 java 를 PATH 에 두세요."
python3 -c '' 2>/dev/null || die "python3 이 필요합니다."

if [ -z "${CANTON_JAR:-}" ] || [ ! -f "${CANTON_JAR:-}" ]; then
  CANTON_JAR=$(find "${DPM_HOME:-$HOME/.dpm}/cache/components/canton-open-source" \
    -name 'canton-open-source-*.jar' 2>/dev/null | sort -V | tail -1)
fi
[ -n "$CANTON_JAR" ] && [ -f "$CANTON_JAR" ] || die "canton jar 을 찾을 수 없습니다.
    dpm 으로 SDK 를 설치했는지 확인하세요:  dpm install
    또는 직접 지정하세요:  export CANTON_JAR=/path/to/canton-open-source-*.jar"

mkdir -p "$WORK"
rm -f "$KEYFILE"

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

title "기동"
say "Step 05 의 ${B}canton/step05.conf${R} 를 그대로 씁니다. Daml 은 Step 04 의"
say "${B}Deposit${R} 을 씁니다. 새로 만드는 것은 하나도 없습니다."
printf '\n'
cat <<'NODES'

    bank    participant   Bank · Alice          5013
    broker  participant   Charlie 를 호스팅합니다  5023
    public  synchronizer

NODES
pause

DAR=$(ls -t .daml/dist/*.dar 2>/dev/null | head -1)
[ -n "$DAR" ] || { dpm build >/dev/null 2>&1; DAR=$(ls -t .daml/dist/*.dar | head -1); }
ok "DAR: $DAR"

pkill -f 'daemon -c canton/' 2>/dev/null
for _ in $(seq 1 30); do
  pgrep -f 'daemon -c canton/' >/dev/null 2>&1 || break
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

BANK=$(grep  '^BANK='  "$LOG" | tail -1 | cut -d= -f2)
ALICE=$(grep '^ALICE=' "$LOG" | tail -1 | cut -d= -f2)
PKG=$(dpm inspect-dar "$DAR" 2>/dev/null | grep -oE '[0-9a-f]{64}' | head -1)
PROP="$PKG:Step04.Deposit:DepositProposal"

SYNC=$(curl -s "$BROKER_API/v2/state/connected-synchronizers" \
  | jq_ 'print(d["connectedSynchronizers"][0]["synchronizerId"])')
[ -n "$SYNC" ] || die "synchronizer id 를 읽지 못했습니다."
ok "노드 4개 기동 — synchronizer ${SYNC:0:28}..."

# ─── 2 ───────────────────────────────────────────────────────────────────────

title "지금까지 누가 서명했는가"
pause

say "Party ID 는 ${B}이름::지문${R} 입니다. 뒷부분은 그 Party 를 발급한 키의"
say "지문입니다. Bank 와 Alice 를 나란히 놓아 봅니다."
printf '\n'
printf '    Bank    %s\n'   "$BANK"
printf '    Alice   %s\n\n' "$ALICE"

BANK_NS="${BANK#*::}"
ALICE_NS="${ALICE#*::}"
if [ "$BANK_NS" = "$ALICE_NS" ]; then
  ok "뒷부분이 같습니다 — 둘 다 bank participant 가 발급했습니다"
else
  warn "뒷부분이 다릅니다 — 예상과 다릅니다"
fi
printf '\n'
say "Alice 의 키는 ${B}bank 노드가 쥐고 있습니다.${R} Alice 명의의 거래는 bank 노드가"
say "대신 서명합니다. Alice 의 동의를 코드가 확인하는 지점은 없습니다."
printf '\n'
note "Step 01 — \"기술적으로 Bank 는 Alice 동의 없이 Alice 명의 Transaction 을 만들 수"
note "있고, 이를 막는 것은 코드가 아니라 규제와 감사입니다.\""

# ─── 3 ───────────────────────────────────────────────────────────────────────

title "Charlie 의 지갑"
pause

say "External Party 는 ${B}자기 키를 자기가 만듭니다.${R} 노드에 부탁하지 않습니다."
printf '\n'
say "Canton 이 요구하는 것은 ${B}Ed25519${R} 입니다. 러너가 순수 python3 로 된"
say "구현을 ${B}.step11/wallet.py${R} 에 만듭니다 — 설치할 것이 없습니다."
printf '\n'

cat > "$WALLET" <<'PYEOF'
"""Charlie 의 지갑 — Ed25519 (RFC 8032). 표준 라이브러리만 씁니다.

    keygen  <keyfile>            시드를 만들고 공개키(base64)를 출력합니다
    sign    <keyfile> <b64hash>  해시에 서명하고 서명(base64)을 출력합니다
    selftest                     RFC 8032 §7.1 테스트 벡터로 자기검사합니다

지갑이 하는 일은 이것뿐입니다. 무엇에 서명하는지는 부르는 쪽이 정합니다.
"""
import base64, hashlib, os, sys

sys.setrecursionlimit(10000)

p = 2**255 - 19
q = 2**252 + 27742317777372353535851937790883648493

def _H(m): return hashlib.sha512(m).digest()
def _inv(x): return pow(x, p - 2, p)

d = -121665 * _inv(121666) % p
I = pow(2, (p - 1) // 4, p)

def _xrecover(y):
    xx = (y * y - 1) * _inv(d * y * y + 1)
    x = pow(xx, (p + 3) // 8, p)
    if (x * x - xx) % p != 0: x = (x * I) % p
    if x % 2 != 0: x = p - x
    return x

_By = 4 * _inv(5) % p
_B = [_xrecover(_By) % p, _By, 1, _xrecover(_By) * _By % p]

def _add(P, Q):
    A = (P[1] - P[0]) * (Q[1] - Q[0]) % p
    Bb = (P[1] + P[0]) * (Q[1] + Q[0]) % p
    C = 2 * P[3] * Q[3] * d % p
    D = 2 * P[2] * Q[2] % p
    E, F, G, Hh = Bb - A, D - C, D + C, Bb + A
    return [E * F % p, G * Hh % p, F * G % p, E * Hh % p]

def _mul(P, e):
    if e == 0: return [0, 1, 1, 0]
    Q = _mul(P, e // 2); Q = _add(Q, Q)
    return _add(Q, P) if e & 1 else Q

def _encode(P):
    zi = _inv(P[2])
    x, y = P[0] * zi % p, P[1] * zi % p
    return int.to_bytes(y | ((x & 1) << 255), 32, "little")

def _clamp(h):
    a = int.from_bytes(h[:32], "little")
    return (a & ((1 << 254) - 8)) | (1 << 254)

def publickey(seed):
    return _encode(_mul(_B, _clamp(_H(seed))))

def sign(seed, msg):
    h = _H(seed)
    a = _clamp(h)
    A = _encode(_mul(_B, a))
    r = int.from_bytes(_H(h[32:] + msg), "little") % q
    R = _encode(_mul(_B, r))
    k = int.from_bytes(_H(R + A + msg), "little") % q
    return R + int.to_bytes((r + k * a) % q, 32, "little")

if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "keygen":
        seed = os.urandom(32)
        with open(sys.argv[2], "wb") as f: f.write(seed)
        os.chmod(sys.argv[2], 0o600)
        print(base64.b64encode(publickey(seed)).decode())
    elif cmd == "sign":
        seed = open(sys.argv[2], "rb").read()
        msg = base64.b64decode(sys.argv[3])
        print(base64.b64encode(sign(seed, msg)).decode())
    elif cmd == "selftest":
        sk = bytes.fromhex("9d61b19deffd5a60ba844af492ec2cc4"
                           "4449c5697b326919703bac031cae7f60")
        pk = bytes.fromhex("d75a980182b10ab7d54bfed3c964073a"
                           "0ee172f3daa62325af021a68f707511a")
        sg = bytes.fromhex("e5564300c360ac729086e2cc806e828a"
                           "84877f1eb8e5d974d873e065224901555f"
                           "b8821590a33bacc61e39701cf9b46bd25"
                           "bf5f0595bbe24655141438e7a100b")
        assert publickey(sk) == pk, "공개키 불일치"
        assert sign(sk, b"") == sg, "서명 불일치"
        print("PASS")
PYEOF

run "python3 $WALLET selftest"
printf '\n'
say "RFC 8032 §7.1 의 테스트 벡터로 자기검사한 것입니다. 구현이 맞다는 근거입니다."
printf '\n'

printf '%s$ python3 %s keygen %s%s\n\n' "$YE" "$WALLET" "$KEYFILE" "$R"
CHARLIE_PUB=$(python3 "$WALLET" keygen "$KEYFILE")
[ -n "$CHARLIE_PUB" ] || die "키 생성에 실패했습니다."
printf '%s\n\n' "$CHARLIE_PUB"
ok "공개키 32바이트 — 시드는 $KEYFILE 에만 있고 노드로 나가지 않습니다"

# ─── 4 ───────────────────────────────────────────────────────────────────────

title "온보딩 ① — 노드가 토폴로지 트랜잭션을 만들어 줍니다"
pause

say "Party 를 원장에 등재하려면 ${B}Topology Transaction${R} 이 필요합니다. 이건"
say "포맷이 까다로우므로 노드에게 만들어 달라고 합니다."
printf '\n'
say "만들어 주기만 할 뿐 ${B}서명은 하지 않습니다.${R}"
printf '\n'

GEN_REQ=$(printf '{"synchronizer":"%s","partyHint":"Charlie","publicKey":{"format":"CRYPTO_KEY_FORMAT_RAW","keyData":"%s","keySpec":"SIGNING_KEY_SPEC_EC_CURVE25519"}}' \
  "$SYNC" "$CHARLIE_PUB")

printf '%s$ POST %s/v2/parties/external/generate-topology%s\n\n' "$YE" "$BROKER_API" "$R"
GEN=$(post "$BROKER_API" /v2/parties/external/generate-topology "$GEN_REQ")
printf '%s' "$GEN" | jq_ '
if d.get("code"):
    print("  실패  " + d["code"]); print("  cause:", d.get("cause","")[:200])
else:
    print("  partyId              " + d["partyId"])
    print("  publicKeyFingerprint " + d["publicKeyFingerprint"])
    print("  topologyTransactions " + str(len(d["topologyTransactions"])) + " 건")
    print("  multiHash            " + d["multiHash"][:44] + " ...")
'
CHARLIE=$(printf '%s' "$GEN" | jq_ 'print(d.get("partyId",""))')
FP=$(printf     '%s' "$GEN" | jq_ 'print(d.get("publicKeyFingerprint",""))')
MULTIHASH=$(printf '%s' "$GEN" | jq_ 'print(d.get("multiHash",""))')
[ -n "$CHARLIE" ] || die "generate-topology 실패."
printf '\n'
ok "아직 원장에 등재된 것은 없습니다 — 서명이 없으니 제출할 수도 없습니다"

# ─── 5 ───────────────────────────────────────────────────────────────────────

title "온보딩 ② — Charlie 가 서명하고 등재합니다"
pause

say "${B}multiHash${R} 하나에 서명하면 토폴로지 트랜잭션 전체가 인가됩니다."
printf '\n'
printf '%s$ python3 %s sign %s %s...%s\n\n' "$YE" "$WALLET" "$KEYFILE" "${MULTIHASH:0:24}" "$R"
SIG=$(python3 "$WALLET" sign "$KEYFILE" "$MULTIHASH")
[ -n "$SIG" ] || die "서명에 실패했습니다."
printf '  %s...\n\n' "${SIG:0:60}"

TXS=$(printf '%s' "$GEN" | jq_ 'print(json.dumps([{"transaction": t} for t in d["topologyTransactions"]]))')
ALLOC_REQ=$(printf '{"synchronizer":"%s","onboardingTransactions":%s,"multiHashSignatures":[{"format":"SIGNATURE_FORMAT_CONCAT","signature":"%s","signedBy":"%s","signingAlgorithmSpec":"SIGNING_ALGORITHM_SPEC_ED25519"}],"waitForAllocation":true}' \
  "$SYNC" "$TXS" "$SIG" "$FP")

printf '%s$ POST %s/v2/parties/external/allocate%s\n\n' "$YE" "$BROKER_API" "$R"
ALLOC=$(post "$BROKER_API" /v2/parties/external/allocate "$ALLOC_REQ")
printf '%s' "$ALLOC" | jq_ '
if d.get("code"):
    print("  실패  " + d["code"]); print("  cause:", d.get("cause","")[:200])
else:
    print("  partyId  " + d["partyId"])
'
ALLOCATED=$(printf '%s' "$ALLOC" | jq_ 'print(d.get("partyId",""))')
[ "$ALLOCATED" = "$CHARLIE" ] || die "allocate 실패."
printf '\n'

say "세 Party 를 나란히 놓습니다."
printf '\n'
printf '    Bank     %s\n'   "$BANK"
printf '    Alice    %s\n'   "$ALICE"
printf '    Charlie  %s\n\n' "$CHARLIE"

CHARLIE_NS="${CHARLIE#*::}"
if [ "$CHARLIE_NS" != "$BANK_NS" ]; then
  ok "Charlie 의 뒷부분만 다릅니다 — 자기 공개키의 지문입니다"
else
  warn "예상과 다릅니다 — Charlie 의 namespace 가 participant 와 같습니다"
fi
printf '\n'
note "Party ID 만 보고도 누가 키를 쥐고 있는지 알 수 있습니다."

# ─── 6 ───────────────────────────────────────────────────────────────────────

title "Bank 가 Charlie 앞으로 발행을 제안합니다"
pause

for api in "$BANK_API" "$BROKER_API"; do
  post "$api" /v2/users "$(printf '{"user":{"id":"app","primaryParty":"","isDeactivated":false,"identityProviderId":""},"rights":[{"kind":{"CanActAs":{"value":{"party":"%s"}}}},{"kind":{"CanActAs":{"value":{"party":"%s"}}}},{"kind":{"CanActAs":{"value":{"party":"%s"}}}}]}' "$BANK" "$ALICE" "$CHARLIE")" >/dev/null
done

say "DepositProposal 의 signatory 는 bank 뿐이므로 Bank 혼자 만들 수 있습니다."
say "Charlie 는 observer 입니다."
printf '\n'

propose() { # $1=owner $2=amount
  post "$BANK_API" /v2/commands/submit-and-wait "$(printf '{"userId":"app","commandId":"%s","actAs":["%s"],"readAs":[],"commands":[{"CreateCommand":{"templateId":"%s","createArguments":{"deposit":{"bank":"%s","owner":"%s","amount":"%s"}}}}]}' \
    "propose-$(date +%s%N)" "$BANK" "$PROP" "$BANK" "$1" "$2")"
}

find_proposal() { # $1=api $2=party
  OFF=$(curl -s "$1/v2/state/ledger-end" | jq_ 'print(d["offset"])')
  post "$1" /v2/state/active-contracts "$(printf '{"filter":{"filtersByParty":{"%s":{"cumulative":[{"identifierFilter":{"WildcardFilter":{"value":{"includeCreatedEventBlob":false}}}}]}}},"verbose":false,"activeAtOffset":%s}' "$2" "$OFF")" \
  | jq_ '
out = ""
for e in (d if isinstance(d, list) else []):
    ce = e.get("contractEntry", {}).get("JsActiveContract", {}).get("createdEvent")
    if ce and ce["templateId"].endswith("DepositProposal"): out = ce["contractId"]
print(out)
'
}

printf '%s$ POST %s/v2/commands/submit-and-wait   (Bank → Charlie, 100.0)%s\n\n' "$YE" "$BANK_API" "$R"
propose "$CHARLIE" 100.0 | verdict
printf '\n'

CID=""
for _ in $(seq 1 30); do
  CID=$(find_proposal "$BROKER_API" "$CHARLIE")
  [ -n "$CID" ] && break
  sleep 1
done
if [ -n "$CID" ]; then
  ok "broker 노드에서도 보입니다 — ${CID:0:24}..."
else
  die "broker 에서 제안을 찾지 못했습니다."
fi
printf '\n'
note "submit-and-wait 는 제출한 노드가 커밋하면 돌아옵니다. 상대 노드에 도달하는"
note "것은 그보다 조금 뒤이므로 러너는 보일 때까지 기다립니다."

# ─── 7 ───────────────────────────────────────────────────────────────────────

title "broker 노드가 Charlie 명의로 그냥 제출하면"
pause

say "broker 는 Charlie 를 호스팅하는 노드이고, 방금 ${B}CanActAs Charlie${R} 권한까지"
say "가진 user 를 만들었습니다. 그대로 수락을 제출해 봅니다."
printf '\n'

accept_direct() { # $1=api $2=party $3=cid
  post "$1" /v2/commands/submit-and-wait "$(printf '{"userId":"app","commandId":"%s","actAs":["%s"],"readAs":[],"commands":[{"ExerciseCommand":{"templateId":"%s","contractId":"%s","choice":"AcceptDeposit","choiceArgument":{}}}]}' \
    "accept-$(date +%s%N)" "$2" "$PROP" "$3")"
}

printf '%s$ POST %s/v2/commands/submit-and-wait   actAs=[Charlie]%s\n\n' "$YE" "$BROKER_API" "$R"
RES=$(accept_direct "$BROKER_API" "$CHARLIE" "$CID")
printf '%s' "$RES" | verdict
printf '\n'

CODE=$(printf '%s' "$RES" | jq_ 'print(d.get("code",""))')
if [ "$CODE" = "NO_SYNCHRONIZER_ON_WHICH_ALL_SUBMITTERS_CAN_SUBMIT" ]; then
  ok "거부되었습니다 — 노드는 Charlie 를 대리할 수 없습니다"
else
  warn "예상과 다릅니다 — code=$CODE"
fi
printf '\n'
say "${B}User 권한이 있어도 안 됩니다.${R} User 는 Participant 안의 API 호출 자격일 뿐"
say "원장에 없습니다. 원장이 요구하는 것은 Charlie 키의 서명입니다."

# ─── 8 ───────────────────────────────────────────────────────────────────────

title "대조 — 같은 것을 Alice 에게 하면"
pause

say "Alice 는 hosted party 입니다. 똑같이 해 봅니다."
printf '\n'

propose "$ALICE" 50.0 >/dev/null
ACID=""
for _ in $(seq 1 30); do
  ACID=$(find_proposal "$BANK_API" "$ALICE")
  [ -n "$ACID" ] && break
  sleep 1
done
[ -n "$ACID" ] || die "Alice 의 제안을 찾지 못했습니다."
printf '%s$ POST %s/v2/commands/submit-and-wait   actAs=[Alice]%s\n\n' "$YE" "$BANK_API" "$R"
ARES=$(accept_direct "$BANK_API" "$ALICE" "$ACID")
printf '%s' "$ARES" | verdict
printf '\n'

if printf '%s' "$ARES" | grep -q updateId; then
  warn "성공했습니다 — Alice 의 동의를 확인한 곳은 어디에도 없습니다"
else
  warn "예상과 다릅니다 — Alice 의 제출이 실패했습니다"
fi
printf '\n'
cat <<'CONTRAST'

    Alice   (hosted)     bank 노드가 제출  →  성공
    Charlie (external)   broker 노드가 제출 →  거부

CONTRAST
say "Step 01 의 표가 실행 결과로 확인된 지점입니다."

# ─── 9 ───────────────────────────────────────────────────────────────────────

title "prepare — 노드가 만들고, 서명은 받지 않습니다"
pause

say "External Party 의 거래는 ${B}두 번에 나눠 제출합니다.${R}"
printf '\n'
cat <<'FLOW'

    prepare   노드가 트랜잭션을 해석해 만들고 해시를 돌려줍니다
      ↓
    sign      Party 가 자기 키로 그 해시에 서명합니다
      ↓
    execute   서명을 붙여 제출합니다

FLOW

PREP_REQ=$(printf '{"userId":"app","commandId":"%s","actAs":["%s"],"readAs":[],"commands":[{"ExerciseCommand":{"templateId":"%s","contractId":"%s","choice":"AcceptDeposit","choiceArgument":{}}}],"synchronizerId":"%s","packageIdSelectionPreference":[],"verboseHashing":false}' \
  "accept-$(date +%s%N)" "$CHARLIE" "$PROP" "$CID" "$SYNC")

printf '%s$ POST %s/v2/interactive-submission/prepare%s\n\n' "$YE" "$BROKER_API" "$R"
PREP=$(post "$BROKER_API" /v2/interactive-submission/prepare "$PREP_REQ")
printf '%s' "$PREP" | jq_ '
if d.get("code"):
    print("  실패  " + d["code"]); print("  cause:", d.get("cause","")[:200])
else:
    import base64
    print("  hashingSchemeVersion    " + d["hashingSchemeVersion"])
    print("  preparedTransactionHash " + d["preparedTransactionHash"] +
          "   (" + str(len(base64.b64decode(d["preparedTransactionHash"]))) + " 바이트)")
    print("  preparedTransaction     " + str(len(d["preparedTransaction"])) + " 자")
'
HASH=$(printf '%s' "$PREP" | jq_ 'print(d.get("preparedTransactionHash",""))')
PTX=$(printf  '%s' "$PREP" | jq_ 'print(d.get("preparedTransaction",""))')
SCHEME=$(printf '%s' "$PREP" | jq_ 'print(d.get("hashingSchemeVersion",""))')
[ -n "$HASH" ] || die "prepare 실패."
printf '\n'
note "OpenAPI 명세는 synchronizerId 와 packageIdSelectionPreference 를 Optional 로"
note "적어 두었지만, 빼면 400 이 납니다. 둘 다 보내야 합니다."
printf '\n'
warn "노드가 만들어 준 것에 그냥 서명하면 안 됩니다"
say "공식 문서가 이렇게 적어 두었습니다 — ${DIM}\"Clients MUST display the content of"
say "the transaction to the user for them to validate before signing the hash if the"
say "preparing participant is not trusted.\"${R}"
printf '\n'
say "노드를 남에게 맡겼다면 ${B}preparedTransaction 을 열어 확인한 뒤${R} 서명해야 합니다."

# ─── 10 ──────────────────────────────────────────────────────────────────────

title "sign · execute — 그리고 남의 키로 서명하면"
pause

say "먼저 ${B}틀린 키${R}로 서명해서 보냅니다."
printf '\n'

execute() { # $1=signature $2=signedBy
  post "$BROKER_API" /v2/interactive-submission/executeAndWait "$(printf '{"preparedTransaction":"%s","partySignatures":{"signatures":[{"party":"%s","signatures":[{"format":"SIGNATURE_FORMAT_CONCAT","signature":"%s","signedBy":"%s","signingAlgorithmSpec":"SIGNING_ALGORITHM_SPEC_ED25519"}]}]},"deduplicationPeriod":{"Empty":{}},"submissionId":"%s","userId":"app","hashingSchemeVersion":"%s"}' \
    "$PTX" "$CHARLIE" "$1" "$2" "sub-$(date +%s%N)" "$SCHEME")"
}

python3 "$WALLET" keygen "$WORK/impostor.key" >/dev/null
BADSIG=$(python3 "$WALLET" sign "$WORK/impostor.key" "$HASH")
printf '%s$ POST %s/v2/interactive-submission/executeAndWait   (impostor.key 로 서명)%s\n\n' "$YE" "$BROKER_API" "$R"
BADRES=$(execute "$BADSIG" "$FP")
printf '%s' "$BADRES" | verdict
printf '\n'
if printf '%s' "$BADRES" | grep -q 'FAILED_TO_EXECUTE_TRANSACTION'; then
  ok "거부되었습니다"
else
  warn "예상과 다릅니다"
fi
rm -f "$WORK/impostor.key"

printf '\n'
say "이제 ${B}Charlie 의 키${R}로 서명합니다."
printf '\n'
printf '%s$ python3 %s sign %s %s...%s\n\n' "$YE" "$WALLET" "$KEYFILE" "${HASH:0:24}" "$R"
GOODSIG=$(python3 "$WALLET" sign "$KEYFILE" "$HASH")
[ -n "$GOODSIG" ] || die "서명에 실패했습니다."
printf '  %s...\n\n' "${GOODSIG:0:60}"

printf '%s$ POST %s/v2/interactive-submission/executeAndWait%s\n\n' "$YE" "$BROKER_API" "$R"
GOODRES=$(execute "$GOODSIG" "$FP")
printf '%s' "$GOODRES" | verdict
printf '\n'

OFF=$(curl -s "$BROKER_API/v2/state/ledger-end" | jq_ 'print(d["offset"])')
DEPOSITS=$(post "$BROKER_API" /v2/state/active-contracts "$(printf '{"filter":{"filtersByParty":{"%s":{"cumulative":[{"identifierFilter":{"WildcardFilter":{"value":{"includeCreatedEventBlob":false}}}}]}}},"verbose":false,"activeAtOffset":%s}' "$CHARLIE" "$OFF")" \
  | jq_ '
n = 0
for e in (d if isinstance(d, list) else []):
    ce = e.get("contractEntry", {}).get("JsActiveContract", {}).get("createdEvent")
    if ce and ce["templateId"].endswith(":Deposit"):
        a = ce["createArgument"]
        print("    Deposit  owner=" + a["owner"].split("::")[0] + "  amount=" + a["amount"])
        n += 1
print("COUNT=" + str(n))
')
printf '%s\n' "$DEPOSITS" | grep -v '^COUNT='
if printf '%s' "$DEPOSITS" | grep -q 'COUNT=0'; then
  die "Charlie 의 Deposit 이 생기지 않았습니다."
else
  ok "Charlie 명의의 Deposit 이 원장에 있습니다"
fi

# ─── 11 ──────────────────────────────────────────────────────────────────────

title "확인한 것"
cat <<SUMMARY

  Party ID           이름::지문. 뒷부분은 ${B}그 Party 를 발급한 키${R}의 지문입니다
  Hosted Party       Participant 가 키를 쥡니다. 노드가 대신 서명합니다
  External Party     본인이 키를 쥡니다. 노드는 대리하지 못합니다
  온보딩              generate-topology → 본인 서명 → allocate
  거래                prepare → 본인 서명 → execute. 두 번에 나뉩니다
  User 권한           있어도 소용없습니다. 원장이 요구하는 것은 키의 서명입니다
  서명 전 확인         노드를 믿지 못하면 preparedTransaction 을 열어 봐야 합니다
  서명 포맷           Ed25519 는 SIGNATURE_FORMAT_CONCAT (RFC 8032 §3.3 의 R‖S)

  ${B}실행으로 확인된 대조${R}

  Alice   (hosted)     노드가 직접 제출  →  성공
  Charlie (external)   노드가 직접 제출  →  NO_SYNCHRONIZER_ON_WHICH_ALL_SUBMITTERS_CAN_SUBMIT
  Charlie              남의 키로 서명    →  FAILED_TO_EXECUTE_TRANSACTION
  Charlie              자기 키로 서명    →  성공

  ${B}확인하지 못한 것${R}

  키를 여러 개 두고 threshold 를 거는 구성 — 키 하나로만 했습니다
  여러 Participant 에 다중 호스팅하는 구성 — broker 한 곳에만 올렸습니다
  키 교체(rotation) — 온보딩 이후 토폴로지를 바꾸지 않았습니다
  HSM·수탁사 연동 — 시드를 파일에 두었습니다

SUMMARY

if [ "$KEEP" = 1 ]; then
  say "노드가 계속 실행 중입니다."
  note "  export BANK='$BANK'"
  note "  export ALICE='$ALICE'"
  note "  export CHARLIE='$CHARLIE'"
  note "  export SYNC='$SYNC'"
  note "  export PKG=$PKG"
  note "  bank    JSON API   $BANK_API"
  note "  broker  JSON API   $BROKER_API"
  note "  지갑                $WALLET"
  note "  Charlie 의 시드      $KEYFILE"
else
  say "노드를 종료합니다. 인메모리이므로 Party·User·Contract 가 모두 사라집니다."
  note "계속 살려두려면: ./steps/step11.sh --keep"
fi
