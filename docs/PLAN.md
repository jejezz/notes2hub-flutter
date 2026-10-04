# Notes2Hub — 계획서

GitHub 기반 메모 앱 · 작성일: 2026-10-04 · 상태: 확정본 v2 (구현 전)

- 소스 repo: local `/Users/jejezz/FlutterProject/notes2hub-flutter` · remote `https://github.com/jejezz/notes2hub-flutter.git`

## 1. 목표
GitHub private repo를 저장소로 쓰는 Markdown 메모 앱. 별도 서버·구독 없이 무료로 동작하고, 다른 PC로 옮겨가도 같은 메모를 이어서 쓸 수 있다.

- 주 사용 형태: **한 PC에서 작업**, 가끔 다른 PC로 이동 (동시 편집은 드묾)
- 데이터는 평문 Markdown + repo → 앱이 없어도 읽을 수 있고, 히스토리가 공짜
- 공유 정책: **전부 공유** (선택적 공유 없음)

## 2. 확정된 결정
| 항목 | 결정 |
|---|---|
| 앱 이름 | **Notes2Hub** |
| 저장 / 동기화 분리 | **저장** = 로컬 파일 저장만. **동기화** = git 처리(commit + pull + push) |
| 동기화 방식 | 옵션: **수동(기본)** / 30초 자동 |
| Pull | 앱 시작, 창 포커스 복귀, 주기(5분)에 자동 (동기화의 일부) |
| 에디터 | Markdown 편집 + 미리보기 (WYSIWYG 아님) |
| 메모 repo | **둘 다 지원**: 앱이 전용 repo 새로 생성 / 기존 repo 선택 |
| 충돌 | 충돌 사본을 자동 생성 (사용자에게 묻지 않음) |
| 인증 | GitHub OAuth Device Flow, 토큰은 OS 키체인/보안 저장소 |
| 암호화 | v1 제외 (v2 후보) |
| 이미지 | 1MB 초과 시 JPEG 저화질로 자동 변환 |
| 플랫폼 | **Desktop(macOS 26+ / Apple Silicon 우선) → Windows·Linux → 모바일은 기술 검증 결과에 따라** |

## 3. 기술 검증: git 설치 없이 가능한가?

### 결론: **가능성이 높음 — 단, PoC로 확정 필요**
- **git2dart** (libgit2 FFI 바인딩): pub.dev 문서상 Windows·Linux·macOS·Android(arm64-v8a, x86_64)·iOS 지원. 모바일은 `PlatformSpecific.initialize()` 호출이 필요. → 시스템 git 없이 clone/fetch/merge/commit/push 가능.
- **대안 B: GitHub REST Git Data API** (blob → tree → commit → ref 갱신): 순수 Dart `http`로 구현 가능, 네이티브 의존성 없음. 단점은 오프라인 작업과 충돌 처리를 직접 구현해야 하고 API rate limit이 있다는 점.
- **대안 C: 시스템 `git` CLI** (`Process.run`): 가장 쉽지만 **데스크톱 전용**이며 git 설치가 필요.

### 선택 (우선순위)
1. **git2dart 채택** → 데스크톱·모바일이 같은 sync 코어를 공유.
2. PoC에서 실패하면 → 데스크톱은 **git CLI**, 모바일은 **REST API 방식**으로 분리. 이때 sync 코어를 `SyncEngine` 인터페이스 뒤에 두어 교체 비용을 최소화한다.

### PoC 체크리스트 (Phase 0, 반나절~1일)
- [ ] macOS에서 HTTPS + 토큰으로 clone / fetch / commit / push
- [ ] 앱 번들(서명·샌드박스) 상태에서 네이티브 라이브러리 로딩 확인
- [ ] 충돌 상황 재현: 서로 다른 두 클론에서 같은 파일 수정 → merge 시 충돌 감지
- [ ] iOS 시뮬레이터·Android 에뮬레이터에서 같은 흐름 확인 (모바일 가능 여부 판정)
- [ ] 빌드 크기·빌드 시간 영향 확인
- 판정 기준: 데스크톱 통과 → 진행. 모바일 실패 → 대안 B로 모바일 별도 트랙 (또는 Desktop 전용으로 출시).

