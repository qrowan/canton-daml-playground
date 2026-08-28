# Step 01 — 용어

Canton 의 용어를 하나의 시나리오를 끝까지 따라가며 익힙니다. 코드는 없습니다.

읽고 나면 이 문장이 해석되어야 합니다.

> 애플리케이션이 **User** 자격으로 **Party** 를 대리해 **Transaction** 을 제출하면,
> 그 Party 를 호스팅하는 **Participant** 가 이를 **Sequencer** 에 보내고, 상대 Party
> 를 호스팅하는 다른 Participant 가 **vetting** 된 **Package ID** 의 코드로 재실행해
> **Confirmation Response** 를 보내며, **Mediator** 가 판정을 내립니다.

각 단어가 무엇을 가리키는지, 그리고 왜 이 순서인지 설명할 수 있으면 됩니다.

---

## 등장 인물

| 이름 | 정체 | Canton 에서의 위치 |
| --- | --- | --- |
| **DTCC** | 예탁결제기관 | Synchronizer 운영 |
| **Citi** | 상업은행. 토큰화 예금 발행 | Participant 운영 + Party |
| **Morgan Stanley** | 투자은행. Bob 의 증권사 | Participant 운영 + Party |
| **Alice** | Citi 의 개인 고객 | Party (Citi 가 발급) |
| **David** | Citi 의 또 다른 개인 고객 | Party (Citi 가 발급) |
| **Bob** | Morgan Stanley 의 개인 고객 | Party (Morgan Stanley 가 발급) |

이후 Step 에서 등장합니다.

| 이름 | 정체 | 어디서 |
| --- | --- | --- |
| **Robinhood** | 소매 브로커. 고객 Party 다수 위탁 호스팅 | 다중 호스팅, 커스터디 |
| **Charlie** | 자기 키를 직접 보유하는 개인 | External Party |
| **SEC** | 감독기관 | Observer, 공시 |
| **Goldman Sachs** | 증권 발행·거래 상대방 | DvP 교환 |

Alice, David, Bob 은 **각자의 은행이 발급한 Party** 입니다. 자기 키를 갖고 있지
않습니다. 자기 키를 쥔 개인은 Charlie 이고, 그 차이는 2절에서 다룹니다.

---

## 시나리오

Citi 가 Alice 에게 토큰화 예금 100 을 발행합니다. Alice 가 그것을 Bob 에게 이체합니다.

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

    Alice 는 Citi 고객, Bob 은 Morgan Stanley 고객 → 서로 다른 Participant
