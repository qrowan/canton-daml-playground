# Step 06 — DvP

Bob 이 보유한 채권을 Alice 에게 팔고, Alice 는 현금을 지급합니다. 두 이전이 **하나의
Transaction 안에서** 일어나야 합니다.

[Step 03](Step03FirstContract.md) 에서 남겨둔 연습문제 5번에 답하는 단계이기도 합니다.

## 실행

저장소 루트에서:

```sh
./steps/step06.sh
```

| 옵션 | 용도 |
| --- | --- |
| (없음) | 단계마다 엔터를 기다립니다 |
| `--auto` | 엔터 없이 전부 실행합니다 |

## 등장 인물

| 이름 | 역할 |
| --- | --- |
| **Citi** | 현금(토큰화 예금) 발행 |
| **GoldmanSachs** | 채권 발행 |
| **Bob** | 채권 보유. 매도자 |
| **Alice** | 현금 보유. 매수자 |
| **David** | 제3자 |

## 다루는 파일

| 파일 | 내용 |
| --- | --- |
| `daml/Step06/Dvp.daml` | `Cash` + `Bond` + `DvpProposal` |
| `daml/Step06/DvpTest.daml` | Daml Script 13개. 그중 8개가 `submitMustFail` |

## 왜 원자성이 필요한가

나눠서 하면 이렇게 됩니다.

```
TX 1   Bob 이 채권을 Alice 에게 이전
TX 2   Alice 가 현금을 Bob 에게 이전      ← 여기서 멈추면 Bob 만 손해
```

이것을 **결제 리스크(principal risk)** 라고 하고, 현실 금융은 중앙청산소나 에스크로를
두어 막습니다.

Daml 은 두 이전을 한 Transaction 에 담아 **구조적으로 없앱니다.** 전부 성공하거나 전부
실패하고, 중간 상태가 존재하지 않습니다.

## 반드시 남아야 할 것

### 1. Step 03 연습문제 5번의 답

Step 03 에서 `Transfer` 가 실패했을 때 이런 질문을 남겼습니다.

> `controller` 를 `owner, newOwner` 로 바꾸면 되지 않나? 이것이 옳은 해결인가?

답은 **그 자체로는 해결이 아니지만, DvP 에서는 바로 그것이 필요하다** 입니다.

```daml
choice CashTransfer : ContractId Cash
  with
    newOwner : Party
  controller owner, newOwner
  do
    create this with owner = newOwner
```

이렇게 두면 이 Choice 는 **양쪽 권한이 모두 있는 Transaction 안에서만** 행사할 수
있습니다. Alice 혼자서는 못 씁니다 (`testAliceCannotMoveCashAlone`). 그런데 DvP 결제
Transaction 은 이미 양쪽 권한을 갖고 있으므로 거기서는 쓸 수 있습니다.

**"단독으로는 불가, 합의된 결제 안에서는 가능"** 이라는 조건을 타입 수준에서 표현한
것입니다.

### 2. 권한이 두 단계로 흐릅니다

`Settle` 을 행사하는 시점입니다.

```
DvpProposal 의 signatory = GoldmanSachs, Bob
Settle 의 controller     = Alice
─────────────────────────────────────────
이 지점의 권한            = GoldmanSachs, Bob, Alice
```

**채권 다리 — 직접 create**

```
만들려는 Bond 의 signatory = GoldmanSachs, Alice        → 충족
```

**현금 다리 — 중첩 exercise**

```
exercise cashCid CashTransfer
  controller = Alice, Bob
    → 둘 다 현재 권한에 있으므로 행사 가능

  그 안의 권한 = [Cash 의 signatory] + [controller]
               = (Citi, Alice) + (Alice, Bob)
               = Citi, Alice, Bob

  만들려는 Cash 의 signatory = Citi, Bob                 → 충족
```

**Citi 는 이 Transaction 에 아무 행위도 하지 않았는데 권한이 실렸습니다.** Cash
Contract 의 signatory 로서 이미 동의해 둔 것이 Choice 를 통해 흘러온 것입니다.

발행자가 결제 시점에 온라인일 필요가 없는 이유입니다. Step 03 의 `AddInterest` 에서
본 것과 같은 원리가, 여기서는 중첩된 exercise 를 통해 두 단계로 흐릅니다.

> 직접 create 로 바꾸면 왜 실패하는지 계산해 볼 것. `create cash with owner = bond.owner`
> 는 `Citi` 의 권한을 얻을 길이 없습니다. 그래서 반드시 exercise 를 거쳐야 합니다.

### 3. 채권만 잠깁니다

`ProposeDvp` 가 원본 `Bond` 를 **소비**합니다.

