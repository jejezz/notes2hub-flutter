import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_identity.dart';
import '../images/asset_store.dart';
import '../images/image_processor.dart';
import '../l10n/app_localizations.dart';
import '../notes/notes_controller.dart';
import '../platform_kind.dart';
import '../settings/settings_menus.dart';
import '../sync/sync_service.dart';
import '../theme/app_theme.dart';
import 'md_toolbar.dart';
import 'share_sheet.dart';
import '../theme/user_content.dart';
import '../window/window_layout.dart';
import 'board_view.dart';
import 'ctrl_edit_shortcuts.dart';
import 'note_preview.dart';
import 'settings_dialog.dart';
import 'history_dialog.dart';
import 'sync_button.dart';
import 'trash_dialog.dart';

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
    this.windowLayout,
  });

  final NotesController controller;
  final SyncService sync;
  final AssetStore assets;
  final VoidCallback onAbout;

  /// 데스크톱에서만 있다 — 창 크기 기억, 좌/우 도킹, 편집 중 확장.
  final WindowLayout? windowLayout;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> with WidgetsBindingObserver {
  final _editor = TextEditingController();
  final _editorFocus = FocusNode();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _capture = TextEditingController();
  final _captureFocus = FocusNode();
  bool _preview = false;
  String? _editorId;
  bool _dragging = false;

  /// 이미지를 줄여 넣는 중이면 (끝낸 장 수, 전체 장 수). 큰 사진은 몇 초 걸려서, 표시가 없으면 먹통처럼 보인다.
  ({int done, int total})? _adding;

  NotesController get c => widget.controller;
  SyncService get sync => widget.sync;
  StreamSubscription<SyncEvent>? _syncEvents;
  bool _wasEditing = false;
  WindowLayout? get layout => widget.windowLayout;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(_syncEditor);
    c.addListener(_onSelectionChanged);
    _syncEditor();
    _syncEvents = sync.events.listen(_onSyncEvent);
  }

  @override
  void dispose() {
    _syncEvents?.cancel();
    c.removeListener(_syncEditor);
    c.removeListener(_onSelectionChanged);
    WidgetsBinding.instance.removeObserver(this);
    _editor.dispose();
    _editorFocus.dispose();
    _search.dispose();
    _searchFocus.dispose();
    _capture.dispose();
    _captureFocus.dispose();
    super.dispose();
  }

  // 앱이 가려질 때 대기 중인 초안을 바로 기록한다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) c.flush();
  }

  /// 메모를 열면(편집 화면) 도킹된 창을 넓히고, 보드로 돌아오면 원래 폭으로 되돌린다.
  void _onSelectionChanged() {
    final editing = c.selectedId != null;
    if (editing == _wasEditing) return;
    _wasEditing = editing;
    final l = layout;
    if (l == null) return;
    unawaited(editing ? l.beginEditing() : l.endEditing());
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

  /// 새 메모의 편집 화면을 연다.
  void _create() {
    c.create();
    setState(() => _preview = false);
    // 다음 프레임에 에디터가 만들어진 뒤 포커스.
    WidgetsBinding.instance.addPostFrameCallback((_) => _editorFocus.requestFocus());
  }

  void _open(String id) {
    c.select(id);
    setState(() => _preview = false);
  }

  /// 카드를 누르면 편집 화면 대신 아래에서 올라오는 시트로 내용을 미리 보여준다 (Markdown 렌더링, 길면 스크롤).
  void _previewNote(String id) {
    final note = c.noteById(id);
    if (note == null) return;
    showNotePreview(
      context,
      body: note.body,
      assets: widget.assets,
      onEdit: () => _open(id),
      // 저장하지 않은 메모(새로 쓰거나 고친 것)는 시트에서 바로 저장할 수 있다.
      onSave: c.isDirty(id) ? () => _saveNote(id) : null,
    );
  }

  /// 편집 화면에서 보드로. 저장하지 않은 편집은 초안으로 남고 카드에 "저장 안 됨"으로 보인다.
  void _back() {
    if (c.selectedId == null) return;
    c.deselect();
    setState(() {});
  }

  /// 보드의 빠른 메모: 입력한 글로 메모를 만들어 바로 저장한다.
  Future<void> _quickCapture(String text) async {
    try {
      await c.capture(text);
      _capture.clear();
    } catch (e) {
      if (mounted) _showError(AppLocalizations.of(context).noteSaveFailed('$e'));
    }
  }

  void _focusSearch() {
    if (c.selectedId != null) _back();
    WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocus.requestFocus());
  }

  Future<void> _save() async {
    final id = c.selectedId;
    if (id != null) await _saveNote(id);
  }

  Future<void> _saveNote(String id) async {
    if (!c.isDirty(id)) return;
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

  void _openSettings() => showSettingsDialog(context, sync, layout);

  // ---- 이미지 첨부 -----------------------------------------------------------

  static const _imageExts = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic'];

  bool _isImageName(String name) => _imageExts.contains(name.split('.').last.toLowerCase());

  Future<void> _pickImages() async {
    if (isMobilePlatform) {
      // 사진 보관함(iOS의 HEIC는 시스템이 JPEG로 바꿔 준다). 카메라는 M3에서 별도 버튼으로.
      final picked = await ImagePicker().pickMultiImage();
      await _addImages([for (final f in picked) (name: f.name, read: f.readAsBytes)]);
      return;
    }
    final files = await openFiles(
      acceptedTypeGroups: [XTypeGroup(label: 'images', extensions: _imageExts)],
    );
    await _addImages([for (final f in files) (name: f.name, read: f.readAsBytes)]);
  }

  /// 폰 카메라로 찍어 바로 첨부한다.
  Future<void> _takePhoto() async {
    try {
      final shot = await ImagePicker().pickImage(source: ImageSource.camera);
      if (shot == null) return;
      await _addImages([(name: shot.name, read: shot.readAsBytes)]);
    } catch (e) {
      if (mounted) _showError(AppLocalizations.of(context).imageFailed('camera', '$e'));
    }
  }

  /// 서식 도구줄: 편집기 값을 바꾸고 본문에 반영한다. 입력 중이던 한글 조합은 확정하고 시작한다.
  void _format(TextEditingValue Function(TextEditingValue) apply) {
    final id = c.selectedId;
    if (id == null) return;
    final next = apply(_editor.value.copyWith(composing: TextRange.empty));
    _editor.value = next;
    c.edit(id, next.text);
    _editorFocus.requestFocus();
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
    setState(() {
      _preview = false;
      _adding = (done: 0, total: items.length);
    });
    final notices = <String>[];
    try {
      await _processImages(id, items, l10n, notices);
    } finally {
      if (mounted) setState(() => _adding = null);
    }
    if (notices.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(notices.join('\n')), duration: const Duration(seconds: 8)));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _editorFocus.requestFocus());
  }

  Future<void> _processImages(
    String id,
    List<({String name, Future<Uint8List> Function() read})> items,
    AppLocalizations l10n,
    List<String> notices,
  ) async {
    var done = 0;
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
      done++;
      if (mounted) setState(() => _adding = (done: done, total: items.length));
    }
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
    final id = c.selectedId;
    if (id != null) await _deleteNote(id);
  }

  /// 메모를 휴지통으로 옮긴다 (편집 화면과 보드 카드가 함께 쓴다). 저장하지 않은 내용이 있으면
  /// 그것이 사라지므로 먼저 확인하고, 아니면 바로 옮긴 뒤 "되돌리기"를 보여준다.
  Future<void> _deleteNote(String id) async {
    final note = c.noteById(id);
    if (note == null) return;
    final l10n = AppLocalizations.of(context);
    final title = note.title.isEmpty ? l10n.noteUntitled : note.title;
    final messenger = ScaffoldMessenger.of(context);
    if (c.isDirty(id) && note.body.trim().isNotEmpty) {
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
    }
    final undoable = !c.isNew(id);
    try {
      await c.delete(id);
    } catch (e) {
      if (mounted) _showError(l10n.noteSaveFailed('$e'));
      return;
    }
    if (!undoable) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.noteMovedToTrash(title)),
          action: SnackBarAction(label: l10n.commonUndo, onPressed: () => c.restore(id)),
        ),
      );
  }

  void _openTrash() => showTrashDialog(context, c);

  void _openHistory() {
    final id = c.selectedId;
    if (id == null) return;
    showHistoryDialog(
      context,
      sync: sync,
      noteId: id,
      onRestore: (body) {
        c.edit(id, body);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).historyRestored)));
      },
    );
  }

  /// 창이 좁으면(화면 가장자리에 세로로 붙인 모양) 제목과 라벨을 줄이고 덜 쓰는 단추는 "더 보기"로 모은다.
  PreferredSizeWidget _buildAppBar(BuildContext context, AppLocalizations l10n) {
    final narrow = MediaQuery.sizeOf(context).width < 720;
    final l = layout;
    final syncButton = ListenableBuilder(
      listenable: Listenable.merge([sync, c]),
      builder: (context, _) => SyncButton(
        sync: sync,
        notes: c,
        shortcut: _syncShortcut,
        onOpenSettings: _openSettings,
        onSync: _syncNow,
        compact: narrow,
      ),
    );
    final newNote = IconButton(
      tooltip: '${l10n.noteNew} (${_mod}N)',
      icon: const Icon(Icons.edit_note_rounded),
      onPressed: _create,
    );
    final windowItems = l == null
        ? const <PopupMenuEntry<String>>[]
        : [
            PopupMenuItem(value: 'left', child: Text(l10n.windowDockLeft)),
            PopupMenuItem(value: 'right', child: Text(l10n.windowDockRight)),
            if (l.docked) PopupMenuItem(value: 'undock', child: Text(l10n.windowUndock)),
          ];
    void onWindowChoice(String v) {
      switch (v) {
        case 'left':
          l?.dockTo(DockSide.left);
        case 'right':
          l?.dockTo(DockSide.right);
        case 'undock':
          l?.undock();
        case 'settings':
          _openSettings();
        case 'trash':
          _openTrash();
        case 'about':
          widget.onAbout();
      }
    }

    if (narrow) {
      // 앱 이름은 좁아도 남긴다. 아이콘 간격을 줄여 자리를 만들고, 그래도 모자라면 말줄임표로 줄인다.
      Widget tight(Widget w) => IconButtonTheme(
        data: IconButtonThemeData(style: IconButton.styleFrom(visualDensity: VisualDensity.compact)),
        child: w,
      );
      return AppBar(
        titleSpacing: AppSpacing.md,
        title: const Text(AppIdentity.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          tight(syncButton),
          if (!isMobilePlatform) tight(newNote), // 폰에서는 보드의 + 버튼을 쓴다
          tight(const ThemeMenuButton()),
          tight(const LanguageMenuButton()),
          tight(
            PopupMenuButton<String>(
              tooltip: l10n.moreTooltip,
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: onWindowChoice,
              itemBuilder: (_) => [
                PopupMenuItem(value: 'settings', child: Text(l10n.settingsTooltip)),
                PopupMenuItem(value: 'trash', child: Text(l10n.trashTooltip)),
                ...windowItems,
                PopupMenuItem(value: 'about', child: Text(l10n.aboutTooltip)),
              ],
            ),
          ),
        ],
      );
    }
    return AppBar(
      title: const Text(AppIdentity.displayName),
      actions: [
        syncButton,
        newNote,
        if (l != null)
          PopupMenuButton<String>(
            tooltip: l10n.windowTooltip,
            icon: const Icon(Icons.view_sidebar_outlined),
            onSelected: onWindowChoice,
            itemBuilder: (_) => windowItems,
          ),
        IconButton(
          tooltip: l10n.trashTooltip,
          icon: const Icon(Icons.restore_from_trash_outlined),
          onPressed: _openTrash,
        ),
        IconButton(
          tooltip: '${l10n.settingsTooltip} ($_mod,)',
          icon: const Icon(Icons.settings_outlined),
          onPressed: _openSettings,
        ),
        const ThemeMenuButton(),
        const LanguageMenuButton(),
        IconButton(tooltip: l10n.aboutTooltip, icon: const Icon(Icons.info_outline_rounded), onPressed: widget.onAbout),
        const SizedBox(width: AppSpacing.sm),
      ],
    );
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
        _primary(LogicalKeyboardKey.keyF): _focusSearch,
        const SingleActivator(LogicalKeyboardKey.escape): _back,
        SingleActivator(LogicalKeyboardKey.arrowLeft, meta: _isMac, control: !_isMac, alt: true): () =>
            layout?.dockTo(DockSide.left),
        SingleActivator(LogicalKeyboardKey.arrowRight, meta: _isMac, control: !_isMac, alt: true): () =>
            layout?.dockTo(DockSide.right),
        SingleActivator(LogicalKeyboardKey.arrowDown, meta: _isMac, control: !_isMac, alt: true): () =>
            layout?.undock(),
        _primary(LogicalKeyboardKey.keyE): () => setState(() => _preview = !_preview),
      },
      // Android 뒤로가기/제스처: 편집 화면이면 앱을 닫지 않고 보드로 돌아간다 (편집 화면은 라우트가 아니라 상태).
      child: ListenableBuilder(
        listenable: c,
        builder: (context, child) => PopScope(
          canPop: c.selectedId == null,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _back();
          },
          child: child!,
        ),
        child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: _buildAppBar(context, l10n),
          floatingActionButton: isMobilePlatform
              ? ListenableBuilder(
                  listenable: c,
                  builder: (context, _) => c.loaded && c.selected == null
                      ? FloatingActionButton(
                          tooltip: l10n.noteNew,
                          onPressed: _create,
                          child: const Icon(Icons.edit_outlined),
                        )
                      : const SizedBox.shrink(),
                )
              : null,
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
                    listenable: Listenable.merge([c, sync]),
                    builder: (context, _) {
                      if (!c.loaded) return const Center(child: CircularProgressIndicator());
                      final editing = c.selected != null;
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        child: editing
                            ? _EditorPane(
                                key: const ValueKey('editor'),
                                controller: c,
                                editor: _editor,
                                focus: _editorFocus,
                                preview: _preview,
                                onPreviewChanged: (v) => setState(() => _preview = v),
                                onSave: _save,
                                onDelete: _delete,
                                onHistory: _openHistory,
                                onBack: _back,
                                assets: widget.assets,
                                onAddImage: _pickImages,
                                onTakePhoto: _takePhoto,
                                onFormat: _format,
                                onPasteImages: _pasteImages,
                              )
                            : NotesBoard(
                                key: const ValueKey('board'),
                                controller: c,
                                sync: sync,
                                assets: widget.assets,
                                capture: _capture,
                                captureFocus: _captureFocus,
                                search: _search,
                                searchFocus: _searchFocus,
                                onCapture: _quickCapture,
                                onPreview: _previewNote,
                                onEdit: _open,
                                onDelete: _deleteNote,
                                onBookmark: c.toggleBookmark,
                                onCreate: _create,
                                onRefresh: _syncNow,
                              ),
                      );
                    },
                  ),
                ),
                if (_dragging) Positioned.fill(child: _DropOverlay(text: l10n.imageDropHere)),
                if (_adding != null)
                  Positioned.fill(
                    child: ImageBusyOverlay(
                      text: _adding!.total > 1
                          ? l10n.imageProcessingCount(_adding!.done, _adding!.total)
                          : l10n.imageProcessing,
                      hint: l10n.imageProcessingHint,
                      progress: _adding!.total > 1 ? _adding!.done / _adding!.total : null,
                    ),
                  ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }
}

