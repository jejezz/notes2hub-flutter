import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../notes/notes_controller.dart';
import '../sync/sync_service.dart';
import '../theme/app_theme.dart';

/// 앱 바의 동기화 버튼 + 상태. 연결 전에는 설정을 열고, 연결 후에는 동기화한다.
class SyncButton extends StatelessWidget {
  const SyncButton({
    super.key,
    required this.sync,
    required this.notes,
    required this.shortcut,
    required this.onOpenSettings,
    required this.onSync,
    this.compact = false,
  });

  final SyncService sync;
  final NotesController notes;
  final String shortcut;
  final VoidCallback onOpenSettings;
  final VoidCallback onSync;

  /// 좁은 창: 라벨 없이 아이콘만 (라벨은 툴팁으로).
  final bool compact;

  static String ago(AppLocalizations l10n, DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return l10n.timeJustNow;
    if (d.inMinutes < 60) return l10n.timeMinutesAgo(d.inMinutes);
    return l10n.timeHoursAgo(d.inHours);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    final (IconData icon, Color? color, String label, String? detail) = () {
      if (!sync.connected) return (Icons.cloud_off_rounded, muted, l10n.syncNotConnected, null);
      if (sync.syncing) return (Icons.sync_rounded, null, l10n.syncRunning, null);
      if (sync.needsReauth) return (Icons.lock_reset_rounded, AppColors.warning, l10n.syncReauth, sync.error);
      if (sync.offline) return (Icons.cloud_off_rounded, AppColors.warning, l10n.syncOffline, null);
      if (sync.error != null) return (Icons.error_outline_rounded, theme.colorScheme.error, l10n.syncError, sync.error);
      if (sync.pending > 0) {
        return (Icons.cloud_upload_outlined, AppColors.warning, l10n.syncPending(sync.pending), null);
      }
      if (sync.unpushed) return (Icons.cloud_upload_outlined, AppColors.warning, l10n.syncUnpushed, null);
      if (sync.remoteAhead) return (Icons.cloud_download_outlined, AppColors.warning, l10n.syncRemoteAhead, null);
      final t = sync.lastSync;
      return (Icons.cloud_done_outlined, muted, t == null ? l10n.syncDone : l10n.syncDoneAgo(ago(l10n, t)), null);
    }();

    final message =
        '$label\n${detail ?? '${l10n.syncTooltip} ($shortcut)'}${sync.repoFullName == null ? '' : '\n${sync.repoFullName}'}';
    final onPressed = sync.syncing ? null : (sync.connected && !sync.needsReauth ? onSync : onOpenSettings);
    final leading = sync.syncing
        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
        : Icon(icon, size: 18, color: color);
    if (compact) {
      return IconButton(tooltip: message, onPressed: onPressed, icon: leading);
    }
    return Tooltip(
      message: detail ?? '${l10n.syncTooltip} ($shortcut)${sync.repoFullName == null ? '' : '\n${sync.repoFullName}'}',
      child: TextButton.icon(
        onPressed: onPressed,
        icon: leading,
        label: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: color)),
      ),
    );
  }
}
