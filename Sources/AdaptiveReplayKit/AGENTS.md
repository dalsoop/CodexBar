# 오프라인 갱신 재현

사용자가 명시한 JSONL trace 해석·시간 진행·정책 비교·통계를 소유한다. 앱과 CodexBarCore에 의존하지 않고 공통 갱신 정책만 공유한다. provider 호출·실제 transcript 탐색·trace 수집·운영 정책 변경은 하지 않는다.

선택적 활동 필드는 입력으로만 취급한다. 오래된 입력에 새 필드가 없어도 해석하며 strict와 tolerant 입력 경로의 오류 의미를 섞지 않는다. legacy gap 분리는 휴면·재시작·긴 요청을 구별할 수 없는 휴리스틱이므로 제외 시간과 segment 수를 숨기지 않는다.

simulated interaction advance는 0초 refresh 가정의 반사실적 값이다. 기록된 일정 감사와 동일 측정으로 취급하지 않는다. 테스트는 합성 trace로 정책·시간 경계·불완전 입력·분리 결과를 확인한다.
