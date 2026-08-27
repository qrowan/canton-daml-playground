# Step 03 — 첫 계약

[Step 02](Step02Environment.md) 는 원장을 관찰했다. 여기서는 **코드를 쓴다.**

Daml 문법과 권한 계산 규칙을 익히고, `dpm test` 로 검증하는 개발 루프를 만든다.
그리고 예금 이체가 왜 아직 불가능한지 확인한다.

## 실행

저장소 루트에서:

```sh
./steps/step03.sh
```

Sandbox 를 띄우지 않는다. `dpm test` 의 인메모리 엔진으로 빠르게 돈다.

| 옵션 | 용도 |
| --- | --- |
| (없음) | 단계마다 엔터를 기다린다 |
| `--auto` | 엔터 없이 전부 실행 |

## 다루는 파일

| 파일 | 내용 |
| --- | --- |
| `daml/Step03/Deposit.daml` | 템플릿. Step 02 의 것에 choice 4개를 더한 것 |
| `daml/Step03/DepositTest.daml` | Daml Script 테스트 11개 |

Step 02 의 `daml/Step02/Deposit.daml` 은 그대로 있다. Step 02 러너를 다시 실행해도
동작한다.

## Step 02 에서 무엇이 늘었는가

| | Step 02 | Step 03 |
| --- | --- | --- |
| 필드 | `bank`, `owner`, `amount` | 같음 |
| `signatory` | `bank, owner` | 같음 |
| `ensure` | `amount > 0.0` | 같음 |
| choice | 없음 | `ShowBalance` `Withdraw` `AddInterest` `Transfer` |

필드를 건드리지 않았으므로 Step 02 러너는 그대로 동작한다.

## 문법

### Template

```
template <이름>
  with        필드 — 원장에 기록될 데이터
    ...
  where       규칙 — 누가 서명하고 무엇을 할 수 있는가
    ...
```

`signatory` 는 동의가 필요한 party, `ensure` 는 원장 기록 전 항상 검사되는 불변식이다.

**template 에 선언되지 않은 것은 존재하지 않는다.** `onlyOwner` 로 막는 게 아니라
애초에 그런 행위가 없다.

### Choice

```
choice <이름> : <반환 타입>
  with
    <인자> : <타입>        행사할 때 넘기는 값
  controller <party>       이 choice 를 행사할 수 있는 party
  do
    <본문>
```

기본은 **consuming** 이다. 행사되면 그 계약은 archive 된다. 소비하지 않으려면
`nonconsuming` 을 앞에 붙인다.

`controller` 는 `signatory` 와 별개다. signatory 가 아닌 party 도 controller 가 될
수 있고, Step 04 에서 그 형태가 나온다.

## 반드시 남아야 할 것

### 1. 권한 = [계약의 signatory] + [choice 의 controller]

`AddInterest` 를 예로 들면:

```
  signatory  = Citi, Alice
  controller = Citi
  ─────────────────────────
  권한        = Citi, Alice

  만들려는 계약의 signatory = Citi, Alice   → 충족
```

**Citi 혼자 행사했는데 Alice 서명이 필요한 계약이 만들어진다.**

여기서 중요한 함의가 나온다 — **계약에 서명한다는 것은 그 template 에 선언된 모든
choice 에 동의한다는 뜻**이다. Alice 는 Deposit 을 수락한 시점에 "Citi 가 이자를
붙일 수 있다"에 이미 동의했다. 매번 다시 묻지 않는다.

현실의 계약과 같다. 약관에 서명하면 그 조항이 발동할 때마다 다시 서명하지 않는다.

**설계 함의**: template 에 choice 를 하나 추가하는 것은 조항을 하나 더 넣는 것이다.
가볍게 볼 일이 아니다.

### 2. 계약은 수정되지 않는다

`Withdraw` 는 `amount` 를 줄이는 것처럼 보이지만 그렇지 않다.

```
Solidity     deposit.amount -= 30       주소 그대로, 값만 변경

Daml         archive(cid1)              cid1 은 무효가 되고
             create Deposit{70.0}       cid2 가 새로 생긴다
             ← 하나의 원자적 트랜잭션
```

`testPartialWithdraw` 가 옛 계약 ID 로 조회하면 `None` 임을 확인한다.

