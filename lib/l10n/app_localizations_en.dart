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

  @override
  String get syncTooltip => 'Sync';

  @override
  String get syncNotConnected => 'Connect GitHub';

  @override
  String get syncRunning => 'Syncing…';

  @override
  String get syncDone => 'Synced';

  @override
  String syncDoneAgo(String time) {
    return 'Synced · $time';
  }

  @override
  String syncPending(int count) {
    return '$count waiting to sync';
  }

  @override
  String get syncOffline => 'Offline';

  @override
  String get syncError => 'Sync error';

  @override
  String get syncReauth => 'Sign in again';

  @override
  String get syncRemoteAhead => 'New changes on remote';

  @override
  String syncConflictCopies(int count) {
    return 'Kept $count conflicting note(s) as “conflict” copies';
  }

  @override
  String syncFailed(String error) {
    return 'Sync failed: $error';
  }

  @override
  String get timeJustNow => 'just now';

  @override
  String timeMinutesAgo(int n) {
    return '$n min ago';
  }

  @override
  String timeHoursAgo(int n) {
    return '$n h ago';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAccount => 'GitHub account';

  @override
  String settingsSignedInAs(String login) {
    return 'Signed in as $login';
  }

  @override
  String get settingsSignedOut => 'Not signed in';

  @override
  String get settingsLoginBrowser => 'Sign in with GitHub';

  @override
  String get settingsLogout => 'Sign out';

  @override
  String get settingsRepo => 'Notes repository';

  @override
  String get settingsNoRepo => 'No repository connected';

  @override
  String get settingsRepoConnect => 'Connect repository';

  @override
  String get settingsRepoChange => 'Change';

  @override
  String get settingsSyncMode => 'Sync mode';

  @override
  String get settingsSyncManual => 'Manual';

  @override
  String get settingsSyncAuto => 'Automatic (30 s after saving)';

  @override
  String get settingsSyncHint =>
      'Pulling happens automatically at launch, when the window regains focus, and every 5 minutes. Pushing follows the setting above.';

  @override
  String get loginTitle => 'Sign in to GitHub';

  @override
  String get loginTabBrowser => 'Browser';

  @override
  String get loginTabToken => 'Token';

  @override
  String get loginDeviceStep =>
      'Enter the code below in your browser and approve';

  @override
  String get loginOpenBrowser => 'Open browser';

  @override
  String get loginCopyCode => 'Copy code';

  @override
  String get loginWaiting => 'Waiting for approval…';

  @override
  String get loginDeviceUnavailable =>
      'This build has no GitHub app registered (Client ID), so browser sign-in is unavailable. Use a token instead.';

  @override
  String get loginStart => 'Start sign-in';

  @override
  String get loginTokenLabel => 'Personal access token';

  @override
  String get loginTokenHelp =>
      'A token with the repo scope is required. It is stored only in the OS secure storage.';

  @override
  String get loginSubmit => 'Sign in';

  @override
  String loginFailed(String error) {
    return 'Could not sign in: $error';
  }

  @override
  String get repoTitle => 'Connect notes repository';

  @override
  String get repoCreateTitle => 'Create a new private repository';

  @override
  String get repoNameLabel => 'Repository name';

  @override
  String get repoCreate => 'Create';

  @override
  String get repoExisting => 'Choose an existing repository';

  @override
  String get repoSearch => 'Search repositories';

  @override
  String get repoPublic => 'Public';

  @override
  String get repoPrivate => 'Private';

  @override
  String get repoPublicConfirmTitle => 'This repository is public';

  @override
  String repoPublicConfirmBody(String name) {
    return '“$name” is public — anyone can read your notes. Connect anyway?';
  }

  @override
  String get repoConnect => 'Connect';

  @override
  String get repoConnecting => 'Connecting…';

  @override
  String get repoNoMatch => 'No matching repositories';

  @override
  String repoLoadFailed(String error) {
    return 'Could not load repositories: $error';
  }

  @override
  String repoConnectFailed(String error) {
    return 'Could not connect the repository: $error';
  }

  @override
  String get settingsTooltip => 'Settings';

  @override
  String syncUnsavedSkipped(int count) {
    return '$count unsaved note(s) were not included in the sync';
  }

  @override
  String get syncUnpushed => 'Changes not uploaded yet';

  @override
  String get imageAdd => 'Add image';

  @override
  String get imageDropHere => 'Drop to add images';

  @override
  String get imageBroken => 'Image not found';

  @override
  String imageConverted(String name, String before, String after) {
    return '$name: over 1 MB, reduced to JPEG ($before → $after)';
  }

  @override
  String imageStillLarge(String name, String size) {
    return '$name: reduced as far as possible but still over 1 MB ($size)';
  }

  @override
  String imageAnimatedTooLarge(String name) {
    return '$name: animated images can\'t be reduced, so files over 1 MB were not added';
  }

  @override
  String imageUnsupported(String name) {
    return '$name: unsupported or unreadable image';
  }

  @override
  String imageFailed(String name, String error) {
    return '$name: could not add the image: $error';
  }

  @override
  String get boardCaptureHint => 'Write something and press Enter';

  @override
  String get boardToday => 'Today';

  @override
  String get boardYesterday => 'Yesterday';

  @override
  String get boardThisWeek => 'This week';

  @override
  String get boardEarlier => 'Earlier';

  @override
  String get chipSynced => 'Synced';

  @override
  String get chipPending => 'Waiting to sync';

  @override
  String get chipConflict => 'Conflict copy';

  @override
  String get editorBack => 'Back to board';

  @override
  String get boardEmptyHint => 'Type in the box above, or create a new note.';
}
