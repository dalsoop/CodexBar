# 외부 도구 연결 계약

기존 CodexBarCLI는 usage·cost 등의 명령으로 공급자 자료를 출력한다. 사용량 JSON은 제공된 details 배열과 선택적 필드를 보존하고 공급자·계정별 자료를 섞지 않는다. 현재 API 키 관리 진입점은 macOS 설정이며 CodexBarCLI에는 OpenClaw 자동 설정 명령이 없다.

`codexbar usage --provider 공급자 --format json`은 선택한 공급자의 사용량 JSON을 반환한다. 공급자별 추가 표시값은 usage.details에 있으며 폐기된 공급자별 별칭을 소비자가 추정하지 않는다. `--account`, `--account-index`, `--all-accounts`는 공급자 하나를 선택했을 때만 사용한다. 자격은 선택한 공급자의 기존 config·환경·CLI·명시적 허용 소스에서 해석한다.

`codexbar cost --provider 공급자 --format json`은 공급자별 payload 배열이다. totals·daily·선택적 projects와 provenance·coverage를 함께 해석한다. Settings의 Export JSON과 같은 envelope라고 가정하지 않는다. 가격을 모르는 모델·부분 기록·불완전 요청은 실제 0이나 완전 합계로 바꾸지 않는다. 종료 종류는 성공0, 일반 실패1, 실행 파일 없음2, 해석 오류3, 기한 초과4, 명시적인 사용법 오류64다. 모든 잘못된 인수가64라는 뜻은 아니다. dashboard 명령의 정상 부분 snapshot은 행의 오류와 함께 종료0일 수 있다.

기존 `codexbar serve`의 GET /usage·/cost는 해당 CLI payload를, /accounts는 표시 계정 자료를, /dashboard/v1/snapshot은 버전이 있는 대시보드 snapshot을 제공한다. GET /health와 /는 공개다. 기본 loopback에서는 /usage·/cost가 인증 없이 제공되지만 대시보드 snapshot은 별도 bearer 정책을 따른다. 비-loopback 바인딩은 bearer와 평문 HTTP의 명시적 수락이 필요하며 모든 데이터 경로에 Authorization: Bearer를 요구한다. 이 token은 Opencodex 키가 아니다. 알 수 없는 route는404이며 성공한 부분 snapshot 안의 공급자 오류와 HTTP 요청 자체의 실패를 구별한다.

새 로컬 관리 연결의 입력은 선택한 ocx 실행 경로와 명시적인 사용자 요청이다. 경로가 비어 있으면 기존 실행 파일 탐색을 사용한다. 모든 프로세스는 셸 없는 인수 배열로 실행하며 원시 결과를 저장하거나 오류문으로 전달하지 않는다.

| 기능 | 입력 | 확인하는 출력 | 실패 |
| --- | --- | --- | --- |
| 상태 | ocx status --json | schemaVersion 1, runtimeRole, proxy.running, dashboard.url | 누락·손상된 응답은 관리 불가 |
| 목록 | ocx access key list --json | keys와 선택적 귀속·완전성 자료 | 중복 ID·필수 필드 오류는 변경 불가 |
| 생성 | ocx access key create 이름 --json | id·name·key·createdAt | 실행 후 불명확하면 확인 필요 |
| 이름 변경 | 보조 실행기 stdin의 id·name | 같은 ID의 검증된 메타데이터 | 지원 구조 아님·ID 없음·권한·통신 오류 |
| 폐기 | ocx access key remove ID --yes --json | success true | 불명확하면 확인 필요 |

이름과 ID는 다른 필드다. 필수 문자열은 비어 있지 않아야 하며 날짜는 UTC ISO 8601을 해석한다. 선택적 범위는 문자열 배열이고 수치는 유한한 음이 아닌 값만 받는다. 알 수 없는 필드는 버리되 필수 필드의 타입 오류를 정상 값으로 대체하지 않는다. 생성 비밀값은 메타데이터와 별도 결과로 전달하고 재조회 인터페이스는 없다.

이름 변경은 @bitkyc08/opencodex 2.88.0의 확인된 실제 설치와 해당 설치의 번들 Bun·runtime-api.ts 계약에 한한다. 입력 JSON에는 id와 name만 허용한다. 기존 관리 클라이언트로 고정 PATCH /api/keys에 그 두 값만 보내며 리다이렉트를 거절한다. 선택한 ID가 없으면 다른 이름으로 대체하지 않는다. 인증은 기존 클라이언트에서 처리하고 Swift 호출자에게 전달하지 않는다.

읽기는 기본 30초·256 KiB 제한을 적용하며 조정할 수 있다. 변경은 자연 종료까지 기다리는 실행 경로를 사용해 화면 이동으로 복제하지 않는다. 오류는 실행 파일 없음·서버 중지·역할 거절·권한 거절·형식·크기·통신·결과 불명으로 구별하며 고정 현지화 문구만 제공한다. 자동 변경 재시도는 없다.

## Linux 표시 어댑터

Linux desktop의 소비자는 같은 사용자로 실행한다. `codexbar-linux --snapshot`은 실행 중 backend의 표시 자료를 반환하며 backend가 없으면 실패 종료한다. `--usage`, `--quick-view`, `--settings`, `--spending`은 필요하면 backend를 시작한다. `--snapshot --with-spending`만 오래된 비용 캐시의 scan을 요청하며 일반 snapshot은 비용 scan을 시작하지 않는다.

같은 사용자 소켓은 보통 `$XDG_RUNTIME_DIR/codexbar-linux/desktop.sock`에 있으며 XDG runtime이 없으면 사용자별 임시 디렉터리를 사용한다. 요청·응답은 개행으로 끝나는 JSON 한 문서다. `{"command":"snapshot"}`은 schemaVersion 1의 snapshot을 반환한다. `configure`는 settings 객체, `autostart`는 action의 enable·disable·status를 받는다. 변경 응답의 ok가 false면 실패이며 error는 해당 요청의 오류다. 알 수 없는 명령은 ok false와 고정 오류를 반환한다.

snapshot의 entries·summary·barEntries는 표시 전용이다. barEntries가 없는 이전 backend는 summary로 대체하고 모르는 필드는 무시한다. 계정 신원·CLI 경로·자격 설정은 포함하지 않는다. busy·stale·error와 비용 availability를 함께 해석하고 자료 없음이나 backend 부재를 실제 0으로 바꾸지 않는다.
