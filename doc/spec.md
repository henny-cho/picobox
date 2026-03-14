# 🚀 PicoBox: Development Blueprint (Master Context)

이 문서는 PicoBox 프로젝트를 개발하는 AI 에이전트 및 시스템 엔지니어를 위한 완성형 통합 컨텍스트 및 시스템 설계 명세서(Instruction)입니다. AI는 프로젝트의 목표를 이해하고, 코드를 생성하거나 수정할 때 반드시 이 문서의 규칙과 아키텍처를 준수해야 합니다.

## 1. 🧠 프로젝트 목적 및 시스템 페르소나 (Project Purpose & Persona)

### 1.1. 시스템 페르소나
당신은 시스템 프로그래밍과 분산 클라우드 아키텍처에 정통한 **'수석 시스템 엔지니어이자 풀스택 개발자'**입니다.

### 1.2. 프로젝트 핵심 목적
PicoBox는 리눅스 네임스페이스(Namespaces)와 cgroups v2를 직접 제어하여 컨테이너를 구동하는 **초경량 분산 컨테이너 플랫폼**입니다. 기존의 무거운 컨테이너 런타임(containerd, Docker)을 대체하여, 에지 컴퓨팅(Edge Computing) 및 저사양 IoT 디바이스에서도 동작할 수 있는 극한의 경량화된 K8s-Lite 형태의 플랫폼을 구축하는 것이 목표입니다.

### 1.3. 핵심 개발 원칙
- **언어 정책 (Language Policy):** 모든 문서는 **한국어**로 작성하며, 프로젝트 내부의 모든 코드 주석 및 커밋 메시지는 **영어**로 작성합니다.
- **사전 테스트 및 검증 루프 (Test-First & Validation Loop):** 각 개발 단계(Phase) 및 최종 목적 달성을 위해 반드시 **최소한의 검증용 테스트 코드를 사전에 작성하고 유지보수**해야 합니다. 모든 스택과 Phase의 완료 조건은 이 테스트 코드를 통과하는 '검증 루프(Validation Loop)'를 성공적으로 거치는 것입니다.
- **형상 관리 (Version Control):** 각 Phase를 완료하거나 의미 있는 세부 단계를 마칠 때마다 반드시 **Git Commit**을 생성하여 형상을 관리합니다. 
- **의존성 최소화 (Zero-External Dependencies):** Go 데몬(`picoboxd`) 개발 시 외부 컨테이너 런타임 라이브러리(runc 등)를 절대 사용하지 않습니다. 순수 Go 표준 라이브러리(`syscall`, `os/exec`)와 `golang.org/x/sys/unix`만을 사용하여 OS 커널을 직접 제어합니다.
- **타입 안정성 (Type Safety & Contract-First):** TypeScript, Go 간의 API 통신(REST/gRPC)은 Protobuf 및 OpenAPI 스키마를 통해 정의되며, `any` 타입 사용을 엄격히 금지합니다.
- **고성능 및 동시성 (High Concurrency):** Go 백엔드(`picobox-master`) 개발 시 Goroutine 누수(Leak)를 방지하고, Context, Channel, Mutex를 안전하게 다루어 고성능 분산 처리를 보장합니다.

## 2. 📦 시스템 아키텍처 및 기술 스택 (Architecture & Tech Stack)

### 2.1. 컴포넌트별 기술 스택 및 역할

| Component | Tech Stack | Role & Responsibility |
| --- | --- | --- |
| **PicoBox Daemon** | Go (Latest Stable), `x/sys/unix` | 리눅스 노드 실행 에이전트. 커널 직접 제어 (Namespaces, cgroups v2, pivot_root) |
| **Master Backend** | Go (Latest Stable), gRPC (Latest Stable), Fiber | 노드 수집, 스케줄링, 이미지 레지스트리 및 API 관제탑 |
| **Web Dashboard** | TypeScript, Next.js (Latest Stable), Tailwind CSS | 클러스터 시각화. 서버 관제실 테마 웹 |
| **Desktop App** | Go, React, Wails | 로컬 노드 제어, 컨테이너 Shell(PTY) 접속 툴 |
| **Mobile Client** | TypeScript, React Native (Expo) | 긴급 상황 알림 및 즉각 대응(SIGKILL) 앱 |

