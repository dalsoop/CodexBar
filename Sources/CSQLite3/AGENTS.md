# 시스템 SQLite 연결

Linux에서 기존 SQLite3 헤더와 라이브러리를 Swift에 노출한다. 저장·이전·사용량 계산 로직을 이 모듈에 넣지 않는다. 플랫폼 조건과 module map을 바꾸면 glibc와 static musl 양쪽 링크 계약을 확인한다.

macOS는 기존 플랫폼 SQLite 경로를 유지한다. CODEXBAR_SQLITE3_LIB_DIR는 Linux 링크 검색 위치를 조정하는 빌드 입력이며 사용자 데이터 경로나 자격 저장소로 해석하지 않는다. 검증은 임시 데이터베이스와 기존 Linux 빌드·포장 검사로 수행한다.
