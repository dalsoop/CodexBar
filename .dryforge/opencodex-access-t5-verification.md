# T5 문서와 합성 UI 검증 기록

작업 위치: `/Volumes/Build/m5m1/home/work/codexbar-gujo/.dryforge/worktrees/T5`
(요청 경로 `/Users/m5m1/work/codexbar-gujo/.dryforge/worktrees/T5`의 실제 경로).
브랜치: `dryforge/opencodex-access-t5`. 기준 통합 커밋: `4b33bfae6b6a126fdcc0bdf90183433024f8a30f`.
`git rev-parse --show-toplevel`로 위치를 먼저 확인하고 `AGENTS.md`를 읽었다.
제품 소스·Core·공급자 구현·로케일 카탈로그·Package.swift·루트 문서는 변경하지 않았다.

## 요구사항과 계획 작업의 연결

| 요구사항 | 문서/검증 작업 | 증거 |
| --- | --- | --- |
| R1 | 설정 진입·저장 토큰·독립 실행 파일 경로·로컬 역할 경계 설명 | configuration.md의 Opencodex 항목, 실제 PreferencesView 선택 경로 및 client/unknown 합성 화면, 기존 IntegrationTests/PreferencesSelectionTests |
| R2 | 목록 메타데이터·불완전/잘린 기록·알 수 없음/사용 없음·갱신 실패 설명 | pane-ko/stale-permission-ko 화면, 기존 StoreTests 및 공통 파서 테스트 |
| R3 | 명시적 생성·이름 검증·비밀값 전달/해제·클립보드 정책 설명 | created-masked-ko, 실제 닫기 버튼 접근성 액션 후 소유 참조 해제, 기존 ClipboardTests/StoreTests |
| R4 | 전체 ID·범위 보존·제한된 rename 보조 실행기·폐기 확인 설명 | 기존 공통 transport/rename 테스트와 StoreTests 성공 증거, 이번 화면에서는 실제 rename/revoke 금지 가짜 소스 |
| R5 | 중복 방지·응답 순서·확인 필요·고정 오류·변경/후속 조회 구별 설명 | stale/permission/stopped 화면, 기존 StoreTests/IntegrationTests |
| R6 | 내장 창·origin/TLS 제한·독립 비영구 세션·재인증 설명 | 실제 WebSession을 감싼 합성 HTML load, 창 소유자 재사용/닫기/재개방, 실제 DashboardView와 TLS 오류 화면, 기존 DashboardWindowTests/WebSessionTests |
| R7 | 공급자 계정과 키 구분·한국어/영어·기존 카탈로그 유지 | 한국어 픽셀 OCR/접근성 단언, 전체 로케일 검사, 기존 공급자 회귀 증거 |
| R8 | 운영/원격/배포·OpenClaw·loopback 귀속 제외 안내 | 실제 CLI·서버·Keychain·공개 클립보드·기본 앱 시작을 사용하지 않은 주입 테스트. git 변경 범위 확인 |
| R9 | 자체 빌드·새 UI 테스트·형식·언어·문서 검사 및 실제 실행 기록 | 아래 명령과 `/tmp/codexbar-access-t5` 로그/exit/json. 변경 없는 공통 게이트는 T4 증거 인계; 최종 통합 기준 게이트는 부모 담당 |

계획의 사용 안내는 R1~R8에, 합성 네이티브/웹 화면 검증은 R1~R7과 R9에,
명령·결과·한계 보고는 R8~R9에 연결한다. 운영 키 발급·소비·다른 기기 배포는 완료 기준에 포함하지 않는다.

## 실행 환경과 명령 기록

모든 스크립트는 다음 환경을 사용했다. 시스템 Python 3.9나 컴파일 산출물 복사는 사용하지 않았다.

```bash
export PATH=/opt/homebrew/opt/python@3.14/libexec/bin:$PATH
export PYTHONDONTWRITEBYTECODE=1
source Scripts/test_environment.sh
export CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS=1
```

`/tmp/codexbar-access-t5/run.py`가 명령마다 `<검사>.log`, `<검사>.exit`, `<검사>.json`에
실행 명령·작업 위치·시간·실제 종료 코드를 기록한다. 성공한 빌드를 문서 준비만을 위해 반복하지 않았다.

필수 공통 게이트의 기존 통과 증거는 `/tmp/codexbar-access-t4/handoff.json`과 각 로그/exit다.
T4 소스 커밋은 `400d408a8fb6a585e8c96b5dc6af4f984c6d59b2`이며 기준 통합에 포함되어 있다.
집중 게이트는 앱 Swift Testing 56개·공통 Swift Testing 19개·XCTest 4개,
공통 게이트는 559개가 실제 통과했다. `swift build`, `make check`, 전체 로케일 검사도 모두 종료 코드 0이었다.
T5가 이 공통 게이트를 다시 실행한 것으로 기록하지 않는다. 부모가 최종 통합 기준으로 요구된 전체 집합을 실행한다.

