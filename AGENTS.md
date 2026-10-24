# CodexBar gujo 포크

여러 모델 공급자의 사용량·한도·지출과 계정 상태를 보여 주는 macOS 메뉴 막대 앱이며 Linux CLI·Qt 데스크톱도 제공한다. `dalsoop/CodexBar`의 `gujo`는 개인 Mac에서 Opencodex 허브 계정과 API 키를 함께 관리하는 포크다. SwiftPM·Swift 6 엄격한 동시성을 사용하며 최소 macOS는 14다.

## 프로젝트 구조

```text
./
├── AGENTS.md → 작업 시작점과 핵심 경계
├── CLAUDE.md → 같은 내용의 Claude 작업 시작점
├── docs/
│   ├── architecture.md → 구성 요소와 데이터 이동
│   ├── business-rules.md → 계정·키·사용 기록의 의미
│   ├── security.md → 로컬 관리 권한과 비밀값 수명
│   ├── standards.md → 구현·검증·저장소 작업 규칙
│   ├── engineering-notes.md → 잘못된 키 선택 등 확인된 함정
│   ├── operations.md → 빌드·안전한 검증·배포 경계
│   ├── contracts.md → CLI와 Opencodex 연결 계약
│   └── tracking/
│       ├── status.md → 구현·검증 상태와 남은 범위
│       ├── decisions/ → 선택 이유와 대안
│       │   └── index.md → 결정 기록 목록
│       └── findings.md → 현재 해결하지 못한 문제
├── Integrations/
│   ├── Linux/AGENTS.md → Qt 데스크톱·로컬 IPC
│   └── Omarchy/AGENTS.md → Quickshell 표시 어댑터
├── WidgetExtension/AGENTS.md → WidgetKit 확장 포장
└── Sources/
    ├── CodexBar/AGENTS.md → 설정·창·사용량 UI
    ├── CodexBarCore/AGENTS.md → 공급자 해석·관리·실행 계층
    ├── CodexBarCLI/AGENTS.md → 명령행 출력과 설정
    ├── CodexBarWidget/AGENTS.md → 공유 스냅샷 표시
    ├── CodexBarClaudeWatchdog/AGENTS.md → Claude PTY 보조 프로세스
    ├── CodexBarClaudeWebProbe/AGENTS.md → 웹 진단 도구
    ├── AdaptiveRefreshCore/AGENTS.md → 갱신 정책의 공통 정본
    ├── AdaptiveReplayKit/AGENTS.md → 오프라인 재현 입력과 실행
    ├── AdaptiveReplayCLI/AGENTS.md → 재현 명령행 진입점
    └── CSQLite3/AGENTS.md → Linux 시스템 SQLite 연결
```

## 먼저 지킬 경계

- 공급자 신원·계정·자격은 다른 공급자의 카드에 섞지 않는다.
- 실제 Keychain이나 실계정 조회는 명시적 요청 없이 실행하지 않는다. 가짜 저장소와 억제된 테스트 환경을 사용한다.
- Never run tests/checks or ad-hoc validation that can display macOS Keychain prompts;
  use parser tests, stubs, test stores, or `KeychainNoUIQuery`.
- API 키 비밀값과 관리 자격을 로그·설정·미러·검증 이미지에 남기지 않는다. 역할이 불명확하면 관리를 허용하지 않는다.
- 포크 수정은 포크에서만 준비한다. 원본 저장소 쓰기, 운영 앱 교체, 배포는 별도 승인 없이 실행하지 않는다.

## 작업 전 확인

`docs/standards.md`, `docs/engineering-notes.md`와 해당 모듈의 `AGENTS.md`를 읽는다. 인증·키 작업 전에는 `docs/security.md`의 역할·비밀값 경계를 확인하고, 이름 변경 전에는 기존 CLI의 이름 재해석 문제를 확인한다. 설정 저장·이전 작업은 메모리 기본 설정과 합성 홈을 주입하는 기존 패턴을 먼저 읽는다. CI·테스트 실행기를 바꾸기 전에는 `docs/DEVELOPMENT.md`의 direct-test와 SwiftPM 캐시 계약을 읽는다.

## 문제 처리

다른 공급자 신원 노출, 잘못된 ID의 키 변경, 비밀값 기록, 관리 역할 우회, 사용자 설정 손상 가능성이 발견되면 변경을 멈추고 사용자에게 즉시 알린다. 현재 범위에서 해결할 수 없는 다른 문제는 재현 조건·영향·미해결 이유를 `docs/tracking/findings.md`에 기록한다.
