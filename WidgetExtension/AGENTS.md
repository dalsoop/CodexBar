# 위젯 확장 포장

macOS WidgetKit app-extension의 Xcode 프로젝트·Info.plist·서명 및 bundle 설정을 소유한다. 표시 코드는 기존 Sources/CodexBarWidget에서 공유하며 별도 복사본이나 공급자 조회 로직을 만들지 않는다.

최소 macOS 14와 application-extension API 제한을 유지한다. 공유 자료와 app-group 선택은 앱 팀·확장 식별자 계약과 일치해야 한다. 프로젝트를 다시 생성하면 project.yml과 실제 프로젝트의 배포 대상·정보 속성·의존성·sandbox 설정이 일치하는지 확인한다. 운영 위젯 등록이나 설치는 빌드 검증에 포함하지 않는다.
