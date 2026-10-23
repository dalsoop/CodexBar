# 확인된 함정

SwiftPM's generated `Bundle.module` accessor can look only in the app root and the original build
directory, while packaged resources live in `Contents/Resources`. The OpenCodex rename helper must use
`CodexBarCoreResources.bundle`, just like other Core resources. The packaged launch smoke test catches
this startup trap by denying access to the checkout; a successful launch on the build machine alone
does not verify resource portability.

WebKit의 `.linkActivated`는 실제 사용자 입력의 증거가 아니다. 외부 리소스가 없는 합성 페이지의 로드 타이머에서 `navigator.userActivation.isActive == false`를 기록한 뒤 DOM `.click()`을 실행해도 이 탐색 유형이 관찰됐다. 이 값으로 사용자 동작을 판정하던 대시보드 컨트롤러는 네트워크 탐색을 취소하면서도 외부 브라우저 기록 클로저를 한 번 호출했다. `evaluateJavaScript`가 입력 컨텍스트에 영향을 줄 수 있으므로 API에서 직접 실행한 `.click()`만으로 무제스처 재현을 주장하지 않는다. 웹 탐색 정책은 항상 사용자 동작 증거 없이 origin을 분류하고 외부 주소를 안내 상태에 보류한다. 외부 브라우저는 네이티브 안내 버튼 콜백에서만 연다. 회귀 검증은 실제 WKNavigationAction을 생산 세션과 컨트롤러로 전달해 일반 링크·새 창 링크·페이지 타이머의 자동 클릭 모두 확인 전 브라우저 호출 0회, 버튼 콜백 후 정확한 주소 1회를 확인한다. 기본 설정의 자동 팝업은 WebKit이 먼저 막으므로 실행 결과와 후속 동일 origin 탐색으로 검증하며, 무제스처 nil-target 탐색이 생산 정책에 도달했다고 주장하지 않는다.

Opencodex 2.88.0의 rename CLI는 ID가 없으면 같은 문자열을 이름으로 다시 찾는다. 선택 뒤 대상이 삭제되고 다른 키의 이름이 그 ID와 같아지면 잘못된 키를 변경할 수 있다. 사전 목록 조회와 사후 응답 검증만으로는 경쟁 상태를 막을 수 없다. 정확한 ID PATCH 경로를 사용하고 해당 충돌을 가짜 관리 모듈로 재현한다. 지원하지 않는 설치에서는 CLI로 되돌아가지 않는다.

Bun의 기본 console 출력은 process.stdout.write·process.stderr.write 재정의를 우회할 수 있다. Node 대체 실행기로만 테스트하면 비밀값 진단 출력 누출을 놓친다. 관리 모듈 import 전에 별도 결과 descriptor를 보관하고 표준 출력·오류 descriptor를 /dev/null로 전환한다. 실제 번들 Bun과 가짜 관리 모듈로 console·별도 Console·직접 fd 쓰기까지 차단되는지 확인한다. 실제 관리 모듈이나 토큰을 테스트에 import하지 않는다.

허브 목록 응답이나 읽기용 snapshot은 로컬 소유권 증거가 아니다. client도 허브 목록에 응답할 수 있다. status의 runtimeRole을 확인하고 변경 직전 재확인하는 테스트를 유지한다.

새 키 발급 후 비밀값은 목록 조회로 다시 얻을 수 없다. 생성 후 새로고침 실패를 생성 실패로 합치면 사용자가 키를 중복 발급할 수 있다. 변경 성공과 목록 갱신 실패를 분리하고 불명확한 응답은 자동 재시도 없이 확인 필요로 남긴다.

인증을 생략하는 loopback 경로에서는 데이터 키를 새로 만들었어도 키별 사용량이 귀속되지 않을 수 있다. 목록의 귀속 시작 시각·모호성·자료 불완전 표시를 함께 검증하고 미제공 수치를 0으로 바꾸지 않는다.

테스트용 UUID UserDefaults는 기본 설정 검색 영역이나 기존 홈 파일을 격리하지 않는다. 테스트에서는 사전형 defaults·합성 홈·파일 URL·기록용 FileManager를 모두 주입한다. 직접 swift test를 실행하면 저장소의 환경 정리 스크립트가 자동 적용되지 않으므로 먼저 불러온다.