### PoC 결과 (2026-10-04, macOS arm64 / macOS 26, git2dart 0.5.6 + git2dart_binaries 1.14.0 = libgit2 1.9.7)
코드: `tool/poc/git2dart_poc.dart` (`flutter test tool/poc/git2dart_poc_test.dart`), `tool/poc/https_clone_test.dart` (`NOTES2HUB_POC_NET=1`).

| 항목 | 결과 |
|---|---|
| git 바이너리 없이 init / commit / push / clone / fetch (로컬 bare origin) | ✅ |
| fast-forward pull, 갈라진 히스토리 merge(다른 파일) | ✅ |
| 같은 파일 수정 → 충돌 감지(`index.conflicts`) → "원격 우선 + 로컬은 충돌 사본" 해소 → push → 상대 PC pull | ✅ |
| 앱 번들(`Notes2Hub.app/Contents/Frameworks/libgit2.dylib`)에 라이브러리 포함, 빌드 성공 | ✅ |
| macOS 런타임에 OpenSSL 불필요 (dylib는 시스템 라이브러리만 링크) | ✅ |
| HTTPS clone (GitHub 공개 repo) | ✅ **단, CA 번들을 지정해야 함** |
| HTTPS + 토큰 push (GitHub private) | ⏳ 미검증 — 실제 토큰 필요, Phase 2에서 확인 |
| Windows / Linux | ⏳ 미검증 (Windows는 DLL 동봉, **Linux는 시스템 libssl 필요**) |
| iOS / Android | ⏳ 미검증 (패키지에 xcframework / android 바이너리는 있음, 에뮬레이터 확인 필요) |

**구현 시 반드시 반영할 발견**
1. **CA 번들**: 기본 상태에서는 `GIT_ERROR_SSL: the SSL certificate is invalid`. `git2dart_binaries`의 `assets/certs/cacert.pem`을 앱 에셋으로 넣고 시작 시 디스크에 풀어 `Libgit2.setSSLCertLocations(file: …)`을 호출해야 한다. (인증서 검증을 끄는 callback은 쓰지 않는다.)
2. **충돌 해소 후 스테이징은 경로를 명시**: `index.addAll(repo.status.keys)`는 충돌 사본(새 파일)을 빠뜨렸다. 해소한 파일은 `index.add(path)`로 직접 추가한다.
3. **fast-forward**는 `Merge.analysis`가 `fastForward`를 줄 때 `Reference.setTarget` + `Checkout.head(force)`로 처리한다 (merge 커밋 불필요).
4. **⚠ macOS 제약**: 동봉된 `libgit2.dylib`가 **arm64 전용, 최소 macOS 26.0**이다. → 이 엔진으로는 Apple Silicon + macOS 26 이상에서만 동작(Intel Mac, 구버전 macOS 불가). 릴리스 템플릿의 `macos-universal.dmg` 가정과도 어긋난다. 대응안: (a) macOS 26+/arm64 전용으로 선언, (b) libgit2를 직접 universal·낮은 deployment target으로 빌드, (c) 구형 macOS는 `GitCliEngine`(시스템 git) 사용. **→ 결정(2026-10-04): (a) 채택.** macOS는 Apple Silicon + macOS 26.0 이상 전용. 배포 산출물은 `Notes2Hub-<버전>-macos-arm64.dmg`, deployment target 26.0, arm64 단일 빌드(`Release/Debug.xcconfig`·Podfile에서 고정, 릴리스 빌드 `lipo`/`vtool`로 확인). 구형 macOS/Intel 요구가 생기면 (c) `GitCliEngine`을 추가한다.
5. **Linux**는 배포 시 `libssl3`(git2dart)과 `libsecret-1-0` + 키링 서비스(flutter_secure_storage)를 README·릴리스 노트에 명시. CI 빌드에는 `libssl-dev`, `libsecret-1-dev`가 필요하다 (첫 CI 실행에서 libsecret 누락으로 실패해 확인됨).

## 4. 아키텍처

