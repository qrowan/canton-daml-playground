# canton-daml-playground

**개발자가 Canton 을 이해하고, Daml 로 컨트랙트를 개발할 수 있도록 합니다.**

Step 을 순서대로 거치면서 그 목표에 도달합니다. 각 Step 은 **문서**와 **러너
스크립트** 한 쌍입니다. 러너는 하나의 터미널에서 설명 → 엔터 → 실행 → 결과 순으로
돕니다.

## 배우는 것

| Step | 문서 | 러너 | 다루는 것 |
| --- | --- | --- | --- |
| 01 | [용어](steps/Step01Terminology.md) | — | Party·Participant·Synchronizer·Contract 등 기본 용어 전체 |
| 02 | [환경 세팅](steps/Step02Environment.md) | `step02.sh` | Participant 기동, Party·User 생성, HTTP 로 Contract 생성·조회 |
| 03 | [첫 계약](steps/Step03FirstContract.md) | `step03.sh` | Daml 문법. Choice / Controller / 권한 계산 |
| 04 | [두 당사자](steps/Step04TwoParties.md) | `step04.sh` | Propose-accept. 권한 결합, Observer |
| 05 | [다중 Participant](steps/Step05MultiParticipant.md) | `step05.sh` | 노드 4개 직접 기동. 데이터 격리·vetting·노드 간 이체 |
| 06 | [DvP](steps/Step06Dvp.md) | `step06.sh` | 증권 ↔ 현금 원자적 교환. 중첩 exercise 로 권한 흐름 |

시나리오는 하나로 이어집니다 — **Citi 가 Alice 에게 토큰화 예금을 발행하고, Alice 가
Bob 에게 이체하고, Bob 이 Goldman Sachs 의 채권과 교환합니다.** 등장 인물은 Step 01 에
정의되어 있습니다.

## 사전 준비

필요한 것은 두 개다. **DPM**(Daml/Canton 공식 CLI)과 **JDK 21 이상**.

