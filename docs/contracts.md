# 외부 도구 연결 계약

## 허브 공급자 계정 관리

공급자의 허브 계정 소스를 켜면 일반 계정 추가·로그인 액션은 `Manage hub accounts...`로 바뀐다. 설정의 로컬 Codex 계정 편집도 숨긴다. 재인증 필요 카드의 액션 역시 같은 공급자의 허브 관리 화면을 연다. 이 경로는 데이터 API 키 관리와 별개이며 로컬 OAuth 홈이나 로그인 사본을 만들지 않는다.

사용자 클릭마다 `ocx status --json`을 새로 읽는다. schemaVersion 1과 실행 중 proxy를 확인하고, hub는 `hub.managementPublicOrigin`, connected client는 `connection.managementUrl`, standalone은 `dashboard.url`의 정확한 loopback 주소만 쓴다. 데이터 주소나 옛 snapshot으로 관리 주소를 추정하지 않는다. URL에는 userinfo·query·기존 fragment·하위 경로를 허용하지 않고, 공통 대시보드 주소 검증의 HTTPS·loopback HTTP·유효한 port 규칙을 적용한다.

Anthropic·xAI는 `#providers?provider=<공급자>&tab=accounts`, Codex는 `#codex-set`을 기본 브라우저로 연다. 기존 서버 UI가 기본 Codex 로그인과 추가 계정의 서로 다른 인증 흐름을 소유한다. 브라우저 열기를 인증 성공으로 표시하거나 계정 전환을 실행하지 않는다. 관리 세션·pairing grant·계정 토큰을 CodexBar에 가져오지 않으며 인증은 사용자가 정상 관리 화면에서 완료한다. client의 로컬 네이티브 키 관리·내장 대시보드 권한은 그대로 거절한다.

전환 요청의 UI 대기는 목록 읽기 실패와 무관하게 11분 뒤 끝난다. 이때 결과는 미확인이며 자동 재시도를 하지 않는다. hub·standalone의 직접 목록 읽기 실패는 오류로 끝내고, 감시 작업이 읽지 않는 자기 요청 폴더에 요청을 만들지 않는다. 전환 성공 안내의 계정 표시명은 현재 개인정보 숨김 설정을 따른다.

기존 CodexBarCLI는 usage·cost 등의 명령으로 공급자 자료를 출력한다. 사용량 JSON은 제공된 details 배열과 선택적 필드를 보존하고 공급자·계정별 자료를 섞지 않는다. 현재 API 키 관리 진입점은 macOS 설정이며 CodexBarCLI에는 OpenClaw 자동 설정 명령이 없다.

`codexbar usage --provider 공급자 --format json`은 선택한 공급자의 사용량 JSON을 반환한다. 공급자별 추가 표시값은 usage.details에 있으며 폐기된 공급자별 별칭을 소비자가 추정하지 않는다. `--account`, `--account-index`, `--all-accounts`는 공급자 하나를 선택했을 때만 사용한다. 자격은 선택한 공급자의 기존 config·환경·CLI·명시적 허용 소스에서 해석한다.

`codexbar cost --provider 공급자 --format json`은 공급자별 payload 배열이다. totals·daily·선택적 projects와 provenance·coverage를 함께 해석한다. Settings의 Export JSON과 같은 envelope라고 가정하지 않는다. 가격을 모르는 모델·부분 기록·불완전 요청은 실제 0이나 완전 합계로 바꾸지 않는다. 종료 종류는 성공0, 일반 실패1, 실행 파일 없음2, 해석 오류3, 기한 초과4, 명시적인 사용법 오류64다. 모든 잘못된 인수가64라는 뜻은 아니다. dashboard 명령의 정상 부분 snapshot은 행의 오류와 함께 종료0일 수 있다.

## CodexBar HTTP 조회

