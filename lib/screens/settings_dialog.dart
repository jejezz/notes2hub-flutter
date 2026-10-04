import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../sync/sync_service.dart';
import '../theme/app_theme.dart';
import 'login_dialog.dart';
import 'repo_dialog.dart';

Future<void> showSettingsDialog(BuildContext context, SyncService sync) => showDialog<void>(
  context: context,
  builder: (_) => _SettingsDialog(sync: sync),
);

class _SettingsDialog extends StatelessWidget {
  const _SettingsDialog({required this.sync});

  final SyncService sync;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: sync,
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
