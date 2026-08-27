# Step 02 — 환경 세팅

[Step 01](Step01Terminology.md) 에서 정의한 용어가 실제로 무엇인지 눈으로 확인합니다.
Canton 원장을 띄우고, party 와 user 를 만들고, HTTP 로 계약을 생성해 프라이버시와
권한 검사를 관찰합니다.

Daml Script(`dpm test`)를 거치지 않고 **실제 애플리케이션이 쓰는 경로**로만 진행합니다.

## 실행

저장소 루트에서:

```sh
./steps/step02.sh
```

스크립트가 자기 파일 위치를 기준으로 저장소 루트를 찾으므로, 어느 경로에서 호출해도
동작합니다.

하나의 터미널에서 **설명 → 엔터 → 실행 → 결과** 순으로 12단계를 진행합니다.
Sandbox 기동과 종료도 스크립트가 처리합니다.

| 옵션 | 용도 |
| --- | --- |
| (없음) | 단계마다 엔터를 기다린다 |
| `--auto` | 엔터 없이 전부 실행 |
| `--keep` | 끝나고 sandbox 를 끄지 않습니다. 직접 더 만져보고 싶을 때 |

`--keep` 으로 끝내면 `API` / `CITI` / `ALICE` / `DAVID` / `PKG` 값을 출력해 주므로,
같은 터미널에서 `curl` 을 이어서 던져볼 수 있습니다.

사전에 [README](../README.md) 의 세팅(`env.sh` 생성)이 끝나 있어야 합니다.

## 등장 인물

| 이름 | 역할 |
| --- | --- |
| **Citi** | 토큰화 예금을 발행하는 은행 (party) |
| **Alice** | Citi 의 고객 (party) |
| **David** | Citi 의 또 다른 고객 (party) |

셋 다 같은 participant 가 발급한 **hosted party** 다. 자기 키를 갖고 있지 않다.

Alice 와 David 는 **같은 은행의 고객이고 같은 노드에 있습니다.** 그런데도 서로의 예금이
보이지 않는다 — 프라이버시의 단위가 기관이나 노드가 아니라 **party** 임을 보여줍니다.

다른 은행 고객인 Bob 은 participant 를 분리하는 Step 05 에서 등장합니다.

## 사용하는 템플릿

`daml/Step02/Deposit.daml`. 문법은 Step 03 에서 다루고, 여기서는 원장 동작을 보기
위한 최소 재료로만 씁니다.

```daml
template Deposit
  with
    bank : Party
    owner : Party
    amount : Decimal
  where
    signatory bank, owner
    ensure amount > 0.0
```

`signatory` 가 둘이므로 **은행과 예금주 양쪽의 권한**이 있어야 계약이 성립합니다.

## 12단계

| # | 단계 | 확인하는 것 |
| --- | --- | --- |
| 1 | DAR 빌드 | 컴파일 결과물이 배포 단위가 된다 |
| 2 | DAR 내부 | `.dalf` 하나가 package 하나, 파일명 뒤 64자가 package-id, 원본 소스도 포함 |
| 3 | Sandbox 기동 | Participant + Sequencer + Mediator 가 한 JVM 에. **synchronizer 연결까지 기다려야 합니다** |
| 4 | 빈 원장 확인 | `sandbox::` admin party 와 `participant_admin` user 만 존재 |
| 5 | Party 생성 | 세 party 의 namespace 지문이 모두 같다 → 같은 노드가 발급 |
| 6 | User 생성 | `citi-settlement` 하나가 Citi + Alice 를 대리 → party ↔ user 는 N:M |
| 7 | package-id | 내용 해시. 원장에 vetting 된 것과 대조 |
| 8 | 권한 부족 | Citi 권한만으로는 예금 생성 실패 |
| 9 | 양쪽 권한 | `actAs` 에 Citi + Alice → 성공 |
| 10 | 조회 | Alice 는 계약을 보고, David 는 빈 배열 |
| 11 | 위조 시도 | David 가 Alice 명의로 만들려 하면 거부 |
| 12 | 정리 | 확인한 것 요약 |

## 이 Step 에서 반드시 남아야 할 것

### 1. JSON API 가 응답하는 것과 원장이 준비된 것은 다르다

3단계에서 `/v2/state/connected-synchronizers` 를 확인합니다. Participant 가
synchronizer 에 연결되기 전에 party 를 만들려 하면 이렇게 거부됩니다.

```
PARTY_ALLOCATION_WITHOUT_CONNECTED_SYNCHRONIZER
Cannot allocate a party without being connected to a synchronizer
```

`sandbox::` admin party 도 이 연결 이후에 나타난다.

### 2. Party ID 의 뒷부분이 발급자를 가리킨다

5단계 출력에서 세 party 의 `::` 뒷부분이 모두 같습니다.

```
Citi::12204ca735307c57cae751278f174ec2610f3147dc5fd8acb5a4b1a1f335564adc05
Alice::12204ca735307c57cae751278f174ec2610f3147dc5fd8acb5a4b1a1f335564adc05
David::12204ca735307c57cae751278f174ec2610f3147dc5fd8acb5a4b1a1f335564adc05
sandbox::12204ca735307c57cae751278f174ec2610f3147dc5fd8acb5a4b1a1f335564adc05
```

