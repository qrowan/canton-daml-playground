# Step 10 — 애플리케이션 연동

지금까지는 원장에 무엇을 쓸 수 있는지를 다뤘습니다. 이번에는 그 위에 애플리케이션을
올립니다.

애플리케이션은 원장의 현재 상태를 알아야 합니다. 화면 하나 그릴 때마다 원장 전체를
조회할 수는 없으므로 자기 쪽에 복제본을 두고 변경분만 받습니다. **그 복제본이 원장과
어긋나지 않게 하는 방법**이 이 Step 의 주제입니다.

## 실행

저장소 루트에서:

```sh
./steps/step10.sh
```

| 옵션 | 용도 |
| --- | --- |
| (없음) | 단계마다 엔터를 기다립니다 |
| `--auto` | 엔터 없이 전부 실행합니다 |
| `--keep` | 끝나고 노드를 끄지 않습니다 |

## 다루는 파일

| 파일 | 내용 |
| --- | --- |
| `.step10/ledger_sync.py` | 러너가 만들어 내는 40줄짜리 동기화 코드 |
| `.step10/state.json` | 애플리케이션이 들고 있는 복제본 |
| `canton/step05.conf` | [Step 05](Step05MultiParticipant.md) 구성 그대로 |
| `daml/Step04/Deposit.daml` | [Step 04](Step04TwoParties.md) 의 Deposit 그대로 |

Daml 도 노드 구성도 새로 만들지 않습니다. 이 Step 에서 새로 나오는 것은 **읽는 쪽의
절차**뿐입니다.

## 어긋나는 두 가지 방식

```
빠짐     구독을 시작하기 전에 일어난 거래를 놓칩니다
중복     이미 반영한 거래를 다시 받아 두 번 적용합니다
```

둘 다 잔액이 틀리는 결과로 이어집니다. Canton 은 **offset** 하나로 둘을 함께
해결합니다.

## 반드시 남아야 할 것

### 1. offset 은 원장의 위치입니다

```sh
curl -s http://localhost:5013/v2/state/ledger-end
```

```json
{"offset": 31}
```

원장에 무언가 일어날 때마다 번호가 올라갑니다. 애플리케이션이 **어디까지 반영했는지**를
기록하는 자리이기도 합니다.

**offset 은 Participant 마다 다릅니다.** 각자 받은 것만 세기 때문입니다. Step 05 에서
두 노드가 서로 다른 것을 본다고 한 것이 여기에도 적용됩니다.

### 2. 스냅샷과 offset 은 한 쌍입니다

순서가 중요합니다.

```python
off = ledger_end()          # 먼저 기준점을 고정하고
acs = acs_at(off)           # 그 시점의 상태를 받는다
```

반대로 하면 — 상태를 먼저 받고 나중에 offset 을 읽으면 — 그 사이에 일어난 거래를 두 번
적용하게 됩니다. `/v2/state/active-contracts` 에 `activeAtOffset` 을 넘기는 이유입니다.

```json
{
  "filter": { "filtersByParty": { "Alice::1220...": { "cumulative": [ ... ] } } },
  "verbose": false,
  "activeAtOffset": 31
}
```

### 3. 따라잡기는 저장한 offset 다음 칸부터입니다

```python
frm, to = state["offset"] + 1, ledger_end()
for off in range(frm, to + 1):
    apply(update_at(off))
state["offset"] = to
```

적용 규칙은 두 줄이 전부입니다.

```python
if kind.endswith("ArchivedEvent"):
    contracts.pop(ev["contractId"], None)
elif kind.endswith("CreatedEvent"):
    contracts[ev["contractId"]] = ev["createArgument"]["amount"]
```

**모든 offset 에 우리 몫이 있는 것은 아닙니다.** 다른 Party 의 거래이거나 Topology
변경이면 그 offset 을 조회해도 우리 필터에 걸리는 것이 없습니다. 건너뛰면 됩니다.

### 4. 인출 하나가 이벤트 둘로 옵니다

20 짜리 예금에서 3 을 인출하면 이렇게 들어옵니다.

```
off  38  12202fa0fe2aaf6e  events=2
    ArchivedEvent   00b66857daa309          ← 20 짜리를 소비
    CreatedEvent    00270a4d248bd0  17.00   ← 17 짜리를 생성
```

