# Step 08 — Reassignment

[Step 06](Step06Dvp.md) 의 DvP 는 현금과 채권이 같은 원장에 있다고 전제했습니다.
실무에서는 그렇지 않습니다. 현금은 자금 결제망에, 증권은 예탁결제망에 있고 둘은 서로
다른 원장입니다.

Canton 에서 원장 하나는 **Synchronizer 하나**입니다. 이 Step 에서는 Synchronizer 를
둘 띄우고, Contract 를 원장 사이로 옮겨 결제를 성립시킵니다.

## 실행

저장소 루트에서:

```sh
./steps/step08.sh
```

| 옵션 | 용도 |
| --- | --- |
| (없음) | 단계마다 엔터를 기다립니다 |
| `--auto` | 엔터 없이 전부 실행합니다 |
| `--keep` | 끝나고 노드를 끄지 않습니다 |

## 다루는 파일

| 파일 | 내용 |
| --- | --- |
| `canton/step08.conf` | 노드 6개 선언 |
| `canton/step08-bootstrap.canton` | Synchronizer 2개 구성, 양쪽 연결, feature flag, DAR, Party |
| `daml/Step06/Dvp.daml` | **Step 06 의 것을 그대로 씁니다** |

Daml 코드는 한 줄도 고치지 않습니다. 원장이 몇 개인지는 Daml 에 나타나지 않습니다 —
Template 에 Synchronizer 를 적는 자리가 없습니다.

## 구성

```
    citi-participant                 goldmansachs-participant
      Citi, Alice                      GoldmanSachs
         │  │                              │  │
         │  └──────────┐        ┌──────────┘  │
         │             │        │             │
    ┌────┴─────────────┴──┐  ┌──┴─────────────┴────┐
    │   dtcc              │  │   euroclear         │
    │   Sequencer 5001    │  │   Sequencer 5004    │
    │   Mediator  5003    │  │   Mediator  5006    │
    │   현금 원장          │  │   증권 원장          │
    └─────────────────────┘  └─────────────────────┘
```

Participant 는 [Step 05](Step05MultiParticipant.md) 와 같이 둘입니다. Morgan Stanley
자리에 GoldmanSachs 가 들어온 것은 다루는 자산이 채권이기 때문이고, 구조는 같습니다.
**실제로 달라지는 변수는 Synchronizer 의 개수 하나뿐입니다.**

## Step 05 에서 무엇이 달라졌는가

| | Step 05 | Step 08 |
| --- | --- | --- |
| Synchronizer | 1 | 2 |
| `bootstrap.synchronizer` | 1회 | 2회 |
| `connect_local` | Participant 당 1회 | Participant 당 2회 |
| `parties.enable` | 1회 | Party 당 2회 (원장마다) |
| `dars.upload` | Participant 당 1회 | Participant 당 2회 (원장마다) |
| feature flag | 없음 | `EnableMultiSynchronizer` |
| 동적 파라미터 | 기본값 | `assignmentExclusivityTimeout` 을 10분으로 |

## 반드시 남아야 할 것

### 1. Contract 는 정확히 한 원장에 속합니다

ACS 항목에는 `synchronizerId` 가 함께 실려 옵니다.

```
    활성   Cash          dtcc         001fd9ee505b59fa
    활성   DvpProposal   euroclear    00c2efd74ea297c1
```

Alice 는 두 원장의 Contract 를 **하나의 목록으로** 봅니다. Participant 가 두 원장에
모두 연결되어 있으므로 조회는 합쳐져 보입니다. 하지만 저장 위치는 갈라져 있습니다.

**한 Transaction 은 한 원장 안에서 실행됩니다.** Sequencer 하나가 순서를 부여하고
Mediator 하나가 판정하기 때문입니다. 원장이 다르면 그 둘이 다르므로 하나의 확인
프로토콜로 묶이지 않습니다.

### 2. 다중 원장은 opt-in 이고 Topology 에 남습니다

Participant 를 두 Synchronizer 에 연결하는 것만으로는 부족합니다.

```scala
p.topology.synchronizer_trust_certificates.propose(
  participantId = p.id,
  synchronizerId = s,
  featureFlags = Seq(ParticipantTopologyFeatureFlag.EnableMultiSynchronizer),
)
```

