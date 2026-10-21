# 구현과 검증 상태

## 2026-10-21 허브 계정 오류 수정

허브 모드의 로컬 로그인 진입점, 재인증 카드의 복구 경로, 읽기 실패 뒤 끝나지 않는 전환 대기, 처리자가 없는 허브 자신의 전환 요청, 개인정보 숨김 뒤 남는 전환 성공 표시를 수정했다. 계정 관리는 사용자가 현재 연결의 정상 관리 화면에서 수행하며 CodexBar는 인증 성공을 추측하거나 자격을 복사하지 않는다. 기존 로컬 API 키 관리·내장 대시보드의 권한 경계는 유지한다.

m5m2의 집중 검사 53개(앱 Swift 19·공통 Swift 29·XCTest 5)가 통과했다. 마지막 검사는 읽기 오류 중 만료뿐 아니라 열린 메뉴의 observation·readiness 갱신도 확인한다. `make check`는 종료 0, SwiftLint는 3107파일 위반 0, 언어 검사는 22카탈로그·영어 2702키 기준 통과다. Build Pipeline 작업 `8418A87B-4E99-4234-A281-C53186B7F041`에 근거를 보존했다. 실제 OAuth·계정 전환·공급자 probe·Keychain·운영 설치·배포는 이 검증에 사용하지 않았다.

m5m1에는 머지 결과 149dee234를 같은 Developer ID·번들 식별자·업데이트 연결로 패키징한 0.78.0 빌드 17113을 설치했다. 이 기준의 집중 검사는 Swift 265개와 XCTest 5개가 통과했고, 별도 proof 환경이 필요한 합성 화면 3개와 선택적 네이티브 창 검사 1개는 실행하지 않았다. make check는 3107 Swift 파일 위반 0, 언어 22카탈로그·영어 2702키 기준 통과다. 위젯·번들 서명과 리소스 로딩·checkout을 읽을 수 없는 6초 격리 실행도 통과했다.

설치본의 Codex·Claude 설정에서 허브 계정 관리 버튼과 재인증 안내를 확인했다. Codex에서는 로컬 관리 계정 편집기가 숨겨지고, 관리 버튼은 기본 브라우저의 현재 허브 `#codex-set` 페이지를 열었다. 실제 계정 추가·OAuth·재인증 제출·계정 전환은 실행하지 않았다. 읽기 오류 뒤 대기 만료와 재시도 상태는 합성 회귀로 검증했다. 설치 전후 Codex 허브 주소 두 줄과 리뷰어·머지 대기열의 기존 오류 기록은 같았다.

m5m2·m1m1에도 같은 서명본 17113을 설치하고 새 프로세스 실행을 확인했다. 기기별 17110 복구본을 남겼으며 앱 식별자·서명 요구사항·업데이트 연결·허브 메타데이터가 유지됐다. 세 기기의 실행 파일 SHA-256이 같고, 실제 프로세스에 매핑된 실행 파일 inode도 각 설치본과 일치했다. 두 클라이언트의 앱·Helpers CLI 리소스 검사는 종료 0이며, 설치 후 1분 이상 실행을 유지했다. 설치 전후 계정 사본 파일은 같았다. 원격 화면은 m5m2 화면 공유의 사용자 로그인 단계에 막혀 검증하지 못했으므로, 프로세스·리소스 확인을 실제 설정 화면 확인으로 세지 않는다. 비밀값 없는 설치·복구·검증 기록은 로컬 `.dryforge/fleet-install/`에 보관한다.

mac-infra 감시 작업 재개·새 계정 상태의 기기 간 전달·실제 허브 교체는 완료로 세지 않는다. 이번 현재 허브 조회에서도 Claude 계정 둘의 주간 사용률은 모두 100%였고 계정 감시·정기 작업은 미적재였다. 감시 작업은 기존 실제 한도 회복과 apply·check·멱등 확인 조건을 유지한다. 세 기기의 기존 계정 배열은 같지만 2026-10-20T09:53:58Z 사본이므로 새 변경의 전달 증거가 아니다. m5m1의 Codex 허브 주소 두 줄과 리뷰어·머지 대기열의 오류 기록은 앞선 기준과 같았다. m1p1은 paused라 접속하지 않았다. 자세한 잔여 조건은 findings에 남겼다. 아래 17112 검증은 앞선 재열기 수정의 이력이다.