```
UI (메모 목록 / 에디터 / 설정 / 동기화 상태)
 └─ NoteRepository      파일 CRUD, 인덱스, 검색
 └─ SyncService         상태머신, 스케줄러(수동/30초/주기 pull)
     └─ SyncEngine(인터페이스)
         ├─ LibGit2Engine   (git2dart)   ← 기본
         ├─ GitCliEngine    (대체, 데스크톱)
         └─ RestApiEngine   (대체, 모바일)
 └─ ImageService        1MB 초과 시 JPEG 변환
 └─ AuthService         Device Flow + 보안 저장소
```

### 저장소 레이아웃
```
notes/
  <uuid>.md            # 메모 1개 = 파일 1개 (충돌 최소화)
assets/
  <uuid>.jpg|png       # 첨부 이미지
.notes2hub/config.json # 앱 설정(선택, 기기 간 공유 가능한 항목만)
```
- 제목은 파일명이 아니라 본문 첫 줄/frontmatter로 관리 (이름 변경으로 인한 충돌 방지)
- frontmatter: `id`, `created`, `updated`. **제목은 저장하지 않고 본문 첫 줄에서 뽑는다** (본문과 어긋나는 것·충돌 면적 방지)
- 저장 전 편집본(초안)은 저장소 **밖** `<앱 데이터>/drafts/<id>.md`에 1초 debounce로 기록 → 비정상 종료 후 복구. 새 메모는 첫 저장 전까지 파일이 없다.
- 앱 데이터 폴더: macOS `~/Library/Application Support/Notes2Hub`(샌드박스에선 컨테이너), Windows `%APPDATA%\Notes2Hub`, Linux `~/.config/Notes2Hub`. 메모는 `<앱 데이터>/data/notes/`

## 4-1. Phase 2 구현 메모 (2026-10-04)

**구성**: `lib/sync/libgit2_engine.dart`(git2dart, **Isolate에서 실행** — 동기 FFI가 UI를 막지 않게) · `sync_service.dart`(로그인·연결·상태·자동 pull/동기화) · `lib/github/`(REST, Device Flow) · `lib/auth/token_store.dart`(OS 보안 저장소) · `lib/screens/`(설정·로그인·저장소 대화상자, 동기화 버튼).

**동작 규칙(구현됨)**
- 동기화 = `notes/*.md`를 스테이징(새 파일 추가·사라진 파일 제거) → 변경이 있으면 커밋(`sync: N notes @ <기기>`) → fetch → fast-forward 또는 병합 → push. push가 거절되면(다른 PC가 먼저 올림) 최대 3번 다시 가져와 합친 뒤 재시도.
- 충돌: 같은 메모를 양쪽에서 고치면 **원격이 본 파일**, 로컬 내용은 `<제목> (충돌 <기기> <날짜>)` 새 메모로 보존. 한쪽이 삭제하고 다른 쪽이 고친 경우는 고친 쪽을 살린다.
- 자동 pull(시작·창 복귀·5분)은 **저장된 변경이 없을 때만** fast-forward한다. 있으면 작업 폴더를 건드리지 않고 "원격에 새 변경"만 표시한다.
- 편집 중(저장 전)인 메모가 원격에서도 바뀌면, 편집본을 충돌 사본으로 따로 저장하고 원격 내용이 본 메모를 차지한다.
- 오프라인이면 로컬 커밋만 남고(다음 동기화 때 push), 상태에 "오프라인" 표시.
- 동기화는 저장된 파일만 다룬다. 저장하지 않은 메모가 있으면 알림만 띄운다.
- 처음 연결할 때 로컬에 있던 메모는 보존된다: 작업 폴더에 `git init` + fetch + 원격 브랜치 checkout(safe)이라 추적되지 않는 로컬 메모가 그대로 남고, 다음 동기화에서 커밋된다.

**로그인**: 브라우저 로그인(GitHub Device Flow)은 OAuth App의 Client ID가 필요하다. GitHub → Settings → Developer settings → OAuth Apps → New OAuth App에서 만들고 **Enable Device Flow**를 켠 뒤, 빌드할 때 `--dart-define=NOTES2HUB_GITHUB_CLIENT_ID=<Client ID>`로 넣는다(`lib/github/github_config.dart`). Client ID가 없으면 로그인 대화상자는 **토큰 입력**(repo 권한 PAT)만 보여준다. 토큰은 항상 보안 저장소에만 저장한다(macOS는 키체인 — 데이터 보호 키체인을 쓰지 않아 별도 프로비저닝 불필요).

