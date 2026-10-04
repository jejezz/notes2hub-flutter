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
