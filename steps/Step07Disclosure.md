# Step 07 — 공시와 감사

Step 02~06 에서 프라이버시는 늘 **"안 보인다"** 쪽이었습니다. 이번에는 반대입니다 —
**보여야 하는 것을 어떻게 보이게 하는가.**

## 실행

저장소 루트에서:

```sh
./steps/step07.sh
```

| 옵션 | 용도 |
| --- | --- |
| (없음) | 단계마다 엔터를 기다립니다 |
| `--auto` | 엔터 없이 전부 실행합니다 |

## 등장 인물

| 이름 | 역할 |
| --- | --- |
| **Citi** | 발행 은행 |
| **Alice** | Citi 의 고객 |
| **Bob** | 이체 상대 |
| **SEC** | 감독기관. 상시 공시 대상 |
| **Auditor** | 외부 감사인. 필요할 때만 공시 |
| **David** | 제3자. 아무것도 못 봄 |

## 다루는 파일

| 파일 | 내용 |
| --- | --- |
| `daml/Step07/Disclosure.daml` | `RegulatedDeposit` + `TransferProposal` + `AuditedDeposit` |
| `daml/Step07/DisclosureTest.daml` | Daml Script 13개 |

## 문제

SEC 는 Citi 가 발행하는 모든 예금을 감독해야 합니다. 그런데 **SEC 는 예금 계약의
Signatory 가 아닙니다.** 당사자가 아니기 때문입니다.

Step 02 에서 David 가 Alice 의 예금을 못 본 것과 같은 상황입니다. Stakeholder 가
아니면 데이터가 도달하지 않습니다.

## 세 가지 역할

| | 뜻 |
| --- | --- |
| **Signatory** | 동의가 필요하다. 계약 성립에 서명이 필요 |
| **Observer** | 보여준다. 권한은 없고 가시성만 |
| **Controller** | 행사할 수 있다. 특정 Choice 를 실행 |

`Observer` 가 이 문제를 풉니다. 서명 없이 가시성만 줍니다.

## 반드시 남아야 할 것

### 1. 공시는 설계 시점에 결정됩니다

```daml
template RegulatedDeposit
  with
    bank : Party
    owner : Party
    regulator : Party
    amount : Decimal
    frozen : Bool
  where
    signatory bank, owner
    observer regulator
```

`regulator` 를 필드로 갖고 `observer` 로 선언합니다. **이 Template 으로 만든 모든
Contract 는 처음부터 SEC 에게 보입니다.**

나중에 "이 거래는 공시하고 저 거래는 감추자" 를 할 수 없습니다. 감추려면 다른
Template 을 써야 합니다.

```
Solidity     이벤트를 나중에 끄고 켤 수 있다
Daml         Template 이 공시 범위를 확정한다
```

**실무 함의**: 규제 대상 자산의 Template 설계는 공시 범위를 확정하는 일입니다.
법무·컴플라이언스가 관여해야 하는 지점이고, 개발자가 혼자 정할 것이 아닙니다.

### 2. 가시성과 권한은 별개입니다

SEC 는 모든 예금을 봅니다. 그런데 **아무것도 못 합니다.**

| 시도 | 결과 |
| --- | --- |
| `ProposeTransfer` | 거부 — Controller 가 `owner` |
| `archiveCmd` | 거부 — Signatory 가 아님 |

`Observer` 는 Choice 를 주지 않기 때문입니다. Step 04 에서 제안을 Observer 가 본다고
수락할 수 있는 게 아니었던 것과 같은 원리입니다.

### 3. 개입하게 하려면 Choice 로 명시합니다

감독기관이 동결까지 할 수 있어야 한다면 그 권한을 Choice 로 써 줘야 합니다.

```daml
choice Freeze : ContractId RegulatedDeposit
  controller regulator
  do
    assertMsg "이미 동결되어 있습니다" (not frozen)
    create this with frozen = True
```

```
signatory  = Citi, Alice
controller = SEC
─────────────────────────
권한        = Citi, Alice, SEC

만들려는 Contract 의 signatory = Citi, Alice        → 충족
```

**SEC 는 Signatory 가 아닌데도 Choice 를 행사합니다.** Step 03 에서 본 대로
Controller 는 Signatory 와 별개이기 때문입니다.