```

---

## 1. 서버 운영자

거래가 시작되기 전에 노드들이 존재합니다.

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

**원장 데이터를 보관하고 Transaction 을 검증하는 서버**입니다. 은행·증권사 같은
기관이 각자 운영합니다.

세 가지를 합니다.

1. 자기 몫의 Contract 를 저장합니다
2. 들어온 Transaction 을 **직접 다시 실행해서** 맞는지 확인합니다
3. 애플리케이션에 Ledger API 를 제공합니다

**"자기 몫"** 이 핵심입니다. Participant 는 전체 원장의 사본을 갖지 않습니다. 자기가
관여한 Contract 만 갖습니다. `morganstanley-participant` 에는 Citi 내부 거래가
존재하지 않습니다.

> **❓ Participant 는 Contract 를 저장하나요, state 를 저장하나요?**
>
> **같은 것입니다.** Daml 에는 Contract 와 별개의 state 가 없습니다.
>
> EVM 은 코드와 스토리지가 따로 있고 함수가 스토리지 변수를 고칩니다. Daml 은
> "Alice 가 Citi 에 100 예금이 있다"는 사실 자체가 Contract 하나이고, **활성
> Contract 들의 집합이 곧 현재 상태**입니다. 그래서 이 저장소 이름이
> **ACS(Active Contract Store)** 입니다.
>
> Participant 는 이 외에 Topology 상태, Package(DAR), Transaction 이력도 보관하지만,
> 업무 데이터에 해당하는 것은 ACS 입니다.

### Synchronizer

**여러 Participant 사이에서 메시지 순서를 정하고 판정을 내리는 인프라**입니다.
프로세스 하나가 아니라 노드 두 종류의 묶음입니다.

| 노드 | 하는 일 | 볼 수 있는 것 |
| --- | --- | --- |
| **Sequencer** (`dtcc-sequencer`) | 모든 메시지에 전순서를 부여해 수신자에게 전달 | Envelope 만 — 수신자, 크기, 시각 |
| **Mediator** (`dtcc-mediator`) | 참가자들의 확인 응답을 모아 최종 판정 | 해시만 |

**Envelope** 은 Canton 의 용어로, 암호화된 내용물을 감싼 봉투에 해당합니다. 수신자와
크기 같은 배송 정보는 겉면에 있고 내용물은 열 수 없습니다.

> **❓ Synchronizer 가 Transaction 을 검증하나요?**
>
> 아닙니다. **검증은 Participant 가 합니다.** Synchronizer 는 순서와 전달만 맡습니다.
>
> 이것이 Canton 을 다른 원장과 가르는 첫 번째 지점입니다. Synchronizer 가 검증하려면
> 내용을 봐야 하고, 그러면 프라이버시가 성립하지 않습니다. 그래서 DTCC 는 Citi 와
> Morgan Stanley 사이의 거래 내용을 볼 수 없습니다.

### Synchronizer 는 여러 개입니다

네트워크에 Synchronizer 가 **여러 개** 존재하고, Participant 는 필요한 곳들에 동시에
연결합니다. 전 세계 상태를 합의하는 단일 체인이 없습니다.

공개 Canton Network 에는 **Global Synchronizer** 라는 고유명사가 하나 있습니다
(Super Validator 컨소시엄이 BFT 로 공동 운영). 그와 별개로 DTCC 같은 기관이 운영하는
사설 Synchronizer 들이 용도별로 존재합니다.

---

## 2. 거래의 주체

노드가 있다고 거래가 되지 않습니다. **주체**가 필요합니다.

```
citi-participant 가 호스팅:          morganstanley-participant 가 호스팅:
  Citi    (은행 법인)                   MorganStanley  (은행 법인)
  Alice   (개인 고객)                   Bob            (개인 고객)
  David   (개인 고객)