아래는 macOS 기준 명령입니다. 다른 OS 이거나 다른 방법을 쓰고 싶으면 공식 문서를 볼 것 —
[DPM 설치](https://docs.canton.network/sdks-tools/cli-tools/dpm).

### 1. DPM

```sh
curl https://get.digitalasset.com/install/install.sh | sh
```

### 2. JDK 21

배포판은 자유다. Homebrew 를 쓴다면:

```sh
brew install openjdk@21
```

### 3. PATH 등록

**둘 다 설치만으로는 셸에서 잡히지 않습니다.** DPM 은 `~/.dpm/bin` 에 들어가고,
Homebrew 의 `openjdk@21` 은 keg-only 라 시스템 JDK 로 등록되지 않습니다.

```sh
cat >> ~/.zshrc <<'EOF'
export JAVA_HOME="$(brew --prefix openjdk@21)"
export PATH="$JAVA_HOME/bin:$HOME/.dpm/bin:$PATH"
EOF
source ~/.zshrc
```

### 4. 확인

```sh
dpm version
```

```
 * 3.5.5
```

```sh
java -version
```

```
openjdk version "21.0.12.1" ...
```

`command not found` 나 `Unable to locate a Java Runtime` 이 나오면 3번을 다시 볼 것.

### 5. SDK 설치

저장소 루트에서. 버전은 `daml.yaml` 이 정합니다.

```sh
dpm install
```

```
Successfully installed SDK 3.5.5
```

## 시작

```sh
./steps/step02.sh
```

그 전에 [Step 01 — 용어](steps/Step01Terminology.md) 를 읽는다. 코드가 없는 문서이고,
이후 Step 의 용어가 전부 여기서 정의됩니다.

| 러너 옵션 | 용도 |
| --- | --- |
| (없음) | 단계마다 엔터를 기다린다 |
| `--auto` | 엔터 없이 전부 실행 |
| `--keep` | 끝나고 노드를 끄지 않는다 (Step 02, 05) |

러너를 먼저 돌리고 해당 Step 문서를 읽는 순서를 권합니다. 문서에는 러너가 보여준 것의
의미와 남겨야 할 결론이 정리되어 있습니다.

## 명령어

```sh
dpm build          # DAR 컴파일 → .daml/dist/
dpm test           # Daml Script 테스트 + Choice 커버리지
dpm sandbox        # Participant + Sequencer + Mediator 를 한 프로세스로
dpm canton-console # Canton 운영 콘솔
dpm studio         # VS Code + Daml 확장
```

`dpm test` 는 인메모리 엔진이고 Canton 이 아닙니다. Sequencer·Mediator·확인 프로토콜이
없습니다. 로직 검증은 `dpm test`, 원장 동작 확인은 `dpm sandbox` 로 합니다.

## 알아둘 것

- **`daml` 어시스턴트는 쓰지 않습니다.** 3.5 에서 제거되었고 [DPM](https://docs.canton.network/sdks-tools/cli-tools/dpm) 이 대체합니다.
- **Daml 3 에는 contract key 가 없습니다.** 2.x 튜토리얼의 `key` / `maintainer` / `fetchByKey` 는 컴파일되지 않습니다.
- **코드를 바꿨으면 `daml.yaml` 의 `version` 을 올려야** 원장에 재업로드됩니다. Package ID 는 내용 해시라서 버전이 같으면 충돌합니다.
- **Sandbox 는 인메모리다.** 종료하면 Party·User·Contract 뿐 아니라 Participant 의 키까지 사라지고, 재기동하면 Party ID 의 namespace 지문이 바뀝니다.

## 문제가 생기면

### `dpm 을 찾을 수 없습니다`

PATH 에 없습니다. 설치 후 추가합니다.

```sh
export PATH="$HOME/.dpm/bin:$PATH"
```

### `java -version` 이 `Unable to locate a Java Runtime` 을 낸다

macOS 의 `/usr/bin/java` 는 JVM 이 아니라 stub 입니다. `JAVA_HOME` 이 설정돼 있거나
`/Library/Java/JavaVirtualMachines` 에 JDK 가 등록돼 있어야 실제 JVM 을 찾는다.
패키지 매니저로 설치한 JDK 는 거기 등록되지 않는 경우가 있습니다. `JAVA_HOME` 을 직접
지정하면 됩니다.

```sh
export JAVA_HOME=/path/to/jdk-21
```

### 셸 설정을 건드리고 싶지 않다

저장소 루트에 `env.sh` 를 만들어 두면 러너가 자동으로 읽는다. `.gitignore` 에 있어
커밋되지 않습니다. 없어도 무방하다.

```sh
export JAVA_HOME=/path/to/jdk-21
export PATH="$JAVA_HOME/bin:$HOME/.dpm/bin:$PATH"
```

### Step 05 가 `canton jar 을 찾을 수 없습니다` 로 멈춘다

DPM 캐시에서 자동으로 찾지만 못 찾으면 직접 지정합니다.

```sh
export CANTON_JAR=/path/to/canton-open-source-*.jar
```

## 공식 문서

| | |
| --- | --- |
| Canton Network 개발자 문서 | https://docs.canton.network/ |
| Daml SDK | https://docs.canton.network/sdks-tools/sdks/daml-sdk |
| DPM | https://docs.canton.network/sdks-tools/cli-tools/dpm |

---

## 저장소 구조

여기부터는 코드를 고칠 때 필요한 내용입니다.

```
steps/            학습 문서 + 러너 스크립트
daml/             Daml 소스 — daml.yaml 의 source 루트
canton/           Canton 노드 설정과 bootstrap 스크립트 (Step 05~)
env.sh            로컬 환경 (gitignore)
```

### 파일명 규칙

**Daml 은 1파일 = 1컨트랙트가 아니라 1파일 = 1모듈입니다.** 파일 경로가 곧 모듈명이고,
컨벤션이 아니라 컴파일러가 강제합니다.

```
daml/Step02/Deposit.daml    →  module Step02.Deposit where
daml/Step03/Deposit.daml    →  module Step03.Deposit where
```

실무에서는 모듈명이 컨트랙트명이 아니라 **도메인 또는 워크플로**를 따르고, 한 모듈에
관련 템플릿 여러 개를 담는다 — Daml 의 propose/accept 패턴은 템플릿 2~3개가 항상
세트로 움직이기 때문입니다.

Step 별로 모듈을 나눈 것은 이 저장소의 튜토리얼 구성이며 실무 컨벤션이 아닙니다.
패키지는 하나로 유지하므로 Package ID 는 전체가 공유하고, 템플릿은 모듈명으로
구분된다 (`<package-id>:Step02.Deposit:Deposit`).

### 네이밍 규칙

문서와 코드 전체에서 실제 기관·인물명을 쓰고, 계층은 문맥으로 구분합니다.

| 계층 | 예 |
| --- | --- |
| Participant 노드 | `citi-participant`, `morganstanley-participant` |
| Synchronizer 노드 | `dtcc-sequencer`, `dtcc-mediator` |
| Party | `Citi`, `Alice`, `Bob` |
| User | `alice-web`, `citi-settlement`, `citi-node-admin` |
