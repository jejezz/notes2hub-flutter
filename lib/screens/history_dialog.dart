import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../notes/note.dart';
import '../sync/sync_models.dart';
import '../sync/sync_service.dart';
import '../theme/app_theme.dart';

/// 메모의 버전 기록: 동기화(커밋)된 시점들을 보고, 고른 버전의 본문을 편집기로 되돌린다.
/// [onRestore]는 고른 버전의 본문을 받는다 — 저장은 사용자가 따로 한다.
Future<void> showHistoryDialog(
  BuildContext context, {
  required SyncService sync,
  required String noteId,
  required ValueChanged<String> onRestore,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _HistoryDialog(sync: sync, noteId: noteId, onRestore: onRestore),
    );

class _HistoryDialog extends StatefulWidget {
  const _HistoryDialog({required this.sync, required this.noteId, required this.onRestore});

  final SyncService sync;
  final String noteId;
  final ValueChanged<String> onRestore;

  @override
  State<_HistoryDialog> createState() => _HistoryDialogState();
}

class _HistoryDialogState extends State<_HistoryDialog> {
  List<NoteVersion>? _versions;
  Object? _error;
  int? _selected;
  final _bodies = <String, String?>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await widget.sync.history(widget.noteId);
      if (mounted) setState(() => _versions = v);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _select(int i) async {
    setState(() => _selected = i);
    final sha = _versions![i].sha;
    if (_bodies.containsKey(sha)) return;
    String? body;
    try {
      final raw = await widget.sync.versionContent(sha, widget.noteId);
      if (raw != null) body = Note.parse(raw, fallbackId: widget.noteId, fallbackTime: DateTime.now()).body;
    } catch (_) {}
    if (mounted) setState(() => _bodies[sha] = body);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final versions = _versions;
    final sel = _selected;
    final selSha = sel == null ? null : versions![sel].sha;
    final body = selSha == null ? null : _bodies[selSha];
    final loadingBody = selSha != null && !_bodies.containsKey(selSha);

    Widget content;
    if (_error != null) {
      content = Text(l10n.historyLoadFailed('$_error'));
    } else if (versions == null) {
      content = const Center(child: Padding(padding: EdgeInsets.all(AppSpacing.xl), child: CircularProgressIndicator()));
    } else if (versions.isEmpty) {
      content = Text(l10n.historyEmpty, style: theme.textTheme.bodyMedium);
    } else {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.historyHint, style: theme.textTheme.bodySmall),
          const SizedBox(height: AppSpacing.sm),
          Flexible(
            flex: 2,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: versions.length,
              itemBuilder: (_, i) => ListTile(
                dense: true,
                selected: i == sel,
                contentPadding: EdgeInsets.zero,
                title: Text(DateFormat.yMMMd(locale).add_Hm().format(versions[i].time)),
                subtitle: Text(versions[i].message, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => _select(i),
              ),
            ),
          ),
          if (sel != null) ...[
            const Divider(),
            Flexible(
              flex: 3,
              child: loadingBody
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      child: SelectableText(body ?? l10n.historyNoSuchVersion, style: theme.textTheme.bodyMedium),
                    ),
            ),
          ],
        ],
      );
    }

    return AlertDialog(
      title: Text(l10n.historyTitle),
      content: SizedBox(width: 520, height: 460, child: content),
      actions: [
        if (body != null)
          FilledButton(
            onPressed: () {
              widget.onRestore(body);
              Navigator.pop(context);
            },
            child: Text(l10n.historyRestore),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonClose)),
      ],
    );
  }
}
