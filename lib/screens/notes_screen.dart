import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_identity.dart';
import '../l10n/app_localizations.dart';
import '../notes/note.dart';
import '../notes/notes_controller.dart';
import '../settings/settings_menus.dart';
import '../theme/app_theme.dart';
import '../theme/user_content.dart';

bool get _isMac => defaultTargetPlatform == TargetPlatform.macOS;
String get _mod => _isMac ? '⌘' : 'Ctrl+';

SingleActivator _primary(LogicalKeyboardKey key) =>
    SingleActivator(key, meta: _isMac, control: !_isMac);

/// 목록 + 편집기. 저장(⌘S)은 로컬 파일 기록뿐이다 — 동기화는 Phase 2.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key, required this.controller, required this.onAbout});

  final NotesController controller;
  final VoidCallback onAbout;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> with WidgetsBindingObserver {
  final _editor = TextEditingController();
  final _editorFocus = FocusNode();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  bool _preview = false;
  String? _editorId;

  NotesController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(_syncEditor);
    _syncEditor();
  }

  @override
  void dispose() {
    c.removeListener(_syncEditor);
    WidgetsBinding.instance.removeObserver(this);
    _editor.dispose();
    _editorFocus.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // 앱이 가려질 때 대기 중인 초안을 바로 기록한다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) c.flush();
  }

  /// 선택이 바뀌었거나 외부에서(변경 취소 등) 본문이 바뀌면 에디터 글자를 맞춘다.
  /// 사용자가 직접 친 글자는 이미 같으므로 건드리지 않는다 (커서 유지).
  void _syncEditor() {
    final note = c.selected;
    final text = note?.body ?? '';
    if (note?.id != _editorId || _editor.text != text) {
      _editorId = note?.id;
      _editor.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    }
  }

  Future<void> _create() async {
    final id = c.create();
    setState(() => _preview = false);
    // 다음 프레임에 에디터가 만들어진 뒤 포커스.
    WidgetsBinding.instance.addPostFrameCallback((_) => _editorFocus.requestFocus());
    assert(id.isNotEmpty);
  }

  Future<void> _save() async {
    final id = c.selectedId;
    if (id == null || !c.isDirty(id)) return;
    try {
      await c.save(id);
    } catch (e) {
      if (!mounted) return;
      _showError(AppLocalizations.of(context).noteSaveFailed('$e'));
    }
  }

  void _showError(String message) {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: l10n.commonCopy,
          onPressed: () => Clipboard.setData(ClipboardData(text: message)),
        ),
      ));
  }

  Future<void> _delete() async {
    final note = c.selected;
    if (note == null) return;
    final l10n = AppLocalizations.of(context);
    final title = note.title.isEmpty ? l10n.noteUntitled : note.title;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.noteDeleteTitle),
        content: Text(l10n.noteDeleteBody(title)),
        actions: [
          // 기본 포커스는 취소 (ui-ux.md §6).
          TextButton(autofocus: true, onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.commonCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.noteDelete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await c.delete(note.id);
    } catch (e) {
      if (mounted) _showError(l10n.noteSaveFailed('$e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CallbackShortcuts(
      bindings: {
        _primary(LogicalKeyboardKey.keyN): _create,
        _primary(LogicalKeyboardKey.keyS): _save,
        _primary(LogicalKeyboardKey.keyF): () => _searchFocus.requestFocus(),
        _primary(LogicalKeyboardKey.keyE): () => setState(() => _preview = !_preview),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: const Text(AppIdentity.displayName),
            actions: [
              IconButton(
                tooltip: '${l10n.noteNew} (${_mod}N)',
                icon: const Icon(Icons.edit_note_rounded),
                onPressed: _create,
              ),
              const ThemeMenuButton(),
              const LanguageMenuButton(),
              IconButton(
                tooltip: l10n.aboutTooltip,
                icon: const Icon(Icons.info_outline_rounded),
                onPressed: widget.onAbout,
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
          ),
          body: ListenableBuilder(
            listenable: c,
            builder: (context, _) {
              if (!c.loaded) return const Center(child: CircularProgressIndicator());
              if (c.isEmpty) return _EmptyState(onCreate: _create);
              return Row(
                children: [
                  SizedBox(
                    width: 300,
                    child: _NoteList(controller: c, search: _search, searchFocus: _searchFocus),
                  ),
                  VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
                  Expanded(
                    child: c.selected == null
                        ? Center(child: Text(l10n.noteSelectHint, style: Theme.of(context).textTheme.bodyMedium))
                        : _EditorPane(
                            controller: c,
                            editor: _editor,
                            focus: _editorFocus,
                            preview: _preview,
                            onPreviewChanged: (v) => setState(() => _preview = v),
                            onSave: _save,
                            onDelete: _delete,
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(AppIdentity.iconAsset, width: 48, height: 48),
          const SizedBox(height: AppSpacing.lg),
          Text(l10n.homeEmptyTitle, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(onPressed: onCreate, child: Text(l10n.homeEmptyAction)),
        ],
      ),
    );
  }
}

class _NoteList extends StatelessWidget {
  const _NoteList({required this.controller, required this.search, required this.searchFocus});

  final NotesController controller;
  final TextEditingController search;
  final FocusNode searchFocus;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final notes = controller.notes;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: TextField(
            controller: search,
            focusNode: searchFocus,
            onChanged: controller.setQuery,
            decoration: InputDecoration(
              hintText: '${l10n.notesSearchHint} (${_mod}F)',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              isDense: true,
              suffixIcon: controller.query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      onPressed: () {
                        search.clear();
                        controller.setQuery('');
                      },
                    ),
            ),
          ),
        ),
        Expanded(
          child: notes.isEmpty
              ? Center(child: Text(l10n.notesNoResults, style: Theme.of(context).textTheme.bodySmall))
              : ListView.builder(
                  itemCount: notes.length,
                  itemBuilder: (context, i) => _NoteTile(
                    note: notes[i],
                    selected: notes[i].id == controller.selectedId,
                    dirty: controller.isDirty(notes[i].id),
                    onTap: () => controller.select(notes[i].id),
                  ),
                ),
        ),
      ],
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.note, required this.selected, required this.dirty, required this.onTap});

  final Note note;
  final bool selected;
  final bool dirty;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final date = DateFormat.yMd(locale).add_Hm().format(note.updated.toLocal());
    final title = note.title.isEmpty ? l10n.noteUntitled : note.title;
    return InkWell(
      onTap: onTap,
      splashFactory: NoSplash.splashFactory,
      child: Container(
        color: selected ? theme.colorScheme.primary.withValues(alpha: 0.12) : null,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: userContentStyle(theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: note.title.isEmpty ? theme.colorScheme.onSurfaceVariant : null,
                    )),
                  ),
                  if (note.snippet.isNotEmpty)
                    Text(
                      note.snippet,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: userContentStyle(theme.textTheme.bodySmall),
                    ),
                  Text(date, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            if (dirty)
              Tooltip(
                message: l10n.noteUnsaved,
                child: const Icon(Icons.circle, size: 8, color: AppColors.warning),
              ),
          ],
        ),
      ),
    );
  }
}

