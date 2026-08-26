# Step 01 — 용어

Canton 의 용어를 하나의 시나리오를 끝까지 따라가며 익힌다. 코드는 없다.

읽고 나면 이 문장이 해석되어야 한다.

> `citi-participant` 가 호스팅하는 `Alice` 가 `alice-web` 으로 제출한 트랜잭션을,
> `morganstanley-participant` 가 vetting 된 package-id 로 재실행해 확인 응답을 보내고,
> `dtcc-mediator` 가 판정을 내린다.

---

## 등장 인물

| 이름 | 정체 | Canton 에서의 위치 |
| --- | --- | --- |
| **DTCC** | 예탁결제기관 | Synchronizer 운영 |
| **Citi** | 상업은행. 토큰화 예금 발행 | Participant 운영 + party |
| **Morgan Stanley** | 투자은행. Bob 의 증권사 | Participant 운영 + party |
| **Alice** | Citi 의 개인 고객 | Party (Citi 가 발급) |
| **Bob** | Morgan Stanley 의 개인 고객 | Party (Morgan Stanley 가 발급) |

이후 Step 에서 등장:

| 이름 | 정체 | 어디서 |
| --- | --- | --- |
| **Robinhood** | 소매 브로커. 고객 party 다수 위탁 호스팅 | 다중 호스팅, 커스터디 |
| **Charlie** | 자기 키를 직접 보유하는 개인 | External party |
| **SEC** | 감독기관 | Observer, 공시 |
| **Goldman Sachs** | 증권 발행·거래 상대방 | DvP 교환 |

Alice 와 Bob 은 **각자의 은행이 발급한 party** 다. 자기 키를 갖고 있지 않다.
자기 키를 쥔 개인은 Charlie 이고, 그 차이는 2막에서 다룬다.

---

## 시나리오

Citi 가 Alice 에게 토큰화 예금 100 을 발행한다. Alice 가 그것을 Bob 에게 이체한다.

```
    ┌─────────────┐                      ┌──────────────────┐
    │    Citi     │  ──── 발행 ────▶     │      Alice       │
    └─────────────┘                      └──────────────────┘
                                                  │
                                                 이체
                                                  ▼
                                         ┌──────────────────┐
                                         │       Bob        │
                                         └──────────────────┘

    Alice 는 Citi 고객, Bob 은 Morgan Stanley 고객 → 서로 다른 participant
```

---

## 1막 — 무대: 누가 컴퓨터를 돌리는가

거래가 시작되기 전에 노드들이 존재한다.

```
  citi-participant                    morganstanley-participant
  (Citi 가 운영)                       (Morgan Stanley 가 운영)
        │                                        │
        └───────────────┬────────────────────────┘
                        │
              ┌─────────┴──────────┐
              │   Synchronizer     │  DTCC 운영
              │   dtcc-sequencer   │  순서 부여
              │   dtcc-mediator    │  판정
              └────────────────────┘
```

### Participant node

**원장 데이터를 보관하고 트랜잭션을 검증하는 서버.** 은행·증권사 같은 기관이 각자 운영한다.

세 가지를 한다.

1. 자기 몫의 계약을 저장한다
2. 들어온 트랜잭션을 **직접 다시 실행해서** 맞는지 확인한다
3. 애플리케이션에 Ledger API 를 제공한다

**"자기 몫"** 이 핵심이다. participant 는 전체 원장의 사본을 갖지 않는다. 자기가 관여한
계약만 갖는다. `morganstanley-participant` 에는 Citi 내부 거래가 존재하지 않는다.

### Synchronizer

**여러 participant 사이에서 메시지 순서를 정하고 판정을 내리는 인프라.** 프로세스
하나가 아니라 노드 두 종류의 묶음이다.

