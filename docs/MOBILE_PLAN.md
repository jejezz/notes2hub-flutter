# Notes2Hub — 모바일(iOS·Android) 계획서

작성일: 2026-10-05 · 상태: **M0 통과 · M1 완료 · M2 Android 실기기 확인 (§3-3), iOS 실기기 남음** · 기준 버전: `v0.1.0-rc.4`

기존 [PLAN.md](PLAN.md)의 Phase 6("판정 시 iOS/Android")을 구체화한 문서다. 데스크톱 설계(저장/동기화 분리, 파일 1개 = 메모 1개, 충돌 사본, 보안 저장소)는 **그대로 유지**하고, 모바일에서 달라지는 부분만 다룬다.

## 1. 목표와 범위

**목표**: 같은 GitHub 메모 repo를 폰에서도 열어 읽고, 쓰고, 동기화한다. PC에서 쓴 메모를 폰에서 이어 보고, 폰에서 적은 빠른 메모가 PC에 나타난다.

**v1 모바일에 넣는 것**
- 보드(빠른 메모 입력 + 날짜별 카드) · 편집(Markdown 편집/미리보기) · 검색 · 북마크
- GitHub 로그인(Device Flow) · 저장소 연결 · 수동/자동 동기화 · 충돌 사본 · 오프라인
- 이미지 첨부: **카메라/사진 보관함에서 선택**, 1MiB 초과 시 JPEG 변환(기존 `ImageProcessor` 그대로)
- **메모 공유**(모바일·macOS·Windows·Linux 공통, `share_plus`): 시스템 공유 화면을 연다. 어떤 앱을 고를지 알 수 없어서 공유 전에 형식을 고른다 — *전체 공유*(글 전체 + 이미지 모두, 메일·메신저), *문자용*(앞 1,000자 + 첫 이미지 1장), *텍스트 복사*. 이미지 참조 문법은 글에서 빼고 파일로 붙인다. Linux는 글만(메일). 진입점: 편집 화면, 카드 길게 누르기 메뉴, 미리보기 시트
- 한국어/영어, 라이트/다크, About·라이선스

**v1 모바일에서 뺀 것 (데스크톱 전용 유지)**
- 창 도킹·크기 기억·편집 중 확장(`lib/window/`), macOS 메뉴 막대, 키보드 단축키 중심 조작, 드래그 앤 드롭
- 백그라운드 자동 동기화(앱이 꺼져 있을 때) — §6 참고
- 다른 앱에서 "공유" 받기(share sheet 수신), 홈 화면 위젯 — v1.1 후보

**대상 OS**: Android 7.0+(API 24, Flutter 3.47 기본 minSdk) · iOS 15+. 64비트 전용(arm64-v8a·x86_64) — 32비트 ARM은 설치되지 않게 막았다.

## 2. 현재 코드에서 모바일로 옮길 때 걸리는 곳

코드를 읽어 확인한 것(2026-10-05). `ios/`·`android/` 폴더는 아직 없다.

