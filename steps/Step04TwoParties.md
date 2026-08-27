# Step 04 — 두 당사자

[Step 03](Step03FirstContract.md) 에서 `Transfer` 가 실패했다. 그리고 발행도 사실은
`submit [Citi, Alice]` 라는 편법에 기대고 있었다.

두 문제의 원인은 같다. **한 트랜잭션에 두 party 의 권한이 필요한데, participant 는
자기가 호스팅하는 party 의 권한만 행사할 수 있다.**

해법은 권한을 두 트랜잭션으로 나누는 것 — **propose / accept** 다.

## 실행

저장소 루트에서:

```sh
./steps/step04.sh
```

| 옵션 | 용도 |
| --- | --- |
| (없음) | 단계마다 엔터를 기다린다 |
| `--auto` | 엔터 없이 전부 실행 |

## 다루는 파일

| 파일 | 내용 |
| --- | --- |
| `daml/Step04/Deposit.daml` | `DepositProposal` + `Deposit` + `TransferProposal` |
| `daml/Step04/DepositTest.daml` | Daml Script 12개 |

## Step 03 에서 무엇이 달라졌는가

| | Step 03 | Step 04 |
| --- | --- | --- |
| 발행 | `submit [Citi, Alice]` 직접 생성 | `DepositProposal` → `AcceptDeposit` |
| 이체 | `Transfer` (실행 실패) | `ProposeTransfer` → `AcceptTransfer` |
| 템플릿 수 | 1 | 3 |
| `observer` | 없음 | 제안 템플릿에 등장 |
| `submit [a, b]` | 테스트에서 사용 | **하나도 없음** |

`ShowBalance` / `Withdraw` / `AddInterest` 는 그대로 가져왔다.

## 왜 `submit [a, b]` 가 편법인가

```
같은 노드      citi-participant { Citi, Alice }
               → actAs [Citi, Alice] 가능

다른 노드      citi-participant          { Citi }
               morganstanley-participant { Bob }
               → 어느 쪽도 두 권한을 동시에 갖지 못함
```

Step 02 에서 통했던 이유는 sandbox 의 participant 가 하나였기 때문이다. Alice 가
Bob 같은 타행 고객이었다면 그 코드는 실제 환경에서 동작하지 않는다.

## 패턴

```
[TX 1]  제안자가 자기 권한만으로 제안 계약을 만든다

          signatory 제안자
          observer  상대방          ← 상대가 볼 수 있게

[TX 2]  상대가 그 제안의 choice 를 행사한다

          권한 = [제안의 signatory] + [choice 의 controller]
               =      제안자        +      상대방

          → 이 합쳐진 권한으로 목표 계약을 만든다
```

두 시점에 나뉘어 있던 동의가 두 번째 트랜잭션에서 결합된다.

## 반드시 남아야 할 것

### 1. 권한 계산 — 발행

```
TX 1   Citi 가 혼자 제안을 만든다
         signatory = Citi 뿐 → Citi 권한만으로 생성 가능

TX 2   Alice 가 AcceptDeposit 을 행사
         권한 = [Citi] + [Alice] = Citi, Alice
         만들려는 Deposit 의 signatory = Citi, Alice   → 충족
```

### 2. 권한 계산 — 이체

```
TX 1   Alice 가 ProposeTransfer 를 행사
         권한 = [Citi, Alice] + [Alice] = Citi, Alice
         만들려는 TransferProposal 의 signatory = Citi, Alice   → 충족
         ← 원본 Deposit 은 여기서 소비된다

TX 2   Bob 이 AcceptTransfer 를 행사
         권한 = [Citi, Alice] + [Bob] = Citi, Alice, Bob
         만들려는 Deposit 의 signatory = Citi, Bob            → 충족
```

**TX 2 에서 Alice 의 권한이 어디서 왔는지 주목할 것.** Alice 는 그 트랜잭션을
제출하지도 않았다. 제안 계약의 signatory 로 남아있던 Alice 의 동의가 그대로 실린 것이다.

이것이 propose/accept 가 작동하는 이유다 — **제안 계약이 제안자의 동의를 보관한다.**

### 3. observer 가 여기서 처음 필요해진다

제안의 signatory 는 제안자뿐이다. 상대방은 서명하지 않았으므로 signatory 가 아니다.
그런데 제안을 **볼 수 없으면 수락할 수도 없다.**