**CA 번들**: `assets/certs/cacert.pem`(Mozilla, git2dart_binaries 동봉본)을 시작 시 앱 데이터 폴더로 풀어 `Libgit2.setSSLCertLocations`에 지정한다. 라이선스 안내는 `assets/licenses/mozilla-ca-bundle.txt`(원문 확인 필요).

**Phase 3 보강 (2026-10-04)**
- **올리지 못한 변경 추적**: 커밋은 했지만 push가 실패한 경우를 `SyncStatus.unpushed`로 감지한다(마지막으로 가져온 원격 상태와 비교, 네트워크 불필요). 이전에는 "대기 0 = 동기화됨"으로 잘못 보였다. 상태 버튼에 "올리지 못한 변경"으로 표시.
- **자동 재시도(자동 모드만)**: 동기화가 실패(오프라인 등)하면 30초 → 1분 → 2분 → 5분(반복) 간격으로 다시 시도, 성공하면 멈춘다. 토큰이 거절된 경우(`authFailed`)는 재시도하지 않고 "다시 로그인"을 표시. 수동 모드는 스스로 재시도하지 않는다.
- **창 복귀·주기 pull로 네트워크가 되는 것을 확인하면**, 자동 모드에서 남은 변경을 바로 올린다.
- **동기화 중 저장**하면 끝난 뒤 한 번 더 예약한다(자동 모드).
- **git 작업 직렬화**: status·pull·sync·connect가 겹치면 index 잠금 충돌이 나므로 서비스에서 한 번에 하나씩 실행한다.
- **표시**: "3분 전" 같은 상대 시간을 30초마다 갱신. 충돌 사본은 목록에서 분기 아이콘으로 구별.
- **알려진 한계**: 동기화 도중 앱을 강제 종료하면 `.git/index.lock`이 남을 수 있다(다음 동기화 오류로 드러남 — 수동 삭제). 메뉴 막대(File 메뉴)는 아직 없고 단축키/툴바만 있다.

**Phase 4 구현 (2026-10-04) — 이미지 첨부**
- **저장 위치와 참조**: `assets/<uuid>.<ext>`(저장소 안, 동기화 대상). 메모에는 `![이름](../assets/<파일>)` 상대 경로로 넣어서 GitHub에서 메모를 열어도 이미지가 보인다. 엔진은 `notes/*.md`와 `assets/*`(`.tmp` 제외)를 스테이징하고, 사라진 파일은 인덱스에서 뺀다.
- **넣는 방법**: ① 붙여넣기(⌘V) — 클립보드에 이미지(스크린샷)나 이미지 파일이 있으면 첨부, 없으면 보통 글자 붙여넣기(EditableText의 `PasteTextIntent`를 ancestor `Actions`로 덮고 `callingAction`으로 위임) ② 창에 드래그 앤 드롭(`desktop_drop`, 드래그 중 강조 테두리) ③ 툴바 버튼/⇧⌘I(`file_selector`; macOS는 `files.user-selected.read-only` 권한 추가).
- **크기 규칙**: 상한은 **1 MiB 미만**(1,048,576바이트 미만). 미만이면 원본 그대로(확장자는 매직 바이트로 판별). 이상이면 JPEG로 변환 — 품질 85→75→65→50, 그래도 크면 긴 변을 2048→1600→1280→960px로 줄이며 같은 품질 단계를 반복. 투명 PNG는 흰 배경에 합성. EXIF 회전은 반영. 끝까지 못 맞추면 가장 작은 결과를 쓰고 경고한다.
- **변환하지 않는 것**: GIF·움직이는 이미지(여러 프레임) — 상한을 넘으면 **거부**(안내 메시지). HEIC는 상한 미만이면 그대로 두고, 넘으면 "지원하지 않음". 알 수 없는 형식은 거부.
- **처리는 Isolate**에서 한다(큰 이미지 변환이 화면을 멈추지 않게). 변환 결과 안내(예: `3.2MB → 640KB`)는 스낵바.
- **고아 첨부 정리**: 시작할 때, 어떤 메모(저장본·편집본)도 참조하지 않고 **7일 넘게 지난** 첨부만 삭제한다(방금 붙였지만 저장 전인 이미지나 막 받아온 파일을 보호).
- **미리보기**: `../assets/…`는 첨부 폴더에서, http(s)는 네트워크에서 표시. 없는 파일은 대체 표시.
- **검증**: 이미지 처리·AssetStore·엔진 동기화 단위 테스트 + macOS 통합 테스트(실제 클립보드에 PNG를 쓰고 ⌘V → 파일 저장·본문 삽입·미리보기).
- **미확인(사람이 해봐야 함)**: 드래그 앤 드롭, 파일 선택 창, Finder에서 복사한 파일 붙여넣기.