| 영역 | 파일 | 모바일 영향 | 조치 |
|---|---|---|---|
| 창 관리 | `main.dart`(`_isDesktop` 분기는 이미 있음), `lib/window/window_layout.dart` | `window_manager`·`screen_retriever`는 데스크톱 전용. `WindowLayout`은 `_isDesktop`일 때만 만들어지므로 로직은 안전하나 **import가 남아** 있다 | 모바일에서 `windowLayout == null`을 정상 경로로 확정. 플러그인이 모바일 빌드를 깨면 조건부 import로 분리 |
| 앱 데이터 경로 | `lib/notes/app_paths.dart` | macOS/Windows/Linux 외에는 `getApplicationSupportDirectory()`로 떨어짐 → 모바일에서 그대로 동작(앱 전용 저장소) | 변경 없음. 테스트만 추가 |
| 토큰 저장 | `lib/auth/token_store.dart` | `flutter_secure_storage`가 Android Keystore / iOS Keychain 지원 | Android `minSdk`·백업 제외 설정 확인(§5) |
| 이미지 입력 | `notes_screen.dart` — `desktop_drop`, `pasteboard`, `file_selector`, `File(p).readAsBytes` | 드롭은 모바일에 없음. 클립보드 이미지·파일 선택은 모바일 지원 여부를 **패키지별로 확인 필요** | 모바일 입력 경로를 `image_picker`(카메라·보관함)로 별도 구현, 드롭/붙여넣기 이미지는 지원되는 범위만 |
| 기기 이름 | `sync_service.dart` `Platform.localHostname` | 폰에서는 `localhost` 같은 의미 없는 값이 나올 수 있음 → 커밋 메시지·충돌 사본 이름에 쓰임 | `device_info_plus`로 "Pixel 8", "iPhone 15" 같은 모델명 사용(사용자가 설정에서 바꿀 수 있게) |
| 단축키 | `notes_screen.dart` `CallbackShortcuts` | 터치에서는 쓸 일 없음(외부 키보드 연결 시엔 유지) | 그대로 두고, 같은 동작을 **터치 UI로도 노출**(§4) |
| 앱 수명주기 | `didChangeAppLifecycleState`(저장 flush, 복귀 시 자동 pull) | 이미 `resumed` 외 상태에서 초안을 flush함 → 모바일에서도 유효하고 **더 중요해짐**(OS가 앱을 조용히 종료) | 유지. `paused` 때 동기화 시도 추가 검토(§6) |
| libgit2 엔진 | `lib/sync/libgit2_engine.dart` (Isolate) | 모바일은 `PlatformSpecific.initialize()` 호출 필수, **Isolate 안에서도 필요한지 확인**. CA 번들 지정 방식이 Android에선 다름(git2dart가 초기화 때 풀어줌) | §3 PoC에서 확정 |
| 빌드/릴리스 | `.github/workflows/release.yml` | macOS·Windows·Linux만 빌드 | 모바일 잡 추가(§7) |

## 3. Phase M0 — 기술 검증 (PoC, 먼저 한다)

가장 큰 불확실성은 **git2dart가 실제 iOS·Android에서 도는가**다(PLAN.md §3에서 "패키지상 지원, 미검증"으로 남긴 항목). 아래를 통과해야 M1로 간다.

| # | 검증 | 통과 기준 |
|---|---|---|
| 1 | `flutter create --platforms=ios,android .` 후 빈 빌드 | Android 에뮬레이터·iOS 시뮬레이터에서 실행 |
| 2 | `PlatformSpecific.initialize()` 후 로컬 bare origin으로 init/commit/push/clone/fetch (`tool/poc/git2dart_poc.dart` 재사용) | macOS PoC와 같은 결과 |
| 3 | **HTTPS + 토큰으로 GitHub private repo clone/push** (실제 기기 또는 에뮬레이터) | 성공. CA 오류 없음 |
| 4 | Isolate 안에서 위 동작 (`LibGit2Engine`이 Isolate를 씀) | 성공. 안 되면 Isolate 시작 시 초기화 추가 |
| 5 | 충돌 시나리오(같은 파일 양쪽 수정) 엔진 테스트 9개 시나리오 | 모바일 타깃에서도 통과 |
| 6 | **실기기** 1대씩(Android, iPhone) | 에뮬레이터 통과가 실기기 통과를 보장하지 않음. 특히 iOS arm64 실기기, Android arm64 |
| 7 | 앱 크기·빌드 시간 | Android arm64 APK/AAB, iOS IPA 크기 기록. 비정상적으로 크면 ABI 분할 |
| 8 | 앱이 동기화 중 강제 종료됐을 때 `.git/index.lock` | 재현 확인 → §6의 stale lock 정리로 해결되는지 |