class _EditorPane extends StatelessWidget {
  const _EditorPane({
    required this.controller,
    required this.editor,
    required this.focus,
    required this.preview,
    required this.onPreviewChanged,
    required this.onSave,
    required this.onDelete,
  });

  final NotesController controller;
  final TextEditingController editor;
  final FocusNode focus;
  final bool preview;
  final ValueChanged<bool> onPreviewChanged;
  final VoidCallback onSave;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final note = controller.selected!;
    final dirty = controller.isDirty(note.id);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          child: Row(
            children: [
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: false, label: Text(l10n.noteEditTab)),
                  ButtonSegment(value: true, label: Text(l10n.notePreviewTab)),
                ],
                selected: {preview},
                onSelectionChanged: (s) => onPreviewChanged(s.first),
              ),
              const SizedBox(width: AppSpacing.md),
              Icon(
                dirty ? Icons.circle : Icons.check_circle_outline_rounded,
                size: dirty ? 8 : 16,
                color: dirty ? AppColors.warning : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  dirty ? l10n.noteUnsaved : l10n.noteSaved,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              if (dirty && !controller.isNew(note.id))
                TextButton(onPressed: () => controller.revert(note.id), child: Text(l10n.noteRevert)),
              Tooltip(
                message: '${l10n.noteSave} (${_mod}S)',
                child: FilledButton.icon(
                  onPressed: dirty ? onSave : null,
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: Text(l10n.noteSave),
                ),
              ),
              IconButton(
                tooltip: l10n.noteDelete,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
        Divider(height: 1, color: theme.dividerColor),
        Expanded(
          child: preview
              ? Markdown(
                  data: note.body,
                  selectable: true,
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                    p: userContentStyle(theme.textTheme.bodyLarge),
                    listBullet: userContentStyle(theme.textTheme.bodyLarge),
                  ),
                  onTapLink: (text, href, title) {
                    final uri = href == null ? null : Uri.tryParse(href);
                    if (uri != null) launchUrl(uri);
                  },
                )
              : Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: TextField(
                    controller: editor,
                    focusNode: focus,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    style: userContentStyle(theme.textTheme.bodyLarge),
                    decoration: InputDecoration(
                      hintText: l10n.noteBodyHint,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                    ),
                    onChanged: (v) => controller.edit(note.id, v),
                  ),
                ),
        ),
      ],
    );
  }
}