## 시행착오와 경계

초기 UI helper 컴파일은 XCTest autoclosure의 await와 NSObject의 직접 접근성 호출 오류로 실패했다 (`ui-initial`, exit 2).
첫 실제 렌더링은 3개 테스트 중 2개에서 총 10개 내용 단언이 실패했다 (`ui-render-red`, exit 2).
생성 결과 마스킹과 실제 닫기·해제 테스트는 이때도 통과했다.
비동기 TaskLocal 범위를 벗어난 AppKit 지연 렌더링은 테스트 기본 언어인 영어를 사용했고,
네이티브 Form은 보이는 텍스트 일부를 접근성 children에서 제공하지 않았다.
공유 defaults 변경이나 영어 허용으로 통과시키지 않았다. 비태스크 메인 루프의 한국어 override와
픽셀 OCR을 사용해 한국어 내용 단언을 유지했다. 제품 한국어 결함으로 단정하거나 제품 소스를 수정하지 않았다.
초기 문서 링크 검사는 생성 전 스크린샷 누락으로 실패했으며 최종 이미지 배치 뒤 다시 확인한다.
언어 범위 밖에서 surface를 먼저 구성하고 나중에 같은 root 값을 다시 설정하는 방식도 캐시된 영어를 남겨
`ui-proof`에서 종료 코드 2로 실패했다. 최종 방식은 합성 source를 `@MainActor` 클래스로 만들어 actor 간 전환을 없애고,
비태스크 한국어 범위 안에서 창/뷰 생성부터 촬영까지 수행한다. 전용 pane과 설정 루트의 성공 캡처 직전
`isRefreshing == false`, `canMutate == true`를 단언한다. 모델 플래그를 직접 바꾸지 않는다.
`ui-settled-ocr-space`는 `API 키`를 `API키`로 읽은 OCR 공백 차이 하나로 실패했다. 최종 내용 비교는
공백만 정규화하며 한국어 문구와 합성 키 이름을 모두 유지한다.

## 화면 증거와 남은 한계

- `screenshots-settled/pane-ko.png`: 실제 전용 pane. 합성 메타데이터와 불완전/잘린 기록 안내, 활성 생성/이름 변경/폐기 버튼.
- `created-masked-ko.png`: 새 결과의 이름·시각과 가린 비밀값. 표시/복사 버튼을 누르지 않고 실제 닫기 버튼의 접근성 액션을 실행해 비밀값 참조 해제를 확인한다.
- `client-ko.png`, `unknown-ko.png`, `stopped-ko.png`, `permission-ko.png`: 역할·중지·권한 오류와 비활성 변경 기능. 가짜 source의 목록 조회 0회, 대시보드 세션 생성 0회를 단언한다.
- `stale-permission-ko.png`: 이전 합성 행을 유지하면서 권한 오류/갱신 실패를 표시하고 변경을 금지한다.
- `dashboard-window-ko.png`, `dashboard-error-ko.png`: 실제 DashboardView를 별도 NSHostingView/창에 호스팅한 로컬 HTML/TLS 실패 화면. 주소·한국어 재시도·오류 문구가 읽힌다.
- `dashboard-html-ko.png`: 실제 비영구 WebView의 외부 리소스 없는 HTML snapshot.
- `settings-ko.png`: 실제 PreferencesView의 선택된 Opencodex 경로를 확인하는 보조 증거. 기존 오프스크린 NSVisualEffect/NSOutlineView 재질 캡처에서 선택 행의 텍스트가 보이지 않고 제목/탐색 영역 상단 일부가 crop된다. 이 이미지를 제품 문서의 대표 화면이나 전체 루트의 시각적 통과 증거로 사용하지 않는다. 운영 창을 띄우거나 재질/제품 소스를 변경해 우회하지 않았다.

WebSession은 테스트 소유의 실제 NSWindow와 비영구 WebView를 만들지만 창 표시 콜백은 no-op이다.
Session.load만 외부 리소스 없는 `loadHTMLString`으로 대체하며 URLRequest/서버/운영 대시보드를 열지 않는다.
동일 연결의 재개방은 실제 창 소유자와 같은 WebSession 한 개를 재사용하고, 닫을 때 native WebView/창 content를 해제한다.
재개방은 새 비영구 datastore를 만든다. 실제 인증·쿠키 소멸의 서버 측 효과는 검증하지 않는다.
DashboardView 캡처는 같은 컨트롤러 상태와 WebView를 별도 격리 창에 호스팅한 증거이며, 생산 창의 화면 표시/포커스 성공을 뜻하지 않는다.