**판정**
- 통과 → git2dart로 모바일 진행(데스크톱과 같은 엔진, 가장 단순).
- 실패(특히 #3·#6) → `RestApiEngine` 트랙(아래 §3-1). 모바일만 REST로 가고 `SyncEngine` 인터페이스 뒤에 두므로 UI·서비스 변경은 없다.

### 3-2. M0 결과 (2026-10-05) — **통과, git2dart로 진행**
코드: `integration_test/mobile_poc_test.dart` (`flutter test integration_test/mobile_poc_test.dart -d <기기>`). 환경: Flutter 3.47.1, git2dart 0.5.6.

| # | 항목 | Android (에뮬레이터 API 35, arm64) | iOS (시뮬레이터 iPhone 16 Pro, iOS 18.4) |
|---|---|---|---|
| 1 | 빈 빌드·실행 | ✅ 앱 실행, 보드 화면 정상(기존 좁은 화면 레이아웃 그대로) | ✅ 빌드·테스트 실행 |
| 2 | init/commit/push/clone/fetch/병합/충돌 해소 (로컬 bare origin) | ✅ | ✅ |
| 3 | HTTPS clone (GitHub 공개 repo) + 번들 CA | ✅ | ✅ |
| 4 | 위 clone을 **Isolate 안에서** | ✅ (`PlatformSpecific.initialize()`를 메인 isolate에서 한 번 호출하면 충분) | ✅ |
| 5 | `LibGit2Engine` 왕복: 연결·동기화·다른 사본 수신·같은 메모 양쪽 수정 → 충돌 사본 1개 | ✅ | ✅ |
| 6 | 실기기 | ⏳ 미검증 | ⏳ 미검증 |
| 7 | 크기 | release APK(arm64) **46.6MB** (debug 117MB) | ⏳ 미측정 |
| 8 | 동기화 중 강제 종료 시 `index.lock` | ⏳ 미검증 | ⏳ 미검증 |
| — | HTTPS + 토큰 push (private) | ⏳ Phase M2에서 실제 로그인으로 확인 | ⏳ 동일 |

**반영한 것**: `lib/main.dart`가 시작 때 `PlatformSpecific.initialize()`를 호출한다(데스크톱에서는 아무 일도 하지 않음). `flutter create --platforms=ios,android --org art.zoomon`으로 `android/`·`ios/` 생성(applicationId/bundle ID `art.zoomon.notes2hub`, macOS와 동일).

**알게 된 것**
- `app_paths.dart`는 모바일에서 `getApplicationSupportDirectory()`로 떨어지고 정상 동작한다 (Android `/data/user/0/art.zoomon.notes2hub/files`, iOS `Library/Application Support`).
- Android 빌드가 `desktop_drop`·`pasteboard`의 Kotlin Gradle Plugin 사용 경고를 낸다("미래 Flutter에서 실패") → 모바일 전용 입력으로 대체/조건부 의존으로 정리할 때 함께 처리(M1).
- iOS: `git2dart_binaries`가 Swift Package Manager를 지원하지 않는다는 경고(현재는 CocoaPods로 정상 빌드).
- 시뮬레이터/에뮬레이터 통과는 실기기 통과를 보장하지 않는다 → 실기기 확인(#6)은 M2 전에 한 번.

### 3-3. 실기기 확인 (2026-10-05) — Android Galaxy S25 (SM-S931N, Android 16)
- PoC 4개 항목(로컬 origin 흐름, 앱 전용 폴더, HTTPS clone + 번들 CA, Isolate 엔진 왕복·충돌 사본) **모두 통과** → §3-2의 #6(Android) 확인 완료.
- release APK(arm64, `INTERNET` 권한 포함)로 **브라우저 로그인(Device Flow) → 저장소 연결 → 폰↔PC 동기화 왕복** 확인(사용자).

**실기기에서 드러나 고친 것** (에뮬레이터·단위 테스트로는 안 보이던 것)
1. **코드를 외울 틈이 없었다**: 코드를 보여주자마자 앱 안 브라우저(Custom Tab)가 덮어버림 → 모바일은 코드를 **자동 복사**하고 브라우저는 사용자가 **브라우저 열기**로 연다(기본 브라우저 앱, `LaunchMode.externalApplication`). 안내문·"코드 복사됨" 알림 추가.
2. **앱 전환 중 네트워크가 잠깐 끊김**(`SocketException: Failed host lookup`, errno 7): 승인 대기 중 확인 요청의 일시적 네트워크 오류가 로그인을 실패시킴 → `ClientException`/`TimeoutException`은 **다음 확인에서 재시도**. 앱이 다시 앞으로 오면(`resumed`) 대기 시간을 건너뛰고 **바로 확인**(`DeviceFlow.awaitToken(wake:)`; iOS는 뒤에 있는 동안 대기가 멈추므로 필요).
3. **추천 저장소인데도 직접 골라야 했다**: 로그인 직후 `notes2hub` 표식의 **비공개 저장소가 정확히 하나**면 선택 없이 자동 연결(`SyncService.connectSuggestedRepo`). 후보 없음/여럿/공개/실패면 기존 선택 화면.
4. **release 빌드에 `INTERNET` 권한이 없었다**: Flutter 기본 템플릿은 debug/profile에만 넣는다 → 메인 매니페스트에 추가.

### 3-4. iPhone 실기기 확인 (2026-10-05) — iPhone 12 mini, iOS 26.6
- PoC 4개 항목 모두 통과(디버그). 서명은 Xcode 프로젝트의 Team(`DEVELOPMENT_TEAM`)으로 자동.
- ⚠ **릴리스 빌드가 흰 화면**이었다 (디버그는 정상). 원인: 릴리스·프로파일(AOT)에서 링커가 정적 링크된 libgit2의 심볼을 지워 `dlsym ... git_libgit2_shutdown: symbol not found`로 `main()`이 중단됨(`PlatformSpecific.initialize()`). 해결: `ios/Flutter/Release.xcconfig`에 `DEAD_CODE_STRIPPING = NO`, `STRIP_STYLE = non-global`. 앱은 41.3MB(전 34.9MB). 같은 일이 다시 생겨도 흰 화면 대신 오류가 보이도록 `main()`에 시작 오류 화면을 추가했다.
- **교훈**: iOS는 디버그만 보고 통과시키지 말고 **릴리스 빌드를 실제로 실행해** 확인한다. CI의 `flutter build ios --no-codesign`은 컴파일만 해서 이런 런타임 문제를 잡지 못한다 (TestFlight 올리기 전에 릴리스 빌드를 한 번 실행해 볼 것).

- 클린 빌드(`flutter clean`)한 릴리스 빌드로 다시 확인: 보드 정상. **브라우저 로그인 → 저장소 연결 → 동기화**도 정상(사용자 확인).

**아직 확인하지 못한 것**: iPhone의 공유·사진 첨부(HEIC)·카메라·서식 도구줄·뒤로가기 제스처, 큰 사진 첨부(`image_picker`), 앱 강제 종료 후 `index.lock`(§6-3), 모바일 한글 입력 중 서식 삽입, 장시간 백그라운드 뒤 복귀.

### 3-1. 대안: `RestApiEngine` (PoC 실패 시만)
PLAN.md §3의 대안 B. GitHub Git Data API(blob → tree → commit → ref)로 `notes/*.md`, `assets/*`를 올리고 내려받는다.
- 로컬 git 이력이 없으므로 "마지막으로 동기화한 원격 커밋 SHA + 파일별 blob SHA" 표를 로컬에 저장해 변경·충돌을 판정한다. 충돌 규칙(원격이 본 파일, 로컬은 충돌 사본)은 동일.
- 메모 1개 = 파일 1개라서 파일 단위 3-way 판정만 하면 된다. 일부 파일만 받는 **지연 로딩**도 가능(큰 repo에 유리).
- 단점: rate limit, 오프라인 중 이력 없음(변경 목록만 보관), 새 엔진 + 테스트 비용. **가능하면 피한다.**

## 4. UI/UX — 모바일에서 달라지는 점

기존 레이아웃은 이미 좁은 창(폭 < 600: 보드 1열, 편집기 아이콘만)을 지원해서 출발점이 좋다. 모바일 전용으로 추가·변경:

**보드**
- 빠른 메모 입력창은 유지하되, 화면 아래 **FAB(새 메모)** 추가. 키보드가 올라오면 입력창이 가려지지 않게 `viewInsets` 반영.
- 카드: 탭 = 미리보기 시트(기존), **길게 누르기 = 편집·삭제·북마크 메뉴**(데스크톱의 카드 아래 버튼은 모바일에서 숨김, 터치 영역 48dp 이상).
- 당겨서 새로고침 = 동기화(`RefreshIndicator`). 동기화 칩은 유지.
- 안전 영역(노치·홈 인디케이터) 반영, 가로 모드는 2열까지.

**편집**
- 전체 화면 편집 페이지는 그대로, **←는 시스템 뒤로 제스처**(Android 예측 뒤로가기, iOS 스와이프)와 맞춘다. 저장하지 않고 나갈 때 초안 보존(기존 동작).
- 키보드 위에 **서식 도구줄**(굵게·제목·목록·체크박스·링크·이미지 추가·편집/미리보기 전환). 데스크톱 단축키(⌘B 등)와 같은 동작을 호출.
- 이미지: 도구줄 버튼 → 카메라 / 사진 보관함(`image_picker`). 선택한 사진은 기존 `ImageProcessor`(Isolate)로 1MiB 처리. 큰 사진은 메모리 폭주를 막기 위해 디코딩 전 `maxWidth` 힌트 사용.
- 저장: 상단 저장 버튼 유지. 폰에서는 실수로 나가는 일이 많아 **편집 중 1초 초안 저장이 이미 기본**이라는 점을 그대로 신뢰.

**설정**
- 창 배치 섹션은 모바일에서 숨김. "기기 이름" 입력 추가. 나머지(동기화 모드·테마·언어)는 공용.

**테마/글꼴**
- 서울남산체 · 시스템 글꼴 규칙(보드는 서울남산체, 사용자 본문은 시스템 글꼴)은 모바일에서도 동일. `user_content.dart`에 이미 iOS 분기가 있고 Android는 기본 글꼴.
- `AppTheme.light(dense: _isDesktop)` — 모바일은 dense 끄기(이미 그렇게 동작).

## 5. 플랫폼별 설정

공통 식별자 후보(§9 결정): macOS의 `art.zoomon.notes2hub`와 **같은 ID**를 Android `applicationId`·iOS bundle ID에 쓴다(스토어에서 앱 하나로 묶고 싶을 때 유리). 표시 이름은 `Notes2Hub`(번역 안 함).

**Android**
- `minSdk` 24(Flutter 기본), arm64-v8a·x86_64만 포함. `git2dart_binaries`는 32비트 libgit2도 넣지만 libflutter·libapp이 64비트만 있어서 `packaging.jniLibs.excludes`로 빼 **32비트 기기에는 설치 자체가 되지 않게** 했다(README에 명시).
- 권한: **`INTERNET`만**. 저장소는 앱 전용 폴더라 저장소 권한 불필요. 카메라는 `image_picker`가 시스템 앱을 호출해 별도 권한 불필요.
- `flutter_secure_storage`: `android:allowBackup="false"` 또는 키 항목 백업 제외(토큰이 다른 기기로 복원돼 못 쓰게 되는 문제 방지).
- 서명: 릴리스 keystore를 만들고 GitHub Secrets로 CI에 주입(분실 시 업데이트 불가 → **백업 필수**).
- 릴리스 산출물: `Notes2Hub-<버전>-android-arm64.apk`(GitHub Release 직접 설치용), 스토어용 `.aab`는 §9 결정에 따라.

**iOS**
- Deployment target 15.0(예정). CocoaPods 사용(git2dart 요건).
- `Info.plist`: `NSPhotoLibraryUsageDescription`, `NSCameraUsageDescription`(한국어/영어 현지화). 수출 규정 암호화 질문(`ITSAppUsesNonExemptEncryption`): HTTPS만 사용 → `false`가 일반적이나 스토어 제출 때 확인.
- Keychain: macOS와 달리 iOS는 기본 키체인으로 충분(데이터 보호 키체인 설정 불필요). **앱 삭제 후 재설치 시 토큰이 남는** iOS 특성 → 첫 실행 때 "이전 로그인 사용" 처리 또는 설치 마커로 정리.
- 서명: Apple Developer Program 필요 여부는 배포 방식(§9)에 달림.

## 6. 동기화 — 모바일 수명주기 대응

모바일은 앱이 **언제든 멈추거나 종료**되는 것이 핵심 차이다. 데스크톱 설계를 바꾸지 않고 다음만 보강한다.

1. **백그라운드 동기화는 하지 않는다(v1).** 동기화는 앱이 앞에 있을 때만. 자동 모드의 30초 타이머, 시작·복귀 시 pull, 5분 주기는 포그라운드에서 그대로 쓴다.
2. **앱이 뒤로 갈 때(`paused`)**: 이미 하는 초안 flush에 더해, 자동 모드면 **한 번 최선 동기화**를 시도한다(iOS는 약 30초, Android는 곧 중단될 수 있음 → 실패해도 괜찮게: 로컬 커밋은 남고 "올리지 못한 변경"으로 표시되는 기존 Phase 3 동작).
3. **stale `.git/index.lock` 자동 정리**(필수로 격상): PLAN.md §4-1이 데스크톱 "알려진 한계"로 남긴 항목. 모바일은 OS가 동기화 중에 앱을 죽이는 일이 흔하므로, 서비스가 동기화를 하고 있지 않은 시작 시점에 락 파일이 있으면 지우고 진행한다.
4. **Device Flow 로그인 중 앱 전환**: 브라우저로 갔다 오는 사이 iOS가 폴링을 멈춘다 → `resumed`에서 즉시 폴링 재개, 코드 복사 버튼 + `github.com/login/device`를 여는 버튼 제공. 만료(15분) 시 안내.
5. **네트워크 전환(Wi-Fi ↔ LTE)**: 실패는 기존 재시도(30초→1분→2분→5분)에 맡긴다. 데이터 요금 걱정을 위해 "Wi-Fi에서만 동기화" 옵션은 v1.1 후보.
6. **저장 공간**: 모든 메모와 첨부가 기기에 있다. 설정에 repo 크기 표시(PLAN.md §9의 500MB 경고선 재사용).

> 후속(v1.1+): Android WorkManager / iOS BGAppRefreshTask 로 가끔 pull만 하는 백그라운드 갱신. iOS는 실행 시점을 OS가 정하므로 신뢰하기 어렵다.

## 7. 빌드·릴리스·CI

- `flutter create --platforms=ios,android .`로 폴더 생성 후, 규약(conventions-v1)의 식별자·버전·아이콘·l10n 규칙에 맞춘다. `flutter-app-convention-audit` 스킬로 모바일 추가분의 누락(아이콘 세트, 이름 현지화 등)을 점검한다.
- **아이콘**: `tool/icon/generate_icons.py`에 Android(adaptive icon: foreground/background, 모노크롬 선택)·iOS(AppIcon 세트, 알파 없음) 출력 추가. 현재 아이콘은 임시 글리프라 정식 아이콘이 나오면 한 번에 교체.
- **버전**: `pubspec.yaml`의 `version: x.y.z+N`을 그대로 공유(Android versionName/versionCode, iOS CFBundleShortVersionString/Version). `scripts/bump-version.sh`가 `+N`을 올리는지 확인.
- **릴리스 워크플로**: 기존 `check → build(macOS/Windows/Linux) → release` 구조에 **build-android**(ubuntu, keystore를 Secrets에서 복원, APK/AAB) 와 **build-ios** 잡을 추가. 모든 빌드가 성공해야 Release가 만들어지는 기존 규칙 유지. 산출물 이름은 `Notes2Hub-<버전>-android-arm64.apk` 형식으로 기존 명명과 맞춘다.
  - iOS: 서명 없이 빌드 검증(`flutter build ios --no-codesign`)까지는 무료 CI로 가능. IPA 서명·업로드는 §9 결정에 따라.
- **테스트**: 기존 `flutter test`(엔진·서비스·보드·좁은 화면)는 모바일 변경 후에도 통과해야 하고, 모바일 전용 단위 테스트(기기 이름, stale lock, 모바일 이미지 입력 경로 어댑터)를 추가한다. 통합 테스트는 안드로이드 에뮬레이터 `-d <emulator>`로 최소 시나리오(메모 작성 → 저장 → 로컬 bare origin 동기화). **iOS 시뮬레이터/macOS 통합 테스트도 실제 키체인을 공유하므로 테스트 전용 키만 쓴다**(CLAUDE.md 규칙 동일).

## 8. 단계와 산출물

| Phase | 내용 | 산출물 / 완료 기준 |
|---|---|---|
| M0 | 모바일 폴더 생성 + git2dart PoC(§3) + 판정 | PoC 결과를 이 문서 §3에 기록. **실패 시 여기서 멈추고 `RestApiEngine` 여부 재결정** |
| M1 ✅ | 모바일 앱 뼈대: 데스크톱 전용 코드 분리, 경로·기기 이름·토큰 저장, 로컬 메모 CRUD가 폰에서 동작 | 에뮬레이터에서 보드·편집·검색·북마크 |
| M2 (Android ✅ / iOS ✅) | 동기화: 로그인(Device Flow, 앱 전환 대응), 저장소 연결, 수동/자동 동기화, 충돌 사본, stale lock 정리 | 실기기 2대(폰+PC)로 왕복 동기화 확인 |
| M3 | 모바일 UI 다듬기: FAB, 길게 누르기 메뉴, 당겨서 새로고침, 서식 도구줄, 키보드·안전 영역·가로 모드 | 주요 화면 폰/태블릿 스크린샷 |
| M4 | 이미지: 카메라/보관함 → 1MiB 변환 → `assets/` 동기화, 미리보기 | 실기기에서 사진 첨부 → PC에서 보임 |
| M5 (코드·CI·문서 완료, 시크릿·스토어 등록 대기) | 릴리스: 아이콘, 서명, CI 모바일 잡, README(설치 방법·32비트 미지원 등), 스토어/설치 배포(§9) | `v0.2.0-rc.1` 모바일 산출물 포함 프리릴리스 |

M0이 가장 중요하고 가장 먼저 한다. 나머지는 PoC 결과에 따라 순서·범위가 바뀔 수 있다.

> 릴리스 절차·시크릿·스토어 체크리스트는 [MOBILE_RELEASE.md](MOBILE_RELEASE.md).

## 9. 결정이 필요한 것 (제안 포함)

| # | 질문 | 제안 | 이유 |
|---|---|---|---|
| 1 | **iOS 배포 방식** | ✅ **결정(2026-10-05)**: Apple Developer Program 연계 완료 → TestFlight/App Store로 배포 | 서명·프로비저닝·App Store Connect 설정은 M5에서 |
| 2 | **Android 배포 방식** | ✅ **결정(2026-10-05)**: GitHub Release APK + **Google Play 추가 예정** | Play는 AAB·앱 서명 키(Play App Signing)·콘텐츠 등급/데이터 안전 양식 필요 → M5 |
| 3 | 식별자 | macOS와 같은 `art.zoomon.notes2hub` | 한 앱으로 일관 |
| 4 | 최소 OS | ✅ Android 7.0(API 24) · iOS 15 | Flutter 3.47 기본값, 실측으로 확인 |
| 5 | 폰에서 직접 편집을 허용할지 vs 읽기 전용 뷰어로 시작할지 | **편집 포함**(빠른 메모가 모바일의 핵심 가치) | 읽기 전용이면 훨씬 가볍지만 쓸모가 줄어듦 |
| 6 | 태블릿 | 폰 레이아웃을 키워서 쓰고, 가로 2~3열 보드까지만(분할 보기 없음) | 데스크톱과 같은 "보드 → 전체 편집" 구조 유지 |
| 7 | 릴리스 버전 | 데스크톱 `v0.1.0` 정식 이후 **`v0.2.0`**부터 모바일 포함 | 같은 태그에 모든 플랫폼 산출물 |

## 10. 리스크

| 리스크 | 영향 | 대응 |
|---|---|---|
| git2dart가 iOS 실기기/Android에서 실패 | 엔진 교체(`RestApiEngine`) 필요 → 일정 증가 | M0에서 가장 먼저 검증, 인터페이스 뒤 교체 |
| libgit2 바이너리가 앱 크기를 크게 늘림 | 설치 용량 | ABI 분할(arm64 위주), 크기 측정 후 판단 |
| iOS 유료 계정 비용 | 배포 불가/지연 | §9-1 결정. 사이드로드로 먼저 검증 |
| OS가 동기화 중 앱 종료 → 락 파일 잔존 | 다음 동기화 오류 | stale lock 자동 정리(§6-3) |
| 큰 사진 처리 중 메모리 부족 | 앱 종료 | Isolate + 디코딩 전 축소 힌트, 한 번에 하나씩 처리 |
| 토큰이 기기 분실·백업으로 노출 | 보안 | Keychain/Keystore, Android 백업 제외, GitHub에서 앱 승인 철회 안내 |
| 모바일 키보드/IME(한글 조합)와 서식 도구줄 충돌 | 입력 깨짐 | 선택 영역·조합 중 삽입 처리를 위젯 테스트로 확인, 실기기 확인 |
| Device Flow가 폰에서 번거로움 | 첫 사용 이탈 | 코드 자동 복사 + 브라우저 열기 버튼, 같은 폰에서 완료 가능한 흐름 확인 |

## 11. 이 문서가 확정되면 바로 할 일
1. §9의 1·2번(배포 방식) 결정
2. M0 PoC 착수 — `flutter create --platforms=ios,android .` + `tool/poc/` 모바일 확장
3. 결과를 §3에 기록하고 CLAUDE.md의 "현재 단계"와 PLAN.md Phase 6에 이 문서 링크 추가
