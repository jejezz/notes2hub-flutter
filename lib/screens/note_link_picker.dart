import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../notes/note.dart';
import '../notes/wiki_links.dart';

/// `[[제목]]`으로 링크할 메모를 고른다. 고른 메모의 제목을 돌려준다 (제목이 없는 메모는 링크할 수 없어 목록에서 뺀다).
Future<String?> showNoteLinkPicker(BuildContext context, List<Note> notes) =>
    showDialog<String>(
      context: context,
      builder: (_) => _Picker(notes: notes),
    );

class _Picker extends StatefulWidget {
  const _Picker({required this.notes});

  final List<Note> notes;

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final key = WikiLinks.normalize(_q);
    final shown = [
      for (final n in widget.notes)
        if (n.title.isNotEmpty && WikiLinks.normalize(n.title).contains(key)) n,
    ];
    return AlertDialog(
      title: Text(l10n.noteLinkPickerTitle),
      content: SizedBox(
        width: 420,
        height: 360,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: l10n.noteLinkSearchHint,
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
              ),
              onChanged: (v) => setState(() => _q = v),
              // Enter는 맨 위 항목을 고른다.
              onSubmitted: (_) {
                if (shown.isNotEmpty) Navigator.pop(context, shown.first.title);
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: shown.isEmpty
                  ? Center(child: Text(l10n.noteLinkNone))
                  : ListView(
                      children: [
                        for (final n in shown)
                          ListTile(
                            dense: true,
                            title: Text(
                              n.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => Navigator.pop(context, n.title),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
      ],
    );
  }
}