**UI 방향: 보드 (2026-10-04, 사용자 선택 "B")**
- 시작 화면은 **보드**, 메모를 열면 **전체 화면 편집 페이지**(별도 화면)다. 왼쪽 목록+오른쪽 편집기 분할은 없앴다. 편집 페이지의 ← 버튼/Esc로 보드로 돌아간다.
- **보드**: 맨 위 **빠른 메모 입력창**(쓰고 Enter → 편집 화면을 열지 않고 바로 메모로 저장)과 검색(⌘F). 아래는 **날짜 묶음**(오늘/어제/이번 주/이전)별 **내용 크기대로 쌓이는 카드**(masonry). 카드는 제목, 발췌, 수정 시각, 첨부 이미지 **표지**, **동기화 칩**(저장 안 됨 / 충돌 사본 / 동기화 대기 / 동기화됨)을 보여준다. 이미지를 보드에 끌어 놓으면 새 메모가 만들어진다.
- 카드별 동기화 상태는 엔진 `SyncStatus.pendingNotes`(커밋 전 변경 + push 전 커밋의 메모 id)에서 온다.
- **편집 페이지**: 본문 폭 820으로 가운데 정렬, 편집/미리보기, 저장, 이미지 추가, 삭제. 저장하지 않고 나가면 초안이 남고 카드에 "저장 안 됨" 칩이 뜬다. 아무것도 쓰지 않은 새 메모는 버린다.
- 제목·발췌는 이미지 줄을 건너뛰고 Markdown 기호(`#`, `**`, 링크)를 뗀 글에서 뽑는다.

**로그인 장벽 줄이기 (2026-10-04)**
- 문제: PAT는 사용자가 직접 만들어 보관해야 하고, 여러 앱이 한 토큰을 같이 쓰면 잃어버려 재발급할 때 다른 앱과의 연결도 끊긴다.
- 해결: **브라우저 로그인(Device Flow)을 기본**으로 한다 — 로그인 창을 열면 바로 시작해 코드를 보여주고 브라우저를 연다. 로그인마다 *이 앱·이 PC 전용* 토큰이 발급되므로 키를 만들거나 보관할 필요가 없고, 한 PC의 토큰을 잃어도 다른 PC·앱에는 영향이 없다. 토큰 입력은 "고급"으로 내렸다(Client ID가 없는 빌드는 처음부터 토큰 입력만 보인다).
- **OAuth App 등록은 원작자 한 번뿐**이다 (Client ID는 비밀이 아니고 Device Flow는 Client Secret이 필요 없다). 사용자는 등록 없이 승인만 한다. 값은 repo 변수 `NOTES2HUB_GITHUB_CLIENT_ID`(워크플로가 `--dart-define`으로 넣음). 로컬 개발에서는 git 제외 파일 `dart_defines.local.json`에 두고 `tool/flutter_local.sh`로 실행하면 `--dart-define-from-file`이 자동으로 붙는다(파일이 없으면 값 없이 실행 → 토큰 입력만 보임).
- **저장소 자동 제안**: 저장소를 연결하면 GitHub 토픽 `notes2hub`를 붙인다(기존 토픽은 유지, 실패해도 연결은 유효). 새 PC에서 로그인하면 이 표식이 붙은 저장소를 대화상자 맨 위에 "이 저장소로 연결" 한 번 클릭으로 제안하고, 로그인 직후 저장소 연결 대화상자가 자동으로 이어서 열린다.
- 보류: 권한을 메모 저장소 하나로 좁히는 **GitHub App**(user-to-server 토큰, 8시간 만료·갱신 필요). 지금은 `repo` 범위(비공개 저장소 전체).

