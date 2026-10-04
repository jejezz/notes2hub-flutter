// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get aboutTooltip => '정보';

  @override
  String aboutVersion(String version, String build) {
    return '버전 $version (빌드 $build)';
  }

  @override
  String get aboutOpenSourceLicenses => '오픈소스 라이선스';

  @override
  String get aboutRepository => 'GitHub';

  @override
  String get commonClose => '닫기';

  @override
  String aboutMenuItem(String appName) {
    return '$appName 정보';
  }

  @override
  String get themeMenuTooltip => '테마';

  @override
  String get themeSystem => '시스템 설정 따르기';

  @override
  String get themeLight => '라이트';

  @override
  String get themeDark => '다크';

  @override
  String get languageMenuTooltip => '언어';

  @override
  String get languageSystem => '시스템 설정 따르기 / System';

  @override
  String get languageSystemShort => '시스템';

  @override
  String get aboutTagline => '내 GitHub 저장소로 동기화하는 Markdown 메모 앱';

  @override
  String get aboutDescription =>
      '메모를 Markdown 파일로 저장하고, 내 GitHub 저장소에 동기화해 여러 PC에서 이어서 씁니다. 별도 서버나 구독이 필요 없습니다.';

  @override
  String get homeEmptyTitle => '아직 메모가 없습니다';

  @override
  String get homeEmptyAction => '새 메모';

  @override
  String get notesSearchHint => '메모 검색';

  @override
  String get noteNew => '새 메모';

  @override
  String get noteUntitled => '제목 없음';

  @override
  String get notesNoResults => '검색 결과가 없습니다';

  @override
  String get noteSelectHint => '메모를 선택하거나 새로 만드세요';

  @override
  String get noteSave => '저장';

  @override
  String get noteSaved => '저장됨';

  @override
  String get noteUnsaved => '저장 안 됨';

  @override
  String get noteRevert => '변경 취소';

  @override
  String get noteDelete => '삭제';

  @override
  String get noteDeleteTitle => '메모를 삭제할까요?';

  @override
  String noteDeleteBody(String title) {
    return '\'$title\' 메모가 영구히 삭제됩니다.';
  }

  @override
  String get commonCancel => '취소';

  @override
  String get commonCopy => '복사';

  @override
  String get noteEditTab => '편집';

  @override
  String get notePreviewTab => '미리보기';

  @override
  String get noteBodyHint => '내용을 Markdown으로 입력하세요';

  @override
  String noteSaveFailed(String error) {
    return '저장하지 못했습니다: $error';
  }

  @override
  String noteLoadFailed(String error) {
    return '메모를 불러오지 못했습니다: $error';
  }

  @override
  String get syncTooltip => '동기화';

  @override
  String get syncNotConnected => 'GitHub 연결';

  @override
  String get syncRunning => '동기화 중…';

  @override
  String get syncDone => '동기화됨';

  @override
  String syncDoneAgo(String time) {
    return '동기화됨 · $time';
  }

  @override
  String syncPending(int count) {
    return '동기화 대기 $count';
  }

  @override
  String get syncOffline => '오프라인';

  @override
  String get syncError => '동기화 오류';

  @override
  String get syncReauth => '다시 로그인 필요';

  @override
  String get syncRemoteAhead => '원격에 새 변경';

  @override
  String syncConflictCopies(int count) {
    return '충돌한 메모 $count개를 \"충돌\" 사본으로 보존했습니다';
  }

  @override
  String syncFailed(String error) {
    return '동기화하지 못했습니다: $error';
  }

  @override
  String get timeJustNow => '방금';

  @override
  String timeMinutesAgo(int n) {
    return '$n분 전';
  }

  @override
  String timeHoursAgo(int n) {
    return '$n시간 전';
  }

  @override
  String get settingsTitle => '설정';

  @override
  String get settingsAccount => 'GitHub 계정';

  @override
  String settingsSignedInAs(String login) {
    return '$login 님으로 로그인됨';
  }

  @override
  String get settingsSignedOut => '로그인하지 않았습니다';

  @override
  String get settingsLoginBrowser => 'GitHub로 로그인';

  @override
  String get settingsLogout => '로그아웃';

  @override
  String get settingsRepo => '메모 저장소';

  @override
  String get settingsNoRepo => '연결된 저장소가 없습니다';

  @override
  String get settingsRepoConnect => '저장소 연결';

  @override
  String get settingsRepoChange => '변경';

  @override
  String get settingsSyncMode => '동기화 방식';

  @override
  String get settingsSyncManual => '수동';

  @override
  String get settingsSyncAuto => '자동 (저장 30초 후)';

  @override
  String get settingsSyncHint =>
      '가져오기는 시작할 때, 창으로 돌아올 때, 5분마다 자동으로 합니다. 보내기는 위 설정을 따릅니다.';

  @override
  String get settingsSyncHintMobile =>
      '가져오기는 시작할 때, 앱으로 돌아올 때, 앱을 열어 둔 동안 5분마다 자동으로 합니다. 보내기는 위 설정을 따릅니다.';

  @override
  String get loginTitle => 'GitHub 로그인';

  @override
  String get loginTabBrowser => '브라우저';

  @override
  String get loginTabToken => '토큰';

  @override
  String get loginDeviceStep => '브라우저에서 아래 코드를 입력하고 승인하세요';

  @override
  String get loginDeviceStepMobile =>
      '코드를 복사했어요. 브라우저 열기를 누르고 입력칸을 길게 눌러 붙여넣은 뒤 승인하세요. 끝나면 이 앱으로 돌아오세요.';

  @override
  String get loginCodeCopied => '코드 복사됨';

  @override
  String get loginOpenBrowser => '브라우저 열기';

  @override
  String get loginCopyCode => '코드 복사';

  @override
  String get loginWaiting => '승인을 기다리는 중…';

  @override
  String get loginDeviceUnavailable =>
      '이 빌드에는 GitHub 앱 등록(Client ID)이 없어 브라우저 로그인을 쓸 수 없습니다. 토큰으로 로그인하세요.';

  @override
  String get loginStart => '로그인 시작';

  @override
  String get loginTokenLabel => 'Personal access token';

  @override
  String get loginTokenHelp => 'repo 권한이 있는 토큰이 필요합니다. 토큰은 OS 보안 저장소에만 저장됩니다.';

  @override
  String get loginSubmit => '로그인';

  @override
  String loginFailed(String error) {
    return '로그인하지 못했습니다: $error';
  }

  @override
  String get repoTitle => '메모 저장소 연결';

  @override
  String get repoCreateTitle => '새 비공개 저장소 만들기';

  @override
  String get repoNameLabel => '저장소 이름';

  @override
  String get repoCreate => '만들기';

  @override
  String get repoExisting => '기존 저장소에서 선택';

  @override
  String get repoSearch => '저장소 검색';

  @override
  String get repoPublic => '공개';

  @override
  String get repoPrivate => '비공개';

  @override
  String get repoPublicConfirmTitle => '공개 저장소입니다';

  @override
  String repoPublicConfirmBody(String name) {
    return '\'$name\'은(는) 누구나 볼 수 있는 공개 저장소입니다. 메모가 모두에게 공개됩니다. 그래도 연결할까요?';
  }

  @override
  String get repoConnect => '연결';

  @override
  String repoAutoConnected(String name) {
    return '$name에 연결했어요';
  }

  @override
  String get repoConnecting => '연결 중…';

  @override
  String get repoNoMatch => '일치하는 저장소가 없습니다';

  @override
  String repoLoadFailed(String error) {
    return '저장소 목록을 불러오지 못했습니다: $error';
  }

  @override
  String repoConnectFailed(String error) {
    return '저장소를 연결하지 못했습니다: $error';
  }

  @override
  String get settingsTooltip => '설정';

  @override
  String syncUnsavedSkipped(int count) {
    return '저장하지 않은 메모 $count개는 동기화에 포함되지 않았습니다';
  }

  @override
  String get syncUnpushed => '올리지 못한 변경';

  @override
  String get imageAdd => '이미지 추가';

  @override
  String get imageDropHere => '이미지를 놓아서 추가';

  @override
  String get imageBroken => '이미지를 찾을 수 없습니다';

  @override
  String imageConverted(String name, String before, String after) {
    return '$name: 1MB를 넘어 JPEG로 줄였습니다 ($before → $after)';
  }

  @override
  String imageStillLarge(String name, String size) {
    return '$name: 최대한 줄였지만 여전히 1MB가 넘습니다 ($size)';
  }

  @override
  String imageAnimatedTooLarge(String name) {
    return '$name: 움직이는 이미지는 줄일 수 없어서 1MB를 넘는 파일은 추가하지 못했습니다';
  }

  @override
  String imageUnsupported(String name) {
    return '$name: 지원하지 않거나 읽을 수 없는 이미지입니다';
  }

  @override
  String imageFailed(String name, String error) {
    return '$name: 이미지를 추가하지 못했습니다: $error';
  }

  @override
  String get boardCaptureHint => '생각나는 대로 쓰고 Enter를 누르세요';

  @override
  String get boardToday => '오늘';

  @override
  String get boardYesterday => '어제';

  @override
  String get boardThisWeek => '이번 주';

  @override
  String get boardEarlier => '이전';

  @override
  String get boardBookmarks => '북마크';

  @override
  String get noteBookmarkAdd => '북마크';

  @override
  String get noteBookmarkRemove => '북마크 해제';

  @override
  String get chipSynced => '동기화됨';

  @override
  String get chipPending => '동기화 대기';

  @override
  String get chipConflict => '충돌 사본';

  @override
  String get editorBack => '보드로 돌아가기';

  @override
  String get boardEmptyHint => '위 입력창에 바로 쓰거나 새 메모를 만드세요.';

  @override
  String get loginAdvancedToken => '토큰으로 로그인 (고급)';

  @override
  String get loginBrowserFirst =>
      '브라우저에서 GitHub 계정으로 승인하면 끝납니다. 토큰을 만들거나 보관할 필요가 없습니다.';

  @override
  String get loginRetry => '다시 시도';

  @override
  String get repoSuggested => 'Notes2Hub 저장소';

  @override
  String get repoSuggestedHint =>
      '이 계정에서 Notes2Hub가 쓰던 저장소입니다. 다른 PC에서 쓰던 메모를 이어서 쓰려면 연결하세요.';

  @override
  String get repoUseThis => '이 저장소로 연결';

  @override
  String get windowTooltip => '창 배치';

  @override
  String get windowDockLeft => '화면 왼쪽에 붙이기';

  @override
  String get windowDockRight => '화면 오른쪽에 붙이기';

  @override
  String get windowUndock => '원래 크기로';

  @override
  String get moreTooltip => '더 보기';

  @override
  String get settingsWindow => '창';

  @override
  String get settingsWindowDock => '화면에 붙이기';

  @override
  String get settingsDockNone => '안 붙임';

  @override
  String get settingsDockLeft => '왼쪽';

  @override
  String get settingsDockRight => '오른쪽';

  @override
  String get settingsAutoExpand => '편집할 때 창을 자동으로 넓히기';

  @override
  String get settingsAutoExpandHint =>
      '창이 화면 가장자리에 붙어 있으면, 메모를 열 때 폭을 넓히고 보드로 돌아오면 원래대로 되돌립니다.';
}
