import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/token_store.dart';
import '../github/github_api.dart';
import '../notes/notes_controller.dart';
import 'sync_models.dart';

/// 로그인·저장소 연결·동기화 상태를 한곳에서 관리한다 (docs/PLAN.md §5).
///
/// 저장(로컬)과 동기화(git)는 별개다: 이 서비스는 저장된 파일만 다루고,
/// 동기화는 수동(기본) 또는 저장 후 30초 자동이다. 가져오기(pull)는 앱 시작·창 복귀·5분 주기.
class SyncService extends ChangeNotifier with WidgetsBindingObserver {
  SyncService({
    required this._prefs,
    required this._tokens,
    required this._engine,
    required this._notes,
    GitHubApi Function(String token)? apiFactory,
    this.autoSyncDelay = const Duration(seconds: 30),
    this.pullInterval = const Duration(minutes: 5),
    this.retryDelays = const [Duration(seconds: 30), Duration(minutes: 1), Duration(minutes: 2), Duration(minutes: 5)],
    String? deviceLabel,
  })  : _apiFactory = apiFactory ?? GitHubApi.new,
        deviceLabel = deviceLabel ?? _defaultDeviceLabel() {
    _notes.onLocalChange = _onLocalChange;
  }

  static const _kLogin = 'gh_login';
  static const _kUserId = 'gh_user_id';
  static const _kName = 'gh_name';
  static const _kRepoName = 'repo_full_name';
  static const _kRepoUrl = 'repo_url';
  static const _kAutoSync = 'auto_sync';

