# CODEX RAN BOOTSTRAP BRIEF

## 목적
이 저장소의 **전체 구조를 먼저 설계**하라. 지금 단계의 목표는 기능 구현이 아니라,

1. 시스템 경계와 실패 도메인을 명확히 하고,
2. OTP 앱 경계와 supervision tree를 설계하고,
3. southbound / ops / artifact 흐름을 분리하고,
4. 이후 구현이 가능한 수준의 **repo skeleton + 설계 문서 + 초기 인터페이스**를 만드는 것이다.

불확실한 부분은 숨기지 말고 **명시적 가정(assumptions)** 으로 적어라.

---

## 프로젝트 배경
이 프로젝트는 **5G SA RAN**을 대상으로 하며, 다음 범위를 우선 설계한다.

- **CU-CP**
- **CU-UP**
- **DU-high**
- **split 7.2x** 전제
- **RU 쪽에 low-PHY**가 있다고 가정
- DU-high 아래 southbound는 **pluggable backend** 구조로 설계
- 초기 southbound 대상은 두 가지
  - `local_du_low`: 우리가 직접 만드는 native 7.2x backend
  - `aerial_backend`: 향후 **NVIDIA Aerial cuBB/cuPHY** 연결용 backend
- 나중에 scheduler 쪽은 **optional cuMAC backend** 확장 가능해야 함

운영/자동화 측면에서는 다음을 전제로 한다.

- **OpenAI Symphony + Codex** 를 사용해 운영 흐름을 오케스트레이션할 수 있어야 함
- **MCP는 사용하지 않음**
- 대신 **skills.sh / skill-like workflow + 내부 `ranctl` 실행기** 구조를 사용
- 모델/에이전트는 **즉각적인 운영 action** 을 제안하고 실행할 수 있어야 하지만,
  **slot/FAPI hot path** 에는 절대 들어가면 안 됨

---

## 설계 철학
다음 원칙은 강제 사항이다.

1. **Control-plane / orchestration / ops-plane / hot-path를 분리**하라.
2. **모델은 의사결정과 절차 선택까지만** 담당하고, 실제 변경은 `ranctl` 같은 결정적 실행기가 담당해야 한다.
3. **DU-high는 BEAM 중심**으로 설계하되, timing-critical southbound path는 **native sidecar / port 경계**를 우선 검토하라.
4. **Aerial 호환성은 day-1 interface requirement** 로 반영하되, Aerial 전용 구현 세부사항이 core 설계를 오염시키면 안 된다.
5. **local backend와 aerial backend를 같은 canonical contract 아래에 둬라.**
6. **모든 운영 action은 precheck / dry-run / apply / verify / rollback** 흐름을 가져야 한다.
7. **실패 도메인(failure domain)** 은 최소한 association, UE subtree, cell-group, backend gateway 단위로 분리하라.
8. 지금은 **MVP 설계 우선**이다. multi-DU, handover, advanced multi-cell coordination, full PHY 구현은 후순위다.

---

## 하드 제약
아래 제약은 절대 위반하지 마라.

- **SA only**
- 초기 목표는 **single DU / single cell / single UE attach+ping 가능 구조**
- **split 7.2x** 기준으로 설계
- **DU-high만 BEAM에서 직접 책임**지고, low-PHY/FH/timing hard RT path는 native 쪽으로 밀어낼 수 있어야 함
- **slot/FAPI hot path에 LLM or agent logic 금지**
- **MCP 금지**
- **skills + `ranctl` + Codex/Symphony** 구조만 사용
- backend switch는 **pre-provisioned target 사이의 controlled failover** 만 허용
- direct raw shell automation을 남발하지 말고, **변경은 `ranctl` contract 아래로 집약**하라
- direct copy-porting이 아니라 **clean-room architecture** 중심으로 문서화하라

---

## Codex의 역할
너는 지금부터 **수석 시스템 아키텍트 + repo bootstrapper** 역할을 한다.