| 노드 | 하는 일 | 볼 수 있는 것 |
| --- | --- | --- |
| **Sequencer** (`dtcc-sequencer`) | 모든 메시지에 전순서를 부여해 수신자에게 전달 | 봉투만 — 수신자, 크기, 시각. **내용은 암호화되어 못 봄** |
| **Mediator** (`dtcc-mediator`) | 참가자들의 확인 응답을 모아 최종 판정 | 해시만 |

**Synchronizer 는 검증하지 않는다.** 검증은 participant 가 한다. Synchronizer 는
순서와 전달만 맡는다. 그래서 DTCC 는 Citi 와 Morgan Stanley 사이의 거래 내용을
볼 수 없다.

### Synchronizer 는 여러 개다

네트워크에 synchronizer 가 **여러 개** 존재하고, participant 는 필요한 곳들에 동시에
연결한다. 전 세계 상태를 합의하는 단일 체인이 없다.

공개 Canton Network 에는 **Global Synchronizer** 라는 고유명사가 하나 있다
(Super Validator 컨소시엄이 BFT 로 공동 운영). 그와 별개로 DTCC 같은 기관이 운영하는
사설 synchronizer 들이 용도별로 존재한다.

---

## 2막 — 신원: 누가 거래의 주체인가

노드가 있다고 거래가 되지 않는다. **주체**가 필요하다.

```
citi-participant 가 호스팅:          morganstanley-participant 가 호스팅:
  Citi    (은행 법인)                   MorganStanley  (은행 법인)
  Alice   (개인 고객)                   Bob            (개인 고객)
```

### Party

**원장 위의 주체.** 계약에 이름이 올라가는 것은 오직 party 다.

### Party ID

**아래 문자열 전체가 party ID 다.** Ledger API 도 이것을 하나의 값으로 다룬다.

```
Alice::1220ea16404d5e38b6f7e3eecaa7af4c83a3d17785919c1df9ae235c573746ce85a0
└──┬─┘  └──────────────────────────┬──────────────────────────────────────┘
identifier                    namespace fingerprint
(발급 시 준 힌트)              (이 신원을 발급·인가한 키의 지문)
```

`Citi` 와 `Alice` 는 둘 다 Citi 가 발급했으므로 뒷부분이 같다. `Bob` 은 Morgan Stanley
가 발급했으므로 다르다. 이름은 힌트일 뿐이고 **식별자는 전체 문자열**이다.

### Namespace 와 호스팅은 다른 것이다

party 에 관한 정보가 토폴로지에 두 갈래로 기록된다. 헷갈리기 쉬우므로 분리해서 볼 것.

| | 무엇을 기록하나 | Party ID 에 나타나나 | 바뀔 수 있나 |
| --- | --- | --- | --- |
| **Namespace** | 이 신원을 **발급·인가한 키** | ✅ `::` 뒷부분 | ❌ **영구 불변** |
| **PartyToParticipant** | 현재 **어느 노드가 호스팅**하는지 | ❌ | ✅ 이관·다중 호스팅 가능 |

Namespace 는 "누가 이 신원을 만들어 줬는가"이고, PartyToParticipant 는 "지금 누가
데이터를 들고 있는가"다. 앞의 것은 발급 이력, 뒤의 것은 현재 배치다.

그래서 **Alice 를 Morgan Stanley 노드로 이관해도 party ID 는 `Alice::1220<Citi 지문>`
그대로다.** 여권 발급국이 거주지를 옮겨도 바뀌지 않는 것과 같다.

### Namespace 키 소유자가 그 party 의 토폴로지를 통제한다

Namespace 키를 가진 쪽이 그 party 의 토폴로지 변경을 인가한다. 따라서 Alice 를 다른
노드로 이관하거나 다중 호스팅하려면 **Citi 의 서명이 필요하다.** 이관한 뒤에도 그렇다.

이것이 다음 절에서 hosted 와 external 을 가르는 기준이 된다.

### Hosted party 와 External party

실제 종속 여부는 **namespace 키를 누가 쥐느냐**로 갈린다.

