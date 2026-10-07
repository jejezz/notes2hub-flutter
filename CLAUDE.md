# Notes2Hub

Conventions: conventions-v1 (jejezz/application-release-templates).

GitHub 저장소를 백엔드로 쓰는 Markdown 메모 앱. 서버/구독 없이 무료로 동작하고, 한 PC에서 쓰다가 다른 PC로 옮겨도 이어서 쓸 수 있다. 설계 전체는 [docs/PLAN.md](docs/PLAN.md).

## 핵심 규칙 (docs/PLAN.md 요약)
- **저장** = 로컬 파일 기록만(git 없음). **동기화** = commit + pull(merge) + push. 수동이 기본, 옵션으로 저장 후 30초 자동.
- 메모 1개 = 파일 1개(`notes/<uuid>.md`). 충돌 시 원격을 본 파일로, 로컬은 "충돌 사본"으로 보존 — 사용자에게 묻지 않는다.
- **삭제 = 휴지통**: 파일을 지우지 않고 frontmatter `deleted:`만 붙인다(동기화로 따라감, 30일 뒤 앱 시작 때 완전 삭제). **버전 기록** = 그 메모 파일이 바뀐 git 커밋 목록(`SyncEngine.history`/`versionContent`), 동기화한 시점만 남는다.
- 전부 공유(선택적 공유 없음). 에디터는 Markdown 편집 + 미리보기.
- 창: 크기·위치 기억, 화면 좌/우 가장자리 **도킹**(세로로 길게), 도킹된 상태에서 메모를 열면 폭을 **자동 확장**했다가 보드로 돌아오면 복원 (`lib/window/window_layout.dart`, 좁은 창 레이아웃 포함).
- UI: 시작 화면 = 카드 **보드**(빠른 메모 입력창 + 날짜별 masonry 카드 + 동기화 칩), 카드를 열면 **전체 화면 편집 페이지**(←/Esc로 복귀). 보드·편집기 코드는 `lib/screens/board_view.dart`, `notes_screen.dart`.
- **통합 테스트(`-d macos`)는 실제 앱의 키체인·컨테이너를 공유한다** — 테스트 전용 키/임시 폴더만 쓸 것.
- 이미지 1MiB 이상이면 JPEG로 자동 변환(GIF/움직이는 이미지는 변환 없이 거부). 첨부는 `assets/`, 메모에서는 `../assets/<파일>`로 참조.
- git 엔진은 `SyncEngine` 인터페이스 뒤에 둔다: git2dart(libgit2, 기본) → 실패 시 git CLI(데스크톱)/REST API(모바일).
- **macOS는 Apple Silicon + macOS 26.0+ 전용** (git2dart 동봉 libgit2가 arm64·minos 26.0). DMG 이름은 `macos-arm64`. Intel/구형 macOS가 필요해지면 `GitCliEngine` 추가.
- 소스 repo(`notes2hub-flutter`)와 메모 데이터 repo(`notes2hub-data` 등)는 별개.
- 토큰은 보안 저장소에만, 로그/파일 금지.
- 로컬 개발용 빌드 값(GitHub Client ID)은 git 제외 파일 `dart_defines.local.json`(견본 `dart_defines.local.example.json`)에 두고 `tool/flutter_local.sh run|build|test …`로 실행한다. 실제 값은 커밋하지 않는다. 배포는 repo 변수 `NOTES2HUB_GITHUB_CLIENT_ID`.

## 현재 단계
Phase 0(뼈대 + macOS PoC), Phase 1(로컬 메모 CRUD·검색·Markdown 편집/미리보기·저장·초안 복구) 완료. Phase 2(GitHub 로그인·repo 생성/선택·동기화·자동 pull, 실사용 확인됨)와 Phase 3(자동 재시도·올리지 못한 변경 추적·git 작업 직렬화·상태 표시) 완료. Phase 4(이미지 첨부: 붙여넣기·드롭·선택, 1MiB 초과 시 JPEG 변환, assets/ 동기화) 완료. Phase 5 완료: CI 빌드 검증(macOS·Windows·Linux) 통과, `v0.1.0-rc.1` 프리릴리스 게시·파일 확인됨(2026-10-04), rc.2 불필요. 남은 것: Windows/Linux 실기기 실행 확인, 실제 스크린샷·데모 GIF, 아이콘(임시 글리프), 브라우저 로그인용 Client ID, 정식 v0.1.0. 이후 Phase는 docs/PLAN.md §8.
모바일(iOS·Android)은 [docs/MOBILE_PLAN.md](docs/MOBILE_PLAN.md): M0(git2dart PoC)·M1(뼈대)·M2(Android 실기기 로그인·저장소 연결·동기화 확인)·M3(폰 UI: + 버튼·당겨서 동기화·길게 누르기·서식 도구줄·카메라)·아이콘 완료(2026-10-05). M5 코드·CI·문서 완료 — 서명 키/Play·App Store 등록은 [docs/MOBILE_RELEASE.md](docs/MOBILE_RELEASE.md). iPhone 실기기(릴리스 빌드)에서 로그인·동기화 확인(2026-10-05; iOS 릴리스는 libgit2 심볼 제거 방지 설정이 필요했다). iPhone의 공유·사진·카메라·서식·뒤로가기, 한글 서식, 강제 종료 후 복구, 백그라운드 복귀도 사용자 확인 완료(§3-5, 단 `index.lock` 자동 정리는 미구현). **남은 것: 테스트 보강, Android 업로드 키·시크릿 등록(없으면 릴리스 CI의 build-android가 실패해 전체 릴리스가 막힌다), 스토어 등록.** Android는 64비트 전용(minSdk 24), 32비트는 설치되지 않는다. 폰에서 `dart_defines.local.json`의 Client ID 없이 빌드하면 브라우저 로그인이 보이지 않는다.