```
발행 후        Bob    Bond{10}                 Alice  Cash{100}

제안 후        Bob    (없음)                    Alice  Cash{100}
                      DvpProposal{Bond, Alice, 100}     ← 채권만 잠김

결제 후        Bob    Cash{100}                Alice  Bond{10}
```

그래서 같은 채권을 두 번 팔 수 없습니다 (`testCannotDoubleSell`).

**이것은 결제 리스크가 아니라 유동성 제약입니다.** Alice 의 현금은 움직인 적이 없고
Bob 은 언제든 `Cancel` 로 회수할 수 있습니다.

### 4. 현금은 잠기지 않습니다

Alice 의 현금은 `Settle` 시점에 인자로 지정됩니다. 그 사이 Alice 가 그 현금을 다른 데
쓰면 `Settle` 이 실패합니다 — 소비된 Contract 를 참조하게 되기 때문입니다
(`testStaleCashFails`).

실패로 끝나므로 안전하지만 Bob 은 헛수고합니다. 양쪽을 다 잠그려면 현금 쪽에도 제안
절차가 필요하고, 그러면 3단계 워크플로가 됩니다.

**실무에서 어느 쪽을 택할지는 거래 성격에 달렸습니다.** 체결률이 중요하면 양쪽을 잠그고,
유동성 회전이 중요하면 한쪽만 잠급니다.

### 5. 원자성은 실패 경로에서 확인됩니다

13개 중 8개가 `submitMustFail` 입니다.

| 테스트 | 검증 |
| --- | --- |
| `testAliceCannotMoveCashAlone` | Alice 혼자 현금을 Bob 에게 보낼 수 없음 |
| `testBobCannotMoveBondAlone` | Bob 혼자 채권을 Alice 에게 보낼 수 없음 |
| `testCannotDoubleSell` | 같은 채권을 두 번 팔 수 없음 |
| `testWrongAmountFails` | 금액이 다르면 **양쪽 다** 안 움직임 |
| `testStaleCashFails` | 이미 쓴 현금으로는 결제 불가 |
| `testOthersCashFails` | 남의 현금으로는 결제 불가 |
| `testStrangerCannotSettle` | 제3자는 결제 불가 |
| `testStrangerCannotCancel` | 제3자는 철회 불가 |

`testWrongAmountFails` 가 핵심입니다. 금액이 맞지 않으면 `Settle` 전체가 실패하고,
채권도 현금도 움직이지 않습니다. **"채권만 넘어가고 현금은 안 오는" 상태가 존재할 수
없습니다.**

## 필요 없어진 것

| 전통적 해법 | Daml 에서 |
| --- | --- |
| 에스크로 계정 | 불필요 — 한 Transaction 이 원자적 |
| 중앙청산소(CCP) | 불필요 — 상대방 리스크가 결제 순간에 없음 |
| HTLC / 해시 타임락 | 불필요 — 크로스체인이 아님 |
| 순차 결제 + 롤백 로직 | 불필요 — 롤백할 중간 상태가 없음 |

기관 결제에서 Canton 이 팔리는 지점이 정확히 이것입니다.

## 다중 노드에서 돌리려면

이 Step 은 `dpm test` 로 진행합니다. [Step 05](Step05MultiParticipant.md) 의 구성에
`goldmansachs` participant 를 추가하면 실제 노드 간 DvP 를 확인할 수 있습니다.

`canton/canton.conf` 에 participant 를 하나 더 선언하고 `bootstrap.canton` 에서
`connect_local` 과 `parties.enable` 을 추가하면 됩니다. 권한 모델이 이미 맞으므로
**Daml 코드는 고칠 것이 없습니다.**

## 직접 해보기

1. `CashTransfer` 의 controller 를 `owner` 만으로 되돌립니다.
   `Settle` 이 어떻게 깨지는가? 에러가 무엇을 요구하는가?

2. `Settle` 에서 현금 다리를 exercise 대신 직접 create 로 바꿉니다.
   ```daml
   create cash with owner = bond.owner
   ```
   왜 실패하는가? 권한 계산을 직접 해볼 것.

3. 금액 검사를 `==` 에서 `>=` 로 바꿉니다.
   `testWrongAmountFails` 는 통과하지만 새 문제가 생깁니다. 거스름돈은?

4. `DvpProposal` 에서 `observer buyer` 를 지웁니다.
   Alice 가 `Settle` 을 행사할 수 있는가?

5. `ProposeDvp` 를 `nonconsuming` 으로 바꿉니다.
   `testCannotDoubleSell` 이 어떻게 되는가?

---

다음: **Step 07 — 공시와 감사.** Observer 로 감독기관에 거래를 공시하고, 누가 무엇을
볼 수 있는지를 설계로 통제합니다.