| | Hosted party | External party |
| --- | --- | --- |
| 예 | `Alice`, `Bob` | `Charlie` |
| Namespace 키 | 발급한 participant 소유 (Citi, Morgan Stanley) | **본인 소유** |
| Party ID 의 `::` 뒷부분 | 발급 기관의 지문 | **본인 키의 지문** |
| 트랜잭션 서명 | Participant 가 대행 | **본인이 직접** |
| 토폴로지 변경 인가 | 발급 participant 의 키 | 본인의 키 |
| Participant 가 배신하면 | 속을 수 있음 | 서명 없이는 불가 |

Alice 는 Citi 가 발급했으므로 Citi 키로 인가된 hosted party 다. 기술적으로 Citi 는
Alice 동의 없이 Alice 명의 트랜잭션을 만들 수 있고, 이를 막는 것은 코드가 아니라
규제와 감사다.

Charlie 처럼 자기 키를 쥐면 그것이 불가능해진다. EVM 의 EOA 에 가장 가까운 형태다.

### User

**participant 안에서만 존재하는 API 호출 자격.** 원장에 없다.

```
alice-web            Alice 를 대리해 Ledger API 를 호출
citi-settlement      Citi 를 대리 (결제·백오피스)
citi-node-admin      노드 자체를 관리 — 어떤 party 도 대리하지 않음
```

권한 종류:

| 권한 | 의미 |
| --- | --- |
| `CanActAs` | 그 party 로 커맨드 제출 |
| `CanReadAs` | 그 party 시점으로 조회만 |
| `CanReadAsAnyParty` | 모든 party 조회 (감사용) |
| `ParticipantAdmin` | 노드 관리. party 생성, DAR 업로드·vetting |

`citi-settlement` 는 노드 설정을 못 건드리고, `citi-node-admin` 은 원장 거래를 못 한다.
서로 다른 층이다.

### 셋의 관계

```
citi-participant  ──1:N──▶  user      user 는 이 노드 안에만 존재
citi-participant  ◀─N:M──▶  party     한 노드가 여러 party, 한 party 를 여러 노드가
party             ◀─N:M──▶  user      한 party 를 여러 계정이, 한 계정이 여러 party 를
```

Robinhood 는 첫 번째를 극단적으로 쓴다 — participant 하나에 고객 party 수만 개.
한 party 를 여러 participant 에 두는 것은 다중 호스팅이고, HA 와 BFT 를 위한 구성이다.

### party 와 user 를 혼동하지 않는 법

> **계약에 이름이 남는 것이 party, 그 party 로 API 를 호출할 자격이 user.**

Daml 엔진은 **user 를 전혀 모른다.** user 는 "이 요청이 그 party 를 주장해도 되는가"만
판정하고 즉시 사라진다. 이후는 party 만 존재한다. 4막에서 이것이 에러 메시지로 드러난다.

---

## 3막 — 코드 합의: 무엇을 예금이라 부를 것인가

주체가 있어도 아직 거래할 수 없다. **양쪽이 같은 코드에 합의**해야 한다.

### Template

**계약의 설계도.** 어떤 필드를 갖고, 누가 서명해야 하고, 무엇을 할 수 있는지를 정의한다.

토큰화 예금 template 이라면 이렇다 (문법은 Step 03 에서 다룬다).

```
template Deposit
  필드      : 발행은행, 예금주, 금액
  signatory : 발행은행, 예금주        ← 양쪽 동의가 있어야 성립
  choice    : Transfer                ← 예금주가 행사할 수 있는 행위
```

Solidity 의 contract 와 대응되지만 결정적으로 다르다. **template 에 선언되지 않은
행위는 존재 자체가 불가능하다.** `onlyOwner` 로 막는 게 아니라 그 함수가 없다.

### Contract

**template 을 실체화한 원장 위의 항목.** "Alice 가 Citi 에 100 예금이 있다"는 사실
하나가 contract 하나다.

