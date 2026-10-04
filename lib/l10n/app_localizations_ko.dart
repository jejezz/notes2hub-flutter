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
}
