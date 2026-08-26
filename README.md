# canton-daml-playground

**목적: 개발자가 Canton 을 이해하고, Daml 로 컨트랙트를 개발할 수 있도록 한다.**

Step 을 순서대로 거치면서 그 목표에 도달한다.

## 학습 경로

| Step | 문서 | 다루는 것 | 상태 |
| --- | --- | --- | --- |
| 01 | [용어](steps/Step01Terminology.md) | Canton 의 모든 기본 용어. 시나리오 서술 + 용어표. 코드 없음 | ✅ |
| 02 | 환경 세팅 | Participant 기동, party·user 생성, HTTP 로 계약 생성·조회 | 예정 |
| 03 | 첫 계약 | Daml 문법. template / signatory / choice | 예정 |
| 04 | 두 당사자 | Propose-accept. 다중 signatory 의 권한 결합 | 예정 |
| 05 | 다중 participant | `canton.conf` 로 노드 2개 + synchronizer. 신뢰 경계·vetting·토폴로지 | 예정 |
| 06 | DvP | 증권 ↔ 현금 원자적 교환. 잠금 | 예정 |
| 07 | 공시·감사 | Observer, disclosure, 감독기관 열람 | 예정 |
| 08 | Synchronizer | 다중 synchronizer, Reassignment | 예정 |

### 시나리오

Step 들은 세 개의 시나리오를 나눠 쓴다. 등장 인물은 Step 01 에 정의되어 있다.

| 시나리오 | 드러나는 것 | Step |
| --- | --- | --- |
| **A. 토큰화 예금 발행·이체** (Citi → Alice → Bob) | Party/participant/user, signatory, propose-accept, 프라이버시 | 01~05 |
| **B. 증권 ↔ 현금 DvP** (Goldman Sachs ↔ Morgan Stanley) | 원자성, 권한 위임, 잠금, 신뢰 경계 | 06 |
| **C. 공시와 자산 이동** (SEC, Charlie) | Observer, external party, Reassignment | 07~08 |

## 환경

| 항목 | 값 |
| --- | --- |
| Daml SDK | 3.4.11 (Canton 3.x, LF 2.1) |
| 설치 위치 | `~/.daml` |
| JVM | OpenJDK 21 (Homebrew keg-only) |

### 세팅

```sh
brew install openjdk@21
```

```sh
curl -sSL -o /tmp/daml-sdk.tar.gz https://github.com/digital-asset/daml/releases/download/v3.4.11/daml-sdk-3.4.11-macos-x86_64.tar.gz && tar xzf /tmp/daml-sdk.tar.gz -C /tmp && /tmp/sdk-3.4.11/install.sh
```

프로젝트 전용 환경 스크립트를 만든다. `~/.zshrc` 를 건드리지 않는다.

```sh
cat > env.sh <<'EOF'
export JAVA_HOME="/opt/homebrew/opt/openjdk@21"
export PATH="$JAVA_HOME/bin:$HOME/.daml/bin:$PATH"
EOF
```

작업 시작할 때마다:

```sh
source ./env.sh
```

`env.sh` 는 `.gitignore` 에 있다. 로컬 경로에 의존하므로 커밋하지 않는다.

### 알아둘 것

- **macOS Apple Silicon**: Daml SDK 는 macOS x86_64 빌드만 배포되므로 Rosetta 를 경유해 실행된다. 동작에는 문제없다.
- **Daml Assistant 는 deprecated**: 3.5 에서 제거되고 [DPM](https://docs.digitalasset.com/build/3.4/dpm/dpm.html) 으로 대체된다.
- **Daml 3 에는 contract key 가 없다**: 2.x 튜토리얼의 `key` / `maintainer` / `fetchByKey` 는 컴파일되지 않는다.
- **코드를 바꿨으면 `daml.yaml` 의 `version` 을 올려야** 원장에 재업로드된다. Package-id 는 내용 해시라서 버전이 같으면 충돌한다.

## 명령어

```sh
daml build          # DAR 컴파일 → .daml/dist/
daml test           # Daml Script 테스트 + choice 커버리지
daml sandbox        # 빈 Canton 원장 (init-script 실행 안 함)
daml start          # Canton + DAR 업로드 + init-script 실행
daml canton-console # Canton 운영 콘솔
daml studio         # VS Code + Daml 확장
```

`daml test` 는 인메모리 엔진이고 Canton 이 아니다. Sequencer·Mediator·확인 프로토콜이
없다. 로직 검증은 `daml test`, 원장 동작 확인은 `daml sandbox` 로 한다.

**Sandbox 는 인메모리다.** 종료하면 party·user·계약뿐 아니라 participant 의 키까지
사라지고, 재기동하면 party ID 의 namespace 지문이 바뀐다.

## 파일 구조

```
steps/            학습 문서 (산문)
daml/             Daml 소스 — daml.yaml 의 source 루트
env.sh            로컬 환경 (gitignore)
```

### 파일명 규칙

**Daml 은 1파일 = 1컨트랙트가 아니라 1파일 = 1모듈이다.** 파일 경로가 곧 모듈명이고,
컨벤션이 아니라 컴파일러가 강제한다.

```
daml/Deposit.daml           →  module Deposit where
daml/Workflow/Dvp.daml      →  module Workflow.Dvp where
```

모듈명은 컨트랙트명이 아니라 **도메인 또는 워크플로**를 따른다. 한 모듈에 관련 템플릿
여러 개를 담는다 — Daml 의 propose/accept 패턴은 템플릿 2~3개가 항상 세트로 움직인다.

### 네이밍 규칙

문서와 코드 전체에서 실제 기관·인물명을 쓰고, 계층은 문맥으로 구분한다.

| 계층 | 예 |
| --- | --- |
| Participant 노드 | `citi-participant`, `morganstanley-participant` |
| Synchronizer 노드 | `dtcc-sequencer`, `dtcc-mediator` |
| Party | `Citi`, `Alice`, `Bob` |
| User | `alice-web`, `citi-settlement`, `citi-node-admin` |