**Contract 는 절대 수정되지 않는다.** 값을 바꾸려면 기존 것을 소비(archive)하고 새
것을 만든다. 그래서 계약 ID 가 매번 바뀌고, 원장에 모든 변경 이력이 남는다. 주소가
고정되고 상태 변수만 변하는 모델과 반대다.

### Choice

**contract 에 대해 실행할 수 있는 행위.** 상태를 바꾸는 유일한 수단이다.

```
choice Transfer
  controller  예금주        ← 이 행위를 할 수 있는 party
  하는 일     기존 예금을 소비하고 새 예금주로 새 계약 생성
```

### Signatory / Observer / Controller

| | 뜻 | 오해하기 쉬운 점 |
| --- | --- | --- |
| **Signatory** | 이 계약이 성립하려면 **동의가 필요한** party | "마음대로 할 수 있는 주인"이 아니다 |
| **Observer** | 계약을 **볼 수 있지만** 권한은 없는 party | SEC 같은 감독기관, 공시 대상 |
| **Controller** | 특정 choice 를 **행사할 수 있는** party | signatory 가 아니어도 된다 |

**Signatory 는 권한의 원천이지 만능 권한이 아니다.** 할 수 있는 일은 template 에
선언된 choice 뿐이다. Citi 가 예금의 signatory 라도, 예금을 임의 계정으로 옮기는
choice 가 template 에 없으면 그 행위는 존재하지 않는다.

### DAR

**컴파일 결과물을 담은 배포 단위.** Java 의 `.jar` 에 해당하는 zip 파일이다.

```
tokenized-deposit-1.0.0.dar
  ├── tokenized-deposit-9f49956106...dalf   ← 컴파일된 바이트코드
  ├── daml-prim-590736e6...dalf              ← 의존 패키지들
  ├── daml-stdlib-....dalf
  └── Deposit.daml                            ← 원본 소스도 함께 (감사용)
```

### Package-id

**`.dalf` 내용의 SHA-256 해시.** 파일명 뒤 64자가 그것이다.

```
9f49956106444057a69883e614389847969359465ba998c746784578303032fc
```

코드가 1바이트만 바뀌어도 달라진다. 트랜잭션은 이 해시로 template 을 지목하므로
**누가 몰래 다른 로직으로 바꿔치기할 수 없다.**

### Vetting

**participant 가 "나는 이 package-id 를 쓰겠다"고 토폴로지에 공표하는 행위.**
파일을 갖고 있는 것과 다르다.

```
1. 업로드   파일이 노드에 저장됨
2. vetting  "이 package-id 를 승인한다"는 서명된 토폴로지 트랜잭션 발행
            → synchronizer 를 통해 다른 participant 들이 알게 됨
```

제출하는 participant 는 트랜잭션을 만들기 전에 "상대도 이 package 를 vetting 했는가"를
확인한다. 안 했으면 **제출 자체가 거부**된다. 상대가 검증할 수 없는 코드로 거래를
시도하는 것을 미리 막는다.

### 여기서 나오는 결론

**"혼자 배포하면 전 세계가 호출"이 원리적으로 불가능하다.** 이해관계자의 모든
participant 가 각자 DAR 을 업로드하고 vetting 해야 한다. 코드 배포는 수수료를 내는
트랜잭션이 아니라 **기관 간 합의를 동반한 운영 절차**다.

동시에 이것이 보호 장치다. Morgan Stanley 는 DAR 안의 소스를 감사하고, 마음에 안
들면 vetting 하지 않으면 된다. Citi 도 DTCC 도 강제할 수 없다.

---

## 4막 — 거래: 실제로 무슨 일이 일어나는가

### 발행 — 왜 한 번에 안 되는가

예금 계약의 signatory 는 Citi 와 Alice **둘 다**다. 그런데 트랜잭션은 한 participant
가 제출한다. Alice 는 Citi 고객이라 `citi-participant` 가 양쪽을 다 호스팅하므로 이
경우는 한 번에 된다.