```

### Party

**원장 위의 주체**입니다. Contract 에 이름이 올라가는 것은 오직 Party 입니다.

#### Party ID

**아래 문자열 전체가 Party ID 입니다.** Ledger API 도 이것을 하나의 값으로 다룹니다.

```
Alice::1220ea16404d5e38b6f7e3eecaa7af4c83a3d17785919c1df9ae235c573746ce85a0
└──┬─┘  └──────────────────────────┬──────────────────────────────────────┘
identifier                    namespace fingerprint
(발급 시 준 힌트)              (이 신원을 발급·인가한 키의 지문)
```

`Citi`, `Alice`, `David` 는 모두 Citi 가 발급했으므로 뒷부분이 같습니다. `Bob` 은
Morgan Stanley 가 발급했으므로 다릅니다. 이름은 힌트일 뿐이고 **식별자는 전체
문자열**입니다.

#### Namespace 와 호스팅

Party 에 관한 정보가 Topology 에 두 갈래로 기록됩니다.

| | 무엇을 기록하나 | Party ID 에 나타나나 | 바뀔 수 있나 |
| --- | --- | --- | --- |
| **Namespace** | 이 신원을 **발급·인가한 키** | ✅ `::` 뒷부분 | ❌ 영구 불변 |
| **PartyToParticipant** | 현재 **어느 노드가 호스팅**하는지 | ❌ | ✅ 이관·다중 호스팅 가능 |

Namespace 는 "누가 이 신원을 만들어 줬는가"이고, PartyToParticipant 는 "지금 누가
데이터를 들고 있는가"입니다. 앞의 것은 발급 이력, 뒤의 것은 현재 배치입니다.

> **❓ 다른 Participant 로 이관되어 호스팅되는 Party 는 Namespace 도 바뀌나요?**
>
> 바뀌지 않습니다. Party ID 는 그대로 `Alice::1220<Citi 지문>` 입니다.
>
> Namespace 는 발급 이력이고 호스팅은 별개의 매핑이기 때문입니다. 여권 발급국이
> 거주지를 옮겨도 바뀌지 않는 것과 같습니다.
>
> 다만 **Namespace 키를 가진 쪽이 그 Party 의 Topology 변경을 인가**합니다. Alice 를
> 다른 노드로 이관하거나 다중 호스팅하려면 Citi 의 서명이 필요하고, 이관한 뒤에도
> 그렇습니다.

#### Hosted Party 와 External Party

실제 종속 여부는 **Namespace 키를 누가 쥐느냐**로 갈립니다.

| | Hosted Party | External Party |
| --- | --- | --- |
| 예 | `Alice`, `David`, `Bob` | `Charlie` |
| Namespace 키 | 발급한 Participant 소유 | **본인 소유** |
| Party ID 의 `::` 뒷부분 | 발급 기관의 지문 | **본인 키의 지문** |
| Transaction 서명 | Participant 가 대행 | **본인이 직접** |
| Topology 변경 인가 | 발급 Participant 의 키 | 본인의 키 |
| Participant 가 배신하면 | 속을 수 있음 | 서명 없이는 불가 |

Alice 는 Citi 가 발급했으므로 Citi 키로 인가된 Hosted Party 입니다. 기술적으로 Citi 는
Alice 동의 없이 Alice 명의 Transaction 을 만들 수 있고, 이를 막는 것은 코드가 아니라
규제와 감사입니다.

Charlie 처럼 자기 키를 쥐면 그것이 불가능해집니다. EVM 의 EOA 에 가장 가까운
형태입니다.

### User

**Participant 안에서만 존재하는 API 호출 자격**입니다. 원장에 없습니다.

```
alice-web            Alice 를 대리해 Ledger API 를 호출
citi-settlement      Citi 를 대리 (결제·백오피스)
citi-node-admin      노드 자체를 관리 — 어떤 Party 도 대리하지 않음
```

권한 종류입니다.

| 권한 | 의미 |
| --- | --- |
| `CanActAs` | 그 Party 로 커맨드 제출 |
| `CanReadAs` | 그 Party 시점으로 조회만 |
| `CanReadAsAnyParty` | 모든 Party 조회 (감사용) |
| `ParticipantAdmin` | 노드 관리. Party 생성, DAR 업로드·vetting |

`citi-settlement` 는 노드 설정을 못 건드리고, `citi-node-admin` 은 원장 거래를 못
합니다. 서로 다른 층입니다.

> **❓ Party 와 User 중 Contract 에 기록되는 것은 무엇인가요?**
>
> **Party 입니다.** Daml 엔진은 User 를 전혀 모릅니다.
>
> User 는 "이 요청이 그 Party 를 주장해도 되는가"만 판정하고 즉시 사라집니다. 이후는
> Party 만 존재합니다. 4절의 권한 오류 메시지에 User 이름이 한 번도 나오지 않는 것이
> 그 증거입니다.
>
> 한 줄로: **Contract 에 이름이 남는 것이 Party, 그 Party 로 API 를 호출할 자격이
> User** 입니다.

### 셋의 관계

```
citi-participant  ──1:N──▶  User      User 는 이 노드 안에만 존재
citi-participant  ◀─N:M──▶  Party     한 노드가 여러 Party, 한 Party 를 여러 노드가
Party             ◀─N:M──▶  User      한 Party 를 여러 계정이, 한 계정이 여러 Party 를
```

Robinhood 는 첫 번째를 극단적으로 씁니다 — Participant 하나에 고객 Party 수만 개.
한 Party 를 여러 Participant 에 두는 것은 다중 호스팅이고, HA 와 BFT 를 위한
구성입니다.

---

## 3. 계약(Contract)과 템플릿(Template)

주체가 있어도 아직 거래할 수 없습니다. **양쪽이 같은 코드에 합의**해야 합니다.

### Template

**Contract 의 설계도**입니다. 어떤 필드를 갖고, 누가 서명해야 하고, 무엇을 할 수
있는지를 정의합니다.

토큰화 예금 Template 이라면 이렇습니다 (문법은 Step 03 에서 다룹니다).

```
template Deposit
  필드      : 발행은행, 예금주, 금액
  signatory : 발행은행, 예금주        ← 양쪽 동의가 있어야 성립
  choice    : Transfer                ← 예금주가 행사할 수 있는 행위