**창 배치: 크기 기억 · 좌/우 도킹 · 편집 중 확장 (2026-10-04)**
- **크기·위치 기억**: 창을 옮기거나 크기를 바꾸면(350ms 지나 안정되면) 저장하고, 다음 실행 때 보이기 전에 복원한다. 저장된 위치가 어느 화면에서도 충분히(120×120 이상) 보이지 않으면(모니터를 뺀 경우) 기본 크기로 첫 화면 가운데에 둔다.
- **도킹**: 화면의 사용 영역(메뉴 막대·Dock·작업 표시줄 제외)의 **왼쪽/오른쪽 가장자리에 위아래를 꽉 채워** 붙인다(기본 폭 420, 최소 320). 앱 바의 창 배치 메뉴(좁으면 ⋯ 메뉴), 설정의 "창" 구역, 단축키 ⌥⌘←/→(도킹)·⌥⌘↓(원래 크기)로 조작한다. 도킹하기 전의 일반 창 크기를 기억해서 "원래 크기로"에서 되돌린다. 폭을 끌어서 바꾸면 그 폭을 기억하고, 창을 가장자리에서 떼어 옮기면 도킹이 풀린다. 다음 실행 때 같은 화면에 다시 붙는다.
- **편집 중 자동 확장**: 도킹된 창에서 메모를 열면 **붙은 가장자리를 고정한 채 폭을 늘리고**(기본 900) 보드로 돌아오면 원래 도킹 폭으로 되돌린다. 편집 중에 폭을 직접 바꾸면 그 폭을 다음 편집에 쓴다. 도킹하지 않은 창은 건드리지 않는다. 설정에서 끌 수 있다(기본 켜짐).
- **좁은 창 레이아웃**(폭 < 720: 앱 바, < 840: 편집기, < 600: 보드): 앱 바는 제목·라벨 없이 아이콘만(덜 쓰는 것은 ⋯ 메뉴), 보드는 입력창과 검색창을 위아래로 쌓은 한 줄 카드, 편집기 도구줄은 아이콘만. 최소 창 크기는 320×420(규약의 960×600 이하 조건을 만족).
- 계산(`dockBounds`, `expandBounds`, `isAnchored`, `isVisibleEnough`, `displayContaining`)은 창 API와 분리해 단위 테스트하고, `WindowPort` 어댑터로 실제 창(`window_manager` + `screen_retriever`)과 연결한다. macOS 통합 테스트로 실제 창의 도킹·확장·복원 좌표가 일치함을 확인했다(±3px).
- 알려진 한계: Windows·Linux의 창 좌표(작업 표시줄, 다중 모니터 배율)는 아직 실기기에서 확인하지 못했다. 편집 중 확장이 화면 폭(1440 등)을 넘는 값은 화면 폭으로 제한한다.

**보드 카드 조작 (2026-10-04)**
- 카드를 **누르면 아래에서 올라오는 시트(modal bottom sheet)로 미리보기**: Markdown을 렌더링해서 보여주고(이미지 포함) 본문만 스크롤된다. [닫기] [편집] 버튼은 고정. 별도의 제목 줄은 없다(본문 첫 줄이 제목이라 중복). 시트의 틀은 branch-dock-flutter와 같다(드래그 핸들, 위쪽 모서리 `AppRadius.sheet`, 화면 높이 85% 이내, 폭 720 이내). 처음에는 스낵바로 만들었다가 사용자가 "아래에서 올라오는 시트"를 뜻했다고 바로잡아 시트로 바꿨다.
- 카드 아래에 **편집·삭제 버튼**: 편집은 편집 화면을 열고, 삭제는 확인 대화상자(기본 포커스 취소)를 거친다. 더블클릭 편집은 단일 클릭 반응을 300ms 늦추므로 두지 않았다.
- **가장 좁은 창(폭 < 600)은 카드를 한 줄에 하나씩**, 넓으면 카드 폭이 260 밑으로 내려가지 않게 열 수를 정한다. 카드 하단의 날짜·칩은 자리가 모자라면 줄을 바꾼다.