Alice 가 Morgan Stanley 고객이었다면 불가능하다. 어느 participant 도 두 party 의
권한을 동시에 갖지 못한다. 그래서 Daml 에는 **propose/accept** 패턴이 있다.

```
1. Citi 가 자기 권한만으로 "발행 제안" 계약을 만든다
     signatory Citi, observer Alice
     → Citi 혼자 서명하므로 혼자 만들 수 있다
     → Alice 는 observer 이므로 이 제안을 볼 수 있다

2. Alice 가 그 제안의 Accept choice 를 행사한다
     → 권한이 합쳐진다: [제안의 signatory] + [choice 의 controller]
                        = Citi + Alice
     → 이 합쳐진 권한으로 예금 계약을 생성
```

**Choice 를 행사하면 그 계약 signatory 의 권한이 실린다** — Daml 권한 모델의 핵심
기계장치다. 두 시점에 나뉘어 있던 동의가 하나의 트랜잭션에서 결합된다.

### 이체 — 확인 프로토콜

Alice 가 Bob 에게 이체한다. 이제 두 participant 가 관여한다.

```
1. citi-participant (제출)
   트랜잭션을 계산 → 당사자별 view 로 쪼개 각각 암호화 → sequencer 에 전송

2. dtcc-sequencer
   순서를 부여해 수신자들에게 전달 (내용은 못 봄)

3. citi-participant, morganstanley-participant (검증)
   각자 자기 view 를 복호화 → vetting 된 package-id 의 코드로 Daml 재실행
   → 결과가 제출된 것과 같은가? 권한은 충족되는가? 이미 소비된 계약은 아닌가?
   → 확인 응답(ConfirmationResponse) 전송

4. dtcc-mediator
   응답을 모아 정족수 확인 → 최종 판정 발행 (해시만 봄)

5. 각 participant
   확정된 계약을 자기 ActiveContractStore 에 반영
```

**제출자가 계산한 결과를 아무도 신뢰하지 않는다.** 각자 독립적으로 재실행한다.
Citi 가 악의를 가져도 Morgan Stanley 의 노드가 거부한다.

### Active Contract Store (ACS)

**participant 가 보관하는, 아직 소비되지 않은 계약들의 집합.** "현재 상태"에 해당한다.

전역 사본이 아니다. `citi-participant` 의 ACS 와 `morganstanley-participant` 의 ACS 는
내용이 다르다. 각자 자기가 이해관계자인 계약만 갖는다.

### Transaction / Offset

트랜잭션은 여러 create 와 archive 를 담는 **원자적 단위**다. 전부 성공하거나 전부
실패한다. 이체가 "출금"과 "입금" 두 단계로 쪼개지지 않는 이유다.

**Offset** 은 원장의 위치를 가리키는 번호다. 조회할 때 "어느 시점 기준"인지 지정한다.

### 권한 위반은 어떻게 보이는가

Bob 이 Alice 명의로 계약을 만들려 하면 이런 에러가 난다.

```
DAML_AUTHORIZATION_ERROR
Interpretation error: node NodeId(0) (9f49956106...:Deposit:Deposit)
  requires authorizers Alice::1220...,
  but only Bob::1220... were given
```

세 가지를 확인할 것.

- **`alice-web` 이라는 user 이름이 없다.** user 는 이미 사라졌고 party 만 남았다
- **`requires authorizers`** — 권한은 필드에 이름을 쓴 것이 아니라 `signatory` 선언에서 나온다
- **앞의 64자 해시** — 어떤 코드로 검증했는지가 에러에 기록된다

---

## 5막 — 프라이버시: 누가 무엇을 보는가

Alice → Bob 이체를 누가 아는가.

