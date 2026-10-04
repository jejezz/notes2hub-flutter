// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get aboutTooltip => 'About';

  @override
  String aboutVersion(String version, String build) {
    return 'Version $version (build $build)';
  }

  @override
  String get aboutOpenSourceLicenses => 'Open Source Licenses';

  @override
  String get aboutRepository => 'GitHub';

  @override
  String get commonClose => 'Close';

  @override
  String aboutMenuItem(String appName) {
    return 'About $appName';
  }

  @override
  String get themeMenuTooltip => 'Theme';

  @override
  String get themeSystem => 'Follow System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get languageMenuTooltip => 'Language';

  @override
  String get languageSystem => 'System / 시스템 설정 따르기';

  @override
  String get languageSystemShort => 'System';

  @override
  String get aboutTagline =>
      'Markdown notes synced through your own GitHub repository';

  @override
  String get aboutDescription =>
      'Keeps your notes as Markdown files and syncs them with your own GitHub repository so you can continue on any PC. No server or subscription needed.';

  @override
  String get homeEmptyTitle => 'No notes yet';

  @override
  String get homeEmptyAction => 'New note';

  @override
  String get notesSearchHint => 'Search notes';

  @override
  String get noteNew => 'New note';

  @override
  String get noteUntitled => 'Untitled';

  @override
  String get notesNoResults => 'No matching notes';

  @override
  String get noteSelectHint => 'Select a note or create a new one';

  @override
  String get noteSave => 'Save';

  @override
  String get noteSaved => 'Saved';

  @override
  String get noteUnsaved => 'Unsaved';

  @override
  String get noteRevert => 'Discard changes';

  @override
  String get noteDelete => 'Delete';

  @override
  String get noteDeleteTitle => 'Delete this note?';

  @override
  String noteDeleteBody(String title) {
    return '“$title” will be permanently deleted.';
  }

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonCopy => 'Copy';

  @override
  String get noteEditTab => 'Edit';

  @override
  String get notePreviewTab => 'Preview';

  @override
  String get noteBodyHint => 'Write in Markdown';

  @override
  String noteSaveFailed(String error) {
    return 'Could not save: $error';
  }

  @override
  String noteLoadFailed(String error) {
    return 'Could not load notes: $error';
  }
}
