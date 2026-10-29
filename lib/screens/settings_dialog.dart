import 'dart:async';

import 'package:flutter/material.dart';

import '../github/github_api.dart';
import '../l10n/app_localizations.dart';
import '../platform_kind.dart';
import '../settings/settings_menus.dart';
import '../sync/sync_service.dart';
import '../theme/app_theme.dart';
import '../window/quick_capture.dart';
import '../window/window_layout.dart';
import 'login_dialog.dart';
import 'repo_dialog.dart';

/// 설정 화면: 모바일까지 지원하는 앱이라 전체 페이지로 민다(settings-screen.md §1).
/// 데스크톱 전용 앱은 AlertDialog를 쓴다 — 이 앱은 그 예외다.
Future<void> showSettingsDialog(
  BuildContext context,
  SyncService sync, [
  WindowLayout? layout,
  QuickCaptureHotkey? quickCapture,
]) => Navigator.of(context).push<void>(
  MaterialPageRoute(builder: (_) => _SettingsScreen(sync: sync, layout: layout, quickCapture: quickCapture)),
);

class _SettingsScreen extends StatelessWidget {
  const _SettingsScreen({required this.sync, this.layout, this.quickCapture});

  final SyncService sync;
  final QuickCaptureHotkey? quickCapture;
  final WindowLayout? layout;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([sync, ?layout, ?quickCapture]),
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(l10n.settingsTitle)),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Section(l10n.settingsSectionAppearance),
              Text(l10n.settingsMode, style: theme.textTheme.bodySmall),
              const SizedBox(height: AppSpacing.xs),
              const ModeSegmentedButton(),
              const SizedBox(height: AppSpacing.md),
              Text(l10n.settingsPalette, style: theme.textTheme.bodySmall),
              const SizedBox(height: AppSpacing.xs),
              const AccentPaletteChips(),
              const SizedBox(height: AppSpacing.md),
              Text(l10n.languageMenuTooltip, style: theme.textTheme.bodySmall),
              const SizedBox(height: AppSpacing.xs),
              const LanguageSegmentedButton(),
              const SizedBox(height: AppSpacing.xl),
              _Section(
                  l10n.settingsAccount,
                  action: sync.loggedIn
                      ? OutlinedButton(onPressed: sync.logout, child: Text(l10n.settingsLogout))
                      : FilledButton(
                          onPressed: () async {
                            final ok = await showLoginDialog(context, sync);
                            // 새 PC에서 로그인한 직후라면 저장소 연결로 바로 이어간다 (Notes2Hub 저장소를 맨 위에 제안).
                            if (ok == true && sync.repoUrl == null && context.mounted) {
                              await _connectAfterLogin(context, sync);
                            }
                          },
                          child: Text(l10n.settingsLoginBrowser),
                        ),
                ),
                Text(
                  sync.loggedIn ? l10n.settingsSignedInAs(sync.login!) : l10n.settingsSignedOut,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.xl),
                _Section(
                  l10n.settingsRepo,
                  action: OutlinedButton(
                    onPressed: sync.loggedIn ? () => showRepoDialog(context, sync) : null,
                    child: Text(sync.repoFullName == null ? l10n.settingsRepoConnect : l10n.settingsRepoChange),
                  ),
                ),
                Text(sync.repoFullName ?? l10n.settingsNoRepo, style: theme.textTheme.bodyMedium),
                const SizedBox(height: AppSpacing.xl),
                _Section(l10n.settingsSyncMode),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: false, label: Text(l10n.settingsSyncManual)),
                    ButtonSegment(value: true, label: Text(l10n.settingsSyncAuto)),
                  ],
                  selected: {sync.autoSync},
                  onSelectionChanged: (s) => sync.setAutoSync(s.first),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(isMobilePlatform ? l10n.settingsSyncHintMobile : l10n.settingsSyncHint, style: theme.textTheme.bodySmall),
                if (layout != null) ...[
                  const SizedBox(height: AppSpacing.xl),
                  _Section(l10n.settingsWindow),
                  Text(l10n.settingsWindowDock, style: theme.textTheme.bodySmall),
                  const SizedBox(height: AppSpacing.xs),
                  SegmentedButton<DockSide>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: DockSide.none, label: Text(l10n.settingsDockNone)),
                      ButtonSegment(value: DockSide.left, label: Text(l10n.settingsDockLeft)),
                      ButtonSegment(value: DockSide.right, label: Text(l10n.settingsDockRight)),
                    ],
                    selected: {layout!.dock},
                    onSelectionChanged: (v) => layout!.dockTo(v.first),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(l10n.settingsAutoExpand),
                    subtitle: Text(l10n.settingsAutoExpandHint, style: theme.textTheme.bodySmall),
                    value: layout!.autoExpand,
                    onChanged: (v) => layout!.setAutoExpand(v),
                  ),
                ],
                if (quickCapture?.supported ?? false) ...[
                  const SizedBox(height: AppSpacing.sm),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(l10n.settingsQuickCapture(QuickCaptureHotkey.label)),
                    subtitle: Text(
                      quickCapture!.enabled && !quickCapture!.registered
                          ? l10n.settingsQuickCaptureTaken
                          : l10n.settingsQuickCaptureHint,
                      style: theme.textTheme.bodySmall,
                    ),
                    value: quickCapture!.enabled,
                    onChanged: quickCapture!.setEnabled,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(l10n.settingsKeepRunning),
                    subtitle: Text(l10n.settingsKeepRunningHint, style: theme.textTheme.bodySmall),
                    value: quickCapture!.keepRunning,
                    onChanged: quickCapture!.enabled && quickCapture!.registered ? quickCapture!.setKeepRunning : null,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
  }
}

/// 섹션 제목. [action]이 있으면 같은 줄 오른쪽에 둔다.
class _Section extends StatelessWidget {
  const _Section(this.text, {this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(
      children: [
        Expanded(child: Text(text, style: Theme.of(context).textTheme.titleSmall)),
        ?action,
      ],
    ),
  );
}

/// 로그인 직후 저장소 연결. 표식이 붙은 비공개 저장소가 하나뿐이면 고르게 하지 않고 바로 연결한다.
/// 후보가 없거나 여럿이거나, 자동 연결이 실패하면 고르는 화면을 연다.
Future<void> _connectAfterLogin(BuildContext context, SyncService sync) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(
        children: [
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: AppSpacing.md),
          Text(l10n.repoConnecting),
        ],
      ),
    ),
  ));
  GitHubRepo? repo;
  try {
    repo = await sync.connectSuggestedRepo();
  } catch (_) {
    repo = null; // 연결 실패 — 고르는 화면에서 다시 시도하게 한다.
  }
  navigator.pop(); // 진행 표시
  if (repo != null) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.repoAutoConnected(repo.fullName))));
  } else if (context.mounted) {
    await showRepoDialog(context, sync);
  }
}
