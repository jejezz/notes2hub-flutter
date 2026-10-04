import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:notes2hub/auth/token_store.dart';
import 'package:notes2hub/images/asset_store.dart';
import 'package:notes2hub/l10n/app_localizations.dart';
import 'package:notes2hub/notes/note_store.dart';
import 'package:notes2hub/notes/notes_controller.dart';
import 'package:notes2hub/screens/board_view.dart';
import 'package:notes2hub/screens/notes_screen.dart';
import 'package:notes2hub/settings/app_settings.dart';
import 'package:notes2hub/sync/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  test('groupOf buckets by calendar day', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final now = DateTime(2026, 10, 4, 15);
    expect(NotesBoard.groupOf(l10n, DateTime(2026, 10, 4, 0, 5), now), 'Today');
    expect(NotesBoard.groupOf(l10n, DateTime(2026, 10, 3, 23, 59), now), 'Yesterday');
    expect(NotesBoard.groupOf(l10n, DateTime(2026, 9, 30), now), 'This week');
    expect(NotesBoard.groupOf(l10n, DateTime(2026, 9, 20), now), 'Earlier');
  });

  testWidgets(
    'board: quick capture makes a card; search filters; card opens the editor; sync chips and cover image show',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tmp = Directory.systemTemp.createTempSync('notes2hub-board');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final assets = AssetStore(Directory('${tmp.path}/assets'));
      final c = NotesController(
        NoteStore(notesDir: Directory('${tmp.path}/notes'), draftsDir: Directory('${tmp.path}/drafts')),
      );
      SharedPreferences.setMockInitialValues({
        'gh_login': 'octo',
        'gh_user_id': 1,
        'repo_url': 'https://x/y.git',
        'repo_full_name': 'o/n',
      });
      final engine = FakeEngine();
      final tokens = MemoryTokenStore();
      await tokens.write('tok');
      // 비동기 작업을 쓰는 서비스는 runAsync 안에서 만든다 — 가짜 시계 영역에서 만든 Future는 pump 전에는 돌지 않는다.
      final sync = (await tester.runAsync(
        () async => SyncService(
          prefs: await SharedPreferences.getInstance(),
          tokens: tokens,
          engine: engine,
          notes: c,
          pullInterval: const Duration(hours: 1),
        ),
      ))!;
      final settings = (await tester.runAsync(AppSettings.load))!;
      addTearDown(() {
        sync.dispose();
        c.dispose();
      });

      // a note with a cover image, one pending, one plain
      final png = img.encodePng(img.Image(width: 8, height: 8));
      late String withImg, pendingId;
      await tester.runAsync(() async {
        await c.load();
        final f = await assets.add(png, 'png');
        withImg = await c.capture('# Trip\n![p](../assets/$f)\nJeju flights');
        pendingId = await c.capture('Release checklist');
        await c.capture('Groceries');
        engine.pendingNotes = {pendingId};
        await sync.init();
      });

      await tester.pumpWidget(
        AppSettingsScope(
          settings: settings,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: NotesScreen(controller: c, sync: sync, assets: assets, onAbout: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // board is the start screen, with all three cards and the Today group
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Trip'), findsOneWidget);
      expect(find.text('Release checklist'), findsOneWidget);
      expect(find.byType(Image), findsWidgets); // cover (and the app icon is only in the empty state)
      expect(find.descendant(of: find.byType(NoteCard), matching: find.text('Waiting to sync')), findsOneWidget);
      expect(find.descendant(of: find.byType(NoteCard), matching: find.text('Synced')), findsNWidgets(2));

      // quick capture
      await tester.enterText(find.widgetWithText(TextField, '').first, 'Call the bank');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Call the bank'), findsOneWidget);
      expect(c.selectedId, isNull); // still on the board

      // search filters cards
      await tester.enterText(
        find.byWidgetPredicate(
          (w) =>
              w is TextField && w.decoration?.hintText == 'Search notes (Ctrl+F)' ||
              w is TextField && (w.decoration?.hintText ?? '').startsWith('Search'),
        ),
        'groc',
      );
      await tester.pumpAndSettle();
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('Trip'), findsNothing);

      // open a card → editor page
      await tester.tap(find.text('Groceries'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      expect(c.selected!.title, 'Groceries');
      expect(withImg, isNotEmpty);
    },
  );
}
