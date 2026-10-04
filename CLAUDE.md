# Notes2Hub

Conventions: conventions-v1 (jejezz/application-release-templates).

GitHub 저장소를 백엔드로 쓰는 Markdown 메모 앱. 서버/구독 없이 무료로 동작하고, 한 PC에서 쓰다가 다른 PC로 옮겨도 이어서 쓸 수 있다. 설계 전체는 [docs/PLAN.md](docs/PLAN.md).

## 핵심 규칙 (docs/PLAN.md 요약)
- **저장** = 로컬 파일 기록만(git 없음). **동기화** = commit + pull(merge) + push. 수동이 기본, 옵션으로 저장 후 30초 자동.
- 메모 1개 = 파일 1개(`notes/<uuid>.md`). 충돌 시 원격을 본 파일로, 로컬은 "충돌 사본"으로 보존 — 사용자에게 묻지 않는다.
- 전부 공유(선택적 공유 없음). 에디터는 Markdown 편집 + 미리보기.
- 이미지 1MiB 이상이면 JPEG로 자동 변환(GIF/움직이는 이미지는 변환 없이 거부). 첨부는 `assets/`, 메모에서는 `../assets/<파일>`로 참조.
- git 엔진은 `SyncEngine` 인터페이스 뒤에 둔다: git2dart(libgit2, 기본) → 실패 시 git CLI(데스크톱)/REST API(모바일).
- **macOS는 Apple Silicon + macOS 26.0+ 전용** (git2dart 동봉 libgit2가 arm64·minos 26.0). DMG 이름은 `macos-arm64`. Intel/구형 macOS가 필요해지면 `GitCliEngine` 추가.
- 소스 repo(`notes2hub-flutter`)와 메모 데이터 repo(`notes2hub-data` 등)는 별개.
- 토큰은 보안 저장소에만, 로그/파일 금지.

## 현재 단계
Phase 0(뼈대 + macOS PoC), Phase 1(로컬 메모 CRUD·검색·Markdown 편집/미리보기·저장·초안 복구) 완료. Phase 2(GitHub 로그인·repo 생성/선택·동기화·자동 pull, 실사용 확인됨)와 Phase 3(자동 재시도·올리지 못한 변경 추적·git 작업 직렬화·상태 표시) 완료. Phase 4(이미지 첨부: 붙여넣기·드롭·선택, 1MiB 초과 시 JPEG 변환, assets/ 동기화) 완료. 다음: Phase 5(Windows/Linux 확인, 릴리스 워크플로). 이후 Phase는 docs/PLAN.md §8.
