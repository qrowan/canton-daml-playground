# canton-daml-playground

**목적: 개발자가 Canton 을 이해하고, Daml 로 컨트랙트를 개발할 수 있도록 한다.**

Step 을 순서대로 거치면서 그 목표에 도달한다.

## 공식 문서

| | |
| --- | --- |
| Canton Network 개발자 문서 | https://docs.canton.network/ |
| Daml SDK | https://docs.canton.network/sdks-tools/sdks/daml-sdk |
| DPM (CLI) | https://docs.canton.network/sdks-tools/cli-tools/dpm |

`docs.digitalasset.com/build/3.4/*` 링크는 현재 404 다. 문서가 docs.canton.network 로
이전되었으므로 그쪽을 볼 것.

## 시작하기

### 1. JDK

```sh
brew install openjdk@21
```

### 2. SDK

Digital Asset 은 3.4.x 부터 **DPM(Digital Asset Package Manager)** 을 공식 CLI 로 삼고
있다. `dpm build` / `dpm test` / `dpm sandbox` 가 각각 `daml build` / `daml test` /
`daml sandbox` 를 대체한다.

```sh
curl https://get.digitalasset.com/install/install.sh | sh
```

```sh
export PATH="${HOME}/.dpm/bin:${PATH}"
```

**단, 이 저장소의 러너 스크립트는 아직 `daml` 어시스턴트를 호출한다.** 러너를 그대로
돌리려면 아래로 3.4.11 을 설치할 것.

```sh
curl -sSL -o /tmp/daml-sdk.tar.gz https://github.com/digital-asset/daml/releases/download/v3.4.11/daml-sdk-3.4.11-macos-x86_64.tar.gz && tar xzf /tmp/daml-sdk.tar.gz -C /tmp && /tmp/sdk-3.4.11/install.sh
```

`daml` 어시스턴트는 3.5 에서 제거될 예정이므로, 이 저장소도 DPM 으로 옮겨야 한다.

### 3. 환경 스크립트

프로젝트 전용으로 만든다. `~/.zshrc` 는 건드리지 않는다.

```sh
cat > env.sh <<'EOF'
export JAVA_HOME="/opt/homebrew/opt/openjdk@21"
export PATH="$JAVA_HOME/bin:$HOME/.daml/bin:$PATH"
EOF
```

작업할 때마다 저장소 루트에서:

```sh
source ./env.sh
```

`env.sh` 는 `.gitignore` 에 있다. 로컬 경로에 의존하므로 커밋하지 않는다.

### 4. 첫 Step

용어부터 읽는다. 코드는 없다.

- [Step 01 — 용어](steps/Step01Terminology.md)

그 다음부터는 **러너 스크립트**로 진행한다. 하나의 터미널에서 설명 → 엔터 → 실행 →
결과 순으로 돈다.

```sh
./steps/step02.sh
```

| 옵션 | 용도 |
| --- | --- |
| (없음) | 단계마다 엔터를 기다린다 |
| `--auto` | 엔터 없이 전부 실행 |
| `--keep` | 끝나고 노드를 끄지 않는다 (Step 02) |

각 Step 문서는 러너가 무엇을 보여주는지와 남겨야 할 결론을 담고 있다. 러너를 돌리고
문서를 읽는 순서를 권한다.

## 학습 경로

| Step | 문서 | 러너 | 다루는 것 |
| --- | --- | --- | --- |
| 01 | [용어](steps/Step01Terminology.md) | — | Canton 의 기본 용어 전체. 시나리오 서술 + 용어표 |
| 02 | [환경 세팅](steps/Step02Environment.md) | `step02.sh` | Participant 기동, Party·User 생성, HTTP 로 Contract 생성·조회 |
| 03 | [첫 계약](steps/Step03FirstContract.md) | `step03.sh` | Daml 문법. Choice / Controller / 권한 계산 |
| 04 | [두 당사자](steps/Step04TwoParties.md) | `step04.sh` | Propose-accept. 권한 결합, Observer |

