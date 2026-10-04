import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notes2hub/auth/token_store.dart';
import 'package:notes2hub/github/github_api.dart';
import 'package:notes2hub/notes/note_store.dart';
import 'package:notes2hub/notes/notes_controller.dart';
import 'package:notes2hub/sync/sync_models.dart';
import 'package:notes2hub/sync/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late NotesController notes;
  late FakeEngine engine;
  late MemoryTokenStore tokens;
  late SyncService svc;

  GitHubApi fakeApi(String token) => GitHubApi(token, client: MockClient((req) async {
        if (req.headers['Authorization'] != 'Bearer good') return http.Response('{"message":"Bad credentials"}', 401);
        if (req.url.path == '/user') return http.Response('{"login":"octo","id":7,"name":"Octo"}', 200);
        return http.Response('[]', 200);
      }));

  Future<SyncService> make({Duration autoDelay = const Duration(milliseconds: 40)}) async {
    SharedPreferences.setMockInitialValues({});
    final s = SyncService(
      prefs: await SharedPreferences.getInstance(),
      tokens: tokens,
      engine: engine,
      notes: notes,
      apiFactory: fakeApi,
      autoSyncDelay: autoDelay,
      pullInterval: const Duration(hours: 1),
      deviceLabel: 'test-pc',
    );
    await s.init();
    return s;
  }

  const repo = GitHubRepo(fullName: 'octo/notes', cloneUrl: 'https://github.com/octo/notes.git', isPrivate: true);

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('notes2hub-svc');
    notes = NotesController(
      NoteStore(notesDir: Directory('${tmp.path}/notes'), draftsDir: Directory('${tmp.path}/drafts')),
      draftDelay: const Duration(milliseconds: 5),
    );
    await notes.load();
    engine = FakeEngine();
    tokens = MemoryTokenStore();
    svc = await make();
  });
  tearDown(() {
    svc.dispose();
    notes.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('a bad token is rejected and nothing is stored', () async {
    await expectLater(svc.loginWithToken('nope'), throwsA(isA<GitHubApiException>()));
    expect(svc.loggedIn, isFalse);
    expect(await tokens.read(), isNull);
  });

  test('login stores the token in the token store (not in prefs) and the profile in prefs', () async {
    await svc.loginWithToken(' good ');
    // " good " trimmed → accepted
    expect(svc.loggedIn, isTrue);
    expect(svc.login, 'octo');
    expect(await tokens.read(), 'good');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().any((k) => (prefs.get(k) ?? '').toString().contains('good')), isFalse);
  });

  test('connect: engine connects, repo is remembered, notes reload, first sync runs with a noreply identity', () async {
    await svc.loginWithToken('good');
    await svc.connectRepo(repo);
    expect(svc.connected, isTrue);
    expect(svc.repoFullName, 'octo/notes');
    expect(engine.calls, ['connect https://github.com/octo/notes.git', 'sync']);
    expect(engine.lastToken, 'good');
    expect(engine.lastIdentity!.email, '7+octo@users.noreply.github.com');
    expect(svc.lastSync, isNotNull);
  });

  test('a failed connect throws and leaves no repo configured', () async {
    await svc.loginWithToken('good');
    engine.connectResult = const SyncResult(error: 'authentication failed', authFailed: true);
    await expectLater(svc.connectRepo(repo), throwsA(isA<SyncException>().having((e) => e.authFailed, 'auth', true)));
    expect(svc.connected, isFalse);
  });

  test('sync reloads notes when remote changes came in and reports conflict copies', () async {
    await svc.loginWithToken('good');
    await svc.connectRepo(repo);
    // a note appears on disk as if pulled from the remote
    File('${tmp.path}/notes/remote1.md')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('---\nid: remote1\ncreated: 2026-01-01T00:00:00Z\nupdated: 2026-01-01T00:00:00Z\n---\n# From remote');
    engine.syncResult = const SyncResult(pushed: true, integrated: true, conflictCopies: 2);
    final events = <SyncEvent>[];
    svc.events.listen(events.add);
    await svc.sync();
    expect(notes.notes.map((n) => n.title), contains('From remote'));
    expect(svc.lastConflictCopies, 2);
    await Future<void>.delayed(Duration.zero);
    expect(events.single.conflictCopies, 2);
  });

  test('offline / auth / error states come from the engine result', () async {
    await svc.loginWithToken('good');
    await svc.connectRepo(repo);

    engine.syncResult = const SyncResult(error: 'failed to resolve address', offline: true);
    await svc.sync();
    expect(svc.offline, isTrue);
    expect(svc.error, isNotNull);

    engine.syncResult = const SyncResult(error: '401', authFailed: true);
    await svc.sync();
    expect(svc.needsReauth, isTrue);

    engine.syncResult = const SyncResult(pushed: true);
    await svc.sync();
    expect(svc.offline, isFalse);
    expect(svc.needsReauth, isFalse);
    expect(svc.error, isNull);
  });

  test('pending count follows saves; manual mode never syncs by itself', () async {
    await svc.loginWithToken('good');
    await svc.connectRepo(repo);
    engine.calls.clear();
    engine.pending = 1;
    final id = notes.create();
    notes.edit(id, 'hello');
    await notes.save(id);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(svc.pending, 1);
    expect(engine.calls, isNot(contains('sync')));
  });

  test('auto mode syncs once, shortly after the last save (debounced)', () async {
    await svc.loginWithToken('good');
    await svc.connectRepo(repo);
    await svc.setAutoSync(true);
    engine.calls.clear();
    final id = notes.create();
    notes.edit(id, 'a');
    await notes.save(id);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    notes.edit(id, 'ab');
    await notes.save(id); // restarts the timer
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(engine.calls.where((c) => c == 'sync'), hasLength(1));
  });

  test('autoPull reloads on integrated, flags remoteAhead when saved changes block it', () async {
    await svc.loginWithToken('good');
    await svc.connectRepo(repo);
    engine.pullResult = const SyncResult(needsSync: true);
    await svc.autoPull();
    expect(svc.remoteAhead, isTrue);
    engine.pullResult = const SyncResult();
    await svc.sync();
    expect(svc.remoteAhead, isFalse);
  });

  test('logout clears token and connection but keeps notes', () async {
    await svc.loginWithToken('good');
    await svc.connectRepo(repo);
    final id = notes.create();
    notes.edit(id, 'keep me');
    await notes.save(id);
    await svc.logout();
    expect(svc.loggedIn, isFalse);
    expect(svc.connected, isFalse);
    expect(await tokens.read(), isNull);
    expect(notes.notes, hasLength(1));
  });

  test('state is restored on the next launch', () async {
    await svc.loginWithToken('good');
    await svc.connectRepo(repo);
    final prefs = await SharedPreferences.getInstance();
    final again = SyncService(
      prefs: prefs,
      tokens: tokens,
      engine: engine,
      notes: notes,
      apiFactory: fakeApi,
      pullInterval: const Duration(hours: 1),
    );
    await again.init();
    expect(again.connected, isTrue);
    expect(again.repoFullName, 'octo/notes');
    again.dispose();
    // the first service lost its onLocalChange hook to `again`; fine for this test
  });

  test('status shows unpushed work even when nothing is uncommitted', () async {
    await svc.loginWithToken('good');
    await svc.connectRepo(repo);
    engine.unpushed = true;
    await svc.refreshPending();
    expect(svc.unpushed, isTrue);
    expect(svc.hasPendingWork, isTrue);
  });

  test('auto mode retries after a failure with growing delays, then stops once it succeeds', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SyncService(
      prefs: await SharedPreferences.getInstance(),
      tokens: tokens,
      engine: engine,
      notes: notes,
      apiFactory: fakeApi,
      autoSyncDelay: const Duration(milliseconds: 20),
      retryDelays: const [Duration(milliseconds: 40), Duration(milliseconds: 80)],
      pullInterval: const Duration(hours: 1),
    );
    await s.init();
    await s.loginWithToken('good');
    await s.connectRepo(repo);
    await s.setAutoSync(true);
    engine.calls.clear();
    engine.syncQueue = [
      const SyncResult(error: 'failed to resolve address', offline: true),
      const SyncResult(error: 'failed to resolve address', offline: true),
      const SyncResult(pushed: true),
    ];
    await s.sync();
    expect(s.offline, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(engine.calls.where((c) => c == 'sync'), hasLength(3)); // initial + 2 retries
    expect(s.offline, isFalse);
    expect(s.error, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(engine.calls.where((c) => c == 'sync'), hasLength(3)); // no further retries
    s.dispose();
  });

  test('manual mode never retries by itself, and a rejected token is not retried in auto mode', () async {
    await svc.loginWithToken('good');
    await svc.connectRepo(repo);
    engine.calls.clear();
    engine.syncResult = const SyncResult(error: 'offline', offline: true);
    await svc.sync();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(engine.calls.where((c) => c == 'sync'), hasLength(1));

    await svc.setAutoSync(true);
    engine.calls.clear();
    engine.syncResult = const SyncResult(error: '401', authFailed: true);
    await svc.sync();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(engine.calls.where((c) => c == 'sync'), hasLength(1));
    expect(svc.needsReauth, isTrue);
  });

  test('git operations never overlap (status/pull/sync are queued)', () async {
    await svc.loginWithToken('good');
    await svc.connectRepo(repo);
    engine.latency = const Duration(milliseconds: 20);
    engine.maxInFlight = 0;
    await Future.wait([svc.refreshPending(), svc.autoPull(), svc.sync(), svc.refreshPending()]);
    expect(engine.maxInFlight, 1);
  });

  test('saving while a sync is running schedules another one in auto mode', () async {
    await svc.loginWithToken('good');
    await svc.connectRepo(repo);
    await svc.setAutoSync(true);
    engine.calls.clear();
    engine.latency = const Duration(milliseconds: 60);
    final running = svc.sync();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    engine.pending = 1; // a save lands mid-sync
    final id = notes.create();
    notes.edit(id, 'late edit');
    await notes.save(id);
    await running;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(engine.calls.where((c) => c == 'sync').length, greaterThanOrEqualTo(2));
  });
}
