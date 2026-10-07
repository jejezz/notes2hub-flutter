import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../images/asset_store.dart';
import 'note.dart';
import 'note_store.dart';
import 'wiki_links.dart';

/// 메모 목록·선택·편집 상태. "저장"은 로컬 파일 기록까지만 한다 (docs/PLAN.md §5).
///
/// 두 겹으로 들고 있다:
///  * [_saved]   디스크의 메모 (새 메모는 아직 없음)
///  * [_working] 저장 전 편집본 — 새 메모 포함. 1초 debounce로 초안 파일에도 적는다.
class NotesController extends ChangeNotifier {
  NotesController(this._store, {this.draftDelay = const Duration(seconds: 1), this.trashRetention = const Duration(days: 30)});

  final NoteStore _store;
  final Duration draftDelay;

  /// 휴지통에 이 기간이 지난 메모는 앱을 켤 때 완전히 지운다 (git 이력에는 남는다).
  final Duration trashRetention;
  final _uuid = const Uuid();

  final Map<String, Note> _saved = {};
  final Map<String, Note> _working = {};
  final Set<String> _draftPending = {};
  Timer? _draftTimer;

  /// 디스크의 메모가 바뀌었을 때(저장·삭제) 불린다 — 동기화 대기 수를 새로 세는 용도.
  VoidCallback? onLocalChange;

  String _query = '';
  String? _selectedId;
  bool _loaded = false;

  bool get loaded => _loaded;
  String get query => _query;
  String? get selectedId => _selectedId;

  /// 최근 수정순 (휴지통 제외). 편집 중인 메모는 편집본을 보여준다.
  List<Note> get notes {
    final byId = {..._saved, ..._working};
    final list = byId.values.where((n) => !n.isTrashed && n.matches(_query)).toList()
      ..sort((a, b) => b.updated.compareTo(a.updated));
    return list;
  }

