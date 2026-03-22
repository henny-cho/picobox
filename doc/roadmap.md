# 🚀 PicoBox 프로젝트 로드맵 (Project Roadmap)

이 문서는 `doc/spec.md` 및 `doc/feature_checklist.md` 기반으로 작성된 **PicoBox** 프로젝트의 통합 구현 로드맵입니다. 현재까지의 개발 진행 상황을 파악하고, 최종 완성을 위한 향후 목표를 상세 페이즈(Phase)로 나누어 구체화합니다.

---

## 🟢 완료 및 진행 중인 페이즈 (Current Progress)

### [x] Phase 1: 개발 환경 및 자동화 도구 고도화 (완료율: 100%)
- `scripts/task.sh`, `scripts/versions.sh` 기반 통합 자동화 스크립트 구축 완료.
- 최신 언어 스택(Go 1.26.1, Node 24) 기반 CI/CD 파이프라인(.github/workflows) 셋업 완료.
- 환경 구성 및 기반 툴 체인(Build, Test, Setup) 검증 완료.

### [x] Phase 2: 코어 엔진 및 격리 레이어 구현 (완료율: 95%)
- `internal/isolation`: Linux Namespace (PID, IPC, UTS, Mount, Network) 격리 엔진 구현 완료. (P-1 90%)
- `internal/isolation/cgroups_linux.go`: Cgroups v2 기반 CPU, Memory 동적 자원 통제 및 쿼터 제한 구현 완료. (P-2 100%)
- `internal/storage`: Pivot Root 및 OverlayFS 기반 파일시스템 격리 구현 완료.

### [ ] Phase 3: 분산 통신 및 컨트롤 플레인 통합 (진행률: 85%)
- `internal/network`, `cmd/picobox-master`: gRPC(`ControlChannel`) 기반 마스터-노드 양방향 스트리밍 구현 완료. (P-4 80%)
- Fiber 프레임워크 기반 REST API 제어 계층 작성 중.
- `web/`: Next.js 기반 클러스터 관제용 프론트엔드 대시보드 상태 동기화 및 연동 작업 중. (P-3 85%)

---

## 🔵 향후 구현 페이즈 (Upcoming Phases - Final Target)

프로젝트 최종 완성을 위해 Phase 4부터는 기능을 세분화하여 진행합니다.

### [ ] Phase 4: 스토리지 레이어 최적화 및 영속성 (Storage & Persistence)
* **4.1. 이미지 레이어 캐싱 (Layer Caching):** 동일한 RootFS 이미지를 여러 번 배포할 때, 매번 압축을 해제하지 않고 `.tar.gz` 상태에서 캐시된 `lowerdir`을 재사용하여 배포 속도 1초 미만 보장.
* **4.2. 영구 볼륨 마운트 (Persistent Volumes):** 컨테이너 재시작 시 데이터가 유지될 수 있도록 호스트의 특정 디렉토리를 컨테이너 내부에 `bind` 마운트하는 기능 (ex. `/var/lib/mysql`) 구현.
* **4.3. 쓰레기 수집 및 클린업 (Garbage Collection):** 종료된 컨테이너의 OverlayFS 레이어, 남은 Cgroup 디렉토리 및 고아(orphan) 프로세스를 안전하게 정리하는 백그라운드 클린업 로직 고도화.

### [ ] Phase 5: 고급 컨테이너 네트워킹 (Advanced Networking)
* **5.1. 컨테이너 브릿지 네트워크 (Bridge Network):** Network Namespace 내에 가상 이더넷 인터페이스(`veth` pair) 설정 및 호스트 브릿지(`picobr0`) 연결 자동화.
* **5.2. 포트 포워딩 및 NAT 지원 (Port Forwarding):** 외부 트래픽이 호스트의 특정 포트를 통해 컨테이너 내부 네트워크 포트로 인입되도록 `iptables` NAT 규칙 작성 및 관리.
* **5.3. 내부 DNS 리졸루션 (Internal DNS):** 동일 노드 내 컨테이너 간 이름 기반(`container_id.picobox.local`) 통신을 지원하는 경량 DNS 인터페이스 매핑.

### [ ] Phase 6: 분산 시스템 가용성 및 보안 확보 (HA & Security)
* **6.1. gRPC mTLS (Mutual TLS):** 마스터 및 에이전트 간 양방향 인증서 기반 통신을 적용하여 비인가 노드의 접근 및 패킷 스니핑 방지.
* **6.2. 컨테이너 로그 영구 수집 (Persistent Logging):** 실행 중 혹시 종료된 컨테이너의 표준 입출력(stdout, stderr) 로그를 에이전트가 캡처하여 마스터에게 스트리밍하고 영구 저장(`logs/` 디렉토리 또는 SQLite DB)하는 기능.
* **6.3. HA 마스터 클러스터링 기반 (고가용성 플랜):** 중앙 통제 노드 장애 시, 상태 복원이 용이하도록 `store.SaveContainer` 동기화 및 엣지 노드의 재연결 백오프(Backoff) 강화.

### [ ] Phase 7: 관측성 및 대시보드 사용성 극대화 (Observability & UX)
* **7.1. 웹 터미널 (Web Terminal - Exec) 연동:** Next.js Dashboard 상에서 실행 중인 컨테이너 내부에 직접 WebSocket + pty로 연결하여 셸(Shell) 접근 구현.
* **7.2. 실시간 노드/컨테이너 메트릭 고도화:** CPU/Memory 리소스 사용량을 시계열 차트로 Dashboard에 표현.
* **7.3. 사용자 정의 템플릿 배포:** Docker Compose와 유사한 YAML/JSON 포맷 기반 다중 컨테이너 및 속성 일괄 배포 인터페이스 구성.

### [ ] Phase 8: 프로덕션 릴리즈 및 엔드투엔드 (E2E) 자동화
* **8.1. 릴리즈 및 환경 패키징 자동화:** GitHub Actions를 활용한 `picoboxd` 및 `picobox-master` 교차 컴파일 바이너리 릴리즈 자동 생성.
* **8.2. 프로비저닝 원클릭 스크립트:** 에지 디바이스나 베어메탈 서버에 노드를 추가할 때 1줄의 스크립트(`curl | bash`)만으로 Daemon이 서비스(`systemd`)로 등록되게 지원.
* **8.3. 100% E2E 통합 오토메이션 벤치마크:** [V-1]~[V-4] 시나리오가 CI상에서 무인으로 수행되도록 `.github/workflows/e2e.yml` 워크플로우를 최종 보완하여 완전한 무결성 검증 환경 확립.