```

Solidity 의 contract 와 대응되지만 결정적으로 다릅니다. **Template 에 선언되지 않은
행위는 존재 자체가 불가능합니다.** `onlyOwner` 로 막는 게 아니라 그 함수가 없습니다.

### Contract

**Template 을 실체화한 원장 위의 항목**입니다. "Alice 가 Citi 에 100 예금이 있다"는
사실 하나가 Contract 하나입니다.

**Contract 는 절대 수정되지 않습니다.** 값을 바꾸려면 기존 것을 소비(archive)하고 새
것을 만듭니다. 그래서 Contract ID 가 매번 바뀌고, 원장에 모든 변경 이력이 남습니다.
주소가 고정되고 상태 변수만 변하는 모델과 반대입니다.

> **❓ Template 과 Contract 는 어떻게 다른가요?**
>
> 표준계약서 **양식**과, 실제로 서명되어 효력이 있는 계약서 **한 장**의 차이입니다.
>
> `Deposit` 은 양식이고 "Citi 와 Alice 가 100 에 서명한 그것"이 Contract 입니다.
> 같은 Template 에서 Contract 가 수천 개 나옵니다.

### Choice

**Contract 에 대해 실행할 수 있는 행위**입니다. 상태를 바꾸는 유일한 수단입니다.

```
choice Transfer
  controller  예금주        ← 이 행위를 할 수 있는 Party
  하는 일     기존 예금을 소비하고 새 예금주로 새 Contract 생성
```

### Signatory / Observer / Controller

| | 뜻 | 오해하기 쉬운 점 |
| --- | --- | --- |
| **Signatory** | 이 Contract 가 성립하려면 **동의가 필요한** Party | "마음대로 할 수 있는 주인"이 아닙니다 |
| **Observer** | Contract 를 **볼 수 있지만** 권한은 없는 Party | SEC 같은 감독기관, 공시 대상 |
| **Controller** | 특정 Choice 를 **행사할 수 있는** Party | Signatory 가 아니어도 됩니다 |

> **❓ Signatory 면 그 Contract 를 마음대로 할 수 있나요?**
>
> 아닙니다. Signatory 는 **"내 동의가 필요하다"** 이지 **"내가 무엇이든 할 수 있다"**
> 가 아닙니다.
>
> 할 수 있는 일은 Template 에 선언된 Choice 뿐입니다. Citi 가 예금의 Signatory 라도,
> 예금을 임의 계정으로 옮기는 Choice 가 Template 에 없으면 그 행위는 존재하지
> 않습니다. Solidity 의 `onlyOwner withdraw()` 와 결정적으로 다른 지점입니다.

> **❓ Observer 면 Choice 를 행사할 수 있나요?**
>
> 아닙니다. Observer 는 **가시성만** 줍니다.
>
> 행사 권한은 그 Choice 의 Controller 가 줍니다. 반대로 Controller 는 Observer 가
> 아니어도 되지만, 볼 수 없으면 실무적으로 행사하기 어렵습니다. Step 04 에서 이 둘을
> 나눠 쓰는 형태가 나옵니다.

### DAR

**컴파일 결과물을 담은 배포 단위**입니다. Java 의 `.jar` 에 해당하는 zip 파일입니다.

```
tokenized-deposit-1.0.0.dar
  ├── tokenized-deposit-9f49956106...dalf   ← 컴파일된 바이트코드
  ├── daml-prim-590736e6...dalf              ← 의존 Package 들
  ├── daml-stdlib-....dalf
  └── Deposit.daml                            ← 원본 소스도 함께 (감사용)
