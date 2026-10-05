# 모바일 릴리스 가이드

iOS·Android를 배포하기 위해 **사람이 한 번 해 두어야 하는 일**과 CI가 하는 일을 정리한다. 설계와 진행 상황은 [MOBILE_PLAN.md](MOBILE_PLAN.md).

## 산출물

| 플랫폼 | 파일 | 용도 |
|---|---|---|
| Android | `Notes2Hub-<버전>-android-arm64.apk` | GitHub Release에서 직접 설치 |
| Android | `Notes2Hub-<버전>-android.aab` | Google Play Console에 올리는 파일 (arm64 + x86_64) |
| iOS | (CI는 서명 없는 빌드 확인만) | TestFlight/App Store는 아래 "iOS" 참고 |

- 버전은 `pubspec.yaml`의 `version: x.y.z+N` 하나다. Android `versionName`/`versionCode`, iOS `CFBundleShortVersionString`/`CFBundleVersion`이 여기서 나온다. `scripts/bump-version.sh`가 `+N`을 항상 1씩 올린다 (스토어는 같은 번호를 다시 받지 않는다).
- 최소 OS: Android 7.0(API 24), iOS 15.0. **32비트 ARM·x86 기기는 지원하지 않는다** — Flutter 엔진과 앱은 64비트만 만들어서, 해당 라이브러리를 패키지에서 빼 설치 자체가 되지 않게 했다 (`android/app/build.gradle.kts`의 `packaging`).

## Android

### 1. 업로드 키 만들기 (한 번)
키 파일과 비밀번호는 **절대 저장소에 올리지 않는다**(`android/.gitignore`가 `*.jks`, `key.properties`를 막고 있다). 잃어버리면 앱 업데이트를 못 하니 안전한 곳에 **백업**한다.

```bash
keytool -genkeypair -v -keystore ~/notes2hub-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

### 2. GitHub 시크릿 (저장소 Settings → Secrets and variables → Actions)
| 시크릿 | 값 |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -i ~/notes2hub-upload.jks` 출력 전체 |
| `ANDROID_KEYSTORE_PASSWORD` | 키 저장소 비밀번호 |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | 키 비밀번호 |

`gh secret set ANDROID_KEYSTORE_BASE64 < <(base64 -i ~/notes2hub-upload.jks)`처럼 파이프로 넣으면 셸 기록에 값이 남지 않는다. **시크릿이 하나라도 없으면 `build-android`가 실패하고, 그러면 릴리스 전체가 만들어지지 않는다**(모든 플랫폼이 성공해야 게시하는 규칙). 첫 태그를 달기 전에 넣어 둘 것.

### 3. 로컬에서 서명된 빌드 만들기 (선택)
`android/key.properties`(git 제외)를 만들면 로컬 `--release` 빌드도 같은 키로 서명된다. 파일이 없으면 debug 키로 서명된다(개발용, 배포 금지).

```properties
storeFile=/Users/<you>/notes2hub-upload.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

> **서명이 바뀌면 설치된 앱을 덮어쓸 수 없다.** 지금 개발 중인 폰에 debug 키로 깔린 앱이 있으면, 업로드 키로 서명한 APK를 설치하기 전에 앱을 삭제해야 한다(로컬 메모는 GitHub에 동기화돼 있으면 다시 받는다 — 단, 동기화하지 않은 변경은 사라진다).

### 4. Google Play
- 개발자 계정(1회 US$25)과 앱 만들기, **Play 앱 서명**을 켠다: 우리가 가진 건 *업로드 키*이고 Google이 실제 *앱 서명 키*를 보관한다. 업로드 키를 잃어도 Google에 재설정을 요청할 수 있다.
- 필요한 것: 스토어 설명(한/영)·스크린샷·512px 아이콘(`assets/icon/app_icon_1024.png`에서), **개인정보 처리방침 URL**, 데이터 보안 양식(토큰은 기기 안에만 저장하고 개발자 서버로 아무것도 보내지 않는다 — 메모는 사용자 본인의 GitHub 저장소로만 간다), 콘텐츠 등급, 대상 연령.
- **새 개인 개발자 계정은 정식 출시 전에 비공개 테스트(여러 명, 일정 기간) 요건이 있을 수 있다.** 계정 종류에 따라 다르니 Play Console의 안내를 확인할 것.
- **같은 앱이라도 서명 키가 달라서** Play로 설치한 앱과 GitHub APK는 서로 덮어 업데이트할 수 없다. 한 사용자는 한 경로만 쓰도록 README에 안내한다.

## iOS

Apple Developer Program은 연계되어 있다. 아직 안 한 것:

1. **App ID 등록**: `art.zoomon.notes2hub` (macOS 앱과 같은 ID). App Store Connect에서 앱 레코드를 만든다.
2. **Xcode 서명 지정**: `ios/Runner.xcworkspace` → Runner 타깃 → Signing & Capabilities에서 Team 선택. 실기기 확인(iPhone)을 이때 한다.
3. **수출 규정(암호화) 질문**: HTTPS/SSH 통신에 libgit2·OpenSSL·libssh2를 쓴다. App Store Connect의 질문에 사실대로 답한다(표준 암호화만 사용). 답이 정해지면 `Info.plist`의 `ITSAppUsesNonExemptEncryption`을 넣어 질문을 줄일 수 있다.
4. **CI 서명·업로드**: 현재 CI는 `flutter build ios --no-codesign` 컴파일 확인만 한다. TestFlight 자동 업로드에는 *배포 인증서(.p12)*, *프로비저닝 프로파일*, *App Store Connect API 키(Issuer ID, Key ID, .p8)*가 시크릿으로 필요하다. 실기기 확인이 끝난 뒤 `build-ios` 잡에 서명·업로드 단계를 추가한다.
5. 스토어 항목은 Android와 같다(설명·스크린샷·개인정보 처리방침·앱 개인정보 보호 응답).

## 릴리스 순서 (데스크톱과 같다)
1. `scripts/bump-version.sh <patch|minor|major|x.y.z-rc.N>` → PR → 병합
2. 병합 커밋에 `vX.Y.Z` 태그 → CI가 macOS·Windows·Linux·Android를 빌드하고 iOS는 컴파일을 확인한 뒤, 전부 성공하면 GitHub Release를 만든다.
3. Play Console에 `.aab`를 올려 검토를 요청한다(처음에는 내부 테스트 트랙으로).
