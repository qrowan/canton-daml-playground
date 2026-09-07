# Step 09 — 업그레이드

[Step 03](Step03FirstContract.md) 에서 Contract 는 수정되지 않는다고 했습니다. archive
하고 새로 만들 뿐입니다. 그런데 그것은 **같은 Template 안에서**의 이야기였습니다.

Template 자체를 고쳐야 하면 사정이 다릅니다. 원장에는 옛 코드로 만들어진 Contract 가
살아 있고, 거래 상대는 아직 옛 코드를 돌리고 있습니다. 전부 멈추고 다시 시작할 수는
없습니다.

## 실행

저장소 루트에서:

```sh
./steps/step09.sh
```

| 옵션 | 용도 |
| --- | --- |
| (없음) | 단계마다 엔터를 기다립니다 |
| `--auto` | 엔터 없이 전부 실행합니다 |
| `--keep` | 끝나고 노드를 끄지 않습니다 |

## 다루는 파일

| 파일 | 내용 |
| --- | --- |
| `upgrade/v1/daml.yaml` | `step09-voucher` 1.0.0 |
| `upgrade/v1/daml/Voucher.daml` | 지금 배포되어 있는 코드 |
| `upgrade/v2/daml.yaml` | `step09-voucher` 2.0.0 + `upgrades:` |
| `upgrade/v2/daml/Voucher.daml` | 유효기간을 붙인 코드 |

노드 구성은 [Step 05](Step05MultiParticipant.md) 의 `canton/step05.conf` 를 그대로
씁니다. 이 Step 에서 달라지는 것은 패키지뿐입니다.

## 왜 패키지가 둘인가

**Package ID 는 내용의 SHA-256 해시입니다.** 한 글자만 고쳐도 완전히 다른 패키지가
되고, 원장에 있는 Contract 는 옛 Package ID 를 가리킨 채 남습니다.

그래서 업그레이드는 "코드를 덮어쓰는 일"이 아니라 **"두 버전을 공존시키는 일"**입니다.
같은 패키지 안에서는 일어날 수 없고, 별도의 패키지가 필요합니다.

```
upgrade/v1/daml.yaml          upgrade/v2/daml.yaml
  name: step09-voucher          name: step09-voucher      ← 같아야 합니다
  version: 1.0.0                version: 2.0.0            ← 높아야 합니다
                                upgrades: ../v1/...dar    ← 무엇의 후속인지
```

`name` 이 같고 `version` 이 높은 것이 **후속 버전의 정의**입니다. 이름이 다르면 그냥
남남입니다.

`upgrades:` 는 컴파일러에게 비교 대상을 알려 줍니다. 이 줄이 있어야 규칙 검사가
돕니다. 비워 두면 검사 없이 그냥 빌드되고, 문제는 원장에서 터집니다.

빌드는 패키지 디렉터리 안에서 합니다.

```sh
cd upgrade/v1 && dpm build
cd upgrade/v2 && dpm build
```

## 반드시 남아야 할 것

### 1. 규칙은 하나다 — 옛 payload 를 새 타입으로 읽을 수 있어야 합니다

원장에 저장된 것은 v1 시절의 값입니다. 그 값을 v2 타입으로 번역할 수 있어야 v2 코드가
옛 Contract 를 다룰 수 있습니다. 컴파일러가 막는 것은 전부 이 한 가지로 정리됩니다.

| 시도 | 컴파일러 |
| --- | --- |
| 맨 뒤에 `Optional` 필드 추가 | 통과 |
| Choice 추가 | 통과 |
| 새 필드를 `Optional` 이 아니게 | 거부 |
| 새 필드를 중간에 끼워넣기 | 거부 |
| 기존 필드 제거 | 거부 |
| 기존 필드 타입 변경 | 거부 |
| Choice 제거 | 거부 |

실제 메시지입니다.