```

### Package ID

**`.dalf` 내용의 SHA-256 해시**입니다. 파일명 뒤 64자가 그것입니다.

```
9f49956106444057a69883e614389847969359465ba998c746784578303032fc
```

코드가 1바이트만 바뀌어도 달라집니다. Transaction 은 이 해시로 Template 을 지목하므로
**누가 몰래 다른 로직으로 바꿔치기할 수 없습니다.**

### Vetting

**Participant 가 "나는 이 Package ID 를 쓰겠다"고 Topology 에 공표하는 행위**입니다.
파일을 갖고 있는 것과 다릅니다.

```
1. 업로드   파일이 노드에 저장됩니다
2. vetting  "이 Package ID 를 승인한다"는 서명된 Topology Transaction 을 발행합니다
            → Synchronizer 를 통해 다른 Participant 들이 알게 됩니다
```

제출하는 Participant 는 Transaction 을 만들기 전에 "상대도 이 Package 를 vetting
했는가"를 확인합니다. 안 했으면 **제출 자체가 거부**됩니다. 상대가 검증할 수 없는
코드로 거래를 시도하는 것을 미리 막습니다.

> **❓ DAR 을 한 곳에 올리면 다른 Participant 도 쓸 수 있나요?**
>
> 아닙니다. **이해관계자의 모든 Participant 가 각자 업로드하고 vetting 해야** 합니다.
>
> 그래서 "혼자 배포하면 전 세계가 호출"이 원리적으로 불가능합니다. 코드 배포는
> 수수료를 내는 Transaction 이 아니라 **기관 간 합의를 동반한 운영 절차**입니다.
>
> 동시에 이것이 보호 장치입니다. Morgan Stanley 는 DAR 안의 소스를 감사하고, 마음에
> 안 들면 vetting 하지 않으면 됩니다. Citi 도 DTCC 도 강제할 수 없습니다.

---

## 4. 거래(Transaction)

### 발행

예금 Contract 의 Signatory 는 Citi 와 Alice **둘 다**입니다. 그런데 Transaction 은 한
Participant 가 제출합니다. Alice 는 Citi 고객이라 `citi-participant` 가 양쪽을 다
호스팅하므로 이 경우는 한 번에 됩니다.

Alice 가 Morgan Stanley 고객이었다면 불가능합니다. 어느 Participant 도 두 Party 의
권한을 동시에 갖지 못합니다. 그래서 Daml 에는 **propose/accept** 패턴이 있습니다.

```
1. Citi 가 자기 권한만으로 "발행 제안" Contract 를 만듭니다
     signatory Citi, observer Alice
     → Citi 혼자 서명하므로 혼자 만들 수 있습니다
     → Alice 는 Observer 이므로 이 제안을 볼 수 있습니다

2. Alice 가 그 제안의 Accept Choice 를 행사합니다
     → 권한이 합쳐집니다: [제안의 Signatory] + [Choice 의 Controller]
                          = Citi + Alice
     → 이 합쳐진 권한으로 예금 Contract 를 생성합니다
