import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../sync/sync_service.dart';
import '../theme/app_theme.dart';
import '../window/window_layout.dart';
import 'login_dialog.dart';
import 'repo_dialog.dart';

Future<void> showSettingsDialog(BuildContext context, SyncService sync, [WindowLayout? layout]) =>
    showDialog<void>(context: context, builder: (_) => _SettingsDialog(sync: sync, layout: layout));

class _SettingsDialog extends StatelessWidget {
  const _SettingsDialog({required this.sync, this.layout});

  final SyncService sync;
  final WindowLayout? layout;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([sync, ?layout]),
      builder: (context, _) => AlertDialog(
        title: Text(l10n.settingsTitle),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Section(l10n.settingsAccount),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        sync.loggedIn ? l10n.settingsSignedInAs(sync.login!) : l10n.settingsSignedOut,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    if (sync.loggedIn)
                      OutlinedButton(onPressed: sync.logout, child: Text(l10n.settingsLogout))
                    else
                      FilledButton(
                        onPressed: () async {
                          final ok = await showLoginDialog(context, sync);
                          // 새 PC에서 로그인한 직후라면 저장소 연결로 바로 이어간다 (Notes2Hub 저장소를 맨 위에 제안).
                          if (ok == true && sync.repoUrl == null && context.mounted) {
                            await showRepoDialog(context, sync);
                          }
                        },
                        child: Text(l10n.settingsLoginBrowser),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                _Section(l10n.settingsRepo),
                Row(
                  children: [
                    Expanded(child: Text(sync.repoFullName ?? l10n.settingsNoRepo, style: theme.textTheme.bodyMedium)),
                    OutlinedButton(
                      onPressed: sync.loggedIn ? () => showRepoDialog(context, sync) : null,
                      child: Text(sync.repoFullName == null ? l10n.settingsRepoConnect : l10n.settingsRepoChange),
                    ),
                  ],
                ),
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
                Text(l10n.settingsSyncHint, style: theme.textTheme.bodySmall),
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
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonClose))],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}