```
The upgraded template Voucher has added new fields, but the following new fields
are not Optional: Field 'expiresAt' with type Timestamp

The upgraded template Voucher has added new fields, but the following fields need
to be moved to the end: 'expiresAt'. All new fields in upgrades must be added to
the end of the definition.

The upgraded template Voucher is missing some of its original fields: 'amount'

The upgraded template Voucher has changed the types of some of its original
fields: Field 'amount' changed type from Numeric 10 to Int64

Choice Redeem appears in package that is being upgraded, but does not appear in
this package.
```

새 필드가 `Optional` 이어야 하는 이유도, 맨 뒤여야 하는 이유도 같습니다 — v1 payload
에는 그 자리가 비어 있고, `None` 이 그 자리를 메웁니다. 중간에 끼우면 기존 필드의
위치가 밀립니다.

### 2. 컴파일러가 막지 못하는 것

```daml
  where
    signatory issuer, owner      -- v1 은 signatory issuer 뿐이었다
```

```
The upgraded template Voucher has changed the definition of its signatories.
Upgrade this warning to an error -Werror=upgraded-template-expression-changed
Created .daml/dist/step09-voucher-2.0.0.dar
```

**에러가 아니라 경고이고, DAR 이 만들어집니다.**

컴파일러는 타입은 검사하지만 **표현식의 의미는 검사하지 못합니다.**
`signatory`·`observer`·`ensure` 를 바꾸면 옛 Contract 의 서명자나 불변식이 소급해서
달라지는데도 경고로 끝납니다. 실무 패키지라면
`-Werror=upgraded-template-expression-changed` 를 켜 두는 편이 낫습니다.

### 3. 옛 Contract 는 그대로 남고, 읽을 때 번역됩니다

v2 를 올려도 원장은 움직이지 않습니다.

```
v2 업로드 직후 — Alice 시점
    v1   0002fe50237539   amount=50   expiresAt=(v1 에 없는 필드)
```

그 Contract 에 v2 에만 있는 Choice 를 행사할 수 있습니다.

```
$ exercise SetExpiry  (templateId = v2)
  성공

    v2   00f99537c15bd7   amount=50   expiresAt=2030-01-01T00:00:00Z
```

읽는 순간 없던 필드가 `None` 으로 채워집니다. **원장에 저장된 값이 바뀐 것이 아니라
읽을 때 번역된 것입니다.**

새 버전을 올렸다고 기존 Contract 가 다시 쓰이지 않습니다. 원장은 그대로 두고 코드만
하나 더 생긴 것입니다.

### 4. `None` 을 어떻게 다룰지가 옛 Contract 의 운명을 정합니다

```daml
    choice Redeem : ()
      controller owner
      do
        now <- getTime
        case expiresAt of
          None -> pure ()                                    -- v1 시절 Contract
          Some deadline -> assertMsg "만료" (now <= deadline)
```

**옛 Contract 도 새 코드로 실행됩니다.** `None` 을 "만료됨" 으로 다뤘다면 v1 시절
Contract 는 전부 사용 불가가 됩니다.

컴파일러는 여기까지 봐 주지 않습니다. 타입은 맞고 빌드도 됩니다. 새 필드의 기본값을
무엇으로 볼 것인가는 설계 판단입니다.

### 5. 버전을 고정할 것인가, 맡길 것인가

`templateId` 를 쓰는 방법이 둘입니다.

| | 형태 | 동작 |
| --- | --- | --- |
| Package ID 고정 | `5e4405c8...:Voucher:Voucher` | 그 버전으로만 실행합니다 |
| package name 참조 | `#step09-voucher:Voucher:Voucher` | 참여자 전원이 가진 것 중 가장 높은 버전으로 풀립니다 |

### 6. 혼자서는 업그레이드할 수 없습니다

v2 를 `bank` 에만 올려 둔 상태에서, **같은 명령**을 두 상대에게 보내 봅니다.

```
Alice 앞으로  #step09-voucher   →  v2   (Alice 는 bank 노드, bank 는 v2 보유)
Bob   앞으로  #step09-voucher   →  v1   (Bob 은 broker 노드, v2 없음)
```