**실무 함의**: 계약 ID 를 외부 시스템에 저장해두면 곧 무효가 된다. 조회는 `query` 로
다시 하는 것이 원칙이다.

### 3. Transfer 는 실패한다 — 그리고 그것이 옳다

```
  signatory  = Citi, Alice
  controller = Alice
  ─────────────────────────
  권한        = Citi, Alice

  만들려는 계약의 signatory = Citi, Bob
                                    ↑ Bob 의 권한이 없다
```

컴파일은 되고 실행에서 실패한다. `testTransferFails` 가 이것을 문서화한다.

**버그가 아니다.** Deposit 은 owner 의 서명이 필요한 계약인데, 아직 아무 관계도 없는
Bob 이 서명했을 리 없다. 남에게 원치 않는 채권·채무를 떠넘길 수 없다는 뜻이고 Daml 이
의도한 안전장치다.

현실에서도 내 예금 계약의 명의를 상대 동의 없이 남에게 넘길 수는 없다.

해결은 Step 04 의 propose/accept 다.

### 4. dpm test 는 Canton 이 아니다

인메모리 엔진으로 스크립트를 실행한다. Sequencer·Mediator·확인 프로토콜이 없다.

| | `dpm test` | Step 02 의 러너 |
| --- | --- | --- |
| 속도 | 빠름 (초 단위) | 느림 (기동 포함) |
| 검증하는 것 | Daml 로직·권한 모델 | 실제 원장 동작 |
| party 관리 | `allocateParty` 로 매번 새로 | 영속 (재기동 전까지) |
| 다중 party 제출 | `submit [Citi, Alice]` 가 항상 통함 | participant 가 둘 다 호스팅할 때만 |

로직은 `dpm test` 로 빠르게, 원장 동작은 러너로 확인한다.

`submit [Citi, Alice]` 는 테스트 전용으로 볼 것. 노드가 다르면 불가능하고, 그때
필요한 것이 Step 04 다.

### 5. 실패 경로를 테스트하라

11개 중 5개가 `submitMustFail` 이다.

| 테스트 | 검증 |
| --- | --- |
| `testBankAloneCannotIssue` | Citi 혼자서는 발행 불가 |
| `testOwnerAloneCannotIssue` | Alice 혼자서도 발행 불가 |
| `testEnsureRejectsZero` | `ensure` 위반은 기록되지 않음 |
| `testWithdrawTooMuch` | 잔액 초과 인출 거부 |
| `testOwnerCannotAddInterest` | controller 가 아니면 행사 불가 |
| `testTransferFails` | 새 owner 의 권한 없음 |

권한 모델에서는 **성공 경로보다 실패 경로가 중요하다.** "되는 것"보다 "안 되는 것"이
보안 속성이기 때문이다.

## 커버리지가 60% 로 나오는 이유

```
- Internal template choices
  5 defined
  3 ( 60.0%) exercised
```

`Transfer` 는 `submitMustFail` 로만 호출되므로 "행사됨"으로 세지 않는다 — 실제로
성공한 적이 없기 때문이다. `Archive` 는 이 테스트에서 직접 부르지 않았다.

## 직접 해보기

1. `Withdraw` 의 `assertMsg` 를 지우고 `dpm test` 를 다시 돌려 본다.
   `testWithdrawTooMuch` 가 실패한다. 왜?

2. `AddInterest` 의 `controller` 를 `owner` 로 바꿔 본다.
   `testBankAddsInterest` 와 `testOwnerCannotAddInterest` 중 무엇이 깨지는가?

3. `ensure` 줄을 지우고 `testEnsureRejectsZero` 를 돌려 본다.

4. `ShowBalance` 에서 `nonconsuming` 을 떼어 본다.
   `testShowBalance` 의 `isSome` 단정이 왜 깨지는가?

5. `Transfer` 의 controller 를 `controller owner, newOwner` 로 바꿔 본다.
   `testTransferFails` 가 통과하지 않게 된다. **이것이 옳은 해결인가?**
   (힌트: 그러면 그 트랜잭션을 누가 제출해야 하는가. Alice 와 Bob 이 서로 다른
   participant 에 있다면?)

5번이 Step 04 로 이어지는 질문이다.

---

다음: **[Step 04 — 두 당사자](Step04TwoParties.md).** propose/accept 로 두 시점에
나뉜 동의를 결합해 이체를 성립시킨다.
