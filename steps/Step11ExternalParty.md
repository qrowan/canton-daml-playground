# Step 11 — External Party

Step 02 부터 지금까지 모든 거래는 Participant 가 대신 서명했습니다. Alice 도 Bob 도
자기 키를 갖고 있지 않습니다. 은행이 만들어 준 Party 이고, 서명도 은행 노드가 합니다.

[Step 01](Step01Terminology.md) 이 그 대비를 이렇게 적어 두었습니다.

| | Hosted Party | External Party |
| --- | --- | --- |
| Namespace 키 | 발급 Participant 소유 | **본인 소유** |
| Transaction 서명 | Participant 가 대행 | **본인이 직접** |
| Participant 가 배신하면 | 속을 수 있음 | 서명 없이는 불가 |

**이번에는 그 마지막 줄을 실행해서 확인합니다.**

## 실행

저장소 루트에서:

```sh
./steps/step11.sh
```

| 옵션 | 용도 |
| --- | --- |
| (없음) | 단계마다 엔터를 기다립니다 |
| `--auto` | 엔터 없이 전부 실행합니다 |
| `--keep` | 끝나고 노드를 끄지 않습니다 |

## 다루는 파일

| 파일 | 내용 |
| --- | --- |
| `.step11/wallet.py` | 러너가 만들어 내는 Ed25519 지갑 |
| `.step11/charlie.key` | Charlie 의 시드 32바이트 |
| `canton/step05.conf` | [Step 05](Step05MultiParticipant.md) 구성 그대로 |
| `daml/Step04/Deposit.daml` | [Step 04](Step04TwoParties.md) 의 Deposit 그대로 |

Daml 도 노드 구성도 새로 만들지 않습니다. 달라지는 것은 **누가 서명하는가** 하나뿐입니다.

```
bank    participant   Bank · Alice           5013
broker  participant   Charlie 를 호스팅합니다   5023
public  synchronizer
```

Charlie 를 `broker` 에 올린 것은 의도한 배치입니다 — **노드를 남에게 맡긴 상황**이
이 Step 의 관심사입니다.

## 반드시 남아야 할 것

### 1. Party ID 뒷부분이 누가 키를 쥐었는지 말해 줍니다

```
Bank     Bank::1220ae1ce10e30def8a48e9d22ea0dba69946e96430ee8f4b63b33e26a0874a454c1
Alice    Alice::1220ae1ce10e30def8a48e9d22ea0dba69946e96430ee8f4b63b33e26a0874a454c1
Charlie  Charlie::12207e619c3d93e7061c65c4eea62263b90e49741721c170729f999bb002d9c278ad
```

Bank 와 Alice 는 뒷부분이 같습니다 — 둘 다 `bank` participant 가 발급했기 때문입니다.
Charlie 만 다르고, 그 값은 **Charlie 공개키의 지문**입니다.

**Party ID 만 보고도 판별됩니다.** 뒷부분이 노드의 지문이면 그 노드가 키를 쥐고 있고,
본인 키의 지문이면 본인이 쥐고 있습니다.

### 2. 온보딩은 세 단계입니다

```
① generate-topology   노드가 Topology Transaction 을 만들어 줍니다
② sign                Charlie 가 multiHash 에 서명합니다
③ allocate            서명을 붙여 등재합니다
```

첫 단계는 노드에게 **만들어만 달라고** 하는 것입니다. 서명은 하지 않습니다.

```sh
POST /v2/parties/external/generate-topology
{
  "synchronizer": "public::1220...",
  "partyHint": "Charlie",
  "publicKey": {
    "format": "CRYPTO_KEY_FORMAT_RAW",
    "keyData": "<공개키 32바이트, base64>",
    "keySpec": "SIGNING_KEY_SPEC_EC_CURVE25519"
  }
}
```

```json
{
  "partyId": "Charlie::12207e61...",
  "publicKeyFingerprint": "12207e61...",
  "topologyTransactions": ["..."],
  "multiHash": "EiCxkt0Q+ZMKGZiGK0rA8C1qim42waKO6yfe0Msyu55+"
}
```