시나리오는 하나로 이어진다 — **Citi 가 Alice 에게 토큰화 예금을 발행하고, Alice 가
Bob 에게 이체한다.** 등장 인물은 Step 01 에 정의되어 있다.

## 환경

| 항목 | 값 |
| --- | --- |
| 이 저장소가 쓰는 SDK | 3.4.11 (Canton 3.x, LF 2.1) |
| 최신 릴리스 | `curl -sS https://get.digitalasset.com/install/latest` 로 확인 |
| 설치 위치 | `~/.daml` (DPM 은 `~/.dpm`) |
| JVM | OpenJDK 21 (Homebrew keg-only) |

### 알아둘 것

- **macOS Apple Silicon**: Daml SDK 는 macOS x86_64 빌드만 배포되므로 Rosetta 를 경유해 실행된다. 동작에는 문제없다.
- **Daml Assistant 는 deprecated**: 3.5 에서 제거되고 [DPM](https://docs.canton.network/sdks-tools/cli-tools/dpm) 으로 대체된다. DPM 은 arm64 네이티브 빌드를 제공한다.
- **Daml 3 에는 contract key 가 없다**: 2.x 튜토리얼의 `key` / `maintainer` / `fetchByKey` 는 컴파일되지 않는다.
- **코드를 바꿨으면 `daml.yaml` 의 `version` 을 올려야** 원장에 재업로드된다. Package ID 는 내용 해시라서 버전이 같으면 충돌한다.
- **Sandbox 는 인메모리다.** 종료하면 Party·User·Contract 뿐 아니라 Participant 의 키까지 사라지고, 재기동하면 Party ID 의 namespace 지문이 바뀐다.

## 명령어

```sh
daml build          # DAR 컴파일 → .daml/dist/
daml test           # Daml Script 테스트 + Choice 커버리지
daml sandbox        # 빈 Canton 원장
daml canton-console # Canton 운영 콘솔
daml studio         # VS Code + Daml 확장
```

`daml test` 는 인메모리 엔진이고 Canton 이 아니다. Sequencer·Mediator·확인 프로토콜이
없다. 로직 검증은 `daml test`, 원장 동작 확인은 `daml sandbox` 로 한다.

## 파일 구조

```
steps/            학습 문서 + 러너 스크립트
daml/             Daml 소스 — daml.yaml 의 source 루트
env.sh            로컬 환경 (gitignore)
```

### 파일명 규칙

**Daml 은 1파일 = 1컨트랙트가 아니라 1파일 = 1모듈이다.** 파일 경로가 곧 모듈명이고,
컨벤션이 아니라 컴파일러가 강제한다.

```
daml/Step02/Deposit.daml    →  module Step02.Deposit where
daml/Step03/Deposit.daml    →  module Step03.Deposit where
```

실무에서는 모듈명이 컨트랙트명이 아니라 **도메인 또는 워크플로**를 따르고, 한 모듈에
관련 템플릿 여러 개를 담는다 — Daml 의 propose/accept 패턴은 템플릿 2~3개가 항상
세트로 움직이기 때문이다.

Step 별로 모듈을 나눈 것은 이 저장소의 튜토리얼 구성이며 실무 컨벤션이 아니다.
패키지는 하나로 유지하므로 Package ID 는 전체가 공유하고, 템플릿은 모듈명으로
구분된다 (`<package-id>:Step02.Deposit:Deposit`).

### 네이밍 규칙

문서와 코드 전체에서 실제 기관·인물명을 쓰고, 계층은 문맥으로 구분한다.

| 계층 | 예 |
| --- | --- |
| Participant 노드 | `citi-participant`, `morganstanley-participant` |
| Synchronizer 노드 | `dtcc-sequencer`, `dtcc-mediator` |
| Party | `Citi`, `Alice`, `Bob` |
| User | `alice-web`, `citi-settlement`, `citi-node-admin` |