[Step 03](Step03FirstContract.md) 의 "계약은 수정되지 않는다" 가 업데이트 스트림에
그대로 나타난 것입니다. 잔액을 바꾸는 갱신 이벤트 같은 것은 없습니다.

### 5. 스냅샷 + 재생 = 현재 상태

러너는 복제본을 만든 뒤 원장을 움직이고, 따라잡은 결과를 원장에 다시 물어 대조합니다.

```
복제본 offset = 40
  0098e86a038b28       10.00
  00270a4d248bd0       17.00
  00cea619b9321f       30.00
  00545b6c15146c       40.00
  00990ff1b8ebbf       50.00
  합계                147.00

verify → 일치  5건
```

**이것이 원장 연동의 전부입니다.** 스냅샷을 한 번 뜨고, 그 다음부터는 업데이트만 받아
적용합니다. 다시 전체 조회할 일이 없습니다.

### 6. 재시작은 스냅샷을 다시 뜨지 않습니다

복제본 파일에 offset 이 남아 있으면 그 다음부터 이어붙이면 됩니다.

```json
{
  "offset": 40,
  "contracts": { "0098e86a...": "10.0000000000", ... }
}
```

**상태와 offset 을 같은 트랜잭션으로 저장해야 합니다.** 상태만 쓰고 offset 을 못 쓴 채
죽으면 재시작 때 같은 업데이트를 다시 적용합니다. 실무에서는 두 값을 같은 DB 트랜잭션에
넣습니다.

### 7. 같은 commandId 로 재시도하는 것이 안전합니다

읽기만 문제가 아닙니다. 제출한 뒤 응답을 못 받으면 애플리케이션은 다시 보낼지 판단해야
합니다.

```
$ commandId 를 그대로 두고 재제출
  실패  DUPLICATE_COMMAND
  cause: Command submission already exists.
```

| 응답을 못 받았을 때 | |
| --- | --- |
| 같은 `commandId` 로 재시도 | **안전합니다.** 두 번 실행되지 않습니다 |
| 새 `commandId` 로 재시도 | 위험합니다. 두 번 실행될 수 있습니다 |

`commandId` 는 애플리케이션이 정합니다. 주문번호처럼 업무상 의미가 있는 값을 쓰면 재시도
판단이 쉬워집니다. 다만 중복 제거에는 **기한**이 있고, 그 기간이 지나면 같은
`commandId` 도 통과합니다.

### 8. Contract ID 를 외부 키로 쓰면 안 됩니다

복제본의 키는 Contract ID 입니다. 그런데 인출 한 번에 20 짜리 ID 가 사라지고 17 짜리
ID 가 새로 생겼습니다.

| | |
| --- | --- |
| **Contract ID** | 매 변경마다 바뀝니다. 외부 시스템의 키로 쓰면 안 됩니다 |
| **offset** | 애플리케이션이 저장해야 하는 값입니다 |
| **commandId** | 애플리케이션이 만들고 저장해야 하는 값입니다 |

업무 키가 필요하면 **Template 필드로 직접 넣어야 합니다** — 계좌번호, 주문번호 같은
것을 계약 내용에 담아 두고 그것으로 찾습니다.

### 9. 브라우저는 원장에 직접 붙지 못합니다

지금까지 러너는 `curl` 로 JSON API 에 붙었습니다. 여기에 화면을 붙이면 브라우저의
자바스크립트가 같은 자리에 서게 됩니다. 그런데 서지 못합니다.

```sh
curl -X OPTIONS $API/v2/state/ledger-end \
  -H "Origin: http://localhost:5173" \
  -H "Access-Control-Request-Method: GET"
```

```
  preflight (OPTIONS)     405
  Access-Control-* 헤더    없음
```

브라우저는 다른 출처로 요청하기 전에 preflight 를 보내는데 JSON Ledger API 가 405 로
답하고, 일반 응답에도 `Access-Control-*` 헤더가 없습니다. **CORS 설정 항목 자체가
없습니다** — `JsonApiConfig` 에 있는 것은 `enabled`·`websocketConfig`·`address`·
`internalPort` 같은 것들뿐입니다.