/// 이미지를 줄여 넣는 동안 화면을 덮는 진행 표시. 큰 사진은 JPEG로 줄이는 데 몇 초 걸리므로, 먹통이 아니라
/// 처리 중임을 알리고(스피너 + 안내) 그동안의 조작을 막는다. [progress]가 null이면 끝을 모르는 진행 표시.
class ImageBusyOverlay extends StatelessWidget {
  const ImageBusyOverlay({super.key, required this.text, required this.hint, this.progress});

  final String text;
  final String hint;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AbsorbPointer(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.32),
        child: Center(
          child: Semantics(
            liveRegion: true,
            label: text,
            child: Card(
              margin: const EdgeInsets.all(AppSpacing.xl),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 3)),
                      const SizedBox(height: AppSpacing.lg),
                      Text(text, style: theme.textTheme.titleSmall, textAlign: TextAlign.center),
                      if (progress != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        LinearProgressIndicator(value: progress),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        hint,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
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

class _EditorPane extends StatelessWidget {
  const _EditorPane({
    super.key,
    required this.controller,
    required this.editor,
    required this.focus,
    required this.preview,
    required this.onPreviewChanged,
    required this.onSave,
    required this.onDelete,
    required this.onHistory,
    required this.onBack,
    required this.assets,
    required this.onAddImage,
    required this.onTakePhoto,
    required this.onFormat,
    required this.onPasteImages,
  });

  final NotesController controller;
  final TextEditingController editor;
  final FocusNode focus;
  final bool preview;
  final ValueChanged<bool> onPreviewChanged;
  final VoidCallback onSave;
  final VoidCallback onDelete;
  final VoidCallback onHistory;
  final VoidCallback onBack;
  final AssetStore assets;
  final VoidCallback onAddImage;
  final VoidCallback onTakePhoto;
  final void Function(TextEditingValue Function(TextEditingValue)) onFormat;

  /// 이미지를 붙여넣었으면 true (그러면 글자 붙여넣기는 하지 않는다).
  final Future<bool> Function() onPasteImages;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final note = controller.selected!;
    final dirty = controller.isDirty(note.id);
    // 창을 화면 가장자리에 세로로 붙인 좁은 모양: 글자 라벨 대신 아이콘으로 줄인다.
    final compact = MediaQuery.sizeOf(context).width < 840;
    final tiny = MediaQuery.sizeOf(context).width < 400;
    final pad = compact ? AppSpacing.md : AppSpacing.xl;
    const dense = VisualDensity.compact;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 2 : AppSpacing.lg, vertical: AppSpacing.sm),
          child: Row(
            children: [
              IconButton(
                tooltip: '${l10n.editorBack} (Esc)',
                visualDensity: compact ? dense : null,
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                onPressed: onBack,
              ),
              SizedBox(width: compact ? 2 : AppSpacing.sm),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: compact ? const ButtonStyle(visualDensity: dense) : null,
                segments: [
                  ButtonSegment(
                    value: false,
                    icon: compact ? const Icon(Icons.edit_outlined, size: 16) : null,
                    tooltip: compact ? l10n.noteEditTab : null,
                    label: compact ? null : Text(l10n.noteEditTab),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: compact ? const Icon(Icons.visibility_outlined, size: 16) : null,
                    tooltip: compact ? l10n.notePreviewTab : null,
                    label: compact ? null : Text(l10n.notePreviewTab),
                  ),
                ],
                selected: {preview},
                onSelectionChanged: (s) => onPreviewChanged(s.first),
              ),
              if (compact)
                // 좁으면 글자·점 대신 저장 단추가 켜져 있는지(= 저장 안 됨)로 알린다.
                const Spacer()
              else ...[
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
              ],
              if (dirty && !controller.isNew(note.id))
                compact
                    ? IconButton(
                        tooltip: l10n.noteRevert,
                        visualDensity: dense,
                        icon: const Icon(Icons.undo_rounded, size: 18),
                        onPressed: () => controller.revert(note.id),
                      )
                    : TextButton(onPressed: () => controller.revert(note.id), child: Text(l10n.noteRevert)),
              if (!tiny)
                Builder(
                  builder: (shareContext) => IconButton(
                    tooltip: l10n.shareTooltip,
                    visualDensity: compact ? dense : null,
                    icon: const Icon(Icons.ios_share_rounded, size: 18),
                    onPressed: () => showShareSheet(
                      context,
                      body: note.body,
                      assets: assets,
                      origin: shareOrigin(shareContext),
                    ),
                  ),
                ),
              if (!isMobilePlatform && !tiny) // 폰에서는 키보드 위 도구줄에 있다
              IconButton(
                tooltip: '${l10n.imageAdd} ($_mod⇧I)',
                visualDensity: compact ? dense : null,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                onPressed: onAddImage,
              ),
              if (compact)
                IconButton.filled(
                  tooltip: '${l10n.noteSave} (${_mod}S)',
                  visualDensity: dense,
                  onPressed: dirty ? onSave : null,
                  icon: const Icon(Icons.save_rounded, size: 18),
                )
              else
                Tooltip(
                  message: '${l10n.noteSave} (${_mod}S)',
                  child: FilledButton.icon(
                    onPressed: dirty ? onSave : null,
                    icon: const Icon(Icons.save_rounded, size: 18),
                    label: Text(l10n.noteSave),
                  ),
                ),
              if (!tiny)
                IconButton(
                  tooltip: l10n.historyTooltip,
                  visualDensity: compact ? dense : null,
                  icon: const Icon(Icons.history_rounded, size: 18),
                  onPressed: onHistory,
                ),
              if (!tiny)
                IconButton(
                  tooltip: l10n.noteDelete,
                  visualDensity: compact ? dense : null,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  onPressed: onDelete,
                )
              else
                // 아주 좁으면(폰 세로, 최소 폭 창) 덜 쓰는 단추를 ⋮ 메뉴로 묶는다.
                Builder(
                  builder: (menuContext) => PopupMenuButton<String>(
                    tooltip: l10n.moreTooltip,
                    icon: const Icon(Icons.more_vert_rounded, size: 18),
                    padding: EdgeInsets.zero,
                    onSelected: (v) {
                      switch (v) {
                        case 'share':
                          showShareSheet(context, body: note.body, assets: assets, origin: shareOrigin(menuContext));
                        case 'image':
                          onAddImage();
                        case 'history':
                          onHistory();
                        case 'delete':
                          onDelete();
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'share', child: Text(l10n.shareTooltip)),
                      if (!isMobilePlatform) PopupMenuItem(value: 'image', child: Text(l10n.imageAdd)),
                      PopupMenuItem(value: 'history', child: Text(l10n.historyTooltip)),
                      PopupMenuItem(value: 'delete', child: Text(l10n.noteDelete)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: theme.dividerColor),
        Expanded(
          // 글 읽기·쓰기 좋은 폭으로 가운데에 모은다.
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              // macOS에서도 Ctrl+C/V/X(복사·붙여넣기·잘라내기)가 되도록 한다 — 편집기와 미리보기 모두.
              child: CtrlEditShortcuts(
                child: preview
                    ? Markdown(
                        data: note.body,
                        selectable: true,
                        padding: EdgeInsets.all(pad),
                        styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                          p: userContentStyle(theme.textTheme.bodyLarge),
                          listBullet: userContentStyle(theme.textTheme.bodyLarge),
                        ),
                        imageBuilder: (uri, title, alt) => NoteImage(uri: uri, alt: alt, assets: assets),
                        onTapLink: (text, href, title) {
                          final uri = href == null ? null : Uri.tryParse(href);
                          if (uri != null) launchUrl(uri);
                        },
                      )
                    : Padding(
                        padding: EdgeInsets.all(pad),
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
            ),
          ),
        ),
        if (isMobilePlatform && !preview)
          MarkdownToolbar(onFormat: onFormat, onGallery: onAddImage, onCamera: onTakePhoto),
      ],
    );
  }
}

class _PasteImageAction extends Action<PasteTextIntent> {
  _PasteImageAction(this.tryImages);

  final Future<bool> Function() tryImages;

  @override
  Object? invoke(PasteTextIntent intent) {
    // callingAction은 invoke가 도는 동안에만 유효하다 — await 뒤에는 null이 되어 글자 붙여넣기가 조용히
    // 사라진다(Phase 4에서 이 때문에 일반 붙여넣기가 안 됐다). 비동기 작업 전에 미리 붙잡아 둔다.
    final textPaste = callingAction;
    unawaited(() async {
      if (!await tryImages()) textPaste?.invoke(intent);
    }());
    return null;
  }
}
