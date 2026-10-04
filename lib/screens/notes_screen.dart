import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:intl/intl.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_identity.dart';
import '../images/asset_store.dart';
import '../images/image_processor.dart';
import '../l10n/app_localizations.dart';
import '../notes/note.dart';
import '../notes/notes_controller.dart';
import '../settings/settings_menus.dart';
import '../sync/sync_service.dart';
import '../theme/app_theme.dart';
import '../theme/user_content.dart';
import 'settings_dialog.dart';
import 'sync_button.dart';

bool get _isMac => defaultTargetPlatform == TargetPlatform.macOS;
String get _mod => _isMac ? '⌘' : 'Ctrl+';

SingleActivator _primary(LogicalKeyboardKey key, {bool shift = false}) =>
    SingleActivator(key, meta: _isMac, control: !_isMac, shift: shift);

String get _syncShortcut => _isMac ? '⇧⌘S' : 'Ctrl+Shift+S';

/// 목록 + 편집기. 저장(⌘S)은 로컬 파일 기록뿐이다 — 동기화는 Phase 2.
class NotesScreen extends StatefulWidget {
  const NotesScreen({
    super.key,
    required this.controller,
    required this.sync,
    required this.assets,
    required this.onAbout,
  });

  final NotesController controller;
  final SyncService sync;
  final AssetStore assets;
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
  bool _dragging = false;