```

**Choice 를 행사하면 그 Contract 의 Signatory 권한이 실립니다.** Daml 권한 모델의 핵심
기계장치이고, 두 시점에 나뉘어 있던 동의가 하나의 Transaction 에서 결합됩니다.

### 이체

Alice 가 Bob 에게 이체합니다. 이제 두 Participant 가 관여합니다.

```
1. citi-participant (제출)
   Transaction 을 계산 → 당사자별 view 로 쪼개 각각 암호화 → Sequencer 에 전송

2. dtcc-sequencer
   순서를 부여해 수신자들에게 전달 (Envelope 만 보므로 내용은 모름)

3. citi-participant, morganstanley-participant (검증)
   각자 자기 view 를 복호화 → vetting 된 Package ID 의 코드로 Daml 재실행
   → 결과가 제출된 것과 같은가? 권한은 충족되는가? 이미 소비된 Contract 는 아닌가?
   → 확인 응답(Confirmation Response) 전송

4. dtcc-mediator
   응답을 모아 정족수 확인 → 최종 판정 발행 (해시만 봄)

5. 각 Participant
   확정된 Contract 를 자기 ACS 에 반영
```

**제출자가 계산한 결과를 아무도 신뢰하지 않습니다.** 각자 독립적으로 재실행합니다.
Citi 가 악의를 가져도 Morgan Stanley 의 노드가 거부합니다.

### Active Contract Store (ACS)

**Participant 가 보관하는, 아직 소비되지 않은 Contract 들의 집합**입니다. 앞서 말한
대로 이것이 곧 "현재 상태"입니다.

전역 사본이 아닙니다. `citi-participant` 의 ACS 와 `morganstanley-participant` 의 ACS
는 내용이 다릅니다. 각자 자기가 이해관계자인 Contract 만 갖습니다.

### Transaction / Offset

Transaction 은 여러 create 와 archive 를 담는 **원자적 단위**입니다. 전부 성공하거나
전부 실패합니다. 이체가 "출금"과 "입금" 두 단계로 쪼개지지 않는 이유입니다.

**Offset** 은 원장의 위치를 가리키는 번호입니다. 조회할 때 "어느 시점 기준"인지
지정합니다.

### 권한 위반은 어떻게 보이는가

Bob 이 Alice 명의로 Contract 를 만들려 하면 이런 오류가 납니다.

```
DAML_AUTHORIZATION_ERROR
Interpretation error: node NodeId(0) (9f49956106...:Deposit:Deposit)
  requires authorizers Alice::1220...,
  but only Bob::1220... were given