### 2.2. Data Flow 및 Call Tree 아키텍처

```mermaid
graph TD
    subgraph "External Control Plane (Clients)"
        W[Web Dashboard]
        M[Mobile App]
        D[Desktop App]
    end

    subgraph "Central Control Node"
        MB[Master Backend]
    end

    subgraph "Worker Nodes (Edge)"
        PD1[PicoBox Daemon 1]
        PD2[PicoBox Daemon 2]
    end

    W -- REST API (Fiber) --> MB
    M -- REST API (Fiber) --> MB
    D -- REST API / Local UDS --> MB

    MB -- gRPC RPC (Deploy/Kill Cmd) --> PD1
    PD1 -- gRPC Stream (Heartbeat/Metrics) --> MB
    
- **Isolation Lifecycle**: `namespace_linux.go:Execute` ➔ `syscall.Clone` ➔ `cgroups_linux.go:ApplyLimits` ➔ `pkg/storage/storage_linux.go:PivotRoot`

### 2.5. 디렉토리 구조 상세 (Detailed Directory Structure)
- `pkg/storage`: 파일시스템 격리(`pivot_root`), 레이어 관리(`OverlayFS`) 담당.
- `pkg/network`: gRPC 공통 클라이언트/서버 래퍼 및 통신 규격 관리.
- `pkg/isolation`: 리눅스 네임스페이스 및 Cgroups 제어 핵심 엔진.

### 2.3. 주요 자료구조 (Data Structures)
- **`NodeMetrics` struct**: 노드의 CPU/Memory 사용량, 호스트명, 디스크 IO 상태 등을 담는 구조체.
- **`ContainerSpec` struct**: 할당할 커널 리소스 Limit (`MemoryMax`, `CPUMax`), 사용될 RootFS 이미지(`docker_export.tar.gz`) 메타데이터.
- **`ContainerState` enum**: `Init`, `Running`, `Stopped`, `OOMKilled` 라이프사이클 상태 추적.

## 3. 📁 모노레포 디렉토리 구조 (Directory Structure)

디렉토리 구조는 명확한 책임 분리와 지속적인 CI/CD 자동화를 따릅니다.

```text
picobox/
├── .github/                  # [CI/CD] GitHub Actions Workflows (ci.yml 등)
├── api/
│   └── proto/                # [Protobuf] gRPC definitions (picobox.proto)
├── cmd/
│   ├── picoboxd/             # [Daemon Entrypoint] main.go
│   └── picobox-master/       # [Master Entrypoint] main.go
├── pkg/                      # [Core Libraries]
│   ├── daemon/               # 데몬 관리 (Master 통신, 컨테이너 라이프사이클 관리)
│   ├── isolation/            # Linux namespaces, cgroup 제어 (namespace_linux.go, cgroups_linux.go)
│   ├── network/              # gRPC client/server wrapper
│   └── storage/              # Pivot_root, OverlayFS
├── script/                   # [Automation] CI/CD 및 환경 setup, build 스크립트. (Lessons Learned 반영)
├── web/                      # [Next.js App] 클러스터 관제용 프론트엔드
├── desktop/                  # [Wails App] 로컬 GUI 클라이언트
├── mobile/                   # [React Native Expo] 모바일 관제 앱
└── docs/                     # [Markdown] 추가 확장 설계 문서 (ex. spec.md)
```

## 4. 🛠️ 상세 개발 및 코딩 컨벤션 (Coding Conventions)

### A. Go (Daemon & Master)
- **Error Handling:** 모든 시스템 콜 에러는 데몬 크래시를 방지하기 위해 `fmt.Errorf("context info: %w", err)`로 래핑하여 상위로 전달합니다. 커널 에러 코드를 명확히 매핑 후 로깅해야 합니다.
- **Logging:** 구조화된 로그를 위해 `log/slog` 패키지를 사용하며, 서버에서는 JSON 포맷(`slog.JSONHandler`)을 기본으로 적용하여 관제 시스템 연동을 용이하게 합니다.

### B. TypeScript (Web & Mobile)
- **Strict Typing:** `tsconfig.json`에서 `strict: true` 유지, `any` 사용 절대 금지합니다.
- **State & Data Fetching:** 서버 상태는 `@tanstack/react-query` 캐싱 처리, 클라이언트 전역 상태는 `zustand`를 활용합니다.

### C. Script & CI/CD (DevOps & Automation)
- **Lessons Learned 지속 반영:** 로컬 및 CI 환경에서 겪은 패키지 의존성 문제, 컴파일 에러, 시스템 권한 등의 이슈와 해결책은 개인 로컬 환경에만 두지 않고, 반드시 `script/setup.sh` 또는 `script/build.sh` 안에 주석과 코드로 지속 업데이트해야 합니다.
- **CI/CD 호환성 (Idempotency):** 스크립트 작성 시 로컬 개발환경뿐만 아니라 GitHub Actions CI 환경(Ubuntu)에서도 사용자 상호작용 없이(Non-interactive) 원활히 동작하도록 멱등성과 무인 자동화를 고려합니다.

## 5. 📝 AI 단계별 프롬프트 가이드 및 TDD/CI 주도 구현 플랜 (Implementation Phases)

아래의 구성을 따라 개발을 단계적으로 진행하며, 모든 Phase는 철저히 **사전 테스트 작성 ➔ 기능 구현 ➔ 로컬 검증 ➔ CI/CD 자동화 통합 ➔ Git Commit** 의 라이프사이클을 돌도록 재설계되었습니다. 
**테스트가 통과하고 GitHub Actions CI에서 정상 빌드/테스트가 증명되면(Validation Loop)** 해당 Phase 혹은 세부 기능을 확정 짓는 Git Commit을 수행합니다.

### Phase 1: 개발 환경 자동화, CI/CD, 통합 테스트 프레임워크 셋업
- **대상 파일:** `script/setup.sh`, `script/build.sh`, `script/test.sh`, `.github/workflows/ci.yml`
- **목표:** 지속적 통합의 뼈대와 공통 테스트 스크립트(`test.sh`) 구축
- **Validation Loop:**
  1. `test.sh`을 작성하여 `go test ./...` 및 Node.js 코드 테스트가 일괄 실행되도록 구성
  2. `ci.yml`에 `test.sh` 실행 단계를 추가하여 파이프라인에서 자동 검증되도록 연동

### Phase 2: 프로토콜 및 통신 계층 검증 (Protocol Layer)
- **대상 파일:** `api/proto/picobox.proto`, `pkg/network/grpc_test.go`
- **목표:** 백엔드 간 고성능 통신(gRPC) 인터페이스 확보 및 Mock 테스트 컴파일
- **Validation Loop:**
  1. `Heartbeat`, `DeployContainer` 뼈대를 작성 및 컴파일 테스트 
  2. Mock gRPC 클라이언트를 작성하여 `grpc_test.go`에서 인터페이스 호환 여부 1차 검증

### Phase 3: 코어 엔진 네임스페이스 격리 (Linux Namespace Runtime)
- **대상 파일:** `pkg/isolation/namespace_test.go`, `pkg/isolation/namespace_linux.go`
- **목표:** `os/exec.Cmd`를 활용한 자식 프로세스 철저 격리 개발
- **Validation Loop:**
  1. (TDD) `namespace_test.go`에서 `CLONE_NEWPID` 네임스페이스 분리가 정상 동작하는지 검사하는 권한 테스트 선반영
  2. `namespace_linux.go` 코어 구현 후 통과 확인
  3. CI/CD 상에서 Root 권한 컨테이너 격리 테스트가 정상 수행되도록 파이프라인(sudo/caps) 조정

### Phase 4: 자원 제한 및 파일시스템 격리 (Cgroup v2 & OverlayFS)
- **대상 파일:** `pkg/isolation/cgroups_test.go`, `pkg/storage/pivot_root_test.go` 및 구현 파일
- **목표:** cgroup 하드 리미트 작동 확인 및 RootFS 분리
- **Validation Loop:**
  1. (TDD) Mock 폴더 볼륨 마운트/Cgroup 디렉토리 생성 테스트 작성 (`cgroups_test.go`)
  2. `cgroups_linux.go` 및 `pivot_root_linux.go` 로직 구현 후 시스템 콜 테스트 통과 확인
  3. 로컬 환경과 CI의 OS 제약 조건을 극복하는 Lessons Learned 스크립트 지속 반영

### Phase 5: 마스터 서버 & API 라우팅 통합 (Control Plane)
- **대상 파일:** `cmd/picobox-master/main_test.go`, `cmd/picobox-master/main.go`
- **목표:** 데몬 모니터링 수신부(gRPC) 및 웹 대시보드 API(REST Fiber) 뼈대 테스트 및 구현
- **Validation Loop:**
  1. (TDD) 통합 웹 API 엔드포인트 Mock 요청 및 gRPC 서버 가동 응답 단위 테스트 (Status 200, JSON 반환 등) 확인
  2. 서버 로직 구축 후 엔드포인트 연동 검증. (`script/test.sh`을 통해 100% 동작 확인)

### Phase 6: 프론트엔드 대시보드 UI 연동 (Admin Dashboard)
- **대상 파일:** `web/app/page.test.tsx`, `web/components/NodeCard.tsx` 등
- **목표:** 클러스터 현황 시각화 및 Mocking 기반 UI 렌더링 테스트
- **Validation Loop:**
  1. (TDD) JEST/React Testing Library를 활용한 페이지 및 컴포넌트 렌더링 로직 UI 테스트 우선 작성
  2. 백엔드 Rest API 연동 및 UI 완성 후 통합 동작 확인 (CI npm/yarn test 연동)

---

## 6. 🧠 Lessons Learned & Engineering Insights (Knowledge Asset)

프로젝트 개발 및 CI/CD 검증 과정에서 확보된 핵심 기술적 교훈입니다.

### 6.1. Environment & Dependency Management
- **Continuous Modernization**: PicoBox는 항상 보안과 성능이 검증된 **최신 안정 버전(Latest Stable)**의 도구 체인을 사용하는 것을 원칙으로 합니다. (예: Go 1.26+, Node 25+, gRPC v1.79+ 등)
- **gRPC Symbol Integrity**: 프로토콜 생성 코드의 최신 규격을 준수하기 위해 gRPC 라이브러리와 관련 플러그인(`protoc-gen-go`, `protoc-gen-go-grpc`)을 항상 최신 안정 버전으로 유지하여 심볼 정합성을 확보합니다.

### 6.2. CI/CD & Local Validation (Act)
- **Privileged Mode**: `act`와 같은 컨테이너형 CI 환경에서 리눅스 네임스페이스 및 cgroups 관련 테스트를 수행하려면 반드시 `--privileged` (또는 `--container-options "--privileged"`) 플래그가 필요합니다.
- **Sudo Dependency**: 최소화된 CI 컨테이너 이미지(`ubuntu:act-latest` 등)에는 `sudo` 명령어가 없습니다. `script/setup.sh`에서 환경을 감지하여 `apt-get install -y sudo`를 선행해야 합니다.
- **Race conditions in Tests**: 통합 테스트 시 Master 서버가 포트(50051)를 점유하기 전에 Daemon이 연결을 시도하면 실패합니다. `test.sh`에서 `ss -ln`을 활용한 포트 대기 로직(Wait-for-Port)을 구현하여 해결했습니다.

### 6.3. Development Efficiency
- **Build Output Standard**: 모든 빌드 결과물은 `./bin/` 디렉토리로 통합 관리합니다. 이는 `test.sh`와 `ci.yml`에서 경로 정합성을 유지하기 위함입니다.
- **npm ci vs npm install**: CI 환경에서는 `package-lock.json`의 무결성을 보장하고 재현성을 높이기 위해 반드시 `npm ci`를 사용해야 합니다.