그리고 Alice 는 이 Template 을 수락한 시점에 "SEC 가 동결할 수 있다" 에 이미
동의했습니다. 약관에 서명하는 것과 같습니다.

### 4. 동결은 권한이 아니라 상태 검사로 막습니다

```daml
choice ProposeTransfer : ContractId TransferProposal
  with
    newOwner : Party
  controller owner
  do
    assertMsg "동결된 예금은 이체할 수 없습니다" (not frozen)
    ...
```

Alice 는 동결 중에도 여전히 Controller 입니다. 막는 것은 **Choice 본문의
`assertMsg`** 입니다. 권한 검사와 상태 검사를 구분할 것.

### 5. 선택적 공시도 archive + create 입니다

SEC 는 상시 공시지만 외부 감사인은 그렇지 않습니다. `Publish` 로 그때그때 엽니다.

```daml
choice Publish : ContractId AuditedDeposit
  with
    auditor : Party
  controller owner
  do
    create AuditedDeposit with deposit = this, auditor
```

Observer 가 하나 더 있는 **새 Contract** 를 만듭니다. Contract 는 수정되지 않으므로
Observer 를 더하는 것도 archive + create 이고, **Contract ID 가 바뀝니다.**

### 6. 공시는 되돌릴 수 없습니다

`Unpublish` 는 Observer 가 없는 Contract 를 새로 만듭니다. 그러나 **이전 Contract 를
이미 본 Participant 의 기록까지 지울 수는 없습니다.**

원장은 append-only 이고 상대 노드의 저장소를 우리가 통제하지 않습니다.

> `Unpublish` 가 하는 일은 **앞으로 안 보이게** 이지 **본 것을 잊게** 가 아닙니다.

실무 함의: 무엇을 누구에게 공개할지는 **한 번 결정하면 취소가 안 되는 선택**입니다.

## 테스트 13개

| 상시 공시 | 검증 |
| --- | --- |
| `testRegulatorSees` | SEC 는 발행 즉시 예금을 본다 |
| `testStrangerSeesNothing` | David 는 아무것도 못 본다 |
| `testRegulatorSeesTransfer` | 이체 제안과 결과가 모두 SEC 에게 보인다 |

| Observer 는 권한이 아니다 | 검증 |
| --- | --- |
| `testRegulatorCannotTransfer` | SEC 는 보지만 이체시킬 수 없다 |
| `testRegulatorCannotArchive` | SEC 는 archive 할 수 없다 |
| `testStrangerCannotFreeze` | 제3자는 동결할 수 없다 |

| 명시된 권한만 행사 | 검증 |
| --- | --- |
| `testRegulatorFreezes` | SEC 는 Freeze Choice 가 있으므로 동결할 수 있다 |
| `testFrozenCannotTransfer` | 동결된 예금은 이체가 막힌다 |
| `testUnfreezeRestores` | 해제하면 다시 이체된다 |
| `testOwnerCannotFreeze` | 예금주는 자기 예금을 동결할 수 없다 |

| 선택적 공시 | 검증 |
| --- | --- |
| `testAuditorSeesNothingBefore` | 공개 전에는 감사인이 못 본다 |
| `testPublishAddsAuditor` | Publish 로 감사인에게 공개된다 |
| `testUnpublishHidesFuture` | Unpublish 하면 이후 Contract 는 안 보인다 |

## 이 Step 으로 확인하지 못한 것

`dpm test` 는 인메모리 엔진이라 **SEC 의 Participant 에 실제로 데이터가 도달하는지**는
보이지 않습니다. [Step 05](Step05MultiParticipant.md) 의 구성에 `sec` participant 를
추가하면 확인할 수 있습니다.

`canton/step05.conf` 에 participant 를 하나 더 선언하고 `step05-bootstrap.canton` 에서
`connect_local` 과 `parties.enable` 을 추가하면 됩니다. Daml 코드는 고칠 것이 없습니다.

---

다음: **[Step 08 — Reassignment](Step08Reassignment.md).** Synchronizer 를 둘 띄우고
Contract 를 원장 사이로 옮겨 결제를 성립시킵니다.
