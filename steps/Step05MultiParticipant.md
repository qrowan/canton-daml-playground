# Step 05 — 다중 Participant

Step 02~04 는 Participant 하나에서 진행했습니다. 그래서 이런 것들이 말뿐이었습니다.

- "각 노드는 자기 몫의 Contract 만 갖는다"
- "Participant 는 자기가 호스팅하는 Party 의 권한만 행사한다"
- "propose/accept 는 노드가 분리되면 필수다"
- "이해관계자의 모든 Participant 가 vetting 해야 한다"

여기서는 노드를 직접 띄워 전부 확인합니다.

## 실행

저장소 루트에서:

```sh
./steps/step05.sh
```

| 옵션 | 용도 |
| --- | --- |
| (없음) | 단계마다 엔터를 기다립니다 |
| `--auto` | 엔터 없이 전부 실행합니다 |
| `--keep` | 끝나고 노드를 끄지 않습니다. Party ID 와 포트를 출력해 줍니다 |

## 구성

```
  citi-participant                    morganstanley-participant
  Citi, Alice 호스팅                   Bob 호스팅
  Ledger 5011 / Admin 5012            Ledger 5021 / Admin 5022
  JSON 5013                           JSON 5023
        │                                        │
        └───────────────┬────────────────────────┘
                        │
              ┌─────────┴──────────┐
              │   dtcc-sequencer   │  5001 / 5002
              │   dtcc-mediator    │  5003
              └────────────────────┘
```

Step 01 에서 그림으로만 봤던 구성입니다.

## 다루는 파일

| 파일 | 내용 |
| --- | --- |
| `canton/canton.conf` | 노드 4개 선언 |
| `canton/bootstrap.canton` | Synchronizer 구성, 노드 연결, DAR 업로드, Party 생성 |
| `steps/step05.sh` | 12단계 러너 |

Daml 코드는 Step 04 의 `daml/Step04/Deposit.daml` 을 그대로 씁니다. **코드를 한 줄도
고치지 않고** 다중 노드에서 동작하는 것이 이 Step 의 논점입니다.

## 설정

```
canton {
  participants {
    citi {
      storage.type = memory
      ledger-api.port = 5011
      admin-api.port = 5012
      http-ledger-api.port = 5013
    }
    ...
  }
  sequencers { dtccSequencer { ... } }
  mediators  { dtccMediator  { ... } }
}
```

Participant 마다 포트가 세 벌입니다.

| 포트 | 용도 |
| --- | --- |
| `ledger-api` | 애플리케이션이 쓰는 gRPC Ledger API |
| `admin-api` | 노드 운영 — Party 생성, DAR 업로드, Topology |
| `http-ledger-api` | JSON Ledger API |

`dpm sandbox` 는 이 구성을 감춰 두고 하나로 묶어 띄웠던 것입니다.

## Bootstrap

노드를 띄우는 것만으로는 부족합니다. Synchronizer 를 만들고 각 Participant 를 연결해야
합니다.

```scala
bootstrap.synchronizer(
  synchronizerName = "dtcc",
  sequencers = Seq(dtccSequencer),
  mediators  = Seq(dtccMediator),
  ...
)

citi.synchronizers.connect_local(dtccSequencer, alias = "dtcc")
morganstanley.synchronizers.connect_local(dtccSequencer, alias = "dtcc")
```

`bootstrap.synchronizer` 가 Sequencer 와 Mediator 를 묶습니다. Step 01 에서
"Synchronizer 는 노드 두 종류의 묶음"이라고 한 것이 이 한 줄입니다.

## 반드시 남아야 할 것

### 1. Namespace 지문이 노드마다 다릅니다

```
Citi     1220b905acc711aa41740dfffd92cf0d7b5f11b6f3aad4ae31c0a941ae8ba0a377c3
Alice    1220b905acc711aa41740dfffd92cf0d7b5f11b6f3aad4ae31c0a941ae8ba0a377c3
Bob      1220cd4b2abc3eb212122711e4bb3994f86b54e001cf9804c4677c6f1330719a7496
```

Step 02 에서는 셋이 모두 같았습니다. 한 노드가 전부 발급했기 때문입니다. 이제 Citi 와
Alice 는 `citi-participant` 가, Bob 은 `morganstanley-participant` 가 발급했습니다.

Party ID 의 뒷부분이 발급자를 가리킨다는 것이 눈에 보입니다.

### 2. 각 노드는 자기 Party 만 압니다

```
citi-participant           Alice, Citi, citi
morganstanley-participant  Bob, morganstanley
```

Bob 은 citi 목록에 없고 Alice 는 morganstanley 목록에 없습니다.

### 3. User 는 노드마다 따로 만들어야 합니다

```
citi-participant           citi-settlement → Citi, Alice
                           alice-web       → Alice
morganstanley-participant  bob-web         → Bob
```

User 는 Participant 내부에만 존재하므로 복제되지 않습니다. 같은 이름으로 양쪽에
만들어도 서로 다른 계정입니다.

### 4. 데이터가 도달하지 않습니다 — 가려진 것이 아닙니다

발행 직후 상태입니다.

```
citi-participant / Alice           활성 Contract 1건
morganstanley-participant / Bob    활성 Contract 0건
```