**`multiHash` 하나에 서명하면 토폴로지 트랜잭션 전체가 인가됩니다.** 트랜잭션마다 따로
서명할 수도 있지만(`SignedTransaction.signatures`), 하나로 묶는 쪽이 간단합니다.

`multiHash` 는 base64 를 풀면 **34바이트**입니다 — 앞 두 바이트 `1220` 이 붙은
멀티해시입니다. **접두를 떼지 말고 34바이트 전체에 서명합니다.**

### 3. 거래는 prepare / sign / execute 로 나뉩니다

```
prepare   노드가 명령을 해석해 트랜잭션을 만들고 해시를 돌려줍니다
  ↓
sign      Party 가 자기 키로 그 해시에 서명합니다
  ↓
execute   서명을 붙여 제출합니다
```

Hosted Party 는 `/v2/commands/submit-and-wait` 한 번이면 끝납니다. 노드가 서명까지
대신하기 때문입니다. External Party 는 **서명이 노드 밖에 있으므로** 두 번으로
나뉩니다.

`prepare` 응답의 `preparedTransactionHash` 는 **32바이트**입니다. 온보딩의 `multiHash`
와 달리 멀티해시 접두가 없습니다.

### 4. 노드는 External Party 를 대리하지 못합니다

`broker` 는 Charlie 를 호스팅하는 노드입니다. 그 노드에 `CanActAs Charlie` 권한을 가진
user 까지 만들어 두고 그냥 제출해 봅니다.

```sh
POST http://localhost:5023/v2/commands/submit-and-wait   actAs=[Charlie]
```

```
실패  NO_SYNCHRONIZER_ON_WHICH_ALL_SUBMITTERS_CAN_SUBMIT
cause: This participant cannot submit as the given submitter on any connected synchronizer
```

**User 권한이 있어도 소용없습니다.** [Step 02](Step02Environment.md) 에서 "User 는
원장에 없다" 고 한 것이 여기서 끝까지 갑니다 — User 는 Participant 안의 API 호출
자격일 뿐이고, 원장이 요구하는 것은 Charlie 키의 서명입니다.

### 5. 같은 것을 Alice 에게 하면 성공합니다

```
Alice   (hosted)     bank 노드가 제출   →  성공
Charlie (external)   broker 노드가 제출  →  거부
```

**Alice 의 동의를 확인한 곳은 어디에도 없습니다.** bank 노드가 Alice 명의로 수락을
제출했고 원장은 그대로 받았습니다. Step 01 의 "Participant 가 배신하면 속을 수 있음"
이 이 한 줄입니다.

### 6. 서명이 틀리면 거부됩니다

다른 키로 서명해서 보내면 이렇게 됩니다.

```
실패  FAILED_TO_EXECUTE_TRANSACTION
cause: Received 0 valid signatures from distinct keys (1 invalid),
       but expected at least 1 valid for Charlie::1220a7168b33...
```

`signedBy` 는 Charlie 의 지문 그대로였는데도 거부됩니다. **지문을 주장하는 것과 그 키를
갖고 있는 것은 다릅니다.**

### 7. 서명하기 전에 무엇에 서명하는지 봐야 합니다

`prepare` 를 부르는 것은 노드입니다. 노드가 만들어 준 해시에 아무 확인 없이 서명하면,
키를 본인이 쥔 의미가 절반으로 줄어듭니다.

공식 문서가 이 지점을 명시합니다.

> "Clients MUST display the content of the transaction to the user for them to validate
> before signing the hash if the preparing participant is not trusted."
> — `PrepareSubmissionResponse.prepared_transaction`

`preparedTransaction` 이 그 내용이고, 응답에 함께 옵니다. **노드를 남에게 맡겼다면 이걸
열어 확인한 뒤 서명하는 것이 전제입니다.** 그러지 않으면 위탁한 노드가 만든 아무
트랜잭션에나 서명하게 됩니다.

### 8. 서명 포맷은 Ed25519 기준으로 정해져 있습니다