Participant 가 Synchronizer 에 가입할 때 제출하는 증서
(`SynchronizerTrustCertificate`) 에 이 flag 가 붙습니다. 켜지 않으면 이 Step 의 모든
동작이 거부됩니다.

```
Submission failed because: Multi-synchronizer feature flag is not enabled
for synchronizer dtcc::1220... on the following participants: Set(PAR::citi::1220...)
```

**설정 파일이 아니라 Topology 입니다.** 어느 Participant 가 다중 원장을 쓸 수 있는지가
네트워크의 공개 상태로 남고, 상대 Participant 도 그것을 보고 검증합니다.

### 3. Reassignment 는 두 단계입니다

```
[TX 1]  unassign    source 원장에서 떼어낸다
                    → reassignmentId 를 받는다

        ─── 이동중 ───   어느 원장에도 붙어 있지 않다

[TX 2]  assign      reassignmentId 로 target 원장에 붙인다
```

`POST /v2/commands/submit-and-wait-for-reassignment` 하나로 둘 다 보냅니다.

```json
{
  "reassignmentCommands": {
    "commandId": "...",
    "userId": "alice-web",
    "submitter": "Alice::1220...",
    "commands": [
      { "command": { "UnassignCommand": { "value": {
          "contractId": "001fd9...",
          "source": "dtcc::1220...",
          "target": "euroclear::1220..." } } } }
    ]
  },
  "eventFormat": { "filtersByParty": { "Alice::1220...": { "cumulative": [ ... ] } } }
}
```

`eventFormat` 을 함께 보내야 응답에 이벤트가 실립니다. 빼면 `events` 가 빈 배열로
오고 `reassignmentId` 를 받을 수 없습니다.

### 4. 원자적이지 않습니다

`unassign` 직후 ACS 를 보면 항목이 남아 있지만 활성이 아닙니다.

```
    이동중   Cash   dtcc → euroclear   001fd9ee505b59fa
```

JSON API 는 이 항목을 `JsIncompleteUnassigned` 로 돌려줍니다. 이 상태에서 그 Contract
를 쓰려고 하면 거부됩니다.

```
code : UNKNOWN_CONTRACT_SYNCHRONIZERS
cause: The synchronizers for the contracts (001fd9...) are currently unknown
```

**Contract 가 사라진 것이 아니라 어느 원장에도 붙어 있지 않은 것입니다.** 애플리케이션은
이 구간을 "이동중"으로 다뤄야 합니다. [Step 04](Step04TwoParties.md) 의 제안 구간과
같은 종류의 문제이고, 차이는 그 구간을 Daml 이 아니라 Canton 이 만든다는 점입니다.

`unassign` 응답에는 두 값이 더 실립니다.

| 필드 | 뜻 |
| --- | --- |
| `reassignmentCounter` | 이 Contract 가 몇 번 옮겨졌는가 |
| `assignmentExclusivity` | 이 시각까지는 제출자만 `assign` 할 수 있다 |

### 4-1. 이동중 구간은 저절로 닫힙니다 — 자동 assign (automatic assignment)

`assignmentExclusivity` 가 지나면 **Participant 가 자동으로 `assign` 합니다.** 제출자가
사라져도 자산이 갇히지 않게 하는 장치입니다.

6번의 자동 재배정 (automatic reassignment) 과는 다른 장치입니다. 이쪽은 이미 시작된
이동을 시간이 지나 마무리하는 것이고, 저쪽은 Transaction 을 위해 이동을 먼저 일으키는
것입니다.

기한은 Synchronizer 의 동적 파라미터 `assignmentExclusivityTimeout` 이고 **기본값은
15초**입니다. 그대로 두면 화면을 읽는 사이에 붙어 버리므로, 이 Step 의 bootstrap 은
10분으로 늘려 둡니다.

```scala
dtccSequencer.topology.synchronizer_parameters.propose_update(
  dtcc.logical,
  _.update(assignmentExclusivityTimeout = NonNegativeFiniteDuration.ofMinutes(10)),
)
```