여기서 morganstanley 노드에 Alice 시점 조회를 하면 `[]` 가 나옵니다. 그런데 **조회
결과만으로는 "없는 것"인지 "가려진 것"인지 구분되지 않습니다.** 제출을 시도해야 확실한
증거가 나옵니다.

```
NO_SYNCHRONIZER_ON_WHICH_ALL_SUBMITTERS_CAN_SUBMIT
This participant cannot submit as the given submitter on any connected synchronizer
```

Step 02 에서는 같은 노드가 양쪽 데이터를 갖고 Ledger API 가 뷰만 분리했습니다. 여기서는
**노드 자체가 그 Contract 를 모릅니다.**

### 5. 편법이 실제로 막힙니다

citi 노드에서 `actAs: [Citi, Bob]` 을 시도하면 거부됩니다.

```
NO_SYNCHRONIZER_ON_WHICH_ALL_SUBMITTERS_CAN_SUBMIT
Not connected to a synchronizer on which this participant can submit for all submitters
```

Step 03 의 `submit [Citi, Alice]` 가 왜 테스트 전용이었는지가 여기서 증명됩니다.

### 6. Observer 가 제안을 상대 노드까지 나릅니다

Alice 가 citi 노드에서 `ProposeTransfer` 를 행사하면, `TransferProposal` 의
`observer newOwner` 때문에 **morganstanley 노드에 그 Contract 가 도달**합니다.

```
morganstanley-participant / Bob    활성 Contract 1건
                                     Step04.Deposit:TransferProposal
```

Step 01 의 "각자 알아야 할 조각만 전달된다"가 실제로 일어난 것입니다. Observer 가
없으면 Bob 의 노드는 제안의 존재조차 모르고, 수락할 방법이 없습니다.

### 7. 상대 노드 반영에는 지연이 있습니다

`submit-and-wait` 는 **제출한 노드 기준**으로 반환합니다. 상대 노드가 그 Contract 를
인덱싱하기까지 약간의 시간이 걸립니다.

러너는 도달할 때까지 폴링합니다. **애플리케이션도 같은 처리가 필요합니다** — 상대에게
보낸 직후 상대 노드를 조회하면 아직 없을 수 있습니다.

### 8. 노드 간 이체가 성립합니다

```
TX 1   citi 노드에서 Alice 가 ProposeTransfer          (userId=alice-web)
TX 2   morganstanley 노드에서 Bob 이 AcceptTransfer    (userId=bob-web)

결과   citi-participant / Alice           0건
       morganstanley-participant / Bob    1건  amount=100.0
```

TX 2 에서 실제로 일어난 일입니다.

```
1. morganstanley-participant 가 Transaction 을 계산해 제출
2. dtcc-sequencer 가 순서를 부여해 양쪽에 전달
3. citi-participant 와 morganstanley-participant 가 각자 재실행 검증
   → 둘 다 vetting 된 같은 Package ID 의 코드를 씁니다
4. dtcc-mediator 가 확인 응답을 모아 판정
5. 각 Participant 가 자기 ACS 에 반영
```

Step 01 의 확인 프로토콜이 실제로 돈 것입니다.

## Daml 코드는 그대로입니다

Step 04 의 `daml/Step04/Deposit.daml` 을 한 줄도 고치지 않았습니다.

propose/accept 로 짜 두었기 때문에 노드가 분리돼도 그대로 동작합니다. 반대로 Step 03 의
`Transfer` 나 `submit [Citi, Alice]` 방식이었다면 여기서 전부 깨졌을 것입니다.

**권한 모델을 처음부터 제대로 짜면 배포 구성이 바뀌어도 코드가 견딥니다.**

## 직접 만져보기

```sh
./steps/step05.sh --keep
```

끝나면 출력된 변수와 포트를 씁니다. Canton 콘솔로 노드에 직접 붙을 수도 있습니다.

```sh
java -jar "$CANTON_JAR" sandbox-console -c canton/canton.conf
```

`CANTON_JAR` 은 러너가 `--keep` 으로 끝날 때 출력해 줍니다. 직접 찾으려면:

```sh
find "${DPM_HOME:-$HOME/.dpm}/cache/components/canton-open-source" -name 'canton-open-source-*.jar'
```

콘솔에서 볼 만한 것들입니다.

```scala
health.status
citi.parties.list()
morganstanley.parties.list()
citi.topology.party_to_participant_mappings.list()
citi.packages.list()
citi.ledger_api.state.acs.of_party(citi.parties.list().head.party)
```

## 아직 확인하지 못한 것

| | 왜 |
| --- | --- |
| 다중 호스팅 / threshold | 한 Party 를 두 노드에 두지 않았습니다 |
| Reassignment | Synchronizer 가 하나입니다 |
| BFT Sequencer / Mediator group | 각각 하나입니다 |
| External Party | 모두 Hosted Party 입니다 |
| 한쪽만 vetting 했을 때의 거부 | 양쪽에 동시에 올렸습니다 |

---

다음: **[Step 06 — DvP](Step06Dvp.md).** 증권과 현금 두 다리를 하나의 Transaction
에서 동시에 이전시켜 원자적 교환을 만듭니다.
