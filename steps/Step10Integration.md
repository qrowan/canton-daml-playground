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

---

여기까지가 원장 위에 애플리케이션을 올리는 데 필요한 최소한입니다. 다음으로 다룰 만한
것은 **Daml Finance** 입니다 — 지금까지 직접 만든 Cash·Bond·Deposit 에 해당하는 것을
표준 라이브러리가 어떻게 제공하는지, 그리고 그것을 쓰면 무엇이 달라지는지입니다.