해야 하는 일:

1. 언어/빌드 구조를 결정한다.
   - 후보:
     - Elixir umbrella 중심 + 필요한 곳에 Erlang
     - pure Erlang/rebar3 중심 + Elixir 운영층
     - hybrid
   - 셋 중 하나를 추천하고 이유를 남겨라.

2. repo 최상위 구조를 설계한다.

3. OTP application 경계를 설계한다.

4. supervision tree와 failure domain을 설계한다.

5. DU-high southbound canonical contract를 설계한다.

6. `ranctl` action contract를 설계한다.

7. Symphony/Codex/skills 기반 ops architecture를 설계한다.

8. 문서, stub, config 예시, 초기 TODO/ticket 목록을 만든다.

하지 말아야 할 일:

- 아직 PHY/L1 runtime을 실제 구현하지 마라.
- 아직 full ASN.1 codec 구현을 하지 마라.
- 실제 eCPRI/O-RAN FH stack을 구현하지 마라.
- Aerial 내부 구현을 추정으로 채우지 마라.
- 동작하지 않는 화려한 코드보다, **명확한 경계와 문서**를 우선하라.

---

## 우선 결정해야 할 핵심 질문
다음 질문에 먼저 답하고, 그 답을 ADR이나 설계 문서에 남겨라.

1. 이 repo는 **Mix umbrella** 로 갈지, **rebar3 중심**으로 갈지, **hybrid** 로 갈지?
2. protocol/transport/OTP 관리에 유리한 영역은 Erlang, 개발 UX에 유리한 영역은 Elixir로 나눌 것인지?
3. `ran_fapi_core` 의 canonical internal representation(IR)은 어떤 형태가 가장 좋은지?
4. `fapi_rt_gateway` 는 Port, NIF, 외부 daemon 중 무엇이 1차 선택인지?
5. Aerial backend와 local backend가 공유해야 하는 최소 공통 contract는 무엇인지?
6. `scheduler_host` 를 나중에 `cpu_scheduler` 와 `cumac_scheduler` 로 갈아끼울 수 있게 하려면 어떤 interface가 필요한지?
7. `ranctl` 의 object model은 무엇인지? (`cell_group`, `backend`, `change`, `incident`, `verify_window` 등)
8. skills는 repo 내부 문서/스크립트와 어떤 관계를 맺어야 하는지?
9. 어떤 파일은 persistent instruction(`AGENTS.md`)에 들어가고, 어떤 파일은 task brief로 남겨야 하는지?

---

## 기대 산출물
다음 산출물을 repo 안에 생성하라. 파일명은 합리적으로 바꿔도 되지만, 구조는 유지하라.

### 1) 최상위 문서
- `README.md`
- `AGENTS.md`
- `docs/architecture/00-system-overview.md`
- `docs/architecture/01-context-and-boundaries.md`
- `docs/architecture/02-otp-apps-and-supervision.md`
- `docs/architecture/03-failure-domains.md`
- `docs/architecture/04-du-high-southbound-contract.md`
- `docs/architecture/05-ranctl-action-model.md`
- `docs/architecture/06-symphony-codex-skills-ops.md`
- `docs/architecture/07-mvp-scope-and-roadmap.md`
- `docs/architecture/08-open-questions-and-risks.md`

### 2) ADR
- `docs/adr/0001-repo-build-structure.md`
- `docs/adr/0002-beam-vs-native-boundary.md`
- `docs/adr/0003-canonical-fapi-ir.md`
- `docs/adr/0004-ranctl-as-single-action-entrypoint.md`
- `docs/adr/0005-ops-automation-with-skills-not-mcp.md`

### 3) 앱/디렉터리 스켈레톤
최소한 아래 수준의 디렉터리 또는 앱 경계를 제안하고, 가능한 경우 stub도 만든다.