## 제공하는 기능

기존 앱은 공급자별 사용량·한도·지출, 계정 카드와 Opencodex 허브 계정 표시·전환을 제공한다. 새 API 키 관리는 공급자 계정 자격과 별도의 로컬 관리 연결을 사용한다.

로컬 관리의 역할·응답 해석·ID 대상 변경과 제한된 이름 변경 보조 실행기를 구현했다. 가짜 설치·관리 모듈로 정상·실패·이름 충돌·출력 누출을 검증했다. 실제 Bun 출력과 Node 출력의 차이도 회귀에 포함한다. 설정에 독립 Opencodex 항목과 경로 저장·토큰 복원·탐색 이력을 연결했다.

앱 수명의 변경 상태, 새 키 일시 전달, 후속 갱신 결과 분리와 클립보드 소유권 검사를 구현했다. 독립 집중 테스트 20개가 통과했다. 대시보드 창은 비영구 WebKit 세션·주소 정책·오류·재시도·닫기 후 해제와 외부 이동의 네이티브 확인을 구현했고 macOS 집중 테스트 18개가 통과했다.

앱 뿌리가 상태와 결과·창을 보관하고 설정 복귀 시 목록을 갱신한다. 경로 변경은 진행 중 변경·새 비밀값을 보존하며, 이전 연결의 늦은 응답과 열린 창은 무효화한다. 한국어·영어를 제공하고 다른 언어의 신규 문구는 영어 fallback으로 키 완전성을 유지한다.

## 최종 검증

문서와 외부 이동 확인 보완을 통합한 기준 36109eb0d에서 swift build, 요구한 집중 make test-fast 필터87개(앱 Swift61·공통 Swift19·XCTest7), CodexBarLinuxTests559개, make check, 전체 언어 검사, 이름 변경 보조 실행기 별도 oxlint, diff 검사가 모두 종료0이었다. 집중 필터의 XCTest에는 합성 화면3개가 포함되며 proof 환경을 켜 실제로 실행했고 skip이 없었다.

실제 PreferencesView의 Opencodex 선택 경로와 별도 pane·마스킹된 결과·역할/권한/서버 오류를 합성 자료로 확인했다. 실제 WebKit에 외부 리소스 없는 HTML을 띄워 창 재사용·재시도·해제를 확인했다. 전체 설정 루트의 오프스크린 제목/선택행 표현에는 캡처 한계가 있어 전체 창의 시각적 완성도를 검증했다고 보지 않는다. 운영 앱 시작·실계정·실제 키 생성/폐기·운영 대시보드 인증은 검증하지 않았다.

공통 테스트는 macOS 호스트에서 실행했다. 기존 Linux 데스크톱·Omarchy의 실제 GUI와 다른 기기의 동작을 새로 검증했다는 뜻이 아니다.

## 이후 범위

1. 다른 Mac의 원격 관리가 필요하면 원격 주체·서버 인증·기기별 권한부터 설계한다. 현재 client에는 로컬 관리 우회를 제공하지 않는다.
2. OpenClaw 자동 연결은 명시적 키 전달과 설정 갱신·복구·Gateway 동작의 별도 흐름이 필요하다.
3. loopback 요청의 키별 사용량 귀속은 인증을 건너뛰는 서버 경로를 먼저 정리해야 한다. 키 발급만으로 비용 분리를 보장하지 않는다.
4. 네이티브 공급자·모델 범위 편집과 키 교체는 별도 확인·권한 보존·교체 실패 복구를 설계한 뒤 확장한다. 현재 고급 관리는 기존 웹 대시보드를 사용한다.

