# 구성 요소와 데이터 이동

CodexBar 앱은 설정과 사용량 상태를 소유하고 Core의 공급자 조회·해석 결과로 메뉴·계정 카드·알림을 갱신한다. CLI도 같은 Core를 사용하지만 앱의 창이나 전역 UI 상태에는 의존하지 않는다. WidgetKit 확장은 앱이 게시한 공유 스냅샷을 읽으며 공급자 인증과 관리 변경을 직접 수행하지 않는다.

| 구성 요소 | 역할과 의존 방향 |
| --- | --- |
| CodexBar | SwiftUI·AppKit 설정과 메뉴, UsageStore·SettingsStore, Core 및 공통 갱신 정책 사용 |
| CodexBarCore | 공급자 조회·해석·설정 저장 계약·프로세스 실행과 Opencodex 관리, 앱 UI에 의존하지 않음 |
| CodexBarCLI | Commander 명령·출력, Core 사용 |
| CodexBarWidget | WidgetKit timeline과 공유 스냅샷 표시, Core 사용 |
| CodexBarClaudeWatchdog | Claude PTY 자식 프로세스 수명 보조, UI 상태 소유 안 함 |
| CodexBarClaudeWebProbe | 명시적 웹 진단 도구, Core의 웹 조회 사용 |
| AdaptiveRefreshCore | Foundation 기반 갱신 결정표, 앱과 재현 도구가 공유 |
| AdaptiveReplayKit | 명시적 trace로 정책을 재현, 공통 정책만 사용 |
| AdaptiveReplayCLI | 재현 인수·출력, ReplayKit 사용 |
| CSQLite3 | Linux 시스템 SQLite 헤더·링크 연결 |
| Integrations/Linux | Qt C++·QML 창·polling·비용·알림·같은 사용자 IPC, Swift CLI의 JSON 조회 사용 |
| Integrations/Omarchy | Quickshell 막대·popup, Linux 데스크톱의 IPC snapshot 사용 |
| WidgetExtension | CodexBarWidget 소스를 공유하는 Xcode app-extension 포장, Core 의존 |

앱의 일반 조회 흐름은 갱신 계기 → UsageFetcher와 공급자별 probe → UsageStore의 공급자별 표현 스냅샷 → 메뉴·설정 카드·위젯 게시다. 공급자 설정은 descriptor에 등록된 타입별 스냅샷으로 전달하며 앱과 CLI의 자격 선택 정책은 각각의 진입점에서 결정한다. 카드가 원시 웹 자료와 조정된 계정 상태를 별도로 합쳐 서로 다른 신원을 표시하지 않게 공통 표현 입력을 사용한다.

사용량 비용 저장소는 정규화한 데이터베이스 위치별 직렬 실행기를 공유한다. 서로 다른 데이터베이스 작업은 같은 SQLite 잠금을 기다리지 않으며 일반 앱 조회는 별도의 scan queue를 사용한다. 비용 결과의 현재 설정 범위·리비전·확인된 빈 결과는 같은 게시 상태에서 선택한다. Workspaces와 위젯은 필요한 스냅샷만 읽는다.

로그인 실행기는 공급자별 실행 파일·환경 선택과 공통 브라우저 대기 프로세스 수명을 분리한다. 공통 프로세스 계층은 종료·기한·출력 한도와 자식 정리를 담당하고 각 공급자가 사용자 복구 문구를 결정한다. 계정 로그인과 Opencodex 데이터 키 발급은 서로 다른 경로다.

Opencodex 설정은 기존 공급자 계정 카드와 별도의 관리 상태를 사용한다. 앱 수명의 상태가 네이티브 변경 하나와 생성 결과를 소유하며 설정 뷰의 생성·소멸은 변경 작업의 수명을 바꾸지 않는다. Core가 실행 파일 탐색·고정 CLI 호출·상태와 메타데이터 해석·역할과 주소 정책을 제공한다.

키 생성의 대표 흐름은 사용자 클릭 → 최신 로컬 역할 확인 → 기존 ocx 생성 명령 → 응답 검증 → 일시 결과 화면 → 메타데이터 목록 갱신이다. 관리 인증은 Opencodex 프로세스 안에서 처리한다. 비밀값은 결과 전달에만 사용하고 공급자 설정·미러·공유 스냅샷으로 보내지 않는다.

이름 변경은 같은 설치의 관리 클라이언트를 제한된 번들 보조 실행기에서 재사용한다. 정확한 ID와 이름만 서버에 보내며 지원 설치가 아니면 이 변경을 제공하지 않는다. CodexBar에 별도 키 저장소나 발급 서버를 만들지 않는다.

대시보드는 검증한 상태 주소를 별도 WebKit 창에 연다. 전용 비영구 웹 저장소는 창 수명에 묶인다. 같은 origin 이동은 WebKit에 남기고 다른 origin 탐색은 창 소유자가 취소한다. 외부 최상위·새 창 요청의 안전한 주소를 보류한 뒤 네이티브 안내 버튼을 통해서만 시스템 브라우저로 전달하며, 웹 탐색 종류를 사용자 입력의 증거로 취급하지 않는다. 웹과 네이티브 모델 사이에는 비밀 브리지가 없으며 웹에서 변경한 내용은 설정으로 돌아와 목록을 다시 읽어 반영한다. 서버·웹 인증의 정본은 기존 Opencodex다.

Linux에서는 데스크톱 backend 하나가 Swift CLI를 통해 공급자 자료를 조회하고 Qt 창·tray를 갱신한다. Omarchy 어댑터는 backend의 비공개 같은 사용자 소켓에서 표시 snapshot만 받는다. backend와 어댑터는 HTTP 서버를 새로 열지 않으며 공급자 인증 자료는 CLI 쪽에 남긴다. macOS의 새 Opencodex 키 화면은 이 경로에 추가되지 않는다.