| | 보는가 | 왜 |
| --- | --- | --- |
| `Alice`, `Bob` | ✅ | 당사자 (signatory) |
| `Citi` | ✅ | 예금 계약의 signatory (발행자) |
| `MorganStanley` | 설계에 따라 | 예금 계약의 stakeholder 로 넣었다면 |
| `SEC` | observer 로 넣었다면 ✅ | **설계에 명시해야 보인다** |
| Goldman Sachs, Robinhood 고객들 | ❌ | **데이터가 도달조차 하지 않음** |
| `dtcc-sequencer`, `dtcc-mediator` | ❌ | 암호화된 봉투와 해시만 |

### Stakeholder / Informee / Sub-transaction view

- **Stakeholder** — 그 계약의 signatory + observer
- **Informee** — 그 트랜잭션의 일부를 통지받는 party
- **Sub-transaction view** — 트랜잭션을 informee 별로 쪼갠 조각

트랜잭션 전체가 모두에게 가지 않는다. **각자 알아야 할 조각만** 암호화되어 전달된다.
공개 체인처럼 "전부 공개된 뒤 일부를 가리는" 것이 아니라 처음부터 도달하지 않는다.

---

## 6막 — 없는 것

EVM 을 알고 오면 찾게 되지만 Canton 에 없는 것들.

| 없는 것 | 대신 |
| --- | --- |
| 전역 상태 / 단일 체인 | participant 별 부분 뷰, synchronizer 여러 개 |
| 컨트랙트 주소 | Contract ID (매 변경마다 바뀜) |
| `to` 로 호출 | 계약의 choice 를 행사 |
| gas | Synchronizer 트래픽 요금 (계산량이 아니라 대역폭) |
| 채굴자 / mempool | Sequencer 가 순서 부여 (내용은 못 봄 → 내용 기반 MEV 어려움) |
| 네이티브 토큰 | 모든 자산이 발행자 서명 계약 |
| 무허가 배포 | 이해관계자 전원의 vetting |
| admin key / `onlyOwner` | Signatory + template 에 선언된 choice 만 존재 |
| 확률적 파이널리티 | 확인 프로토콜 종료 시 즉시 확정, reorg 없음 |

---

## 용어표

### 인프라

| 용어 | 한 줄 정의 |
| --- | --- |
| **Participant node** | 원장 데이터를 보관하고 트랜잭션을 재실행 검증하는 서버. 기관이 운영 |
| **Synchronizer** | 순서 부여와 판정을 담당하는 인프라. Sequencer + Mediator |
| **Sequencer** | 메시지에 전순서를 부여해 전달. 내용은 암호화되어 못 봄 |
| **Mediator** | 확인 응답을 모아 최종 판정. 해시만 봄 |
| **Global Synchronizer** | 공개 Canton Network 의 공용 synchronizer. Super Validator 가 공동 운영 |

### 신원

| 용어 | 한 줄 정의 |
| --- | --- |
| **Party** | 원장 위의 주체. 계약에 이름이 올라가는 것 |
| **Party ID** | `<identifier>::<namespace fingerprint>` 문자열 **전체** |
| **Namespace** | Party ID 의 `::` 뒷부분. 그 신원을 **발급·인가한** 키의 지문. 영구 불변 |
| **PartyToParticipant** | 그 party 를 현재 **어느 노드가 호스팅**하는지의 매핑. 변경 가능 |
| **Hosted party** | Namespace 키를 발급 participant 가 쥔 party. Alice, Bob 이 이 형태 |
| **External party** | Namespace 키를 party 자신이 쥔 party. Charlie 가 이 형태 |
| **User** | Participant 내부의 API 호출 자격. 원장에 없고 Daml 엔진이 모름 |
| **CanActAs / CanReadAs** | User 가 특정 party 로 제출 / 조회할 수 있는 권한 |
| **ParticipantAdmin** | 노드 관리 권한. Party 생성, DAR 업로드. Party 를 대리하지 않음 |

### 원장