실측하면 이렇습니다.

```
기본값 15초                    10분으로 늘린 뒤
  t+ 5s  이동중                  t+ 5s  이동중
  t+10s  이동중                  t+25s  이동중
  t+20s  이동중                  ...      (10분까지 유지)
  t+25s  활성 / euroclear   ← Canton 이 붙임
```

**그래서 수동 `assign` 은 "안 하면 안 되는 일"이 아니라 "빨리 하는 일"입니다.**
제출자가 곧바로 붙이는 것이 정상 경로이고, 자동 assign (automatic assignment) 은
그러지 못했을 때의 안전망입니다.

### 5. Contract ID 가 바뀌지 않습니다

```
unassign 전   dtcc        001fd9ee505b59fa
assign 후     euroclear   001fd9ee505b59fa      ← 같습니다
```

[Step 03](Step03FirstContract.md) 의 "계약은 수정되지 않는다" 와 헷갈리기 쉽습니다.
거기서는 `amount` 가 바뀌므로 archive + create 였고 Contract ID 가 새로 생겼습니다.

Reassignment 는 내용을 바꾸지 않습니다. `bank`·`owner`·`amount` 가 그대로이고 같은
Contract 가 유지됩니다. 바뀌는 것은 **어느 원장이 이 Contract 를 관리하는가**입니다.

**Reassignment 는 소유권 이전이 아닙니다.** 소유권은 Daml 의 `owner` 필드이고,
Reassignment 는 그것을 건드리지 않습니다.

### 6. 자동 재배정 (automatic reassignment) — API 호출 3번이 1번으로

수동으로 옮기지 않고 곧바로 `Settle` 을 제출해도 성공합니다.

```
현금  dtcc       00329b42ba017d89
제안  euroclear  00e66e21b0e09bb9

$ Settle — unassign/assign 없이 그대로
  성공  updateId: 12206ee3768ee8d1a40732aa
```

필요한 Contract 가 다른 원장에 있으면 Participant 가 먼저 옮기고 Transaction 을
실행합니다. 2번의 feature flag 가 여는 것은 3번의 수동 API 와 이 자동 동작 둘
다입니다. flag 없이 이것을 시도하면
`AUTOMATIC_REASSIGNMENT_FOR_TRANSACTION_FAILED` 로 거부됩니다.

#### 전후 비교

애플리케이션이 부르는 API 는 3번에서 1번이 됩니다.

```
                     수동                              자동
    ──────────────────────────────────────────────────────────────────────
    앱의 API 호출     3번                               1번

      1            submit-and-wait-for-reassignment   ─┐
                     UnassignCommand                   │  Participant 가
      2            submit-and-wait-for-reassignment    │  대신 제출합니다
                     AssignCommand                    ─┘
      3            submit-and-wait                    submit-and-wait
                     Settle                             Settle
```

**원장에 남는 것은 양쪽이 완전히 같습니다.** 업데이트 스트림
(`POST /v2/updates/update-by-offset`) 을 읽어 보면 드러납니다.

```
수동 — commandId 가 셋 다 다릅니다
  off 78  Reassignment  sync=dtcc       cmd=M1-unassign   JsUnassignedEvent  Cash
  off 81  Reassignment  sync=euroclear  cmd=M2-assign     JsAssignmentEvent  Cash
  off 84  Transaction   sync=euroclear  cmd=M3-settle     Archived DvpProposal / Created Bond / Archived Cash

자동 — 업데이트 3개는 그대로이고 commandId 만 하나입니다
  off 62  Reassignment  sync=dtcc       cmd=tr-2853513043 JsUnassignedEvent  Cash
  off 65  Reassignment  sync=euroclear  cmd=tr-2853513043 JsAssignmentEvent  Cash
  off 68  Transaction   sync=euroclear  cmd=tr-2853513043 Archived DvpProposal / Created Bond / Archived Cash
```

| | 자동이 줄이는 것 |
| --- | --- |
| 앱 ↔ Participant 왕복 | 3번 → 1번 |
| 앱이 `reassignmentId` 를 들고 있을 필요 | 없어집니다 |
| 어느 Contract 가 어느 원장에 있는지 앱이 알 필요 | 없어집니다 |

