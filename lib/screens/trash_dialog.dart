import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../notes/notes_controller.dart';
import '../theme/app_theme.dart';

/// 휴지통: 지운 메모를 되살리거나 완전히 지운다. 열려 있는 동안 동기화로 바뀌어도 목록이 따라간다.
Future<void> showTrashDialog(BuildContext context, NotesController controller) =>
    showDialog<void>(context: context, builder: (_) => _TrashDialog(controller: controller));

class _TrashDialog extends StatelessWidget {
  const _TrashDialog({required this.controller});

  final NotesController controller;

  Future<bool> _confirm(BuildContext context, String message, String action) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(message),
        actions: [
          // 기본 포커스는 취소 (되돌릴 수 없는 동작).
          TextButton(autofocus: true, onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.commonCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final items = controller.trashed;
        return AlertDialog(
          title: Text(l10n.trashTooltip),
          content: SizedBox(
            width: 460,
            child: items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    child: Text(l10n.trashEmpty, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.trashHint, style: theme.textTheme.bodySmall),
                      const SizedBox(height: AppSpacing.sm),
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (final n in items)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  n.title.isEmpty ? l10n.noteUntitled : n.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  l10n.trashDeletedAt(DateFormat.MMMd(locale).add_Hm().format(n.deletedAt!.toLocal())),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: l10n.trashRestore,
                                      icon: const Icon(Icons.restore_from_trash_rounded),
                                      onPressed: () => controller.restore(n.id),
                                    ),
                                    IconButton(
                                      tooltip: l10n.trashPurge,
                                      icon: Icon(Icons.delete_forever_outlined, color: theme.colorScheme.error),
                                      onPressed: () async {
                                        final title = n.title.isEmpty ? l10n.noteUntitled : n.title;
                                        if (await _confirm(context, l10n.trashPurgeConfirm(title), l10n.trashPurge)) {
                                          await controller.purge(n.id);
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          actions: [
            if (items.isNotEmpty)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                onPressed: () async {
                  if (await _confirm(context, l10n.trashEmptyAllConfirm(items.length), l10n.trashEmptyAll)) {
                    await controller.emptyTrash();
                  }
                },
                child: Text(l10n.trashEmptyAll),
              ),
            TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonClose)),
          ],
        );
      },
    );
  }
}