```

세 가지를 확인할 것입니다.

- **User 이름이 없습니다.** User 는 이미 사라졌고 Party 만 남았습니다
- **`requires authorizers`** — 권한은 필드에 이름을 쓴 것이 아니라 `signatory` 선언에서 나옵니다
- **앞의 64자 해시** — 어떤 코드로 검증했는지가 오류에 기록됩니다

---

## 5. Privacy

Alice → Bob 이체를 누가 아는지 봅니다.

| | 보는가 | 왜 |
| --- | --- | --- |
| `Alice`, `Bob` | ✅ | 당사자 (Signatory) |
| `Citi` | ✅ | 예금 Contract 의 Signatory (발행자) |
| `MorganStanley` | 설계에 따라 | Stakeholder 로 넣었다면 |
| `SEC` | Observer 로 넣었다면 ✅ | **설계에 명시해야 보입니다** |
| `David`, Goldman Sachs | ❌ | **데이터가 도달조차 하지 않습니다** |
| `dtcc-sequencer`, `dtcc-mediator` | ❌ | Envelope 과 해시만 |

David 가 Alice 와 **같은 은행 고객이고 같은 Participant 에 있는데도** 보지 못한다는
점에 주목할 것입니다. 프라이버시의 단위는 기관도 노드도 아니라 **Party** 입니다.

### Stakeholder / Informee / Sub-transaction view

- **Stakeholder** — 그 Contract 의 Signatory + Observer
- **Informee** — 그 Transaction 의 일부를 통지받는 Party
- **Sub-transaction view** — Transaction 을 Informee 별로 쪼갠 조각

Transaction 전체가 모두에게 가지 않습니다. **각자 알아야 할 조각만** 암호화되어
전달됩니다. 공개 체인처럼 "전부 공개된 뒤 일부를 가리는" 것이 아니라 처음부터
도달하지 않습니다.

---

## 6. Canton 에 없는 것

EVM 을 알고 오면 찾게 되지만 없는 것들입니다.

| 없는 것 | 대신 |
| --- | --- |
| 전역 상태 / 단일 체인 | Participant 별 부분 뷰, Synchronizer 여러 개 |
| 컨트랙트 주소 | Contract ID (매 변경마다 바뀜) |
| `to` 로 호출 | Contract 의 Choice 를 행사 |
| gas | Synchronizer 트래픽 요금 (계산량이 아니라 대역폭) |
| 채굴자 / mempool | Sequencer 가 순서 부여 (내용은 못 봄 → 내용 기반 MEV 어려움) |
| 네이티브 토큰 | 모든 자산이 발행자 서명 Contract |
| 무허가 배포 | 이해관계자 전원의 vetting |
| admin key / `onlyOwner` | Signatory + Template 에 선언된 Choice 만 존재 |
| 확률적 파이널리티 | 확인 프로토콜 종료 시 즉시 확정, reorg 없음 |

---

## 용어표

### 인프라

| 용어 | 한 줄 정의 |
| --- | --- |
| **Participant node** | 원장 데이터를 보관하고 Transaction 을 재실행 검증하는 서버. 기관이 운영 |
| **Synchronizer** | 순서 부여와 판정을 담당하는 인프라. Sequencer + Mediator |
| **Sequencer** | 메시지에 전순서를 부여해 전달. Envelope 만 보므로 내용은 모름 |
| **Mediator** | 확인 응답을 모아 최종 판정. 해시만 봄 |
| **Envelope** | 암호화된 내용물을 감싼 배송 단위. 겉면에 수신자·크기·시각 |
| **Global Synchronizer** | 공개 Canton Network 의 공용 Synchronizer. Super Validator 가 공동 운영 |

### 신원

| 용어 | 한 줄 정의 |
| --- | --- |
| **Party** | 원장 위의 주체. Contract 에 이름이 올라가는 것 |
| **Party ID** | `<identifier>::<namespace fingerprint>` 문자열 **전체** |
| **Namespace** | Party ID 의 `::` 뒷부분. 그 신원을 **발급·인가한** 키의 지문. 영구 불변 |
| **PartyToParticipant** | 그 Party 를 현재 **어느 노드가 호스팅**하는지의 매핑. 변경 가능 |
| **Hosted Party** | Namespace 키를 발급 Participant 가 쥔 Party. Alice, David, Bob |
| **External Party** | Namespace 키를 Party 자신이 쥔 Party. Charlie |
| **User** | Participant 내부의 API 호출 자격. 원장에 없고 Daml 엔진이 모름 |
| **CanActAs / CanReadAs** | User 가 특정 Party 로 제출 / 조회할 수 있는 권한 |
| **ParticipantAdmin** | 노드 관리 권한. Party 생성, DAR 업로드. Party 를 대리하지 않음 |

### 원장

| 용어 | 한 줄 정의 |
| --- | --- |
| **Template** | Contract 의 설계도. 필드, Signatory, Choice 를 정의 |
| **Contract** | Template 의 인스턴스. **수정 불가**, 변경은 archive + create |
| **Choice** | Contract 에 대해 실행 가능한 행위. 상태 변경의 유일한 수단 |
| **Signatory** | Contract 성립에 동의가 필요한 Party. 만능 권한이 아님 |
| **Observer** | Contract 를 볼 수 있으나 권한은 없는 Party |
| **Controller** | 특정 Choice 를 행사할 수 있는 Party. Signatory 가 아니어도 됨 |
| **Propose/Accept** | 여러 Party 의 동의를 두 Transaction 에 나눠 결합하는 패턴 |
| **ACS** | Active Contract Store. 소비되지 않은 Contract 들 = 현재 상태 |
| **Transaction** | 여러 create/archive 의 원자적 단위 |
| **Offset** | 원장의 위치를 가리키는 번호 |

### 코드 배포

| 용어 | 한 줄 정의 |
| --- | --- |
| **Daml** | Contract 를 기술하는 언어 |
| **DAR** | 컴파일 결과물 zip. `.dalf` 여러 개 + 원본 소스 |
| **DALF** | 컴파일된 Package 하나 |
| **Package ID** | `.dalf` 내용의 SHA-256 해시. Template 을 지목하는 식별자 |
| **Vetting** | Participant 가 "이 Package ID 를 쓰겠다"고 Topology 에 공표 |

### 프로토콜

| 용어 | 한 줄 정의 |
| --- | --- |
| **확인 프로토콜** | 제출 → 순서 부여 → 각자 재실행 검증 → 판정 → 반영 |
| **Confirmation Response** | 검증 Participant 가 보내는 승인/거부 응답 |
| **Stakeholder** | Contract 의 Signatory + Observer |
| **Informee** | Transaction 의 일부를 통지받는 Party |
| **Sub-transaction view** | Informee 별로 쪼갠 Transaction 조각 |
| **Reassignment** | Contract 를 다른 Synchronizer 로 이동 |
| **Topology** | 누가 존재하고 어떤 키·Party·Package 를 갖는지의 상태 |

---

## 자가 점검

답할 수 있으면 다음 Step 으로 갑니다.

1. `morganstanley-participant` 는 Citi 내부 거래를 볼 수 있습니까? 왜 그렇습니까?
2. `Alice` 와 `alice-web` 중 Contract 에 기록되는 것은 무엇입니까?
3. DTCC 가 Alice → Bob 이체 내용을 볼 수 있습니까?
4. 예금 Template 에 `Transfer` Choice 가 없으면 Citi 가 Alice 의 예금을 옮길 수 있습니까?
5. Morgan Stanley 가 어떤 Package 를 vetting 하지 않으면 무슨 일이 일어납니까?
6. 예금 금액을 100 에서 200 으로 "수정"하면 Contract ID 는 어떻게 됩니까?
7. Signatory 가 Citi 와 Alice 둘인 Contract 를 Citi 혼자 만들 수 있습니까?
8. `Alice` 와 `Charlie` 의 차이는 무엇입니까?
9. Alice 를 Morgan Stanley 노드로 이관하면 Party ID 는 어떻게 됩니까?
10. Participant 가 저장하는 "state" 는 무엇입니까?

> 답: 1. 못 봅니다, 데이터가 도달하지 않습니다 · 2. `Alice` · 3. 못 봅니다, Envelope
> 만 봅니다 · 4. 못 옮깁니다, 그 행위가 존재하지 않습니다 · 5. 그 코드로는 거래 자체가
> 성립하지 않습니다 · 6. 기존 Contract 가 소비되고 새 ID 가 생깁니다 · 7. 못 만듭니다,
> propose/accept 가 필요합니다 · 8. Namespace 키를 발급 Participant 가 쥐는가 본인이
> 쥐는가 · 9. 그대로입니다, Namespace 는 발급 이력이고 호스팅은 별개의 매핑입니다 ·
> 10. 활성 Contract 들의 집합(ACS)입니다. Contract 와 별개의 state 는 없습니다

---

다음: **[Step 02 — 환경 세팅](Step02Environment.md).** 여기서 정의한 것들을 실제로
만들어 봅니다. Participant 를 띄우고, Party 와 User 를 만들고, Contract 를 생성해
프라이버시와 권한 검사를 확인합니다.