```
브라우저  ──╳──▶  JSON Ledger API      직접 붙지 못합니다
브라우저  ────▶  자기 서버  ────▶  JSON Ledger API
```

**화면이 있는 애플리케이션에는 서버가 반드시 있습니다.** 취향의 문제가 아니라 원장에
붙을 수 있는 것이 서버뿐이기 때문입니다. 공식 문서가 프론트엔드를 원장에 직접
붙이지 않는 구성을 기본으로 두는 것도 같은 이유입니다.

앞에서 정리한 것과 이어집니다 — 애플리케이션은 **Party 를 가진 쪽이 자기 자리에서
운영합니다.** 원장에 붙는 자격이 노드에 있고, 그 노드에 붙을 수 있는 것이 서버뿐이므로
그렇게 됩니다.


## 흔히 막히는 곳

| 증상 | 원인 |
| --- | --- |
| 재시작할 때마다 잔액이 늘어남 | offset 을 저장하지 않았거나, 상태와 따로 저장했습니다 |
| 스냅샷 직후 몇 건이 비어 있음 | `activeAtOffset` 없이 조회했습니다. 기준점을 고정해야 합니다 |
| `UPDATE_NOT_FOUND` | 그 offset 에 우리 필터에 걸리는 것이 없습니다. 정상이며 건너뛰면 됩니다 |
| 같은 예금이 두 개 생김 | 재시도할 때 `commandId` 를 새로 만들었습니다 |
| 저장해 둔 Contract ID 로 조회가 안 됨 | 그 사이 archive 되었습니다. 업무 키를 Template 에 두어야 합니다 |

## 이 Step 으로 확인하지 못한 것

| | 왜 |
| --- | --- |
| 스트리밍 구독 | offset 을 하나씩 조회했습니다. 실제 애플리케이션은 gRPC 스트림이나 JSON API 의 WebSocket 으로 밀어 받습니다 — **받은 뒤 적용하는 규칙은 같습니다** |
| 여러 Party 를 한 애플리케이션이 따라가는 경우 | Alice 하나만 따라갔습니다 |
| ACS 가 큰 경우의 분할 조회 | 다섯 건이었습니다 |
| 화면이 붙은 완전한 애플리케이션 | 러너는 복제본까지만 만들었습니다 — 아래 참조 |

## 화면까지 붙이려면

여기까지가 원장 위에 애플리케이션을 올리는 데 필요한 최소한입니다. 화면이 붙은 완전한
구성은 공식 레퍼런스 애플리케이션이 그대로 보여줍니다.

**[cn-quickstart](https://github.com/digital-asset/cn-quickstart)** — 소프트웨어 라이선스
업무를 다루는 풀스택 예제입니다. 공식 문서 기준으로 이렇게 구성되어 있습니다.

| | |
| --- | --- |
| 프론트엔드 | React + TypeScript + Vite |
| 백엔드 | Spring Boot (Java). TypeScript 도 지원됩니다 |
| 둘 사이의 계약 | 공유 `openapi.yaml` 에서 타입을 생성해 컴파일 시점에 맞춥니다 |
| 읽기 | PQS — 원장을 PostgreSQL 로 투영해 SQL 로 조회합니다 |
| 인증 | OAuth2 / OIDC. 로컬에서는 Keycloak |
| 실행 | Docker Compose 로 LocalNet |

이 Step 에서 확인한 것이 그 안에 그대로 들어 있습니다 — 브라우저가 `commandId` 를
만들어 보내고, 화면은 5초마다 다시 조회해 갱신하고, 원장 접근은 전부 백엔드를
거칩니다.

| 문서 | |
| --- | --- |
| 애플리케이션 구조 | https://docs.canton.network/appdev/modules/m4-app-architecture |
| 백엔드 | https://docs.canton.network/appdev/modules/m4-backend-dev |
| 프론트엔드 | https://docs.canton.network/appdev/modules/m4-frontend-dev |

위 표는 **공식 문서 기준**입니다. 이 저장소에서 실행해 확인한 것이 아닙니다.

---

다음: **[Step 11 — External Party](Step11ExternalParty.md).** 지금까지 모든 거래는
Participant 가 대신 서명했습니다. 자기 키를 쥔 Party 는 무엇이 달라지는지 다룹니다.
