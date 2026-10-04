import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'note.dart';
import 'note_store.dart';

/// 메모 목록·선택·편집 상태. "저장"은 로컬 파일 기록까지만 한다 (docs/PLAN.md §5).
///
/// 두 겹으로 들고 있다:
///  * [_saved]   디스크의 메모 (새 메모는 아직 없음)
///  * [_working] 저장 전 편집본 — 새 메모 포함. 1초 debounce로 초안 파일에도 적는다.
class NotesController extends ChangeNotifier {
  NotesController(this._store, {this.draftDelay = const Duration(seconds: 1)});

  final NoteStore _store;
  final Duration draftDelay;
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

  /// 최근 수정순. 편집 중인 메모는 편집본을 보여준다.
  List<Note> get notes {
    final byId = {..._saved, ..._working};
    final list = byId.values.where((n) => n.matches(_query)).toList()
      ..sort((a, b) => b.updated.compareTo(a.updated));
    return list;
  }

  bool get isEmpty => _saved.isEmpty && _working.isEmpty;

  /// 저장하지 않은 메모 수 (아직 아무것도 쓰지 않은 새 메모는 제외).
  int get unsavedCount => _working.values.where((n) => n.body.trim().isNotEmpty).length;

  Note? get selected => _selectedId == null ? null : (_working[_selectedId] ?? _saved[_selectedId]);

  bool isDirty(String id) => _working.containsKey(id);
  bool isNew(String id) => !_saved.containsKey(id);

  Future<void> load() async {
    for (final n in await _store.loadAll()) {
      _saved[n.id] = n;
    }
    // 앱이 저장 없이 꺼졌어도 편집 내용이 돌아온다.
    for (final d in await _store.loadDrafts()) {
      final base = _saved[d.id];
      if (base != null && base.body == d.body) {
        await _store.clearDraft(d.id);
      } else {
        _working[d.id] = d;
      }
    }
    final first = notes;
    _selectedId = first.isEmpty ? null : first.first.id;
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

  Future<void> delete(String id) async {
    await _store.delete(id);
    _saved.remove(id);
    _working.remove(id);
    _draftPending.remove(id);
    _afterRemoval(id);
    notifyListeners();
    onLocalChange?.call();
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
    if (_selectedId != null && selected == null) {
      final rest = notes;
      _selectedId = rest.isEmpty ? null : rest.first.id;
    } else if (_selectedId == null) {
      final rest = notes;
      _selectedId = rest.isEmpty ? null : rest.first.id;
    }
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
    if (_selectedId != id) return;
    final rest = notes;
    _selectedId = rest.isEmpty ? null : rest.first.id;
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