**복사·붙여넣기 (2026-10-04)**
- **버그 수정**: Phase 4에서 붙여넣기를 이미지 인식용 `Action`으로 덮으면서, 클립보드에 이미지가 없을 때 넘겨야 할 기본 글자 붙여넣기(`callingAction`)를 `await` 뒤에 불러서 **일반 글자 붙여넣기가 조용히 사라졌다**(`callingAction`은 `invoke`가 도는 동안에만 유효). 이미지 붙여넣기만 검증했던 것이 원인. 이제 `await` 전에 붙잡아 둔다.
- **macOS에서도 Ctrl+C / Ctrl+V / Ctrl+X** 가 된다(⌘ 단축키는 그대로). Flutter macOS 기본 단축키는 ⌘만 연결되어 있어서 Windows·Linux 습관대로 Ctrl을 누르면 반응이 없었다. 같은 Intent에 Ctrl 조합을 더 연결한다(`lib/screens/ctrl_edit_shortcuts.dart`). Ctrl+A는 macOS의 "줄 처음으로"(emacs 방식)와 겹쳐서 건드리지 않는다. 편집기, 미리보기, 카드 미리보기 시트에 적용.
- 검증: macOS 통합 테스트가 실제 클립보드로 ⌘V, Ctrl+V(선택 영역 대체), Ctrl+C, Ctrl+X를 확인한다.

**자동 검증**: `flutter test`(엔진 9개 시나리오 — 로컬 bare origin으로 충돌·삭제·병합·오프라인 포함 / 서비스 / GitHub API / Device Flow) + `flutter test integration_test/app_test.dart -d macos`(샌드박스 앱에서 키체인·데이터 폴더·CA 번들 + HTTPS clone).
**실사용 확인(2026-10-04, 사용자)**: 토큰 로그인·저장소 연결·동기화 정상.
**미검증**: 실제 Device Flow 로그인(Client ID 필요), 두 PC 간 실제 충돌.

## 5. 동작 규칙

### 저장 (로컬)
- **"저장"** = 편집 내용을 로컬 파일에 기록하는 것까지만. git 명령은 실행하지 않는다.
- 단축키 ⌘S. 데이터 유실 방지를 위해 편집 중 짧은 debounce(예: 1초)로 로컬 임시 저장도 수행(옵션, 기본 켜짐).
- 저장하면 메모 상태가 "동기화 대기"가 된다.

### 동기화 (git)
- **"동기화"** = `add → commit → pull(merge) → push`. 저장된 변경만 대상.
  - 수동(기본): 동기화 버튼/단축키(⇧⌘S)
  - 자동: 저장 후 30초 뒤 동기화 (설정에서 켜기, 30초 debounce — 저장이 이어지면 타이머 재시작)
- 변경 없으면 커밋하지 않음. 커밋 메시지: `sync: <변경 메모 수> notes @ <기기명> <시각>`
- 미저장(편집 중) 내용은 동기화 대상이 아님. 동기화 시작 시 미저장 변경이 있으면 먼저 저장할지 묻거나 자동 저장(설정).

### Pull
- 앱 시작, 창 포커스 복귀, 5분 주기에 자동 실행(동기화의 pull 단계만). 로컬 저장 변경이 있어 fast-forward 불가 시 merge로 처리.
- 편집 중인 메모가 원격에서 바뀌면 덮어쓰지 않고 충돌 규칙(아래)을 따른다.

### 충돌 처리
- 같은 파일이 양쪽에서 수정되면: **원격 버전을 본 파일로 두고, 로컬 버전을 `<제목> (충돌 <기기명> <날짜>).md` 사본으로 보존**, 목록에 "충돌 사본" 배지 표시. 사용자가 비교 후 직접 정리.
- push 거절(non-fast-forward) 시 pull → 재시도 (최대 3회).