  /// 휴지통의 메모, 최근에 버린 순.
  List<Note> get trashed =>
      _saved.values.where((n) => n.isTrashed).toList()..sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));

  bool get isEmpty => !_saved.values.any((n) => !n.isTrashed) && _working.isEmpty;

  /// 저장하지 않은 메모 수 (아직 아무것도 쓰지 않은 새 메모는 제외).
  int get unsavedCount => _working.values.where((n) => n.body.trim().isNotEmpty).length;

  Note? get selected => _selectedId == null ? null : (_working[_selectedId] ?? _saved[_selectedId]);

  /// 편집 중인 내용을 포함한 메모 본문.
  String bodyOf(String id) => (_working[id] ?? _saved[id])?.body ?? '';

  /// 어떤 메모(저장본·편집본)라도 참조하는 첨부 파일 이름 — 고아 정리의 기준.
  Set<String> get referencedAssets => {
    for (final n in {..._saved, ..._working}.values) ...AssetStore.referencedIn(n.body),
  };

  /// 편집 중인 내용을 포함한 메모 (없으면 null).
  Note? noteById(String id) => _working[id] ?? _saved[id];

  /// `[[제목]]`이 가리키는 메모 — 휴지통 밖에서 제목이 같은 것 중 가장 최근에 고친 것 (없으면 null).
  Note? noteByTitle(String title) {
    final key = WikiLinks.normalize(title);
    if (key.isEmpty) return null;
    Note? best;
    for (final n in {..._saved, ..._working}.values) {
      if (n.isTrashed || WikiLinks.normalize(n.title) != key) continue;
      if (best == null || n.updated.isAfter(best.updated)) best = n;
    }
    return best;
  }

  /// [id] 메모를 `[[제목]]`으로 링크한 다른 메모들, 최근 수정순.
  List<Note> backlinksTo(String id) {
    final target = noteById(id);
    final key = target == null ? '' : WikiLinks.normalize(target.title);
    if (key.isEmpty) return const [];
    return [
      for (final n in notes)
        if (n.id != id && WikiLinks.titlesIn(n.body).any((t) => WikiLinks.normalize(t) == key)) n,
    ];
  }

  bool isDirty(String id) => _working.containsKey(id);
  bool isNew(String id) => !_saved.containsKey(id);

  Future<void> load() async {
    for (final n in await _store.loadAll()) {
      _saved[n.id] = n;
    }
    await _purgeExpired();
    // 앱이 저장 없이 꺼졌어도 편집 내용이 돌아온다.
    for (final d in await _store.loadDrafts()) {
      final base = _saved[d.id];
      if (base != null && base.body == d.body) {
        await _store.clearDraft(d.id);
      } else {
        _working[d.id] = d;
      }
    }
    _selectedId = null; // 시작은 보드 — 메모를 고르면 편집 화면이 열린다.
    _loaded = true;
    notifyListeners();
  }

  /// 불러오기에 실패해도 화면은 열어야 할 때.
  void markLoaded() {
    _loaded = true;
    notifyListeners();
  }

  void setQuery(String q) {
    _query = q;
    notifyListeners();
  }

  void select(String id) {
    _flushDrafts();
    _dropEmptyNew(except: id);
    _selectedId = id;
    notifyListeners();
  }

  /// 편집 화면에서 보드로 돌아간다. 대기 중인 초안은 기록하고, 아무것도 쓰지 않은 새 메모는 버린다.
  void deselect() {
    _flushDrafts();
    _dropEmptyNew(except: '');
    _selectedId = null;
    notifyListeners();
  }

  /// 빠른 메모: 글 한 덩이로 메모를 만들어 바로 저장한다 (편집 화면을 열지 않음). 만든 id를 돌려준다.
  Future<String> capture(String text) async {
    final now = DateTime.now();
    final note = Note(id: _uuid.v4(), created: now, updated: now, body: text.trim());
    await _store.save(note);
    _saved[note.id] = note;
    notifyListeners();
    onLocalChange?.call();
    return note.id;
  }

  /// 새 메모는 저장하기 전까지 파일이 없다 (빈 파일이 저장소에 쌓이지 않게).
  String create() {
    final now = DateTime.now();
    final id = _uuid.v4();
    _flushDrafts();
    _dropEmptyNew(except: id);
    _working[id] = Note(id: id, created: now, updated: now, body: '');
    _selectedId = id;
    _query = '';
    notifyListeners();
    return id;
  }

  /// 에디터에서 본문이 바뀔 때마다 부른다. 목록 재정렬을 피하려고 notify는 하지만
  /// `updated`는 건드리지 않는다 (저장 때 갱신).
  void edit(String id, String body) {
    final base = _working[id] ?? _saved[id];
    if (base == null || base.body == body) return;
    final saved = _saved[id];
    if (saved != null && saved.body == body) {
      _working.remove(id);
      _draftPending.remove(id);
      unawaited(_store.clearDraft(id));
    } else {
      _working[id] = base.copyWith(body: body);
      _draftPending.add(id);
      _draftTimer?.cancel();
      _draftTimer = Timer(draftDelay, _flushDrafts);
    }
    notifyListeners();
  }

  /// 북마크를 켜고 끈다. 본문은 건드리지 않고(`updated`도 그대로) 즉시 디스크에 적는다.
  /// 편집 중인 변경이 있으면 그것은 저장하지 않은 채로 남긴다.
  Future<void> toggleBookmark(String id) async {
    final current = noteById(id);
    if (current == null) return;
    final value = !current.bookmarked;
    final saved = _saved[id];
    final working = _working[id];
    if (saved != null) {
      final note = saved.copyWith(bookmarked: value);
      await _store.save(note); // 초안 파일도 지워지므로 아래에서 편집본이 있으면 다시 쓴다.
      _saved[id] = note;
    }
    if (working != null) {
      final w = working.copyWith(bookmarked: value);
      _working[id] = w;
      if (saved != null) await _store.writeDraft(w);
    }
    notifyListeners();
    if (saved != null) onLocalChange?.call();
  }

  /// 로컬 파일에 저장. 실패하면 예외를 던지고 편집본은 그대로 남는다.
  Future<void> save(String id) async {
    final w = _working[id];
    if (w == null) return;
    final note = w.copyWith(updated: DateTime.now());
    await _store.save(note);
    _saved[id] = note;
    _working.remove(id);
    _draftPending.remove(id);
    notifyListeners();
    onLocalChange?.call();
  }

  /// 저장 전 편집을 버린다. 새 메모면 메모 자체가 사라진다.
  Future<void> revert(String id) async {
    if (!_working.containsKey(id)) return;
    _working.remove(id);
    _draftPending.remove(id);
    await _store.clearDraft(id);
    if (!_saved.containsKey(id)) _afterRemoval(id);
    notifyListeners();
  }

  /// 휴지통으로 옮긴다 (파일은 남고 `deleted:` 표시만 붙는다). 저장 전 편집은 버려진다.
  /// 저장된 적 없는 새 메모는 옮길 파일이 없으니 그냥 사라진다.
  Future<void> delete(String id) async {
    final saved = _saved[id];
    if (saved == null) {
      _working.remove(id);
      _draftPending.remove(id);
      await _store.clearDraft(id);
    } else {
      final note = saved.copyWith(deletedAt: DateTime.now());
      await _store.save(note); // 초안 파일도 함께 지워진다.
      _saved[id] = note;
      _working.remove(id);
      _draftPending.remove(id);
    }
    _afterRemoval(id);
    notifyListeners();
    onLocalChange?.call();
  }

  /// 휴지통에서 꺼낸다.
  Future<void> restore(String id) async {
    final saved = _saved[id];
    if (saved == null || !saved.isTrashed) return;
    final note = saved.copyWith(restore: true);
    await _store.save(note);
    _saved[id] = note;
    notifyListeners();
    onLocalChange?.call();
  }

  /// 휴지통의 메모 하나를 파일째 지운다. 되돌릴 수 없다 (git 이력에만 남는다).
  Future<void> purge(String id) async {
    await _store.delete(id);
    _saved.remove(id);
    _working.remove(id);
    _draftPending.remove(id);
    _afterRemoval(id);
    notifyListeners();
    onLocalChange?.call();
  }

  Future<void> emptyTrash() async {
    final ids = [for (final n in trashed) n.id];
    if (ids.isEmpty) return;
    for (final id in ids) {
      await _store.delete(id);
      _saved.remove(id);
    }
    notifyListeners();
    onLocalChange?.call();
  }

  Future<void> _purgeExpired() async {
    final limit = DateTime.now().subtract(trashRetention);
    for (final n in _saved.values.toList()) {
      if (n.deletedAt != null && n.deletedAt!.isBefore(limit)) {
        await _store.delete(n.id);
        _saved.remove(n.id);
      }
    }
  }

  /// 동기화로 디스크의 메모가 바뀐 뒤 다시 읽는다. 편집 중이던 내용은 보존한다.
  /// 저장 전 편집 중인 메모가 원격에서도 바뀌었다면, 편집본을 충돌 사본으로 따로 저장해
  /// 원격 내용이 본 메모를 차지하게 한다 (docs/PLAN.md §5).
  Future<void> reload({String label = ''}) async {
    final before = Map<String, Note>.of(_saved);
    final disk = await _store.loadAll();
    _saved
      ..clear()
      ..addEntries(disk.map((n) => MapEntry(n.id, n)));
    for (final id in _working.keys.toList()) {
      final old = before[id], now = _saved[id];
      if (old == null || now == null || old.body == now.body) continue;
      final mine = _working.remove(id)!;
      _draftPending.remove(id);
      await _store.clearDraft(id);
      final copy = conflictCopyOf(mine, newId: _uuid.v4(), label: label, now: DateTime.now());
      await _store.save(copy);
      _saved[copy.id] = copy;
    }
    if (_selectedId != null && selected == null) _selectedId = null; // 원격에서 지워졌다
    notifyListeners();
  }

  /// 아무것도 쓰지 않고 떠난 새 메모는 남기지 않는다.
  void _dropEmptyNew({required String except}) {
    final id = _selectedId;
    if (id == null || id == except) return;
    final w = _working[id];
    if (w != null && !_saved.containsKey(id) && w.body.trim().isEmpty) {
      _working.remove(id);
      _draftPending.remove(id);
      unawaited(_store.clearDraft(id));
    }
  }

  void _afterRemoval(String id) {
    if (_selectedId == id) _selectedId = null; // 지운 메모의 편집 화면에서 보드로 돌아간다.
  }

  /// 대기 중인 초안을 즉시 기록한다 (선택 변경, 앱이 백그라운드로 갈 때).
  void flush() => _flushDrafts();

  void _flushDrafts() {
    _draftTimer?.cancel();
    final ids = _draftPending.toList();
    _draftPending.clear();
    for (final id in ids) {
      final w = _working[id];
      if (w != null) unawaited(_store.writeDraft(w));
    }
  }

  @override
  void dispose() {
    _flushDrafts();
    super.dispose();
  }
}
