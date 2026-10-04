import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notes2hub/auth/token_store.dart';
import 'package:notes2hub/github/github_api.dart';
import 'package:notes2hub/l10n/app_localizations.dart';
import 'package:notes2hub/notes/note_store.dart';
import 'package:notes2hub/notes/notes_controller.dart';
import 'package:notes2hub/screens/login_dialog.dart';
import 'package:notes2hub/screens/repo_dialog.dart';
import 'package:notes2hub/sync/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  late Directory tmp;
  late FakeEngine engine;
  late NotesController notes;

  GitHubApi api(String token) => GitHubApi(
    token,
    client: MockClient((req) async {
      if (token != 'good') return http.Response('{"message":"Bad credentials"}', 401);
      if (req.url.path == '/user') return http.Response('{"login":"octo","id":7,"name":"Octo"}', 200);
      if (req.url.path.endsWith('/topics')) return http.Response('{"names":["notes2hub"]}', 200);
      return http.Response(
        '[{"full_name":"octo/zzz-other","clone_url":"https://github.com/octo/zzz-other.git","private":true,"topics":[]},'
        '{"full_name":"octo/my-notes","clone_url":"https://github.com/octo/my-notes.git","private":true,"topics":["notes2hub"]}]',
        200,
      );
    }),
  );

  Future<SyncService> makeSync(WidgetTester tester, {bool loggedIn = false, bool autoDispose = true}) async {
    SharedPreferences.setMockInitialValues({});
    final tokens = MemoryTokenStore();
    final svc = (await tester.runAsync(() async {
      final s = SyncService(
        prefs: await SharedPreferences.getInstance(),
        tokens: tokens,
        engine: engine,
        notes: notes,
        apiFactory: api,
        pullInterval: const Duration(hours: 1),
      );
      await s.init();
      if (loggedIn) await s.loginWithToken('good');
      return s;
    }))!;
    // 연결하면 주기 타이머가 생긴다 — 테스트가 끝나기 전에 직접 정리해야 하는 경우 autoDispose: false.
    if (autoDispose) addTearDown(svc.dispose);
    return svc;
  }

  Future<void> host(WidgetTester tester, Widget Function(BuildContext) opener) => tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(body: Center(child: opener(context))),
      ),
    ),
  );

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('notes2hub-dlg');
    engine = FakeEngine();
    notes = NotesController(
      NoteStore(notesDir: Directory('${tmp.path}/notes'), draftsDir: Directory('${tmp.path}/drafts')),
    );
  });
  tearDown(() {
    notes.dispose();
    tmp.deleteSync(recursive: true);
  });

  testWidgets(
    'without a client id the login dialog shows the token form straight away; a bad token reports the error',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final sync = await makeSync(tester);
      bool? result;
      await host(
        tester,
        (c) => FilledButton(onPressed: () async => result = await showLoginDialog(c, sync), child: const Text('open')),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Personal access token'), findsOneWidget);
      expect(find.textContaining('no GitHub app registered'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'bad');
      await tester.tap(find.text('Sign in').last);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not sign in'), findsOneWidget);
      expect(sync.loggedIn, isFalse);
      expect(result, isNull); // dialog still open

      await tester.enterText(find.byType(TextField), 'good');
      await tester.tap(find.text('Sign in').last);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(sync.loggedIn, isTrue);
      expect(result, isTrue);
    },
  );

  testWidgets('repo dialog puts the Notes2Hub-marked repository on top with a one-click connect', (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sync = await makeSync(tester, loggedIn: true, autoDispose: false);
    await host(tester, (c) => FilledButton(onPressed: () => showRepoDialog(c, sync), child: const Text('open')));
    await tester.tap(find.text('open'));
    // 목록을 불러오는 동안은 스피너가 계속 돌아 pumpAndSettle이 끝나지 않는다 — 몇 번 직접 pump한다.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    expect(find.text('Notes2Hub repositories'), findsOneWidget);
    // the marked repo is in the suggestion card and listed first below; the unmarked one comes after
    expect(find.text('octo/my-notes'), findsNWidgets(2));
    expect(find.text('octo/zzz-other'), findsOneWidget);
    final listOrder = tester.widgetList<ListTile>(find.byType(ListTile)).map((t) => (t.title as Text).data).toList();
    expect(listOrder.indexOf('octo/my-notes'), lessThan(listOrder.indexOf('octo/zzz-other')));

    await tester.tap(find.text('Connect this repository'));
    // 연결은 실제 파일 읽기(메모 다시 읽기)를 거친다 — 실제 시간과 pump를 번갈아 진행한다.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump(const Duration(milliseconds: 25));
    }
    await tester.pumpAndSettle();
    expect(engine.calls.first, 'connect https://github.com/octo/my-notes.git');
    expect(sync.repoFullName, 'octo/my-notes');
    sync.dispose();
  });
}