| | 자동이 줄이지 않는 것 |
| --- | --- |
| 원장 업데이트 | 3개 그대로 |
| 확인 프로토콜 실행 | 3회 그대로 (dtcc 1회, euroclear 2회) |
| 이동중 구간 | 존재합니다 |
| 원자성 | 없습니다. 여전히 별개의 Transaction 세 개입니다 |

**경계는 앱과 Participant 사이입니다.** 원장 쪽에서는 아무것도 줄지 않습니다.

#### 누가 대신하는가 — "Canton" 이 아닙니다

자동 재배정을 제출하는 것은 **Alice 를 호스팅하는 `citi-participant`** 이고,
`UnassignedEvent` 의 `submitter` 에는 `Alice` 가 찍힙니다. Alice 가 그 한 번의
command 로 이미 준 권한을 쓰는 것이지 새 권한이 생기는 것이 아닙니다. Step 03~04 의
권한 계산은 그대로입니다.

다른 참여자의 Participant 는 재배정에 관여조차 하지 않습니다. 같은 구간에서
`goldmansachs-participant` 가 본 업데이트는 하나뿐입니다.

```
  off 62  Transaction  sync=euroclear   Archived DvpProposal / Created Bond / Created Cash
```

Reassignment 두 개가 없습니다. `Cash` 의 stakeholder 는 Citi 와 Alice 뿐이고 둘 다
`citi-participant` 가 호스팅하므로, GoldmanSachs 의 노드는 그 재배정을 볼 이유가
없습니다. Sequencer 와 Mediator 도 순서 부여와 판정만 할 뿐 실행하지 않습니다.

#### 그렇다면 수동 Reassignment 는 왜 쓰는가

| 상황 | 이유 |
| --- | --- |
| 결제 원장을 고르고 싶을 때 | 원장마다 수수료·규제·운영 주체가 다릅니다 |
| 미리 옮겨 두고 싶을 때 | 결제 시점의 지연을 줄입니다 |
| 이동 자체가 업무일 때 | 예탁 이관은 그 자체로 하나의 처리입니다 |

자동 경로에서 **어느 원장으로 모을지는 제출자가 정합니다.** 위에서는
`synchronizerId = euroclear` 를 지정해 현금이 euroclear 로 갔습니다. 생략하면 Canton 이
고릅니다 — 그 선택을 통제하고 싶을 때가 수동을 쓰는 이유 중 하나입니다.

## 흔히 막히는 곳

| 증상 | 원인 |
| --- | --- |
| `PACKAGE_SERVICE_CANNOT_AUTODETECT_SYNCHRONIZER` | `dars.upload` 에 `synchronizerId` 를 안 줬습니다. 원장이 둘이면 자동 판별이 안 됩니다 |
| `cannot automatically determine synchronizer` | `parties.enable` 에 `synchronizer` 를 안 줬습니다. 같은 이유입니다 |
| `Multi-synchronizer feature flag is not enabled` | 2번의 flag 를 안 켰습니다 |
| `MISSING_FIELD: command` | Reassignment JSON 이 `{"command": {"UnassignCommand": {"value": ...}}}` 꼴이어야 합니다 |
| `Invalid reassignment ID` | `eventFormat` 을 안 보내 `reassignmentId` 를 못 받았습니다 |
| `Cannot find reassignment data` | 이미 assign 되었습니다. `assignmentExclusivity` 가 지나 Canton 이 먼저 붙였을 수 있습니다 |

## 이 Step 으로 확인하지 못한 것

| | 왜 |
| --- | --- |
| Synchronizer 마다 다른 신뢰 구성 | 참가자·수수료·프로토콜 버전을 같게 두었습니다 |
| Reassignment 가 막히는 경우 | 두 Participant 를 양쪽에 모두 연결했습니다 |
| 원장 사이의 시간·순서 관계 | 한 Transaction 이 두 원장에 걸치지 않으므로 다루지 않았습니다 |

---

다음: **Step 09 — 업그레이드.** 이미 배포된 Template 을 고쳐야 할 때 무엇이 일어나는지
다룹니다.