기본 `CodexBarApp.main()`은 실제 설정·계정 초기화를 실행하므로 호출하지 않았다.
패키지 앱 전체 진입, 운영 창 활성화/포커스, 실계정 인증, 실제 키 생성/이름 변경/폐기, 실제 소비, 원격 Mac 배포는 미검증이다.
공개 클립보드·Keychain·계정/probe·실제 ocx status/list도 사용하지 않았다.
`compile_and_run.sh`, `package_app.sh`, 설치본 교체·프로세스 종료·push/deploy를 실행하지 않았다.
외부 라이브러리는 추가하지 않았고 OCR은 macOS 기본 Vision 프레임워크만 사용한다.


## 최종 실행 결과

최종 `ui-settled`는 **종료 코드 0, XCTest 3개/실패 0/skip 0**이다.
성공 pane/루트의 안정 상태, 한국어 내용, 오류 상태, 마스킹된 결과의 실제 닫기와 비밀값 해제,
실제 비영구 WebSession의 창 재사용/닫기/새 datastore를 확인했다.
다른 타깃의 `Executed 0 tests` 출력은 추가 테스트 통과 수로 세지 않았다.

PNG 11개를 `/tmp/codexbar-access-t5/screenshots-settled`에 보관했다.
이 중 제한이 있는 설정 루트 이미지를 제외한 10개만 `docs/screenshots/opencodex-access`에 반영했다.
모두 개별 2 MiB 미만이며 `screenshots-manifest.json`에 크기·해상도·SHA-256을 기록했다.
생성 결과는 항상 가린 상태로 촬영했고 공개 클립보드를 쓰거나 비밀값을 표시하지 않았다.

아래 명령은 앞서 명시한 환경에서 실제 실행되었다. 각 증거 이름은 `/tmp/codexbar-access-t5/<이름>.{log,exit,json}`이다.

| 실제 명령 | 종료 코드 | 증거 이름 |
| --- | --- | --- |
| `git rev-parse --show-toplevel` | 0 | `worktree` |
| `swift build` | 0 | `build` |
| `CODEXBAR_OPENCODEX_ACCESS_PROOF_DIR=/tmp/codexbar-access-t5/screenshots-settled make test-fast FILTER=OpenCodexAccessScreenshotRenderTests` | 0 | `ui-settled` |
| `/Users/m5m1/work/codexbar-gujo/.dryforge/worktrees/T1/.build/lint-tools/bin/swiftformat --lint --cache ignore Tests/CodexBarTests/OpenCodexAccessScreenshotRenderTests.swift` | 0 | `scoped-format-final` |
| `/Users/m5m1/work/codexbar-gujo/.dryforge/worktrees/T1/.build/lint-tools/bin/swiftlint lint --strict --no-cache Tests/CodexBarTests/OpenCodexAccessScreenshotRenderTests.swift` | 0 | `scoped-lint-final` |
| `node Scripts/check-app-locales.mjs` | 0 | `locales` |
| `node Scripts/docs-list.mjs` | 0 | `docs-list` |
| `node Scripts/check-documentation-links.mjs` | 0 | `docs-links-final` |
| `python3 /tmp/codexbar-access-t5/check_evidence.py` | 0 | `evidence-check` |
| `git diff --check` | 0 | `diff-check` |


T4에서 인계받은 요구된 게이트의 실제 명령과 종료 코드(실행 위치는 T4):

| 실제 명령 | 종료 코드 | 기존 증거 |
| --- | --- | --- |
| `make test-fast FILTER='OpenCodexAccess|OpenCodexDashboard|PreferencesSelectionTests|OpenCodexHubCardTests|OpenCodexHubClaudeCardTests|OpenCodexHubCodexNativeStateTests|StatusMenuOpenCodexHubAccountsTests|ClaudeSwapOpenCodexSwitchTests'` | 0 | `/tmp/codexbar-access-t4/focused.log` |
| `CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS=1 swift test --filter CodexBarLinuxTests` | 0 | `/tmp/codexbar-access-t4/linux.log` |
| `make check` | 0 | `/tmp/codexbar-access-t4/check.log` |

이 인계는 T5 변경 이후의 최종 통합 게이트 실행을 대신하지 않는다.
부모가 최종 기준 브랜치에서 요구 집합을 실행한다. 전체 앱/운영 인증 미검증과 루트 캡처 한계는 위에 명시했다.
제품 소스 수정 요청이 필요한 결함은 발견하지 않았다. 변경은 문서·합성 UI 테스트·화면 증거·이 기록에 한정한다.