| 용어 | 한 줄 정의 |
| --- | --- |
| **Template** | 계약의 설계도. 필드, signatory, choice 를 정의 |
| **Contract** | Template 의 인스턴스. **수정 불가**, 변경은 archive + create |
| **Choice** | Contract 에 대해 실행 가능한 행위. 상태 변경의 유일한 수단 |
| **Signatory** | 계약 성립에 동의가 필요한 party. 만능 권한이 아님 |
| **Observer** | 계약을 볼 수 있으나 권한은 없는 party |
| **Controller** | 특정 choice 를 행사할 수 있는 party. Signatory 가 아니어도 됨 |
| **Propose/Accept** | 여러 party 의 동의를 두 트랜잭션에 나눠 결합하는 패턴 |
| **ACS** | Active Contract Store. 소비되지 않은 계약들. Participant 마다 내용이 다름 |
| **Transaction** | 여러 create/archive 의 원자적 단위 |
| **Offset** | 원장의 위치를 가리키는 번호 |

### 코드 배포

| 용어 | 한 줄 정의 |
| --- | --- |
| **Daml** | 계약을 기술하는 언어 |
| **DAR** | 컴파일 결과물 zip. `.dalf` 여러 개 + 원본 소스 |
| **DALF** | 컴파일된 package 하나 |
| **Package-id** | `.dalf` 내용의 SHA-256 해시. Template 을 지목하는 식별자 |
| **Vetting** | Participant 가 "이 package-id 를 쓰겠다"고 토폴로지에 공표 |

### 프로토콜

| 용어 | 한 줄 정의 |
| --- | --- |
| **확인 프로토콜** | 제출 → 순서 부여 → 각자 재실행 검증 → 판정 → 반영 |
| **Confirmation response** | 검증 participant 가 보내는 승인/거부 응답 |
| **Stakeholder** | 계약의 signatory + observer |
| **Informee** | 트랜잭션의 일부를 통지받는 party |
| **Sub-transaction view** | Informee 별로 쪼갠 트랜잭션 조각 |
| **Reassignment** | 계약을 다른 synchronizer 로 이동 |
| **Topology** | 누가 존재하고 어떤 키·party·package 를 갖는지의 상태 |

---

## 자가 점검

답할 수 있으면 다음 Step 으로 간다.

1. `morganstanley-participant` 는 Citi 내부 거래를 볼 수 있는가? 왜?
2. `Alice` 와 `alice-web` 중 계약에 기록되는 것은?
3. DTCC 가 Alice → Bob 이체 내용을 볼 수 있는가?
4. 예금 template 에 `Transfer` choice 가 없으면 Citi 가 Alice 의 예금을 옮길 수 있는가?
5. Morgan Stanley 가 어떤 package 를 vetting 하지 않으면 무슨 일이 일어나는가?
6. 예금 금액을 100 에서 200 으로 "수정"하면 계약 ID 는 어떻게 되는가?
7. `signatory` 가 Citi 와 Alice 둘인 계약을 Citi 혼자 만들 수 있는가?
8. `Alice` 와 `Charlie` 의 차이는 무엇인가?
9. Alice 를 Morgan Stanley 노드로 이관하면 party ID 는 어떻게 되는가?

> 답: 1. 못 본다, 데이터가 도달하지 않음 · 2. `Alice` · 3. 못 본다, 암호화됨 ·
> 4. 못 옮긴다, 그 행위가 존재하지 않음 · 5. 그 코드로는 거래 자체가 성립하지 않음 ·
> 6. 기존 계약이 소비되고 새 ID 가 생김 · 7. 못 만든다, propose/accept 가 필요 ·
> 8. Namespace 키를 발급 participant 가 쥐는가 본인이 쥐는가 ·
> 9. 그대로다. Namespace 는 발급 이력이고 호스팅은 별개의 매핑이다

---

다음: **Step 02 — 환경 세팅.** 여기서 정의한 것들을 실제로 만들어 본다. Participant
를 띄우고, party 와 user 를 만들고, 계약을 생성해 프라이버시와 권한 검사를 확인한다.