### 상태 표시
`동기화됨 / 저장되지 않은 변경(편집 중) / 동기화 대기 N / 동기화 중 / 오프라인 / 오류(재시도)` — 오프라인이면 로컬 커밋만 쌓고 복귀 시 push.

## 6. 이미지 정책 (1MB 초과)
- 대상: 붙여넣기·드롭으로 추가되는 이미지 (1MB 이하는 원본 유지)
- 처리: JPEG 변환 → 품질 85부터 낮추며, 그래도 크면 긴 변을 2048 → 1600 → 1280 px로 줄여 **1MB 미만**이 될 때까지 반복 (최저 품질 50, 최소 해상도 960px)
- 투명 PNG는 흰 배경으로 합성 후 변환 (알파 손실 안내). 목표 미달 시 경고 표시 후 최저 설정 결과를 저장.
- 구현: `image` 패키지를 Isolate에서 실행 (UI 블로킹 방지). 변환 원본은 보관하지 않음 → 설정에 "변환 안 함" 옵션 제공 고려.
- GIF·애니메이션 등은 변환하지 않고 1MB 초과 시 거부/경고.

## 7. 보안 / 개인정보
- 토큰은 키체인(macOS Keychain, Windows Credential Locker 등) 저장, 파일·로그에 기록 금지
- 권한 범위: private repo만 필요한 최소 scope (`repo`, 가능하면 fine-grained 토큰 안내)
- 앱 시작 시 repo가 public이면 경고
- v2 후보: 메모 암호화(age), 앱 잠금

## 8. 단계별 일정 (제안)
| Phase | 내용 | 산출물 |
|---|---|---|
| 0 | 프로젝트 뼈대 (flutter-app-bootstrap 규약, `notes2hub-flutter`) + **git2dart PoC** | 기술 판정 결과 |
| 1 | 메모 CRUD, 목록/검색, Markdown 에디터(미리보기), **로컬 저장** | 로컬 메모 앱 |
| 2 | Device Flow 로그인, repo 새로 생성/기존 선택, clone, **수동 동기화**, pull | 동기화 MVP |
| 3 | 30초 자동 동기화, 충돌 사본, 오프라인 처리, 상태 표시 | 안정화 |
| 4 | 이미지 첨부 + 1MB 변환 | 첨부 지원 |
| 5 | Windows/Linux 확인, 릴리즈 워크플로 (release-check) | 데스크톱 릴리즈 |
| 6 | (판정 시) iOS/Android | 모바일 |

## 9. 리스크
| 리스크 | 대응 |
|---|---|
| git2dart 네이티브 빌드/서명 문제 | Phase 0 PoC, 실패 시 CLI/REST 대체 |
| libgit2 merge API의 사용 난이도 | 파일 단위(UUID) 설계로 충돌 면적 최소화, 충돌은 파일 단위로만 처리 |
| 토큰 탈취 | 보안 저장소 + 최소 scope |
| repo 비대화(이미지) | 1MB 제한, 경고선(예: repo 500MB) 표시 |
| 커밋 히스토리 노이즈 | 수동 동기화가 기본, 자동은 30초 debounce (저장은 커밋을 만들지 않음) |

## 10. 메모 repo 설정 (둘 다 지원)
- **새로 만들기**: 로그인 후 앱이 private repo(기본 이름 `notes2hub-data`)를 생성하고 clone.
- **기존 repo 선택**: 계정의 repo 목록에서 선택(또는 URL 입력) 후 clone. 비어 있지 않은 repo는 `notes/` 폴더만 메모로 인식하고 그 밖의 파일은 건드리지 않는다. public repo 선택 시 경고.
- 소스 코드 repo(`notes2hub-flutter`)와 메모 데이터 repo는 **별개**.

## 11. 미정 / 확인 필요
- 폴더/태그 지원 시점 (제안: v1은 평면 목록 + 검색만)
- 로컬 임시 저장(편집 중 1초 debounce)을 기본 켬으로 할지 (제안: 켬)
