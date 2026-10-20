# 개발과 운영

macOS 개발은 Xcode 27의 Swift 도구와 기존 SwiftPM 의존성이 필요하다. 저장소 manifest는 Swift tools 6.2 이상이며 최소 macOS 14를 선언한다. 지원하지 않는 이전 도구체인의 성공을 보장하지 않는다.

포크를 checkout한 루트에서 먼저 빌드한다. 아래 명령은 설치된 앱을 교체하지 않는다.

```sh
export PATH="/opt/homebrew/opt/python@3.14/libexec/bin:$PATH"
export PYTHONDONTWRITEBYTECODE=1
swift build
make test-fast FILTER='OpenCodexAccess|OpenCodexDashboard|PreferencesSelectionTests|OpenCodexHubCardTests|OpenCodexHubClaudeCardTests|OpenCodexHubCodexNativeStateTests|StatusMenuOpenCodexHubAccountsTests|ClaudeSwapOpenCodexSwitchTests'
/bin/bash -c 'source Scripts/test_environment.sh; CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS=1 swift test --filter CodexBarLinuxTests'
make check
node Scripts/check-app-locales.mjs
.build/lint-tools/bin/oxlint --config .oxlintrc.json --deny-warnings --report-unused-disable-directives Sources/CodexBarCore/Resources/OpencodexAccess/rename.mjs
```

test-fast는 저장소의 환경 정리 경로를 사용한다. 직접 swift test에는 test_environment.sh를 먼저 적용하여 상속 자격과 실제 세션 파일 접근을 막는다. CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS는 테스트의 Keychain 접근을 억제하는 값이며 실계정 검증 허가가 아니다. CODEXBAR_USE_LOCAL_SWEETCOOKIEKIT=1은 인접한 기존 SweetCookieKit 소스를 사용할 때만 설정한다. 기본은 manifest의 고정 의존성 해석이다.

PYTHONDONTWRITEBYTECODE=1은 가짜 실행기의 Python 캐시가 ambient-home 격리 assertion을 오염시키지 않도록 한다. 실제 앱의 격리 정책과 assertion은 그대로 실행한다.

Python은 os.waitid와 WNOWAIT를 제공해야 한다. 기본 Xcode Python3.9에는 없으므로 위 명령은 이미 설치된 Homebrew Python3.14를 우선한다. 다른 호스트에서는 해당 기능이 있는 python3 경로로 바꾼다.

기본 JavaScript 수집은 플러그인 자료만 검사하므로 이름 변경 보조 실행기는 마지막 oxlint 명령으로 따로 검사한다. make check가 도구를 준비한 뒤 실행해야 한다.

빠른 수정 중에는 수정 파일만 형식 검사한다. make check는 언어·생성 자료·문서 링크·스크립트·포장 계약·JavaScript·Swift 형식 검사를 포함하므로 최종 변경에서 실행한다. 장시간 전체 테스트가 필요한 경우 ./Scripts/test.sh --direct-workers 8을 백그라운드 또는 CI에서 사용한다.

앱 포장·재실행을 명시적으로 승인받은 개발 작업은 ./Scripts/compile_and_run.sh를 사용할 수 있다. 이 명령은 기존 프로세스를 중단하므로 격리된 UI 검증의 대용으로 사용하지 않는다. ./Scripts/package_app.sh는 로컬 앱 묶음을 다시 만든다. 검증 때 실행 파일과 새 묶음의 일치를 확인한다.

포크 배포는 기존 동기화·서명·공증 경로의 별도 작업이다. 로컬 포장으로 공개 릴리스를 대체하지 않는다. CI 릴리스는 기존 서명·공개 키·산출물·업데이트 feed·Homebrew tap 일치를 확인한다. 사용자의 명시적 배포 요청 없이는 태그·릴리스·feed·tap을 쓰지 않는다.

Linux 데스크톱을 수정할 때는 Linux·C++17·qmake6·Qt6.4 이상의 Base·Declarative/Quick·Quick Controls·Network·D-Bus·SVG와 별도 CodexBar CLI가 필요하다. 저장소 루트에서 아래 순서로 로컬 build 디렉터리를 만든다. CLI의 Core 리소스 bundle은 CLI 실행 파일 곁에 유지한다.

```sh
mkdir -p .local/linux-build
cd .local/linux-build
qmake6 ../../Integrations/Linux/codexbar-linux.pro
make -j4
cd ../..
node --test Integrations/Omarchy/test.mjs Integrations/Omarchy/notifications.test.mjs
python3 Integrations/Omarchy/test_install.py
python3 Integrations/Linux/tests/test_desktop.py
python3 Integrations/Linux/tests/test_package.py
```

Qt runtime 검증은 합성 HOME/XDG·가짜 CLI와 QT_QPA_PLATFORM=offscreen·QT_QUICK_BACKEND=software 환경을 사용한다. 이 명령은 실제 설치·autostart·Omarchy shell 재시작을 수행하지 않는다. glibc 데스크톱과 musl CLI는 다른 산출물이므로 CLI 호환성으로 데스크톱 실행을 보장하지 않는다.