Canton 이 참여자 전원의 vetting 상태를 보고 **모두가 가진 가장 높은 버전**을 고릅니다.
못박으면 거부됩니다.

```
$ Bob 앞으로 v2 를 못박아서 발행
  실패  NO_SYNCHRONIZER_FOR_SUBMISSION
  cause: Some packages are not known to all informees on synchronizer public::1220...
```

`broker` 에도 올리면 그때부터 v2 로 풀립니다.

```
Bob 앞으로  #step09-voucher   →  v2
```

**업그레이드는 배포가 아니라 합의입니다.** 내 노드에 올리는 것만으로는 아무 일도
일어나지 않고, 거래 상대가 올려야 그 버전이 쓰이기 시작합니다.

그래서 `#package-name` 참조가 실무의 기본값입니다. 참여자들이 각자의 속도로 올려도
거래는 계속되고, 전원이 올린 시점부터 자동으로 새 버전이 쓰입니다. Package ID 를
못박으면 그 조율을 직접 해야 합니다.

## 운영 중인 노드에 올리는 법

[Step 05](Step05MultiParticipant.md) 는 bootstrap 콘솔로 DAR 을 올렸습니다. 이미 돌고
있는 노드에는 Ledger API 로 올립니다. 노드를 멈추지 않습니다.

```sh
curl -X POST http://localhost:5013/v2/packages \
  -H 'Content-Type: application/octet-stream' \
  --data-binary @upgrade/v2/.daml/dist/step09-voucher-2.0.0.dar
```

업로드는 vetting 까지 포함합니다 — 이 노드가 이 코드로 검증에 참여하겠다고 Topology 에
선언하는 것입니다.

## 이 Step 의 Template 이 단순한 이유

```daml
template Voucher
  with
    issuer : Party
    owner : Party
    amount : Decimal
  where
    signatory issuer
    observer owner
```

`signatory` 가 발행사 하나뿐입니다. [Step 02](Step02Environment.md)~04 의 `Deposit` 은
은행과 고객 양쪽이 서명했는데, 예금은 양쪽의 채권채무 관계이기 때문입니다.

상품권은 발행사가 일방적으로 지는 채무입니다. 소지자는 서명하지 않고 받기만 합니다.
덕분에 발행사 혼자 한 Transaction 으로 발행할 수 있고, 소지자가 다른 Participant 에
있어도 propose/accept 가 필요 없습니다. 6번의 vetting 실험이 이 성질을 씁니다.

## 흔히 막히는 곳

| 증상 | 원인 |
| --- | --- |
| `DPM did not provide information for package at ...` | `dpm build --package-root` 로는 안 됩니다. 그 디렉터리에서 `dpm build` 하거나 `DAML_PACKAGE` 를 쓰세요 |
| 규칙 위반인데 그냥 빌드됨 | `daml.yaml` 에 `upgrades:` 가 없습니다 |
| `KNOWN_PACKAGE_VERSION` | 같은 name·version 인데 내용이 다릅니다. version 을 올리세요 |
| `NO_SYNCHRONIZER_FOR_SUBMISSION` | 상대 Participant 가 그 패키지를 vetting 하지 않았습니다 |
| `Invalid template ... or choice:X` | 그 Package ID 에 없는 Choice 입니다. 버전을 잘못 못박았습니다 |

## 이 Step 으로 확인하지 못한 것

| | 왜 |
| --- | --- |
| 버전을 되돌리는 경우 | v2 로 채운 필드가 있는 Contract 는 v1 타입으로 번역되지 않습니다 |
| Interface 를 쓴 버전 분리 | Template 직접 참조만 다루었습니다 |
| `multi-package.yaml` | 패키지마다 따로 빌드했습니다 |

---

다음: **[Step 10 — 애플리케이션 연동](Step10Integration.md).** offset 과 ACS 스냅샷으로
원장을 따라가는 애플리케이션을 만듭니다.