`codexbar serve`는 기본 `127.0.0.1:8080`에서 평문 HTTP를 제공한다. `--host`는 `localhost` 또는 IPv4 주소를 받으며 `localhost`는 `127.0.0.1`로 바인딩한다. TLS·CORS는 제공하지 않는다. 비-loopback 바인딩은 토큰과 `--allow-plain-http`가 모두 있어야 시작하며, 이 옵션은 매 요청의 토큰과 응답이 암호화 없이 전송됨을 수락하는 것이다. 기본 loopback 바인딩은 비-loopback Host 헤더를 거절한다.

토큰은 `CODEXBAR_DASHBOARD_TOKEN` 환경 변수 또는 `--dashboard-token 값`으로 설정한다. 환경 변수가 옵션보다 우선하며 양끝 공백·개행을 제거한다. 제공한 값이 빈 문자열이나 공백뿐이면 시작 오류다. 옵션 값은 프로세스 인수에 노출되므로 환경 변수를 우선한다. 토큰 변경은 새 값으로 서버를 재시작해야 적용된다. 이 토큰은 CodexBar 조회 서버의 자격이며 Opencodex API 키나 관리 토큰이 아니다.

| GET 경로 | 응답 | 기본 loopback 인증 | 비-loopback 인증 |
| --- | --- | --- | --- |
| `/`, `/health` | 정적 웹 화면, `{"status":"ok"}`와 확인 가능한 경우 `version` | 공개 | 공개 |
| `/usage`, `/cost` | 각 CLI의 사용량·비용 payload | 불필요 | Bearer 필수 |
| `/accounts`, `/accounts/<id>` | 표시용 계정 목록·단일 계정 | 불필요 | Bearer 필수 |
| `/dashboard/v1/snapshot` | 아래 schemaVersion 1 envelope | Bearer 필수 | Bearer 필수 |

`/accounts`의 성공 본문은 `{"schemaVersion":1,"accounts":[]}` 형태이며 저장된 공급자 토큰 계정과 관리되는 Codex 계정의 표시 메타데이터를 담는다. 각 행은 `id`, `provider`, `source`, `label`, `active`와 선택적 `identity.accountEmail`이다. `source`는 `token-account` 또는 `codex-managed`이며 비활성 공급자의 저장 계정도 포함한다. ID는 불투명한 조회 키로 취급하고 단일 조회 경로에 넣을 때 URL 인코딩한다. `/accounts/<id>` 성공은 envelope 없이 해당 행 객체 하나다. 없는 ID는 404와 `{"error":"account not found"}`, 저장소 읽기 실패는 500과 `{"error":"could not load accounts"}`이며 빈 목록으로 대체하지 않는다. 이 조회는 사용량 수집·자격 파일 읽기·계정 선택 변경을 하지 않는다.

인증 헤더는 `Authorization: Bearer <설정한 토큰>`이다. Bearer 스킴은 대소문자를 구별하지 않지만 토큰 값은 정확히 일치해야 한다. 헤더 바깥쪽 공백·개행과 토큰 양끝 공백을 제거하며 스킴 다음에는 공백이 필요하다. query의 `token`은 인증으로 받지 않는다. snapshot은 토큰을 설정하지 않아도 공개되지 않으며, 임의 Bearer 헤더를 보내도 401이다. 설정된 경우에도 헤더 누락·형식 오류·잘못된 토큰은 같은 응답이다. 인증은 snapshot 설정 읽기·입력 해석·캐시 접근보다 먼저 검사한다. 중복 Authorization 헤더는 HTTP 파서가 400으로 거절한다.

인증 실패의 상태·헤더·본문은 다음과 같다. 아래 요청과 응답, 실행 형태는 모두 합성 예시다.

```http
HTTP/1.1 401 Unauthorized
WWW-Authenticate: Bearer
Cache-Control: no-store
Content-Type: application/json; charset=utf-8
Content-Length: 24
Connection: close

{"error":"unauthorized"}
```

```text
CODEXBAR_DASHBOARD_TOKEN=synthetic-example-token codexbar serve

GET /dashboard/v1/snapshot?detail=shell&provider=codex HTTP/1.1
Host: 127.0.0.1:8080
Authorization: Bearer synthetic-example-token
```

