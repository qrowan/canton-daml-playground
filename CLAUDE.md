# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 이 저장소의 목적

**개발자가 Canton 을 이해하고, Daml 로 컨트랙트를 개발할 수 있도록 합니다.**

교육용 저장소입니다. 프로덕션 코드가 아니라 **Step 을 순서대로 밟으며 배우는 교재**이고,
Step 마다 **문서(`steps/StepNN*.md`) + 러너 스크립트(`steps/stepNN.sh`)** 한 쌍으로
구성됩니다. 러너는 한 터미널에서 설명 → 엔터 → 실행 → 결과 순으로 돕니다.

읽는 사람은 이 저장소를 통해 지식을 쌓습니다. **틀린 내용이 들어가면 안 됩니다** —
아래 "주장은 실행해서 확인한다" 를 반드시 지킵니다.

## 명령어

```sh
dpm build                        # DAR 컴파일 → .daml/dist/
dpm test                         # Daml Script 테스트 + Choice 커버리지
dpm sandbox                      # Participant + Sequencer + Mediator 한 프로세스
dpm canton-console               # Canton 운영 콘솔
dpm inspect-dar <dar>            # Package ID 확인

./steps/stepNN.sh                # 단계마다 엔터 대기
./steps/stepNN.sh --auto         # 엔터 없이 전부 실행 (검증용)
./steps/stepNN.sh --keep         # 끝나고 노드를 끄지 않음 (02·05·08·09·10)
```

**`daml` 어시스턴트는 쓰지 않습니다.** 3.5 에서 제거되었고 DPM 이 대체합니다.
`env.sh`(gitignore)가 있으면 러너가 자동으로 읽지만 없어도 됩니다 — PATH 에 `dpm` 과
`java` 만 있으면 동작합니다.

### 개별 테스트

`dpm test` 는 패키지 전체를 돌립니다. 하나만 돌리려면 `-p` 로 이름을 거릅니다.

```sh
dpm test -p testTransferFails
```

### upgrade/ 하위 패키지

`upgrade/v1`·`upgrade/v2` 는 루트와 **별개 패키지**입니다 (`step09-voucher` 1.0.0 / 2.0.0).
`dpm build --package-root` 는 동작하지 않습니다.

```sh
cd upgrade/v1 && dpm build
DAML_PACKAGE="$PWD/upgrade/v2" dpm build     # 디렉터리를 옮기지 않을 때
```

## 구조

```
steps/     Step 문서 + 러너. 이 저장소의 본체
daml/      Daml 소스. daml.yaml 의 source 루트
canton/    노드 설정과 bootstrap (step05.conf, step08.conf)
upgrade/   Step 09 용 별도 패키지 v1 / v2
```

### Step 과 자원의 관계

Step 마다 새 Daml 을 만들지 않습니다. **앞 Step 의 것을 재사용하는 것이 원칙**이고,
"무엇이 달라지는가" 를 한 가지로 좁히는 것이 이 교재의 방식입니다.

| Step | Daml | 노드 |
| --- | --- | --- |
| 02·03·04 | `daml/StepNN/Deposit.daml` | `dpm sandbox` |
| 05 | Step04 재사용 | `canton/step05.conf` — participant 2 + sync 1 |
| 06·07 | `daml/StepNN/*.daml` | `dpm test` 만 |
| 08 | **Step06 재사용** (한 줄도 안 고침) | `canton/step08.conf` — participant 2 + sync 2 |
| 09 | `upgrade/v1`·`v2` | step05.conf 재사용 |
| 10 | Step04 재사용 | step05.conf 재사용 |

포트: sync `5001~5006`, participant `5011~5013` / `5021~5023` / `5031~5033`.
러너는 기동 전에 `pkill -f 'daemon -c canton/'` 로 이 저장소의 canton 데몬 전부를
정리합니다 (설정이 둘이고 포트가 겹치므로).

### 러너의 공통 골격

모든 러너가 같은 헬퍼를 씁니다. 새 Step 을 만들 때 기존 러너를 복사해 시작하세요.

```
title  단계 제목 + [N/TOTAL]      say/note/ok/warn/die  출력
pause  엔터 대기 (--auto 면 통과)  run   명령을 보여주고 실행
jq_    python3 으로 JSON 파싱      result 응답을 성공/실패로 출력
```

JSON Ledger API 는 **성공하면 `code` 필드를 보내지 않습니다.** 기본값으로 `-` 를 찍으면
"없음"인지 "실패"인지 구분되지 않으므로 `result()` 를 쓰세요.

## 지켜야 할 것

### 주장은 실행해서 확인한다

러너나 문서가 사실을 주장하면 **먼저 돌려서 확인합니다.** 이 저장소에서 실제로
있었던 일:

- 러너가 "각 노드는 자기가 호스팅하는 Party 만 안다" 고 주장 → 실측 결과 **모든 노드가
  모든 Party 를 안다.** 갈리는 것은 `isLocal` 이었음
- Step 08 이 "이동중에는 쓸 수 없다" 를 시연 → `--auto` 에서만 통했고 사람이 엔터를
  누르는 속도에서는 이미 자동 assign 된 상태였음

러너 단계마다 응답을 확인하고 판단하세요. **실패했는데 성공했다고 찍는 일이 없어야
합니다.** 성공/실패를 무조건 출력하지 말고 응답이나 ACS 를 다시 조회해 판단합니다.

변경 후에는 반드시:

```sh
dpm build && dpm test
for st in 02 03 04 05 06 07 08 09 10; do ./steps/step$st.sh --auto >/dev/null 2>&1 || echo "step$st 실패"; done
```