  static String _defaultDeviceLabel() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'device';
    }
  }

  final SharedPreferences _prefs;
  final TokenStore _tokens;
  final SyncEngine _engine;
  final NotesController _notes;
  final GitHubApi Function(String token) _apiFactory;
  final Duration autoSyncDelay;
  final Duration pullInterval;

  /// 자동 모드에서 동기화가 실패(오프라인 등)했을 때 다시 시도하는 간격. 마지막 값을 반복한다.
  final List<Duration> retryDelays;
  final String deviceLabel;

  String? _token;
  bool _syncing = false;
  bool _offline = false;
  bool _needsReauth = false;
  bool _remoteAhead = false;
  String? _error;
  DateTime? _lastSync;
  int _pending = 0;
  bool _unpushed = false;
  Set<String> _pendingNotes = const {};
  int _retryStep = 0;
  Future<void> _tail = Future.value();
  Timer? _retryTimer, _tick;
  int _lastConflictCopies = 0;
  Timer? _autoTimer, _pullTimer, _pendingTimer;
  final _events = StreamController<SyncEvent>.broadcast();

  Stream<SyncEvent> get events => _events.stream;

  // ---- 상태 -----------------------------------------------------------------

  String? get login => _prefs.getString(_kLogin);
  String? get repoFullName => _prefs.getString(_kRepoName);
  String? get repoUrl => _prefs.getString(_kRepoUrl);
  bool get autoSync => _prefs.getBool(_kAutoSync) ?? false;

  bool get loggedIn => _token != null && login != null;
  bool get connected => loggedIn && repoUrl != null;
  bool get syncing => _syncing;
  bool get offline => _offline;

  /// 토큰이 거절됐다 — 다시 로그인해야 한다.
  bool get needsReauth => _needsReauth;

  /// 원격에 아직 받지 못한 변경이 있다 (저장된 변경이 있어 자동으로 가져오지 못함).
  bool get remoteAhead => _remoteAhead;
  String? get error => _error;
  DateTime? get lastSync => _lastSync;

  /// 저장했지만 아직 동기화(커밋)하지 않은 파일 수.
  int get pending => _pending;

  /// 커밋은 했지만 아직 push하지 못한 것이 있다 (오프라인 등으로 동기화가 중간에 실패).
  bool get unpushed => _unpushed;

  /// 아직 원격에 반영되지 않은 메모 id들 — 보드 카드의 동기화 상태 표시용.
  Set<String> get pendingNotes => _pendingNotes;

  /// 동기화할 것이 남았는가 — 상태 표시와 자동 재시도의 기준.
  bool get hasPendingWork => _pending > 0 || _unpushed;

  /// 마지막 동기화에서 만든 충돌 사본 수 (알림용).
  int get lastConflictCopies => _lastConflictCopies;

  GitIdentity? get _identity {
    final l = login;
    if (l == null) return null;
    final id = _prefs.getInt(_kUserId) ?? 0;
    final name = _prefs.getString(_kName);
    return GitIdentity(
      name: (name == null || name.isEmpty) ? l : name,
      email: '$id+$l@users.noreply.github.com',
    );
  }

  // ---- 수명 -----------------------------------------------------------------

  Future<void> init() async {
    try {
      _token = await _tokens.read();
    } catch (_) {
      _token = null; // 보안 저장소를 못 읽으면 로그아웃 상태로 시작한다.
    }
    WidgetsBinding.instance.addObserver(this);
    if (connected) {
      _pullTimer = Timer.periodic(pullInterval, (_) => autoPull());
      await refreshPending();
      unawaited(autoPull());
    }
    // "3분 전" 같은 표시가 멈춰 있지 않게 주기적으로 다시 그린다.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_lastSync != null) notifyListeners();
    });
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(autoPull());
  }

  bool _disposed = false;

  // 끝나지 않은 비동기 작업(시작 pull 등)이 dispose 뒤에 돌아와도 안전하게 무시한다.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  void _emit(SyncEvent e) {
    if (!_disposed) _events.add(e);
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _autoTimer?.cancel();
    _pullTimer?.cancel();
    _pendingTimer?.cancel();
    _retryTimer?.cancel();
    _tick?.cancel();
    _notes.onLocalChange = null;
    _events.close();
    super.dispose();
  }

  // ---- 로그인 / 저장소 -------------------------------------------------------

  /// 토큰을 검증하고(GET /user) 보안 저장소에 넣는다. 실패하면 [GitHubApiException].
  Future<void> loginWithToken(String token) async {
    final t = token.trim();
    final user = await _apiFactory(t).user();
    await _tokens.write(t);
    _token = t;
    await _prefs.setString(_kLogin, user.login);
    await _prefs.setInt(_kUserId, user.id);
    await _prefs.setString(_kName, user.displayName);
    _needsReauth = false;
    _error = null;
    notifyListeners();
  }

  /// 로그아웃: 토큰과 연결 정보를 지운다. 로컬 메모 파일은 그대로 둔다.
  Future<void> logout() async {
    _autoTimer?.cancel();
    _pullTimer?.cancel();
    _retryTimer?.cancel();
    await _tokens.delete();
    _token = null;
    for (final k in [_kLogin, _kUserId, _kName, _kRepoName, _kRepoUrl]) {
      await _prefs.remove(k);
    }
    _error = null;
    _offline = false;
    _needsReauth = false;
    _remoteAhead = false;
    notifyListeners();
  }

  Future<List<GitHubRepo>> listRepos() => _apiFactory(_token!).repos();

  Future<GitHubRepo> createRepo(String name, {String? description}) =>
      _apiFactory(_token!).createRepo(name, description: description);

  /// 저장소를 연결하고 첫 동기화까지 한다. 실패하면 [SyncException].
  Future<void> connectRepo(GitHubRepo repo) async {
    final r = await _engine.connect(remoteUrl: repo.cloneUrl, token: _token!);
    if (!r.ok) throw SyncException(r.error!, authFailed: r.authFailed, offline: r.offline);
    await _prefs.setString(_kRepoName, repo.fullName);
    await _prefs.setString(_kRepoUrl, repo.cloneUrl);
    _pullTimer?.cancel();
    _pullTimer = Timer.periodic(pullInterval, (_) => autoPull());
    await _notes.reload(label: deviceLabel);
    notifyListeners();
    await sync();
  }

  Future<void> disconnectRepo() async {
    _autoTimer?.cancel();
    _pullTimer?.cancel();
    _retryTimer?.cancel();
    await _prefs.remove(_kRepoName);
    await _prefs.remove(_kRepoUrl);
    _remoteAhead = false;
    _pending = 0;
    _unpushed = false;
    _pendingNotes = const {};
    notifyListeners();
  }

  Future<void> setAutoSync(bool value) async {
    await _prefs.setBool(_kAutoSync, value);
    if (!value) {
      _autoTimer?.cancel();
      _retryTimer?.cancel();
    }
    if (value && connected && hasPendingWork) _scheduleAutoSync();
    notifyListeners();
  }

  // ---- 동기화 ---------------------------------------------------------------

  void _onLocalChange() {
    _pendingTimer?.cancel();
    _pendingTimer = Timer(const Duration(milliseconds: 300), refreshPending);
    if (connected && autoSync) _scheduleAutoSync();
  }

  /// 저장이 이어지는 동안은 타이머를 계속 다시 시작한다 — 마지막 저장 30초 뒤에 한 번.
  void _scheduleAutoSync() {
    _autoTimer?.cancel();
    _autoTimer = Timer(autoSyncDelay, () => unawaited(sync()));
  }

  /// git 작업끼리 겹치면 index 잠금 충돌이 나므로 하나씩 차례로 실행한다.
  Future<T> _serial<T>(Future<T> Function() job) {
    final run = _tail.then((_) => job());
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<void> refreshPending() async {
    if (!connected) return;
    try {
      final st = await _serial(_engine.status);
      if (st.changed != _pending || st.unpushed != _unpushed || !setEquals(st.pendingNotes, _pendingNotes)) {
        _pending = st.changed;
        _unpushed = st.unpushed;
        _pendingNotes = st.pendingNotes;
        notifyListeners();
      }
    } catch (_) {
      // 개수를 못 세어도 동기화 자체는 막지 않는다.
    }
  }

  /// 커밋 → 가져오기(병합) → 푸시. 이미 진행 중이면 무시한다.
  Future<void> sync() async {
    final identity = _identity;
    if (!connected || _syncing || identity == null) return;
    _autoTimer?.cancel();
    _retryTimer?.cancel();
    _syncing = true;
    _lastConflictCopies = 0;
    notifyListeners();
    try {
      final r = await _serial(() => _engine.sync(token: _token!, identity: identity, deviceLabel: deviceLabel));
      _applyResult(r);
      if (r.ok) {
        _lastSync = DateTime.now();
        _remoteAhead = false;
        _lastConflictCopies = r.conflictCopies;
        _retryStep = 0;
      }
      if (r.integrated || r.conflictCopies > 0) await _notes.reload(label: deviceLabel);
      if (!r.ok && !r.offline) _emit(SyncEvent.failed(r.error!));
      if (r.ok && r.conflictCopies > 0) _emit(SyncEvent.conflictCopies(r.conflictCopies));
      _syncing = false;
      await refreshPending();
      _planFollowUp(r);
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// 자동 모드의 뒷정리: 실패하면 간격을 늘려 가며 다시 시도하고(오프라인 → 복귀 시 자동으로 올라감),
  /// 동기화하는 사이에 또 저장했다면 한 번 더 예약한다. 로그인이 거절된 경우는 사용자가 해결해야 한다.
  void _planFollowUp(SyncResult r) {
    if (!autoSync || _disposed) return;
    if (!r.ok) {
      if (r.authFailed) return;
      final delay = retryDelays[_retryStep.clamp(0, retryDelays.length - 1)];
      _retryStep++;
      _retryTimer?.cancel();
      _retryTimer = Timer(delay, () => unawaited(sync()));
    } else if (hasPendingWork) {
      _scheduleAutoSync();
    }
  }

  /// 앱 시작·창 복귀·주기: 저장된 변경이 없을 때만 원격 변경을 가져온다.
  Future<void> autoPull() async {
    if (!connected || _syncing) return;
    final r = await _serial(() => _engine.pull(token: _token!));
    _applyResult(r);
    if (r.ok) {
      _remoteAhead = r.needsSync;
      if (r.integrated) await _notes.reload(label: deviceLabel);
    }
    notifyListeners();
    // 네트워크가 되는 것을 확인했으니, 못 올린 변경이 남아 있으면 자동 모드에서 바로 올린다.
    if (r.ok && autoSync && !_syncing) {
      await refreshPending();
      if (hasPendingWork) unawaited(sync());
    }
  }

  void _applyResult(SyncResult r) {
    _offline = r.offline;
    _needsReauth = r.authFailed;
    _error = r.ok ? null : r.error;
  }
}

/// 동기화 결과 중 사용자에게 알릴 것 (스낵바).
class SyncEvent {
  const SyncEvent.failed(this.message)
      : conflictCopies = 0,
        failed = true;
  const SyncEvent.conflictCopies(this.conflictCopies)
      : message = null,
        failed = false;

  final bool failed;
  final String? message;
  final int conflictCopies;
}

class SyncException implements Exception {
  const SyncException(this.message, {this.authFailed = false, this.offline = false});

  final String message;
  final bool authFailed;
  final bool offline;

  @override
  String toString() => message;
}