snapshot의 `detail`은 생략하면 `full`, 명시하면 정확히 `full` 또는 `shell`이다. 양끝 공백은 제거하지만 빈 값·다른 대소문자·`summary`는 400이며 본문 형태는 `{"error":"Unknown dashboard detail 'summary'."}`다. `provider`는 생략하거나 공백뿐이면 활성 공급자 기본 선택을 사용한다. 등록된 공급자 ID·CLI 별칭, `both`(주 공급자 묶음), `all`(전체 등록 공급자)을 대소문자 구분 없이 받으며 양끝 공백을 제거한다. 쉼표 목록은 받지 않는다. 알 수 없는 값 `missing`은 400과 `{"error":"Unknown provider 'missing'."}`를 반환한다. `detail=shell&provider=codex`처럼 두 입력을 함께 쓸 수 있다.

snapshot 성공은 HTTP 200의 단일 JSON 객체다. `/usage`·`/cost`의 배열을 이 객체로 감싸거나 같은 형태라고 가정하지 않는다.

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-10-21T00:00:00Z",
  "staleAfterSeconds": 180,
  "host": {
    "codexBarVersion": null,
    "refreshIntervalSeconds": 60,
    "usageBarsShowUsed": false
  },
  "providers": []
}
```

`generatedAt`은 ISO 8601 생성 시각, `staleAfterSeconds`는 최소 180초와 갱신 간격의 3배 중 큰 값이다. `host.codexBarVersion`은 확인 불가 시 null이며, `refreshIntervalSeconds`는 응답 캐시 갱신 간격, `usageBarsShowUsed`는 사용량 막대의 사용 비율 표시 여부다. `detail=shell`도 같은 envelope를 반환하되 `providers[]`의 각 행은 설정에서 얻은 `id`, `name`, `enabled`, `display`만 포함하며 공급자 조회·비용 스캔을 하지 않는다. `display`는 `accentColor`, `sortKey`, `priority`다.

`full` 행은 위 필드에 `source`, `status`, `identity`, `windows`, `credits`, `cost`, `error`, `updatedAt`을 추가한다. 자료가 없는 선택 값은 null이고 `windows`는 배열이다. 제공되는 공급자에는 선택적으로 `accounts`와 `accountsError`가 추가된다. 공급자 오류는 `error`의 `code`, `message`, `kind`로 표시되며 다른 정상 행을 버리거나 HTTP 오류로 바꾸지 않는다. 빈 배열·부분 성공·모든 행의 오류를 요청 자체 실패와 구별한다. HTTP 오류 본문은 공통으로 `{"error":"오류 설명"}`이며 알 수 없는 경로는 404, GET 이외 method는 405, 요청 기한 초과는 504다.

snapshot·계정 응답은 성공과 오류 모두 `Cache-Control: no-store`다. `/usage`·`/cost`도 데이터 응답에 이를 적용한다. JSON 응답은 `Content-Type: application/json; charset=utf-8`, 실제 UTF-8 본문 바이트 수의 `Content-Length`, `Connection: close`를 보낸다. HTTP 캐시 금지와 서버 내부 응답 캐시는 별개다. snapshot은 기본 60초 내부 캐시를 사용하고 만료 후 이전 정상 자료를 즉시 반환하며 백그라운드 갱신할 수 있으므로 소비자는 생성 시각과 유효 기간으로 오래됨을 표시한다. `--refresh-interval 0`은 이 동작을 끈다. `--request-timeout` 기본은 30초이고 0은 기한을 해제한다.

일반 snapshot의 신원 표시는 `--identity full|redacted`로 고정할 수 있고 생략하면 앱의 개인정보 숨김 설정을 요청마다 따른다. 시작 옵션 `--all-accounts`로 계정을 확장한 snapshot은 기본 신원을 숨기고 중립적인 계정 이름과 일반 오류를 사용하며 명시적인 `--identity`로 변경할 수 있다. 이 옵션은 query 입력이 아니며 `/usage`·`/cost`의 payload를 바꾸지 않는다.

## Opencodex 로컬 관리

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