### 기관 실명을 쓰지 않는다

실명을 지목하면 잘못 지목하게 됩니다. **역할명만 씁니다.**

| 이름 | 역할 |
| --- | --- |
| `Bank` | 토큰화 예금·현금을 발행하는 금융기관 |
| `Broker` | 상대 금융기관 |
| `Issuer` | 증권 발행사 |
| `Regulator` | 상시 공시 대상 |
| `Auditor` | 선택 공시 대상 |
| `Custodian` | 남의 Party 를 대신 호스팅하는 수탁 사업자 |
| `Alice` `Bob` `David` | hosted party (개인 고객) |
| `Charlie` | external party (자기 키 보유) |
| `public` / `consortium` | 공용 원장 / 컨소시엄 원장 |

Daml 템플릿 필드명도 역할 기반입니다 (`bank`·`owner`·`issuer`·`regulator`·`auditor`).

### Synchronizer 는 자산 종류로 나뉘지 않는다

**"현금 원장 / 증권 원장" 이라고 쓰지 마세요.** Synchronizer 는 거래 내용을 보지 못하므로
그 안에 무엇이 있는지 알 수가 없습니다. 경계를 정하는 것은
규제·성능·격리·비용·거버넌스이고, 자산이 갈리는 것은 운영 주체와 참여 자격이 다른 데서
나오는 **결과**입니다. 그래서 원장 이름을 참여 자격 기준(`public`/`consortium`)으로
두었습니다.

### 문체

- 문서와 러너 출력은 **`~습니다`** 체
- 커밋 메시지는 **`~다`** 체 (평서형)
- 번역된 기술 용어는 원어로 (`계약` 대신 `Contract`, `봉투` 대신 `Envelope` 는 예외적으로 병기)
- **작성자를 위한 메타 서술을 넣지 않습니다** — "이 문서의 표기", "참고로 필자는" 같은 것.
  다른 개발자가 읽는 문서입니다
- "직접 해보기" 같은 연습문제 절을 두지 않습니다

### Daml 파일의 주석 규칙

**설명과 구현을 확실히 분리합니다.** 파일 맨 위에 블록 주석으로 설명을 모으고,
구분선 아래 구현에는 주석을 넣지 않습니다.

```daml
{-
================================================================================
 Step NN — 제목
================================================================================
 설명, 권한 계산, 설계 판단, 함정
================================================================================
-}

module StepNN.Thing where

template Thing
  ...   -- 여기부터는 주석 없음
```

### 커밋

작성자는 `qrowan <hsjii1589@gmail.com>` (local git config). **`Co-Authored-By` 트레일러를
넣지 않습니다.** 본문에는 무엇을 왜 바꿨는지와 **확인해서 알아낸 것**을 적습니다 —
이 저장소의 커밋 로그가 곧 검증 기록입니다.

## 알아둘 것 (실측으로 확인된 것)

- **Daml 3 에는 contract key 가 없습니다.** 2.x 튜토리얼의 `key`/`maintainer`/`fetchByKey`
  는 컴파일되지 않습니다
- **코드를 바꿨으면 `daml.yaml` 의 `version` 을 올려야** 재업로드됩니다. Package ID 가
  내용 해시라서 같은 버전에 다른 내용이면 `KNOWN_PACKAGE_VERSION` 입니다
- **Contract 는 수정되지 않습니다.** archive + create 이므로 Contract ID 가 매번 바뀝니다.
  외부 시스템의 키로 쓸 수 없습니다
- **권한 = [Contract 의 signatory] + [Choice 의 controller]**. 한쪽 권한만으로 상대의
  서명이 필요한 Contract 를 만들 수 없고, 노드가 분리되면 propose/accept 가 필수입니다
- **`dpm sandbox -c custom.conf` 는 동작하지 않습니다** (자체 설정·bootstrap 이 박혀 있음).
  다중 노드는 canton jar 을 직접 띄웁니다
- **JSON API 업로드로 vetting 까지 됩니다** — `POST /v2/packages` 에 DAR 바이너리.
  노드를 멈추지 않습니다
- **Reassignment 응답에 `eventFormat` 을 함께 보내야** 이벤트가 실립니다. 빼면
  `reassignmentId` 를 못 받습니다
- **`assignmentExclusivityTimeout` 기본값은 15초**이고 지나면 Participant 가 자동으로
  assign 합니다. Step 08 bootstrap 이 10분으로 늘려 둡니다
- **다중 Synchronizer 는 opt-in** 입니다. `SynchronizerTrustCertificate` 에
  `EnableMultiSynchronizer` 를 붙여야 수동 Reassignment 도 자동 재배정도 동작하고,
  `dars.upload`·`parties.enable` 을 원장마다 따로 불러야 합니다
- **업그레이드는 배포가 아니라 합의**입니다. `#package-name` 참조는 참여자 전원이 가진
  가장 높은 버전으로 풀리고, 상대가 vetting 하기 전에는 새 버전이 쓰이지 않습니다
- **서명자 정의 변경은 컴파일 에러가 아니라 경고**입니다. DAR 이 만들어지므로
  `-Werror=upgraded-template-expression-changed` 를 켜는 편이 낫습니다

## 문서 링크

| | |
| --- | --- |
| Canton Network 문서 | https://docs.canton.network/ |
| DPM | https://docs.canton.network/sdks-tools/cli-tools/dpm |

`docs.digitalasset.com/build/3.4/*` 는 404 입니다.