```text
apps/
  ran_core/
  ran_cu_cp/
  ran_cu_up/
  ran_du_high/
  ran_fapi_core/
  ran_scheduler_host/
  ran_action_gateway/
  ran_observability/
  ran_config/
  ran_test_support/

native/
  fapi_rt_gateway/
  local_du_low_adapter/
  aerial_adapter/

ops/
  skills/
    ran-observe/
    ran-capture-artifacts/
    ran-freeze-attaches/
    ran-drain-cell-group/
    ran-switch-l1-backend/
    ran-restart-fapi-gateway/
    ran-rollback-change/
  symphony/
    WORKFLOW.md

bin/
  ranctl

config/
  dev/
  lab/
  prod/

examples/
  incidents/
  ranctl/
```

### 4) skills skeleton
각 skill 디렉터리에 최소한 다음을 포함하라.

- `SKILL.md`
- 필요하면 `scripts/*.sh`
- 필요하면 `references/*.md`

하지만 scripts는 **직접적인 raw shell automation** 이 아니라,
가능한 한 `bin/ranctl` 을 호출하는 형태로 설계하라.

### 5) `ranctl` 설계 문서 + 예시
`ranctl` 은 실제 실행기다. 아래 subcommand와 JSON 입출력 예시를 제시하라.

- `precheck`
- `plan`
- `apply`
- `verify`
- `rollback`
- `observe`
- `capture-artifacts`

아래 공통 필드도 포함하라.

- `scope`
- `cell_group`
- `target_backend`
- `change_id`
- `incident_id`
- `dry_run`
- `ttl`
- `reason`
- `idempotency_key`
- `verify_window`
- `max_blast_radius`

### 6) 초기 ticket 목록
- `docs/backlog/initial-tickets.md`
- 최소 **30개 이상**
- 문서 작업, interface 설계, stub 생성, config 정리, test harness, ops workflow를 포함
- 티켓은 **MVP 우선순위** 기준으로 정렬

---

## 설계 대상 시스템의 권장 방향
아래 방향을 기본값으로 삼되, 필요하면 반박하고 더 나은 대안을 제시하라.

### 권장 방향 A: 언어/빌드
- **Mix umbrella** 를 1순위로 검토
- protocol/transport/OTP 코어는 **Erlang 또는 Elixir 중 적합한 언어 선택 가능**
- 운영 도구/설정/테스트 지원은 Elixir 친화적으로 가도 됨
- 단, 선택 근거를 남겨라

### 권장 방향 B: southbound
- `ran_du_high` 는 직접 raw backend를 알지 않는다
- `ran_fapi_core` 가 canonical IR을 만든다
- 실제 southbound transport는 `native/fapi_rt_gateway` 가 처리한다
- backend profile은 대략 다음을 상정한다
  - `local_fapi_profile`
  - `aerial_fapi_profile`
  - `stub_fapi_profile`

### 권장 방향 C: scheduler
- `scheduler_host` 라는 추상 경계를 둔다
- 초기 구현은 `cpu_scheduler`
- 나중에 `cumac_scheduler` 추가 가능해야 한다

### 권장 방향 D: ops
- Symphony/Codex는 incident orchestration에 사용
- skill은 절차 지식 + 얇은 실행 wrapper
- 실제 변경은 `ranctl`
- destructive action은 approval or explicit gate 전제

---

## 반드시 문서화해야 할 구조
다음은 문서에 **ASCII diagram** 으로라도 반드시 포함하라.

1. 전체 context diagram
2. CU-CP / CU-UP / DU-high / southbound / native gateway 경계
3. OTP supervision tree
4. failure domain diagram
5. `ranctl` action lifecycle
6. Symphony/Codex/skills/ranctl 실행 흐름
7. backend switch / rollback 흐름

---

## 산출물 품질 기준
산출물은 아래 기준을 만족해야 한다.