이 지문이 **이 party 들을 발급·인가한 키**의 것입니다. `partyIdHint` 로 준 이름은
힌트일 뿐이고 식별자는 전체 문자열입니다.

### 3. Party 만으로는 아무것도 못 합니다

Party 는 원장의 주체이고, 그 party 로 API 를 호출하려면 **user** 가 필요하다.
인증이 꺼져 있어도 그렇다. 없이 제출하면:

```
INVALID_TOKEN: The submitted request is missing a user-id
```

6단계에서 `citi-settlement` 에 Citi 와 Alice 두 party 의 `CanActAs` 를 줍니다.
은행 백오피스가 자기 명의와 고객 명의를 모두 대리하는 실제 구성입니다.

### 4. 권한은 필드가 아니라 signatory 선언에서 나옵니다

8단계와 11단계가 같은 것을 두 각도에서 보여줍니다.

```
DAML_AUTHORIZATION_ERROR
requires authorizers Alice::1220..., but only David::1220... were given
```

`createArguments` 에 `owner` 를 Alice 로 쓴 것이 Alice 의 권한을 만들어주지 않습니다.

**에러에 `david-web` 이라는 user 이름이 없습니다.** User 는 "David 를 주장해도 되는가"만
판정하고 사라졌고, Daml 엔진에는 party 만 도달했습니다. 앞에 붙은 64자 해시는 어떤
코드로 검증했는지의 기록입니다.

### 5. 지금의 프라이버시는 절반입니다

10단계에서 David 의 조회 결과가 `[]` 다. 하지만 **participant 가 하나**이므로
물리적으로는 같은 노드가 양쪽 데이터를 갖고 있고, Ledger API 가 party 단위로 뷰를
분리해 보여주는 것입니다.

Participant 가 서로 다를 때 비로소 **데이터 자체가 도달하지 않습니다.** Step 05 에서
노드를 분리해 확인합니다.

## Sandbox 는 인메모리다

종료하면 party·user·계약뿐 아니라 **participant 의 키까지 사라집니다.** 재실행하면
namespace 지문부터 새로 생성되므로, 이전 실행의 party ID 는 무효다.

그래서 `step02.sh` 는 party ID 와 package-id 를 하드코딩하지 않고 매번 조회합니다.

## 직접 만져보기

```sh
./steps/step02.sh --keep
```

끝나면 출력된 변수를 그대로 씁니다.

```sh
export API=http://localhost:7575
export CITI='Citi::1220...'   # 출력값 복사
export ALICE='Alice::1220...'
export DAVID='David::1220...'
export PKG=...
```

예금을 하나 더 만들어 봅니다.

```sh
curl -s -X POST $API/v2/commands/submit-and-wait -H 'Content-Type: application/json' -d "{\"commands\":[{\"CreateCommand\":{\"templateId\":\"$PKG:Step02.Deposit:Deposit\",\"createArguments\":{\"bank\":\"$CITI\",\"owner\":\"$ALICE\",\"amount\":\"250.0\"}}}],\"commandId\":\"manual-1\",\"userId\":\"citi-settlement\",\"actAs\":[\"$CITI\",\"$ALICE\"],\"readAs\":[]}" | python3 -m json.tool
```

`ensure amount > 0.0` 를 위반해 봅니다.

```sh
curl -s -X POST $API/v2/commands/submit-and-wait -H 'Content-Type: application/json' -d "{\"commands\":[{\"CreateCommand\":{\"templateId\":\"$PKG:Step02.Deposit:Deposit\",\"createArguments\":{\"bank\":\"$CITI\",\"owner\":\"$ALICE\",\"amount\":\"0.0\"}}}],\"commandId\":\"manual-2\",\"userId\":\"citi-settlement\",\"actAs\":[\"$CITI\",\"$ALICE\"],\"readAs\":[]}" | python3 -m json.tool
```

끝나면 `pkill -f canton`.

## 이 Step 으로 확인할 수 없는 것

Participant 가 **1개뿐**이라 Canton 고유의 것 대부분이 재현되지 않습니다.

| 확인 불가 | 왜 |
| --- | --- |
| 참가자 간 신뢰 경계 | 확인자가 항상 자기 자신 |
| 진짜 데이터 격리 | 한 노드가 양쪽 데이터를 보유 (API 가 뷰만 분리) |
| 다중 서명의 실무 제약 | 한 노드가 두 party 를 호스팅하므로 `actAs:[Citi,Alice]` 가 그냥 통함 |
| 토폴로지 교환 / vetting 협상 | 노드 간 오갈 상대가 없음 |
| 다중 호스팅 / threshold | 노드가 하나 |
| Reassignment | Synchronizer 가 하나 |

---

다음: **[Step 03 — 첫 계약](Step03FirstContract.md).** Daml 문법을 읽고 choice 를
추가합니다. 그리고 이체가 왜 아직 불가능한지 확인합니다.