| 필드 | 값 |
| --- | --- |
| 공개키 `format` | `CRYPTO_KEY_FORMAT_RAW` — 32바이트 원본 |
| 공개키 `keySpec` | `SIGNING_KEY_SPEC_EC_CURVE25519` |
| 서명 `format` | `SIGNATURE_FORMAT_CONCAT` |
| 서명 `signingAlgorithmSpec` | `SIGNING_ALGORITHM_SPEC_ED25519` |

`SIGNATURE_FORMAT_CONCAT` 은 **RFC 8032 §3.3 의 `R‖S`** 입니다 — Ed25519 구현이 그냥
내놓는 64바이트 그대로입니다. proto 주석이 `SIGNATURE_FORMAT_RAW` 를 "Legacy format no
longer used" 로 적어 두었으므로 쓰지 않습니다.

### 9. 지갑은 해시를 받아 서명만 돌려줍니다

러너가 만드는 `.step11/wallet.py` 는 세 가지만 합니다.

```sh
python3 .step11/wallet.py selftest              # RFC 8032 §7.1 테스트 벡터
python3 .step11/wallet.py keygen  <keyfile>     # 시드 생성, 공개키 출력
python3 .step11/wallet.py sign    <keyfile> <b64hash>
```

Ed25519 는 표준 라이브러리에 없지만 **RFC 8032 구현이 60줄이면 됩니다.** 설치할 것이
없다는 뜻이고, 동시에 **서명 경계가 어디인지**를 코드로 보여 줍니다 — 지갑은 무엇에
서명하는지 모릅니다. 그것을 정하는 것은 부르는 쪽입니다.

실무에서 이 자리에 오는 것이 HSM 이나 수탁사입니다. 인터페이스는 같습니다 — 해시를
넣고 서명을 받습니다.

## 흔히 막히는 곳

| 증상 | 원인 |
| --- | --- |
| `prepare` 가 400, `Missing required field at 'synchronizerId'` | OpenAPI 명세는 Optional 로 적혀 있지만 **`synchronizerId` 와 `packageIdSelectionPreference` 를 둘 다 보내야 합니다** |
| `execute` 가 400, `Missing required field at 'deduplicationPeriod'` | 마찬가지로 필수입니다. 쓰지 않으면 `{"Empty":{}}` |
| `allocate` 가 서명을 거부 | `multiHash` 를 base64 로 푼 **34바이트 전체**에 서명해야 합니다. `1220` 접두를 떼면 안 됩니다 |
| `Received 0 valid signatures` | 서명한 키와 `signedBy` 지문이 다릅니다 |
| `NO_SYNCHRONIZER_ON_WHICH_ALL_SUBMITTERS_CAN_SUBMIT` | External Party 를 `submit-and-wait` 로 보냈습니다. `prepare`/`execute` 를 써야 합니다 |
| 상대 노드에서 계약이 안 보임 | `submit-and-wait` 는 **제출한 노드**가 커밋하면 돌아옵니다. 상대 노드 도달은 조금 뒤입니다 |

## 이 Step 으로 확인하지 못한 것

| | 왜 |
| --- | --- |
| 키 여러 개와 threshold | `confirmationThreshold` 를 기본값으로 두고 키 하나만 썼습니다 |
| 다중 호스팅 | `otherConfirmingParticipantUids` 를 비우고 `broker` 한 곳에만 올렸습니다 |
| 키 교체 | 온보딩 이후 토폴로지를 바꾸지 않았습니다 |
| HSM·수탁사 연동 | 시드를 파일에 두었습니다. 인터페이스는 같습니다 |
| `preparedTransaction` 을 실제로 뜯어 확인하는 것 | 7번은 문서가 요구하는 것을 인용했을 뿐 러너가 파싱하지는 않았습니다 |

---

여기까지가 "자기 키를 쥔다" 가 실제로 무엇을 바꾸는지입니다. **노드를 위탁할 때 계약서
대신 코드가 막아 주는 범위**가 이 Step 의 결론입니다.
