# Omarchy 표시 어댑터

Quickshell 막대와 popup 표시를 소유하며 Linux 데스크톱의 같은 사용자 IPC snapshot을 읽는다. 공급자 CLI를 직접 조회하거나 자체 polling backend·인증 저장소·설정 화면을 만들지 않는다. 다중 모니터도 backend 하나의 조회를 공유한다.

backend가 없으면 자료 없음으로 표시하고 사용자 창 열기 동작만 backend 시작을 요청한다. 알 수 없는 quota는 소진으로 표시하지 않는다. 새 barEntries가 없으면 기존 summary로 표시하며 막대에서 숨긴 공급자도 backend 조회·popup·알림에서는 유지한다. popup에 계정 신원을 추가하지 않는다.

manifest와 Panel.qml의 진입 계약을 함께 유지한다. 검증은 node --test Integrations/Omarchy/test.mjs Integrations/Omarchy/notifications.test.mjs와 격리된 installer 테스트를 사용한다. 실제 shell 재시작·로그인 설정 쓰기는 표시 검사와 분리한다.