compile_and_run.sh는 기존 CodexBar를 중단하고 새 앱을 띄운다. 운영 앱을 보존하는 검증에서는 이 명령을 사용하지 않는다. 서명이 달라진 ad-hoc 앱은 기존 Keychain 허가를 그대로 얻지 못할 수 있으므로 반복 재시작으로 허가를 해결하려 하지 않는다.

LaunchServices가 제출한 `application.net.ranode.codexbar.*` 작업은 `launchctl list`·`print`·`kickstart -p`가 성공해도 재시작 가능하다는 뜻이 아니다. m5m2의 jetsam 작업에 `kickstart -k -p`를 호출하자 기존 프로세스가 종료된 뒤 종료 코드 102로 실패했다. 기존 설치본과 실행을 복구한 뒤, 최종 배포는 정확한 앱 PID에 SIGTERM을 보내 정상 종료를 기다리고 검증된 서명 실행 파일을 분리 실행했다. 설치 파일과 실제 프로세스의 실행 파일 매핑·지속 실행·리소스 검사를 따로 확인했다. 이 프로세스 검증은 원격 설정 화면의 증거가 아니며, opencodex 프록시나 mac-infra 작업 재시작과도 별개다.

Xcode Python이 packaged-app 격리 테스트의 ambient-home에 Library/Caches/com.apple.python을 만들면 빈 홈 assertion이 실패한다. 가짜 sandbox 실행기 자체의 pyc 기록이며 앱의 접근 증거가 아니다. PYTHONDONTWRITEBYTECODE=1 환경으로 같은 테스트를 다시 실행해 assertion을 통과시키고 검사 기준을 완화하지 않는다.

명시적 계정 카드의 자료가 비었을 때 현재 활성 계정의 snapshot으로 채우면 다른 신원이 나타난다. 계정 컨텍스트는 빈 상태 그대로 두고 공통 카드 입력을 사용한다. Codex 카드는 조정된 표현을 받아야 하며 원시 대시보드를 별도 입력으로 합치지 않는다. 빈 계정과 서로 다른 활성 계정을 함께 둔 회귀로 확인한다.

비용 기록의 긴 corpus scan을 Swift 협력 실행기에서 바로 돌리면 주 스레드가 쉬고 있어도 다른 비동기 작업과 메뉴가 굶을 수 있다. scan은 별도 utility 직렬 큐에 유지한다. 데이터베이스의 직렬 실행기는 정규화된 DB 위치별로 공유하므로 다른 DB의 잠금까지 하나로 묶지 않는다. symlink로 같은 DB를 가리키는 경우와 서로 다른 DB의 병행 검사를 구별한다.

Codex 대화 제목의 DB 위치를 프로세스 전체에서 캐시하면 사용자 config 수정이나 새 state DB 버전을 놓친다. 한 번의 제목 보강 안에서만 탐색을 재사용하고 다음 호출에서 다시 확인한다. 임의 프로젝트 config는 신뢰하지 않는다. rollout 이후 유효 설정을 복원할 수 없고 악의적인 checkout이 다른 파일로 유도할 수 있기 때문에 사용자 config와 명시적 환경의 제한된 경로만 해석한다.

문자열 lookup의 한국어 검사가 통과해도 AppKit이 Swift task 밖에서 Form을 늦게 그리면 일부 캡처가 영어로 나올 수 있다. 테스트 기본 언어는 영어이며 TaskLocal을 잡은 호출과 실제 그리기 callback의 범위가 다르기 때문이다. main-loop의 동기 TaskLocal 범위 안에서 실제 뷰를 만들고 촬영하며, MainActor 가짜 소스로 조회를 끝낸 상태를 확인한다. 공용 defaults를 바꾸지 않고 픽셀 OCR·접근성·isRefreshing false를 함께 확인한다. OCR의 공백 생략만 정규화하고 문구 자체를 삭제해 검사를 통과시키지 않는다.

Opencodex 2.88.0의 Remote Link client는 `connection.managementUrl`에 `serverUrl`과 같은 loopback SSH 데이터 터널을 보고한다. m1m1의 65130과 m5m2의 52293에서 확인했으며 m1m1의 `/` GET은 404였다. 계정관리 화면으로 열지 않는다. 별도 HTTPS 관리 origin을 배포 또는 공급자 설정에서 주고, 패키징 시 `CODEXBAR_OPENCODEX_HUB_MANAGEMENT_ORIGIN`을 현재 허브의 검증된 `hub.managementPublicOrigin`으로 제공한다. 주소를 코드에서 호스트명으로 추정하지 않는다. Tailscale 관리 주소는 공개 인터넷 주소가 아니다.
