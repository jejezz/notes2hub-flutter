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
| 플랫폼 | **Desktop(macOS 우선) → 모바일은 기술 검증 결과에 따라** |

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
- frontmatter: `id`, `created`, `updated`, `title`

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