```daml
template DepositProposal
  with
    deposit : Deposit
  where
    signatory deposit.bank      -- Citi 만 서명
    observer deposit.owner      -- Alice 는 볼 수만 있다

    choice AcceptDeposit : ContractId Deposit
      controller deposit.owner  -- 수락 권한은 여기서 온다
```

**observer 와 controller 를 혼동하지 말 것.** observer 는 가시성만 준다. observer
라고 아무 choice 나 행사할 수 있는 게 아니고, 반대로 controller 는 observer 가
아니어도 된다(다만 볼 수 없으면 실무적으로 행사가 어렵다).

### 4. 거절과 철회는 반드시 되돌려야 한다

`ProposeTransfer` 는 원본 `Deposit` 을 **소비한다.**

```daml
choice RejectTransfer : ContractId Deposit
  controller newOwner
  do
    create deposit          -- deposit.owner 는 원 소유자 그대로
```

돌려주지 않으면 **예금이 사라진다.** 흔한 버그이며, `Reject` 를 `pure ()` 로 두면
자산이 증발한다.

반면 발행 제안은 아무것도 소비하지 않았으므로 `RejectDeposit` 은 `pure ()` 가 맞다.
되돌릴 것이 없다.

**판별법**: 그 제안을 만들 때 무언가를 소비했는가? 소비했다면 거절 경로에서 반드시
복구해야 한다.

### 5. 제안 구간에는 원본이 존재하지 않는다

```
발행 후     Deposit{Alice, 100}                   활성 1건

제안 후     TransferProposal{deposit, Bob}        활성 1건
            Deposit 은 소비됨                      활성 0건

수락 후     Deposit{Bob, 100}                      활성 1건
            TransferProposal 은 소비됨
```

중간 상태에서 **Alice 의 예금 조회 결과가 빈 배열이다.** `testProposalConsumesDeposit`
이 이것을 확인한다.

실무 함의: 이 구간을 사용자에게 "이체 대기중"으로 보여줘야 한다. 잔액이 0 으로 보이면
안 된다. 애플리케이션은 `Deposit` 뿐 아니라 `TransferProposal` 도 함께 조회해야 한다.

## 테스트 12개

| 발행 | 검증 |
| --- | --- |
| `testIssueViaProposal` | Citi 가 혼자 제안 → Alice 가 수락 → 예금 생성 |
| `testProposalVisibleToOwner` | 제안이 Citi 와 Alice 에게만 보인다 (David 는 못 봄) |
| `testRejectIssue` | 거절하면 예금이 생기지 않는다 |
| `testCancelIssue` | 제안자도 철회할 수 있다 |
| `testStrangerCannotAcceptIssue` | David 는 Alice 앞으로 온 제안을 수락할 수 없다 |
| `testDirectIssueStillFails` | 여전히 한쪽 권한만으로는 예금을 못 만든다 |

| 이체 | 검증 |
| --- | --- |
| `testTransferViaProposal` | Alice 제안 → Bob 수락 → 소유권 이동 |
| `testProposalConsumesDeposit` | 제안 구간에 예금 계약이 존재하지 않는다 |
| `testRejectReturnsDeposit` | Bob 이 거절하면 Alice 에게 되돌아온다 |
| `testCancelReturnsDeposit` | Alice 가 철회해도 되돌아온다 |
| `testStrangerCannotAccept` | David 는 Bob 앞으로 온 제안을 수락할 수 없다 |
| `testCannotTransferToSelf` | 자기 자신에게는 이체할 수 없다 |

## 왜 제안 계약이 전체 Deposit 을 담는가

```daml
template TransferProposal
  with
    deposit : Deposit       -- 통째로
    newOwner : Party
```

금액과 은행을 따로 복사하지 않고 통째로 들고 있으면, 수락 시
`create deposit with owner = newOwner` 한 줄로 끝난다. `Deposit` 에 필드가 늘어도
제안 템플릿을 고칠 필요가 없다.

signatory 도 `deposit.bank, deposit.owner` 로 참조한다.

## 남은 문제

지금까지는 전부 participant 하나에서 확인했다. **"노드가 분리돼도 동작한다"는 아직
말뿐이다.**

---

다음: **[Step 05 — 다중 Participant](Step05MultiParticipant.md).** 노드를 직접 띄우고
Alice 와 Bob 을 서로 다른 Participant 에 두어 실제로 확인한다.