  NotesController get c => widget.controller;
  SyncService get sync => widget.sync;
  StreamSubscription<SyncEvent>? _syncEvents;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(_syncEditor);
    _syncEditor();
    _syncEvents = sync.events.listen(_onSyncEvent);
  }

  @override
  void dispose() {
    _syncEvents?.cancel();
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
      _editor.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
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

  void _onSyncEvent(SyncEvent e) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    if (e.failed) {
      _showError(l10n.syncFailed(e.message ?? ''));
    } else {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l10n.syncConflictCopies(e.conflictCopies))));
    }
  }

  /// 동기화는 저장된 파일만 다룬다. 저장하지 않은 편집이 빠졌다면 알린다.
  Future<void> _syncNow() async {
    if (!sync.connected) return _openSettings();
    final skipped = c.unsavedCount;
    await sync.sync();
    if (skipped > 0 && mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).syncUnsavedSkipped(skipped))));
    }
  }

  void _openSettings() => showSettingsDialog(context, sync);

  // ---- 이미지 첨부 -----------------------------------------------------------

  static const _imageExts = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic'];

  bool _isImageName(String name) => _imageExts.contains(name.split('.').last.toLowerCase());

  Future<void> _pickImages() async {
    final files = await openFiles(
      acceptedTypeGroups: [XTypeGroup(label: 'images', extensions: _imageExts)],
    );
    await _addImages([for (final f in files) (name: f.name, read: f.readAsBytes)]);
  }

  Future<void> _dropImages(List<XFile> files) async {
    await _addImages([
      for (final f in files)
        if (_isImageName(f.name)) (name: f.name, read: f.readAsBytes),
    ]);
  }

  /// 붙여넣기: 클립보드에 이미지(스크린샷 등)나 이미지 파일이 있으면 첨부하고 true.
  /// 없으면 false — 호출한 쪽이 보통의 글자 붙여넣기를 한다.
  Future<bool> _pasteImages() async {
    try {
      final paths = (await Pasteboard.files()).where(_isImageName).toList();
      if (paths.isNotEmpty) {
        await _addImages([
          for (final p in paths) (name: p.split(Platform.pathSeparator).last, read: File(p).readAsBytes),
        ]);
        return true;
      }
      final bytes = await Pasteboard.image;
      if (bytes != null && bytes.isNotEmpty) {
        await _addImages([(name: 'image', read: () async => bytes)]);
        return true;
      }
    } catch (_) {
      // 클립보드를 읽지 못하면 글자 붙여넣기로 넘어간다.
    }
    return false;
  }

  static String _size(int bytes) =>
      bytes >= 1024 * 1024 ? '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB' : '${(bytes / 1024).round()}KB';

  /// 이미지를 1MB 미만으로 맞춰(필요하면 JPEG로 줄여) 첨부 폴더에 저장하고, 본문의 커서 자리에 넣는다.
  Future<void> _addImages(List<({String name, Future<Uint8List> Function() read})> items) async {
    if (items.isEmpty || !mounted) return;
    final l10n = AppLocalizations.of(context);
    final id = c.selectedId ?? c.create();
    setState(() => _preview = false);
    final notices = <String>[];
    for (final item in items) {
      final base = item.name.contains('.') ? item.name.substring(0, item.name.lastIndexOf('.')) : item.name;
      try {
        final r = await prepareImage(await item.read());
        switch (r.outcome) {
          case ImageOutcome.kept:
            break;
          case ImageOutcome.converted:
            notices.add(l10n.imageConverted(item.name, _size(r.originalSize), _size(r.bytes!.length)));
          case ImageOutcome.convertedStillLarge:
            notices.add(l10n.imageStillLarge(item.name, _size(r.bytes!.length)));
          case ImageOutcome.rejectedAnimated:
            notices.add(l10n.imageAnimatedTooLarge(item.name));
          case ImageOutcome.unsupported:
            notices.add(l10n.imageUnsupported(item.name));
        }
        if (!r.usable) continue;
        final file = await widget.assets.add(r.bytes!, r.ext!);
        _insert(id, AssetStore.markdownFor(file, alt: base));
      } catch (e) {
        notices.add(l10n.imageFailed(item.name, '$e'));
      }
    }
    if (notices.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(notices.join('\n')), duration: const Duration(seconds: 8)));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _editorFocus.requestFocus());
  }

  /// 편집기에 보이는 메모면 커서 자리에, 아니면 본문 끝에 한 줄로 넣는다.
  void _insert(String id, String markdown) {
    if (c.selectedId != id) {
      final body = c.bodyOf(id);
      c.edit(id, '${body.isEmpty || body.endsWith('\n') ? body : '$body\n'}$markdown\n');
      return;
    }
    final text = _editor.text;
    final sel = _editor.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final prefix = start > 0 && text[start - 1] != '\n' ? '\n' : '';
    final insert = '$prefix$markdown\n';
    final next = text.replaceRange(start, end, insert);
    _editor.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + insert.length),
    );
    c.edit(id, next);
  }

  void _showError(String message) {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: l10n.commonCopy,
            onPressed: () => Clipboard.setData(ClipboardData(text: message)),
          ),
        ),
      );
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
        _primary(LogicalKeyboardKey.keyS, shift: true): _syncNow,
        _primary(LogicalKeyboardKey.comma): _openSettings,
        _primary(LogicalKeyboardKey.keyI, shift: true): _pickImages,
        _primary(LogicalKeyboardKey.keyF): () => _searchFocus.requestFocus(),
        _primary(LogicalKeyboardKey.keyE): () => setState(() => _preview = !_preview),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: const Text(AppIdentity.displayName),
            actions: [
              ListenableBuilder(
                listenable: Listenable.merge([sync, c]),
                builder: (context, _) => SyncButton(
                  sync: sync,
                  notes: c,
                  shortcut: _syncShortcut,
                  onOpenSettings: _openSettings,
                  onSync: _syncNow,
                ),
              ),
              IconButton(
                tooltip: '${l10n.noteNew} (${_mod}N)',
                icon: const Icon(Icons.edit_note_rounded),
                onPressed: _create,
              ),
              IconButton(
                tooltip: '${l10n.settingsTooltip} ($_mod,)',
                icon: const Icon(Icons.settings_outlined),
                onPressed: _openSettings,
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
          body: DropTarget(
            onDragEntered: (_) => setState(() => _dragging = true),
            onDragExited: (_) => setState(() => _dragging = false),
            onDragDone: (d) {
              setState(() => _dragging = false);
              _dropImages(d.files);
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: ListenableBuilder(
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
                                ? Center(
                                    child: Text(l10n.noteSelectHint, style: Theme.of(context).textTheme.bodyMedium),
                                  )
                                : _EditorPane(
                                    controller: c,
                                    editor: _editor,
                                    focus: _editorFocus,
                                    preview: _preview,
                                    onPreviewChanged: (v) => setState(() => _preview = v),
                                    onSave: _save,
                                    onDelete: _delete,
                                    assets: widget.assets,
                                    onAddImage: _pickImages,
                                    onPasteImages: _pasteImages,
                                  ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                if (_dragging) Positioned.fill(child: _DropOverlay(text: l10n.imageDropHere)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 이미지를 끌어 올렸을 때 창 전체에 보이는 안내 (ui-ux.md §7: 드래그 중 강조 테두리).
class _DropOverlay extends StatelessWidget {
  const _DropOverlay({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return IgnorePointer(
      child: Container(
        margin: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.08),
          border: Border.all(color: primary, width: 2),
          borderRadius: BorderRadius.circular(AppRadius.tile),
        ),
        alignment: Alignment.center,
        child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: primary)),
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
                    style: userContentStyle(
                      theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: note.title.isEmpty ? theme.colorScheme.onSurfaceVariant : null,
                      ),
                    ),
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
            if (note.isConflictCopy)
              const Padding(
                padding: EdgeInsets.only(left: AppSpacing.sm),
                child: Icon(Icons.call_split_rounded, size: 16, color: AppColors.warning),
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
    required this.assets,
    required this.onAddImage,
    required this.onPasteImages,
  });

  final NotesController controller;
  final TextEditingController editor;
  final FocusNode focus;
  final bool preview;
  final ValueChanged<bool> onPreviewChanged;
  final VoidCallback onSave;
  final VoidCallback onDelete;
  final AssetStore assets;
  final VoidCallback onAddImage;

  /// 이미지를 붙여넣었으면 true (그러면 글자 붙여넣기는 하지 않는다).
  final Future<bool> Function() onPasteImages;

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
              IconButton(
                tooltip: '${l10n.imageAdd} ($_mod⇧I)',
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                onPressed: onAddImage,
              ),
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
                  imageBuilder: (uri, title, alt) => _NoteImage(uri: uri, alt: alt, assets: assets),
                  onTapLink: (text, href, title) {
                    final uri = href == null ? null : Uri.tryParse(href);
                    if (uri != null) launchUrl(uri);
                  },
                )
              : Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  // 붙여넣기: 이미지가 있으면 첨부, 없으면 EditableText의 기본 동작 (callingAction).
                  child: Actions(
                    actions: {PasteTextIntent: _PasteImageAction(onPasteImages)},
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
        ),
      ],
    );
  }
}

class _PasteImageAction extends Action<PasteTextIntent> {
  _PasteImageAction(this.tryImages);

  final Future<bool> Function() tryImages;

  @override
  Object? invoke(PasteTextIntent intent) {
    unawaited(() async {
      if (!await tryImages()) callingAction?.invoke(intent);
    }());
    return null;
  }
}

/// 미리보기의 이미지: `../assets/<이름>`은 첨부 폴더에서, http(s)는 네트워크에서.
class _NoteImage extends StatelessWidget {
  const _NoteImage({required this.uri, required this.alt, required this.assets});

  final Uri uri;
  final String? alt;
  final AssetStore assets;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    Widget broken(Object _, StackTrace? _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.broken_image_outlined, size: 16),
        const SizedBox(width: AppSpacing.xs),
        Text(alt == null || alt!.isEmpty ? l10n.imageBroken : alt!, style: theme.textTheme.bodySmall),
      ],
    );
    final Widget image;
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      image = Image.network(uri.toString(), fit: BoxFit.contain, errorBuilder: (c, e, s) => broken(e, s));
    } else if (uri.pathSegments.isNotEmpty) {
      image = Image.file(
        assets.file(uri.pathSegments.last),
        fit: BoxFit.contain,
        errorBuilder: (c, e, s) => broken(e, s),
      );
    } else {
      image = broken('', null);
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720, maxHeight: 480), child: image),
    );
  }
}