1. **모호한 문장을 줄이고 인터페이스를 명시**할 것
2. 가능하면 표 대신 **구조화된 목록과 code block** 으로 정리할 것
3. 실제 구현 전에 위험 지점을 분리해둘 것
4. 미래 확장(Aerial, cuMAC, multi-cell)을 고려하되 MVP를 망치지 말 것
5. "나중에 생각"으로 넘기지 말고, 최소한 placeholder contract를 둘 것
6. repo를 처음 보는 사람이 30분 안에 전체 구조를 이해할 수 있게 할 것
7. 문서와 디렉터리 스켈레톤이 서로 충돌하지 않게 할 것

---

## 작업 순서
아래 순서를 따르라.

### Phase 1 — 이해와 결정
- 이 brief를 요약한다
- 핵심 architecture decision 5~10개를 먼저 적는다
- build 구조와 앱 경계를 결정한다

### Phase 2 — 문서 우선 설계
- `README.md`
- `AGENTS.md`
- architecture docs
- ADR
를 먼저 만든다

### Phase 3 — repo skeleton
- 디렉터리 구조 생성
- 최소 stub module / placeholder file 생성
- config skeleton 생성

### Phase 4 — ops skeleton
- `ops/skills/*`
- `ops/symphony/WORKFLOW.md`
- `bin/ranctl` placeholder
- examples

### Phase 5 — backlog
- initial tickets 생성
- 우선순위, 위험도, 의존성까지 남긴다

---

## AGENTS.md에 들어가야 하는 내용
`AGENTS.md` 는 길게 쓰지 말고, **항상 적용되는 저장소 규칙만** 넣어라.
예:

- slot/FAPI hot path에 agent logic 금지
- 모든 변경은 `ranctl` 경유
- destructive action은 approval gate 필요
- docs 먼저, runtime 구현은 나중
- interface 변경 시 ADR 또는 architecture doc 업데이트
- stub는 TODO와 future contract를 명시

반대로 이 brief 전체를 `AGENTS.md` 로 복붙하지는 마라.

---

## Codex에게 요구하는 응답 방식
작업을 시작할 때 다음 형식으로 진행하라.

1. 먼저 10~20줄 정도로 **설계 전략 요약**을 적는다.
2. 그 다음 **제안 repo tree** 를 보여준다.
3. 그 다음 생성/수정할 파일 목록을 적는다.
4. 그 다음 실제 파일 생성/수정을 시작한다.
5. 끝날 때는
   - 만든 파일 목록
   - 핵심 결정사항
   - 남은 리스크
   - 다음 추천 작업 5개
   를 요약한다.

---

## 구현보다 설계가 우선인 항목
지금은 아래 항목을 **stub + 문서 + contract** 수준에서 멈춰라.

- ASN.1 codec
- SCTP live stack
- GTP-U runtime
- full MAC scheduling logic
- real DU-low implementation
- real Aerial integration
- real cuMAC integration
- real Symphony hooks beyond skeleton

---

## 최종 목표
이 작업의 최종 목적은 다음 상태를 만드는 것이다.

- 이 repo를 처음 연 사람이 전체 구조를 이해할 수 있다
- Codex가 이후 단계에서 **일관된 방식으로 구현을 확장**할 수 있다
- BEAM core / native RT path / ops automation 경계가 명확하다
- split 7.2x, local DU-low, NVIDIA Aerial, future cuMAC, Symphony/Codex/skills/`ranctl` 가 **하나의 coherent architecture** 아래 정리된다

---

## 시작 지시문
이제 위 brief를 바탕으로 다음을 수행하라.

1. build structure를 선택하고 근거를 남겨라
2. 전체 repo tree를 설계하라
3. architecture docs와 ADR을 먼저 작성하라
4. 그 다음 skeleton/stub를 생성하라
5. 마지막에 initial backlog를 작성하라

불확실한 점은 숨기지 말고 문서의 `Assumptions`, `Open Questions`, `Deferred Decisions` 섹션에 기록하라.
