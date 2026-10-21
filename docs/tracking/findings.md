# 미해결 문제

허브 계정 목록 감시 작업의 재가동과 새 계정 추가·재인증 결과의 기기 간 전달은 아직 미검증이다. 2026-10-21 설치 확인 중 현재 허브의 읽기 전용 조회에서도 Claude 계정 둘의 주간 사용률은 모두 100%였다. `net.ranode.mac-infra.hub-accounts`와 `net.ranode.mac-infra.periodic`은 미적재였다. 실제 한도 회복과 정상 apply·check·두 번째 apply 확인 뒤에만 운영을 재개하는 기존 조건을 유지한다. 보고된 리셋 시각은 회복 보장이 아니며, 예정된 전환 시험이 끝난 뒤에만 실제 허브 교체를 연습하는 기존 조건도 유지한다. 이번에는 감시 작업·라우팅·실계정 로그인을 변경하지 않았다.

m5m1·m5m2·m1m1 모두 최신 머지본 149dee234의 빌드 17113을 설치했다. m5m1은 실제 관리 화면 연결과 재인증 안내를 확인했다. 두 클라이언트는 같은 서명·실행 파일 해시와 새 프로세스의 실행 파일 매핑, 앱·Helpers CLI 리소스 로딩, 1분 이상 실행을 확인했지만 실제 설정 화면은 미검증이다. m5m2 화면 공유 연결은 사용자 이름·암호 입력을 요구해 그 단계에서 멈췄다. 원격 사용자 로그인 후 두 기기의 설정·관리 화면 연결을 각각 확인해야 한다. 암호를 대화나 검증 기록으로 수집하지 않았고 원격 접근 권한도 바꾸지 않았다.

세 기기의 2026-10-20T09:53:58Z 계정 사본은 공급자별 계정 배열 지문이 일치했고, 두 클라이언트는 설치 전후 사본 파일도 같았다. 전체 providers에는 허브와 클라이언트의 전환 권한 차이가 있으므로 이를 같은 자료로 정규화하지 않고, 계정 배열만의 대조라고 기록한다. 오래된 사본의 일치는 새 변경의 전달 성공이 아니다. m1p1은 inventory의 paused 역할을 존중해 접속·배포하지 않았다.

전체 PreferencesView를 표시 순서에 올리지 않은 NSWindow에서 cacheDisplay로 촬영하면 위쪽 제목이 잘리고 선택한 sidebar 행의 문자·재질이 누락된다. 같은 기능을 별도 pane으로 호스팅하면 한국어 내용과 동작 버튼은 정상이며 검사도 통과한다. 이 현상만으로 운영 앱의 표시 결함이라고 판단할 수 없다.

영향은 앞선 합성 검사에서 전체 설정 창을 촬영하는 방식에 한정된다. 모델·선택 경로·창 재사용·비밀값 해제와 별도 pane의 내용 검증을 대신 실패로 보지는 않지만, 이를 전체 앱 시작 검증으로 확대하지 않는다. 이 합성 검사에서는 실제 설정·계정 초기화를 포함하는 기본 앱 시작을 실행하지 않았다. 이후 승인된 운영 설치에서 확인한 m5m1의 실제 창과 두 클라이언트의 프로세스 실행은 위에 별도로 기록했으며, 합성 캡처의 한계나 원격 화면 미검증을 해소한 것으로 합치지 않는다.

## 메뉴 막대 앱의 화면 접근 복구

빌드 17111에서는 설치본이 `LSUIElement=true`인 `UIElement`로 실행되고 설정을 열 때만 일반 앱으로 전환됐다. untitled 창 열기는 거절하면서 명시적 재열기 처리는 없었으므로, 화면 제어 도구가 실행 중인 앱을 다시 열어도 창이 생기지 않고 약 5초 뒤 `-10005: timeoutReached`로 끝났다. 프로세스 표본에서는 주 스레드가 정상 AppKit 이벤트 루프에서 대기했다. 별도의 `native pipe closed before response`는 화면 제어 세션 초기화로 복구했다. 도구 내부의 정확한 대기 조건은 확인하지 못했다.

빌드 17112는 `applicationShouldHandleReopen`에서 기존 설정 창을 열고 선택한 pane을 유지한다. 초기화 전에 들어온 재열기는 보관하고 기본 설정이 준비되면 한 번만 처리한다. 빈 SwiftUI Settings 창의 자동 열기 거절은 유지한다. 관련 44개 테스트와 make check, 서명·격리 실행 검증이 통과했다.

실제 설치본은 창 없는 첫 시작 뒤 도구에서 다시 열자 약 1.2초 안에 설정 접근성을 반환했다. Opencodex 화면에서 키 3개의 행과 관리 버튼을 읽고 내장 대시보드의 실제 온라인 화면을 확인했다. 창을 닫은 뒤 Finder로 전환하자 Launch Services 분류가 `UIElement`로 돌아갔고, Finder의 앱 열기 동작 뒤 다시 `Foreground`로 전환됐다. 같은 설정 식별자와 선택한 Opencodex pane이 유지됐다. 키 생성·변경·폐기는 하지 않았다.

남은 도구 제약은 완전히 종료된 앱의 첫 실행이다. 초기 창을 만들지 않으므로 첫 선택은 여전히 timeout일 수 있고, 실행된 앱을 한 번 더 선택하면 재열기가 설정 창을 표시한다. 사용자가 수동으로 메뉴를 열 필요는 없다. 앱 상태 조회 자체도 재열기를 일으킬 수 있어 닫힘 검증은 Finder로 전환한 뒤 수행했다. `LSUIElement` 제거·서명된 Info.plist 직접 수정·시스템 접근성 권한 초기화는 필요하지 않았다. 실제 로그인 입력·인증 거절 경로는 별도로 검증하지 않았으며, 페이지가 정상 표시된 것을 모든 인증 경로의 검증으로 확대하지 않는다.

비밀값 없는 실행 결과는 로컬 `.dryforge/reopen/verification.json`에 기록한다. 운영 화면·키 이름·웹 본문·쿠키는 저장소의 검증 자료에 추가하지 않았다.

## Remote Link account-management address in installed build 17113

The installed client's `connection.managementUrl` is a loopback SSH data tunnel, not the hub's browser UI. m1m1's `http://127.0.0.1:65130/` returned HTTP 404. The central HTTPS management origin reported by the hub returned HTML / HTTP 200 from both m1m1 and m5m2 through Tailscale. Source changes and tests are prepared in PR #2; the installed build still needs the separately approved integration, publication and installation. See [the follow-up audit](account-flow-audit-20261021.md). This is independent of the intentionally unloaded account-snapshot watcher jobs, which remain subject to their existing recovery conditions.