## 적용 상태

최신 원격 0.78.0 변경을 보존한 뒤 로컬 gujo에 통합했다. 같은 Developer ID·번들 식별자·설정·업데이트 연결을 유지한 빌드 17113을 /Applications/CodexBar.app에 설치하고 새 프로세스 실행을 확인했다. 이전 설치본은 복구용으로 보관했다. 기능과 재열기 수정은 포크 gujo에 통합했다. 공개 릴리스·태그·feed 배포는 실행하지 않았다.

## 설치 전후 확인

최신 0.78.0 소스와 합친 결과에서 집중 테스트 92개(앱 Swift 66·공통 Swift 19·XCTest 7), 공통 테스트 565개, 빌드·정적·전체 언어·보조 실행기 lint 검사가 모두 종료 0이었다. 합성 화면 3개도 skip 없이 실행했다. 패키지와 위젯의 서명·번들 무결성, checkout을 읽을 수 없는 격리 환경의 리소스 로딩과 6초 실행 검사도 통과했다.

실제 Opencodex 상태는 hub·서버 실행 중이며, 운영 상태와 키 목록 응답을 제품 파서가 정상 해석했다. 키 3개의 메타데이터만 읽었고 생성·변경·폐기는 하지 않았다. 운영 대시보드는 기본 TLS 검증과 HEAD 요청에서 HTTP 200이었다. 웹 본문·쿠키·원시 응답은 기록하지 않았다. 빌드 17112에서 명시적 앱 재열기가 기존 설정 창을 표시하도록 보완했다. 관련 44개 테스트·make check·서명·격리 실행 검증을 통과했고, 설치본의 실제 Opencodex 설정과 키 3개 행, 내장 대시보드 온라인 화면을 확인했다. 창 닫기 뒤 Finder 재열기와 선택 pane 유지도 확인했다. 창 없는 첫 실행의 도구 선택 timeout은 재열기로 복구할 수 있다. 실제 로그인 입력·인증 거절 경로는 별도로 검증하지 않았다.

## 2026-10-21 follow-up prepared in PR #2

Remote Link clients reported their SSH data tunnel as `connection.managementUrl`; opening it as account management returned HTTP 404. PR #2 separates the browser's HTTPS management origin from that tunnel, supports a fleet-packaged default and an explicit provider setting, and explains missing configuration. The actual hub HTTPS origin returned HTML / HTTP 200 from both m1m1 and m5m2. The follow-up passed 49 focused tests and `make check` on m5m2. PR #2 merged as `eebd27843`; signed and notarized build 17114 was published and installed through Gujo Cloud Apps on m5m1, m5m2 and m1m1. Earlier build evidence above is retained as history. The source audit and screenshot are in [account-flow-audit-20261021.md](account-flow-audit-20261021.md).

## 2026-10-21 passive list follow-up

The hub and linked m1m1 CLI listed three Claude accounts, while CodexBar showed the stale snapshot's two. Clients now request a passive account list without the forbidden quota-refresh flag. Cached quota is retained only for a unique matching identity, remains dated and marked unavailable, and never substitutes stale membership or account state. The follow-up passed 87 focused Swift tests, six isolated synthetic pool-kernel tests and `make check` on m5m2. Roster reads, projection, compact layout expansion and switch-request targeting cover 12, 20 and 50 accounts; this is not a live throughput or full-roster failover proof. The server still limits one request to at most three account failovers within its shared send budget.

PR #3 merged as `3c27a6920e1722e75cf9412d40abc915b10dd9c6`. Signed, notarized and stapled build 17115 was published to the existing Sparkle feed; public verification and the ZIP contract passed. Gujo Cloud Apps installed it on m5m1, m5m2 and m1m1. All three run the same source and executable, and their actual app state mirrors now list three Claude accounts, matching each passive CLI list. Snapshot files remain unchanged; the paused snapshot jobs were not resumed. New-account OAuth and live load with ten or more real accounts were not performed by this session.
