import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ko.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ko'),
  ];

  /// No description provided for @aboutTooltip.
  ///
  /// In ko, this message translates to:
  /// **'정보'**
  String get aboutTooltip;

  /// No description provided for @aboutVersion.
  ///
  /// In ko, this message translates to:
  /// **'버전 {version} (빌드 {build})'**
  String aboutVersion(String version, String build);

  /// No description provided for @aboutOpenSourceLicenses.
  ///
  /// In ko, this message translates to:
  /// **'오픈소스 라이선스'**
  String get aboutOpenSourceLicenses;

  /// No description provided for @aboutRepository.
  ///
  /// In ko, this message translates to:
  /// **'GitHub'**
  String get aboutRepository;

  /// No description provided for @commonClose.
  ///
  /// In ko, this message translates to:
  /// **'닫기'**
  String get commonClose;

  /// No description provided for @aboutMenuItem.
  ///
  /// In ko, this message translates to:
  /// **'{appName} 정보'**
  String aboutMenuItem(String appName);

  /// No description provided for @themeMenuTooltip.
  ///
  /// In ko, this message translates to:
  /// **'테마'**
  String get themeMenuTooltip;

  /// No description provided for @themeSystem.
  ///
  /// In ko, this message translates to:
  /// **'시스템 설정 따르기'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In ko, this message translates to:
  /// **'라이트'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In ko, this message translates to:
  /// **'다크'**
  String get themeDark;

  /// No description provided for @languageMenuTooltip.
  ///
  /// In ko, this message translates to:
  /// **'언어'**
  String get languageMenuTooltip;

  /// No description provided for @languageSystem.
  ///
  /// In ko, this message translates to:
  /// **'시스템 설정 따르기 / System'**
  String get languageSystem;

  /// No description provided for @languageSystemShort.
  ///
  /// In ko, this message translates to:
  /// **'시스템'**
  String get languageSystemShort;

  /// No description provided for @aboutTagline.
  ///
  /// In ko, this message translates to:
  /// **'내 GitHub 저장소로 동기화하는 Markdown 메모 앱'**
  String get aboutTagline;

  /// No description provided for @aboutDescription.
  ///
  /// In ko, this message translates to:
  /// **'메모를 Markdown 파일로 저장하고, 내 GitHub 저장소에 동기화해 여러 PC에서 이어서 씁니다. 별도 서버나 구독이 필요 없습니다.'**
  String get aboutDescription;

  /// No description provided for @homeEmptyTitle.
  ///
  /// In ko, this message translates to:
  /// **'아직 메모가 없습니다'**
  String get homeEmptyTitle;

  /// No description provided for @homeEmptyAction.
  ///
  /// In ko, this message translates to:
  /// **'새 메모'**
  String get homeEmptyAction;

  /// No description provided for @notesSearchHint.
  ///
  /// In ko, this message translates to:
  /// **'메모 검색'**
  String get notesSearchHint;

  /// No description provided for @noteNew.
  ///
  /// In ko, this message translates to:
  /// **'새 메모'**
  String get noteNew;

  /// No description provided for @noteUntitled.
  ///
  /// In ko, this message translates to:
  /// **'제목 없음'**
  String get noteUntitled;

  /// No description provided for @notesNoResults.
  ///
  /// In ko, this message translates to:
  /// **'검색 결과가 없습니다'**
  String get notesNoResults;

  /// No description provided for @noteSelectHint.
  ///
  /// In ko, this message translates to:
  /// **'메모를 선택하거나 새로 만드세요'**
  String get noteSelectHint;

  /// No description provided for @noteSave.
  ///
  /// In ko, this message translates to:
  /// **'저장'**
  String get noteSave;

  /// No description provided for @noteSaved.
  ///
  /// In ko, this message translates to:
  /// **'저장됨'**
  String get noteSaved;

  /// No description provided for @noteUnsaved.
  ///
  /// In ko, this message translates to:
  /// **'저장 안 됨'**
  String get noteUnsaved;

  /// No description provided for @noteRevert.
  ///
  /// In ko, this message translates to:
  /// **'변경 취소'**
  String get noteRevert;

  /// No description provided for @noteDelete.
  ///
  /// In ko, this message translates to:
  /// **'삭제'**
  String get noteDelete;

  /// No description provided for @noteDeleteTitle.
  ///
  /// In ko, this message translates to:
  /// **'메모를 삭제할까요?'**
  String get noteDeleteTitle;

  /// No description provided for @noteDeleteBody.
  ///
  /// In ko, this message translates to:
  /// **'\'{title}\' 메모가 영구히 삭제됩니다.'**
  String noteDeleteBody(String title);

  /// No description provided for @commonCancel.
  ///
  /// In ko, this message translates to:
  /// **'취소'**
  String get commonCancel;

  /// No description provided for @commonCopy.
  ///
  /// In ko, this message translates to:
  /// **'복사'**
  String get commonCopy;

  /// No description provided for @noteEditTab.
  ///
  /// In ko, this message translates to:
  /// **'편집'**
  String get noteEditTab;

  /// No description provided for @notePreviewTab.
  ///
  /// In ko, this message translates to:
  /// **'미리보기'**
  String get notePreviewTab;

  /// No description provided for @noteBodyHint.
  ///
  /// In ko, this message translates to:
  /// **'내용을 Markdown으로 입력하세요'**
  String get noteBodyHint;

  /// No description provided for @noteSaveFailed.
  ///
  /// In ko, this message translates to:
  /// **'저장하지 못했습니다: {error}'**
  String noteSaveFailed(String error);

  /// No description provided for @noteLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'메모를 불러오지 못했습니다: {error}'**
  String noteLoadFailed(String error);

  /// No description provided for @syncTooltip.
  ///
  /// In ko, this message translates to:
  /// **'동기화'**
  String get syncTooltip;

  /// No description provided for @syncNotConnected.
  ///
  /// In ko, this message translates to:
  /// **'GitHub 연결'**
  String get syncNotConnected;

  /// No description provided for @syncRunning.
  ///
  /// In ko, this message translates to:
  /// **'동기화 중…'**
  String get syncRunning;

  /// No description provided for @syncDone.
  ///
  /// In ko, this message translates to:
  /// **'동기화됨'**
  String get syncDone;

  /// No description provided for @syncDoneAgo.
  ///
  /// In ko, this message translates to:
  /// **'동기화됨 · {time}'**
  String syncDoneAgo(String time);

  /// No description provided for @syncPending.
  ///
  /// In ko, this message translates to:
  /// **'동기화 대기 {count}'**
  String syncPending(int count);

  /// No description provided for @syncOffline.
  ///
  /// In ko, this message translates to:
  /// **'오프라인'**
  String get syncOffline;

  /// No description provided for @syncError.
  ///
  /// In ko, this message translates to:
  /// **'동기화 오류'**
  String get syncError;

  /// No description provided for @syncReauth.
  ///
  /// In ko, this message translates to:
  /// **'다시 로그인 필요'**
  String get syncReauth;

  /// No description provided for @syncRemoteAhead.
  ///
  /// In ko, this message translates to:
  /// **'원격에 새 변경'**
  String get syncRemoteAhead;

  /// No description provided for @syncConflictCopies.
  ///
  /// In ko, this message translates to:
  /// **'충돌한 메모 {count}개를 \"충돌\" 사본으로 보존했습니다'**
  String syncConflictCopies(int count);

  /// No description provided for @syncFailed.
  ///
  /// In ko, this message translates to:
  /// **'동기화하지 못했습니다: {error}'**
  String syncFailed(String error);

  /// No description provided for @timeJustNow.
  ///
  /// In ko, this message translates to:
  /// **'방금'**
  String get timeJustNow;

  /// No description provided for @timeMinutesAgo.
  ///
  /// In ko, this message translates to:
  /// **'{n}분 전'**
  String timeMinutesAgo(int n);

  /// No description provided for @timeHoursAgo.
  ///
  /// In ko, this message translates to:
  /// **'{n}시간 전'**
  String timeHoursAgo(int n);

  /// No description provided for @settingsTitle.
  ///
  /// In ko, this message translates to:
  /// **'설정'**
  String get settingsTitle;

  /// No description provided for @settingsAccount.
  ///
  /// In ko, this message translates to:
  /// **'GitHub 계정'**
  String get settingsAccount;

  /// No description provided for @settingsSignedInAs.
  ///
  /// In ko, this message translates to:
  /// **'{login} 님으로 로그인됨'**
  String settingsSignedInAs(String login);

  /// No description provided for @settingsSignedOut.
  ///
  /// In ko, this message translates to:
  /// **'로그인하지 않았습니다'**
  String get settingsSignedOut;

  /// No description provided for @settingsLoginBrowser.
  ///
  /// In ko, this message translates to:
  /// **'GitHub로 로그인'**
  String get settingsLoginBrowser;

  /// No description provided for @settingsLogout.
  ///
  /// In ko, this message translates to:
  /// **'로그아웃'**
  String get settingsLogout;

  /// No description provided for @settingsRepo.
  ///
  /// In ko, this message translates to:
  /// **'메모 저장소'**
  String get settingsRepo;

  /// No description provided for @settingsNoRepo.
  ///
  /// In ko, this message translates to:
  /// **'연결된 저장소가 없습니다'**
  String get settingsNoRepo;

  /// No description provided for @settingsRepoConnect.
  ///
  /// In ko, this message translates to:
  /// **'저장소 연결'**
  String get settingsRepoConnect;

  /// No description provided for @settingsRepoChange.
  ///
  /// In ko, this message translates to:
  /// **'변경'**
  String get settingsRepoChange;

  /// No description provided for @settingsSyncMode.
  ///
  /// In ko, this message translates to:
  /// **'동기화 방식'**
  String get settingsSyncMode;

  /// No description provided for @settingsSyncManual.
  ///
  /// In ko, this message translates to:
  /// **'수동'**
  String get settingsSyncManual;

  /// No description provided for @settingsSyncAuto.
  ///
  /// In ko, this message translates to:
  /// **'자동 (저장 30초 후)'**
  String get settingsSyncAuto;

  /// No description provided for @settingsSyncHint.
  ///
  /// In ko, this message translates to:
  /// **'가져오기는 시작할 때, 창으로 돌아올 때, 5분마다 자동으로 합니다. 보내기는 위 설정을 따릅니다.'**
  String get settingsSyncHint;

  /// No description provided for @settingsSyncHintMobile.
  ///
  /// In ko, this message translates to:
  /// **'가져오기는 시작할 때, 앱으로 돌아올 때, 앱을 열어 둔 동안 5분마다 자동으로 합니다. 보내기는 위 설정을 따릅니다.'**
  String get settingsSyncHintMobile;

  /// No description provided for @loginTitle.
  ///
  /// In ko, this message translates to:
  /// **'GitHub 로그인'**
  String get loginTitle;

  /// No description provided for @loginTabBrowser.
  ///
  /// In ko, this message translates to:
  /// **'브라우저'**
  String get loginTabBrowser;

  /// No description provided for @loginTabToken.
  ///
  /// In ko, this message translates to:
  /// **'토큰'**
  String get loginTabToken;

  /// No description provided for @loginDeviceStep.
  ///
  /// In ko, this message translates to:
  /// **'브라우저에서 아래 코드를 입력하고 승인하세요'**
  String get loginDeviceStep;

  /// No description provided for @loginDeviceStepMobile.
  ///
  /// In ko, this message translates to:
  /// **'코드를 복사했어요. 브라우저 열기를 누르고 입력칸을 길게 눌러 붙여넣은 뒤 승인하세요. 끝나면 이 앱으로 돌아오세요.'**
  String get loginDeviceStepMobile;

  /// No description provided for @loginCodeCopied.
  ///
  /// In ko, this message translates to:
  /// **'코드 복사됨'**
  String get loginCodeCopied;

  /// No description provided for @loginOpenBrowser.
  ///
  /// In ko, this message translates to:
  /// **'브라우저 열기'**
  String get loginOpenBrowser;

  /// No description provided for @loginCopyCode.
  ///
  /// In ko, this message translates to:
  /// **'코드 복사'**
  String get loginCopyCode;

  /// No description provided for @loginWaiting.
  ///
  /// In ko, this message translates to:
  /// **'승인을 기다리는 중…'**
  String get loginWaiting;

  /// No description provided for @loginDeviceUnavailable.
  ///
  /// In ko, this message translates to:
  /// **'이 빌드에는 GitHub 앱 등록(Client ID)이 없어 브라우저 로그인을 쓸 수 없습니다. 토큰으로 로그인하세요.'**
  String get loginDeviceUnavailable;

  /// No description provided for @loginStart.
  ///
  /// In ko, this message translates to:
  /// **'로그인 시작'**
  String get loginStart;

  /// No description provided for @loginTokenLabel.
  ///
  /// In ko, this message translates to:
  /// **'Personal access token'**
  String get loginTokenLabel;

  /// No description provided for @loginTokenHelp.
  ///
  /// In ko, this message translates to:
  /// **'repo 권한이 있는 토큰이 필요합니다. 토큰은 OS 보안 저장소에만 저장됩니다.'**
  String get loginTokenHelp;

  /// No description provided for @loginSubmit.
  ///
  /// In ko, this message translates to:
  /// **'로그인'**
  String get loginSubmit;

  /// No description provided for @loginFailed.
  ///
  /// In ko, this message translates to:
  /// **'로그인하지 못했습니다: {error}'**
  String loginFailed(String error);

  /// No description provided for @repoTitle.
  ///
  /// In ko, this message translates to:
  /// **'메모 저장소 연결'**
  String get repoTitle;

  /// No description provided for @repoCreateTitle.
  ///
  /// In ko, this message translates to:
  /// **'새 비공개 저장소 만들기'**
  String get repoCreateTitle;

  /// No description provided for @repoNameLabel.
  ///
  /// In ko, this message translates to:
  /// **'저장소 이름'**
  String get repoNameLabel;

  /// No description provided for @repoCreate.
  ///
  /// In ko, this message translates to:
  /// **'만들기'**
  String get repoCreate;

  /// No description provided for @repoExisting.
  ///
  /// In ko, this message translates to:
  /// **'기존 저장소에서 선택'**
  String get repoExisting;

  /// No description provided for @repoSearch.
  ///
  /// In ko, this message translates to:
  /// **'저장소 검색'**
  String get repoSearch;

  /// No description provided for @repoPublic.
  ///
  /// In ko, this message translates to:
  /// **'공개'**
  String get repoPublic;

  /// No description provided for @repoPrivate.
  ///
  /// In ko, this message translates to:
  /// **'비공개'**
  String get repoPrivate;

  /// No description provided for @repoPublicConfirmTitle.
  ///
  /// In ko, this message translates to:
  /// **'공개 저장소입니다'**
  String get repoPublicConfirmTitle;

  /// No description provided for @repoPublicConfirmBody.
  ///
  /// In ko, this message translates to:
  /// **'\'{name}\'은(는) 누구나 볼 수 있는 공개 저장소입니다. 메모가 모두에게 공개됩니다. 그래도 연결할까요?'**
  String repoPublicConfirmBody(String name);

  /// No description provided for @repoConnect.
  ///
  /// In ko, this message translates to:
  /// **'연결'**
  String get repoConnect;

  /// No description provided for @repoAutoConnected.
  ///
  /// In ko, this message translates to:
  /// **'{name}에 연결했어요'**
  String repoAutoConnected(String name);

  /// No description provided for @repoConnecting.
  ///
  /// In ko, this message translates to:
  /// **'연결 중…'**
  String get repoConnecting;

  /// No description provided for @repoNoMatch.
  ///
  /// In ko, this message translates to:
  /// **'일치하는 저장소가 없습니다'**
  String get repoNoMatch;

  /// No description provided for @repoLoadFailed.
  ///
  /// In ko, this message translates to:
  /// **'저장소 목록을 불러오지 못했습니다: {error}'**
  String repoLoadFailed(String error);

  /// No description provided for @repoConnectFailed.
  ///
  /// In ko, this message translates to:
  /// **'저장소를 연결하지 못했습니다: {error}'**
  String repoConnectFailed(String error);

  /// No description provided for @settingsTooltip.
  ///
  /// In ko, this message translates to:
  /// **'설정'**
  String get settingsTooltip;

  /// No description provided for @syncUnsavedSkipped.
  ///
  /// In ko, this message translates to:
  /// **'저장하지 않은 메모 {count}개는 동기화에 포함되지 않았습니다'**
  String syncUnsavedSkipped(int count);

  /// No description provided for @syncUnpushed.
  ///
  /// In ko, this message translates to:
  /// **'올리지 못한 변경'**
  String get syncUnpushed;

  /// No description provided for @imageAdd.
  ///
  /// In ko, this message translates to:
  /// **'이미지 추가'**
  String get imageAdd;

  /// No description provided for @imageProcessing.
  ///
  /// In ko, this message translates to:
  /// **'이미지를 넣는 중…'**
  String get imageProcessing;

  /// No description provided for @imageProcessingCount.
  ///
  /// In ko, this message translates to:
  /// **'이미지를 넣는 중… {done} / {total}'**
  String imageProcessingCount(int done, int total);

  /// No description provided for @imageProcessingHint.
  ///
  /// In ko, this message translates to:
  /// **'큰 사진은 1MB 미만으로 줄이느라 시간이 조금 걸립니다.'**
  String get imageProcessingHint;

  /// No description provided for @shareTooltip.
  ///
  /// In ko, this message translates to:
  /// **'공유'**
  String get shareTooltip;

  /// No description provided for @shareTitle.
  ///
  /// In ko, this message translates to:
  /// **'메모 공유'**
  String get shareTitle;

  /// No description provided for @shareFull.
  ///
  /// In ko, this message translates to:
  /// **'전체 공유'**
  String get shareFull;

  /// No description provided for @shareFullHint.
  ///
  /// In ko, this message translates to:
  /// **'메일·메신저 — 글 전체와 이미지를 모두'**
  String get shareFullHint;

  /// No description provided for @shareSms.
  ///
  /// In ko, this message translates to:
  /// **'문자용'**
  String get shareSms;

  /// No description provided for @shareSmsHint.
  ///
  /// In ko, this message translates to:
  /// **'앞 {max}자까지, 이미지는 첫 번째 1장만'**
  String shareSmsHint(int max);

  /// No description provided for @shareCopy.
  ///
  /// In ko, this message translates to:
  /// **'텍스트 복사'**
  String get shareCopy;

  /// No description provided for @shareCopyHint.
  ///
  /// In ko, this message translates to:
  /// **'글만 클립보드에 복사 (이미지 제외)'**
  String get shareCopyHint;

  /// No description provided for @shareCopied.
  ///
  /// In ko, this message translates to:
  /// **'클립보드에 복사했어요'**
  String get shareCopied;

  /// No description provided for @shareFailed.
  ///
  /// In ko, this message translates to:
  /// **'공유하지 못했습니다: {error}'**
  String shareFailed(String error);

  /// No description provided for @shareNothing.
  ///
  /// In ko, this message translates to:
  /// **'아직 공유할 내용이 없어요'**
  String get shareNothing;

  /// No description provided for @imageDropHere.
  ///
  /// In ko, this message translates to:
  /// **'이미지를 놓아서 추가'**
  String get imageDropHere;

  /// No description provided for @imageBroken.
  ///
  /// In ko, this message translates to:
  /// **'이미지를 찾을 수 없습니다'**
  String get imageBroken;

  /// No description provided for @imageConverted.
  ///
  /// In ko, this message translates to:
  /// **'{name}: 1MB를 넘어 JPEG로 줄였습니다 ({before} → {after})'**
  String imageConverted(String name, String before, String after);

  /// No description provided for @imageStillLarge.
  ///
  /// In ko, this message translates to:
  /// **'{name}: 최대한 줄였지만 여전히 1MB가 넘습니다 ({size})'**
  String imageStillLarge(String name, String size);

  /// No description provided for @imageAnimatedTooLarge.
  ///
  /// In ko, this message translates to:
  /// **'{name}: 움직이는 이미지는 줄일 수 없어서 1MB를 넘는 파일은 추가하지 못했습니다'**
  String imageAnimatedTooLarge(String name);

  /// No description provided for @imageUnsupported.
  ///
  /// In ko, this message translates to:
  /// **'{name}: 지원하지 않거나 읽을 수 없는 이미지입니다'**
  String imageUnsupported(String name);

  /// No description provided for @imageFailed.
  ///
  /// In ko, this message translates to:
  /// **'{name}: 이미지를 추가하지 못했습니다: {error}'**
  String imageFailed(String name, String error);

  /// No description provided for @boardCaptureSend.
  ///
  /// In ko, this message translates to:
  /// **'빠른 메모 저장'**
  String get boardCaptureSend;

  /// No description provided for @formatBold.
  ///
  /// In ko, this message translates to:
  /// **'굵게'**
  String get formatBold;

  /// No description provided for @formatItalic.
  ///
  /// In ko, this message translates to:
  /// **'기울임'**
  String get formatItalic;

  /// No description provided for @formatHeading.
  ///
  /// In ko, this message translates to:
  /// **'제목'**
  String get formatHeading;

  /// No description provided for @formatList.
  ///
  /// In ko, this message translates to:
  /// **'목록'**
  String get formatList;

  /// No description provided for @formatChecklist.
  ///
  /// In ko, this message translates to:
  /// **'체크리스트'**
  String get formatChecklist;

  /// No description provided for @formatQuote.
  ///
  /// In ko, this message translates to:
  /// **'인용'**
  String get formatQuote;

  /// No description provided for @formatLink.
  ///
  /// In ko, this message translates to:
  /// **'링크'**
  String get formatLink;

  /// No description provided for @imageTakePhoto.
  ///
  /// In ko, this message translates to:
  /// **'사진 찍기'**
  String get imageTakePhoto;

  /// No description provided for @imageFromGallery.
  ///
  /// In ko, this message translates to:
  /// **'사진 보관함'**
  String get imageFromGallery;

  /// No description provided for @boardCaptureHint.
  ///
  /// In ko, this message translates to:
  /// **'생각나는 대로 쓰고 Enter를 누르세요'**
  String get boardCaptureHint;

  /// No description provided for @boardToday.
  ///
  /// In ko, this message translates to:
  /// **'오늘'**
  String get boardToday;

  /// No description provided for @boardYesterday.
  ///
  /// In ko, this message translates to:
  /// **'어제'**
  String get boardYesterday;

  /// No description provided for @boardThisWeek.
  ///
  /// In ko, this message translates to:
  /// **'이번 주'**
  String get boardThisWeek;

  /// No description provided for @boardEarlier.
  ///
  /// In ko, this message translates to:
  /// **'이전'**
  String get boardEarlier;

  /// No description provided for @boardBookmarks.
  ///
  /// In ko, this message translates to:
  /// **'북마크'**
  String get boardBookmarks;

  /// No description provided for @noteBookmarkAdd.
  ///
  /// In ko, this message translates to:
  /// **'북마크'**
  String get noteBookmarkAdd;

  /// No description provided for @noteBookmarkRemove.
  ///
  /// In ko, this message translates to:
  /// **'북마크 해제'**
  String get noteBookmarkRemove;

  /// No description provided for @chipSynced.
  ///
  /// In ko, this message translates to:
  /// **'동기화됨'**
  String get chipSynced;

  /// No description provided for @chipPending.
  ///
  /// In ko, this message translates to:
  /// **'동기화 대기'**
  String get chipPending;

  /// No description provided for @chipConflict.
  ///
  /// In ko, this message translates to:
  /// **'충돌 사본'**
  String get chipConflict;

  /// No description provided for @editorBack.
  ///
  /// In ko, this message translates to:
  /// **'보드로 돌아가기'**
  String get editorBack;

  /// No description provided for @boardEmptyHint.
  ///
  /// In ko, this message translates to:
  /// **'위 입력창에 바로 쓰거나 새 메모를 만드세요.'**
  String get boardEmptyHint;

  /// No description provided for @loginAdvancedToken.
  ///
  /// In ko, this message translates to:
  /// **'토큰으로 로그인 (고급)'**
  String get loginAdvancedToken;

  /// No description provided for @loginBrowserFirst.
  ///
  /// In ko, this message translates to:
  /// **'브라우저에서 GitHub 계정으로 승인하면 끝납니다. 토큰을 만들거나 보관할 필요가 없습니다.'**
  String get loginBrowserFirst;

  /// No description provided for @loginRetry.
  ///
  /// In ko, this message translates to:
  /// **'다시 시도'**
  String get loginRetry;

  /// No description provided for @repoSuggested.
  ///
  /// In ko, this message translates to:
  /// **'Notes2Hub 저장소'**
  String get repoSuggested;

  /// No description provided for @repoSuggestedHint.
  ///
  /// In ko, this message translates to:
  /// **'이 계정에서 Notes2Hub가 쓰던 저장소입니다. 다른 PC에서 쓰던 메모를 이어서 쓰려면 연결하세요.'**
  String get repoSuggestedHint;

  /// No description provided for @repoUseThis.
  ///
  /// In ko, this message translates to:
  /// **'이 저장소로 연결'**
  String get repoUseThis;

  /// No description provided for @windowTooltip.
  ///
  /// In ko, this message translates to:
  /// **'창 배치'**
  String get windowTooltip;

  /// No description provided for @windowDockLeft.
  ///
  /// In ko, this message translates to:
  /// **'화면 왼쪽에 붙이기'**
  String get windowDockLeft;

  /// No description provided for @windowDockRight.
  ///
  /// In ko, this message translates to:
  /// **'화면 오른쪽에 붙이기'**
  String get windowDockRight;

  /// No description provided for @windowUndock.
  ///
  /// In ko, this message translates to:
  /// **'원래 크기로'**
  String get windowUndock;

  /// No description provided for @moreTooltip.
  ///
  /// In ko, this message translates to:
  /// **'더 보기'**
  String get moreTooltip;

  /// No description provided for @settingsWindow.
  ///
  /// In ko, this message translates to:
  /// **'창'**
  String get settingsWindow;

  /// No description provided for @settingsWindowDock.
  ///
  /// In ko, this message translates to:
  /// **'화면에 붙이기'**
  String get settingsWindowDock;

  /// No description provided for @settingsDockNone.
  ///
  /// In ko, this message translates to:
  /// **'안 붙임'**
  String get settingsDockNone;

  /// No description provided for @settingsDockLeft.
  ///
  /// In ko, this message translates to:
  /// **'왼쪽'**
  String get settingsDockLeft;

  /// No description provided for @settingsDockRight.
  ///
  /// In ko, this message translates to:
  /// **'오른쪽'**
  String get settingsDockRight;

  /// No description provided for @settingsAutoExpand.
  ///
  /// In ko, this message translates to:
  /// **'편집할 때 창을 자동으로 넓히기'**
  String get settingsAutoExpand;

  /// No description provided for @settingsAutoExpandHint.
  ///
  /// In ko, this message translates to:
  /// **'창이 화면 가장자리에 붙어 있으면, 메모를 열 때 폭을 넓히고 보드로 돌아오면 원래대로 되돌립니다.'**
  String get settingsAutoExpandHint;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ko'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ko':
      return AppLocalizationsKo();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
