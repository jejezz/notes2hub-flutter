import 'dart:async';
import 'dart:io';

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
  final String deviceLabel;

  String? _token;
  bool _syncing = false;
  bool _offline = false;
  bool _needsReauth = false;
  bool _remoteAhead = false;
  String? _error;
  DateTime? _lastSync;
  int _pending = 0;
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
    await _prefs.remove(_kRepoName);
    await _prefs.remove(_kRepoUrl);
    _remoteAhead = false;
    notifyListeners();
  }

  Future<void> setAutoSync(bool value) async {
    await _prefs.setBool(_kAutoSync, value);
    if (!value) _autoTimer?.cancel();
    if (value && _pending > 0) _scheduleAutoSync();
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

  Future<void> refreshPending() async {
    if (!connected) return;
    try {
      final n = await _engine.pendingCount();
      if (n != _pending) {
        _pending = n;
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
    _syncing = true;
    _lastConflictCopies = 0;
    notifyListeners();
    try {
      final r = await _engine.sync(token: _token!, identity: identity, deviceLabel: deviceLabel);
      _applyResult(r);
      if (r.ok) {
        _lastSync = DateTime.now();
        _remoteAhead = false;
        _lastConflictCopies = r.conflictCopies;
      }
      if (r.integrated || r.conflictCopies > 0) await _notes.reload(label: deviceLabel);
      if (!r.ok && !r.offline) _emit(SyncEvent.failed(r.error!));
      if (r.ok && r.conflictCopies > 0) _emit(SyncEvent.conflictCopies(r.conflictCopies));
    } finally {
      _syncing = false;
      await refreshPending();
      notifyListeners();
    }
  }

  /// 앱 시작·창 복귀·주기: 저장된 변경이 없을 때만 원격 변경을 가져온다.
  Future<void> autoPull() async {
    if (!connected || _syncing) return;
    final r = await _engine.pull(token: _token!);
    _applyResult(r);
    if (r.ok) {
      _remoteAhead = r.needsSync;
      if (r.integrated) await _notes.reload(label: deviceLabel);
    }
    notifyListeners();
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
