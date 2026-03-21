# PicoBox: Comprehensive Feature Checklist & System Guide

PicoBox는 분산 환경에서 안전하고 효율적인 컨테이너 실행 및 모니터링을 실현하기 위한 고성능 오케스트레이션 솔루션입니다. 이 문서는 제품(Product) 관점의 비전부터 하부 레이어의 기술적 세부 사항까지 아우르는 통합 가이드입니다.

---

## 1. Product 비전 및 핵심 기능 (Core Vision)

| 기능 ID | 핵심 기능 (Feature) | 제품 관점의 가치 (Value Proposition) | 구현율 |
| :--- | :--- | :--- | :---: |
| **P-1** | **즉각적인 고립 환경** | 단 1초 만에 호스트와 완전히 격리된 실행 환경(Sandbox)을 프로비저닝 | 90% |
| **P-2** | **동적 자원 할당 제어** | 실행 중인 환경의 CPU/Memory 자원을 물리적으로 제한하여 안정성 확보 | 100% |
| **P-3** | **멀티 노드 통합 대시보드** | 분산된 수십 개의 에이전트를 하나의 화면에서 실시간으로 관측 및 제어 | 85% |
| **P-4** | **무중단 상태 모니터링** | 에이전트 손실 시 즉각적인 감지 및 컨테이너 상태 영속성 보장 | 80% |

---

## 2. 시스템 아키텍처 및 데이터 흐름 (Top-Down Architecture)

### [Web] -> [Master] -> [Agent] 흐름 분석

1. **사용자 요청 (Web UI)**:
   - `DeployModal.tsx`에서 컨테이너 스펙 입력 (ID, Image, Cmd, Memory, CPU)
   - `fetch('/api/deploy', { method: 'POST', body: JSON.stringify(formData) })` 호출
2. **제어 센터 (Master - API & Logic)**:
   - **API (Fiber)**: REST 요청을 수신하여 `ContainerInfo` 객체 생성
   - **Store (SQLite)**: `store.SaveContainer()`를 통해 상태 영구 저장
   - **Streaming**: 해당 노드와 연결된 gRPC Stream (`ControlChannel`)을 찾아 `MasterMessage.deploy_request` 전송
3. **실행 엔진 (Agent - Runtime)**:
   - `ControlChannel`을 통해 `ContainerSpec` 수신
   - **Storage API**: OverlayFS 레이어 구성 (`upper`, `lower`, `work`, `merged`)
   - **Isolation API**: `namespace.NewContainerProcess()`를 호출하여 격리된 프로세스 실행
   - **Cgroups API**: `/sys/fs/cgroup/...` 경로에 PID를 등록하고 리소스 제한 설정

---

## 3. 레이어별 상세 기능 명세 (Technical Specification)

### [A] Daemon Layer (picoboxd)
- **Namespace Isolation**: `CLONE_NEWNS`, `CLONE_NEWUTS`, `CLONE_NEWIPC`, `CLONE_NEWPID`, `CLONE_NEWNET` 적용
- **Cgroup v2 Interface**:
  - `SetMemoryLimit`: `memory.max` 파일 제어
  - `ApplyLimits`: `cgroup.procs`에 PID 기록
- **Metrics Reporter**: `procfs` 기반 노드 상태 수집 (`/proc/stat`, `/proc/meminfo`)

### [B] Control Plane Layer (picobox-master)
- **gRPC Service**: `ControlChannel(stream AgentMessage) returns (stream MasterMessage)`
- **Persistence Table**:
  - `nodes`: 에이전트 생존 확인 및 메트릭 저장
  - `containers`: 전체 라이프사이클(Pending -> Running -> Stopped -> Error) 관리

### [C] Frontend Layer (Dashboard)
- **State Management**: React Query 또는 Svelte Store(선택 시)를 통한 실시간 동기화
- **Terminal Integration**: WebSocket 기반의 Exec 결과 출력 및 입력 스트림 (Planned)

---

## 4. E2E 검증 시나리오 (Verification Guide)

