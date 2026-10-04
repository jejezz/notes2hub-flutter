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
import 'package:notes2hub/screens/note_preview.dart';
import 'package:notes2hub/screens/notes_screen.dart';
import 'package:notes2hub/settings/app_settings.dart';
import 'package:notes2hub/sync/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  cardButtonsTest();
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

      // tapping a card previews it in a snackbar (no editor yet); its Edit action opens the editor
      await tester.tap(find.text('Groceries'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.byType(NotePreviewSnack), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
      await tester.tap(find.descendant(of: find.byType(SnackBar), matching: find.text('Edit')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      expect(c.selected!.title, 'Groceries');
      expect(find.byType(SnackBar), findsNothing);
      expect(withImg, isNotEmpty);
    },
  );
}

void cardButtonsTest() {
  testWidgets('card buttons: edit opens the editor, delete asks first; a long note previews in a scrollable snackbar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tmp = Directory.systemTemp.createTempSync('notes2hub-cardbtn');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final assets = AssetStore(Directory('${tmp.path}/assets'));
    final c = NotesController(
      NoteStore(notesDir: Directory('${tmp.path}/notes'), draftsDir: Directory('${tmp.path}/drafts')),
    );
    SharedPreferences.setMockInitialValues({});
    final tokens = MemoryTokenStore();
    final sync = (await tester.runAsync(
      () async => SyncService(
        prefs: await SharedPreferences.getInstance(),
        tokens: tokens,
        engine: FakeEngine(),
        notes: c,
        pullInterval: const Duration(hours: 1),
      ),
    ))!;
    final settings = (await tester.runAsync(AppSettings.load))!;
    addTearDown(() {
      sync.dispose();
      c.dispose();
    });
    late String longId, shortId;
    await tester.runAsync(() async {
      await c.load();
      longId = await c.capture(
        '# Long note\n${List.generate(80, (i) => 'line number $i of the long note').join('\n\n')}',
      );
      shortId = await c.capture('Short one\nwith a body');
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

    Finder card(String t) => find.ancestor(of: find.text(t), matching: find.byType(NoteCard));

    // long note → snackbar content scrolls and is height-limited
    await tester.tap(find.text('Long note'));
    await tester.pumpAndSettle();
    final snack = find.byType(NotePreviewSnack);
    expect(snack, findsOneWidget);
    expect(tester.getSize(snack).height, lessThanOrEqualTo(420));
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: snack, matching: find.byType(Scrollable)).first,
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(100));
    await tester.drag(find.descendant(of: snack, matching: find.byType(SingleChildScrollView)), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, greaterThan(0));
    await tester.tap(find.byIcon(Icons.close)); // the snackbar's close icon
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);

    // edit button → editor
    await tester.tap(find.descendant(of: card('Long note'), matching: find.byIcon(Icons.edit_outlined)));
    await tester.pumpAndSettle();
    expect(c.selectedId, longId);
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    // delete button → confirmation; cancel keeps the note, confirm removes it
    await tester.tap(find.descendant(of: card('Short one'), matching: find.byIcon(Icons.delete_outline_rounded)));
    await tester.pumpAndSettle();
    expect(find.text('Delete this note?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Short one'), findsOneWidget);

    await tester.tap(find.descendant(of: card('Short one'), matching: find.byIcon(Icons.delete_outline_rounded)));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    // 지우기는 실제 파일 삭제를 거친다 — 실제 시간과 pump를 번갈아 진행한다.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(find.text('Short one'), findsNothing);
    expect(File('${tmp.path}/notes/$shortId.md').existsSync(), isFalse);
    await tester.pump(const Duration(seconds: 1)); // 동기화 상태 갱신 타이머(300ms)를 비운다
  });
}