### [V-1] 격리성 및 배포 검증 (Isolation & Deployment)
| 검증 항목 | 상세 테스트 시나리오 | 검증 방법 (Method) | 성공 기준 (Success Criteria) |
| :--- | :--- | :--- | :--- |
| **프로세스 격리** | 컨테이너 내에서 `ps -ef` 실행 시 호스트 프로세스 노출 여부 확인 | 컨테이너 쉘 진입 후 `ps` 실행 | 오직 `/bin/sh` 및 컨테이너 내부 프로세스만 보여야 함 |
| **네임스페이스 고립** | 호스트와 컨테이너의 Namespace ID 대조 | `ls -l /proc/self/ns/pid` 비교 (Host vs Container) | 두 ID값이 서로 달라야 함 |
| **파일시스템 고립** | 컨테이너 내부 `/tmp` 파일 생성이 호스트 `/tmp`에 보이는지 확인 | 컨테이너 내 `touch /tmp/isolated_file` 실행 | 호스트의 `/tmp`에는 해당 파일이 존재하지 않아야 함 |
| **RootFS 정밀도** | OverlayFS 마운트 옵션 및 레이어 상태 확인 | `mount | grep overlay` | `lowerdir`, `upperdir`가 컨테이너 ID별로 정확히 분리되어 있어야 함 |

### [V-2] 자원 관리 및 제한 검증 (Resource Constraints)
| 검증 항목 | 상세 테스트 시나리오 | 검증 방법 (Method) | 성공 기준 (Success Criteria) |
| :--- | :--- | :--- | :--- |
| **메모리 하드 리밋** | 50MB 제한 부여 후 100MB 할당 시도 | `stress --vm 1 --vm-bytes 100M` 실행 | 컨테이너 프로세스가 즉시 종료되며 `dmesg`에 `oom-kill` 기록 |
| **CPU 쿼터 제한** | CPU 20% 제한 부여 후 연산 부하 발생 | `stress --cpu 1` 실행 후 호스트에서 `top` 모니터링 | 해당 PID의 CPU 점유율이 20%를 초과하지 않음 |
| **Cgroup v2 영속성** | 리소스 제한 변경 시 실시간 반영 여부 | `/sys/fs/cgroup/.../memory.max` 값 직접 확인 | 배포 옵션 변경 즉시 커널 설정값이 갱신되어야 함 |

### [V-3] 가용성 및 장애 복구 (HA & Recovery)
| 검증 항목 | 상세 테스트 시나리오 | 검증 방법 (Method) | 성공 기준 (Success Criteria) |
| :--- | :--- | :--- | :--- |
| **에이전트 이탈 감지** | 실행 중인 `picoboxd` 프로세스 강제 종료 (`kill -9`) | 웹 대시보드 실시간 관측 | 10초 내에 노드 상태가 `Offline`으로 변경되고 경고 발생 |
| **gRPC 세션 재연결** | 네트워크 일시 단절 후 복구 시 세션 복구 확인 | `iptables`로 50051 포트 차단 후 해제 | 에이전트가 지수 백오프 기반으로 재연결되어 메트릭 전송 재개 |
| **데이터 정합성** | 마스터 재시작 후 컨테이너 상태 복구 확인 | `systemctl restart picobox-master` | 대시보드에 기존 컨테이너 리스트 및 스펙이 누실 없이 다시 나타남 |

### [V-4] 이미지 및 저장소 검증 (Storage & Image)
| 검증 항목 | 상세 테스트 시나리오 | 검증 방법 (Method) | 성공 기준 (Success Criteria) |
| :--- | :--- | :--- | :--- |
| **이미지 압축 해제** | `.tar.gz` 형식의 RootFS 이미지 배포 | `scripts/prepare-rootfs.sh` 결과물 사용 | 마운트 전 `lowerdir`에 이미지 내용이 정확히 압축 해제되어야 함 |
| **레이어 클린업** | 컨테이너 삭제 후 남은 디렉토리 정리 확인 | `rm -rf storage/containers/<id>` | 컨테이너 정지 및 삭제 시 모든 런타임 레이어가 삭제되어야 함 |

---

## 5. 향후 개선 및 기술 부채 (Roadmap & Debt)

1. **[Security] TLS 인증**: gRPC 통신 시 mTLS(Mutual TLS) 적용으로 에이전트 통신 보안 강화.
2. **[Image] Layer Caching**: 동일 이미지 배포 시 RootFS를 매번 압축 해제하지 않고 캐싱된 레이어 활용.
3. **[Log] Persistent Logging**: 종료된 컨테이너의 로그를 마스터에서 조회 가능하도록 저장 로직 구현.
