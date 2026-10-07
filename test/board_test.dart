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
import 'package:notes2hub/theme/app_theme.dart';
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

      // tapping a card previews it in a bottom sheet (no editor yet); its Edit button opens the editor
      await tester.tap(find.text('Groceries'));
      await tester.pumpAndSettle();
      expect(find.byType(NotePreviewSheet), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
      await tester.tap(
        find.descendant(of: find.byType(NotePreviewSheet), matching: find.widgetWithText(FilledButton, 'Edit')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NotePreviewSheet), findsNothing);
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      expect(c.selected!.title, 'Groceries');
      expect(withImg, isNotEmpty);
    },
  );
}

void cardButtonsTest() {
  testWidgets(
    'card buttons: edit opens the editor, delete goes to the trash; a long note previews in a scrollable bottom sheet',
    (tester) async {
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

      // long note → the sheet is height-limited, its body scrolls, the Close/Edit buttons stay put
      await tester.tap(find.text('Long note'));
      await tester.pumpAndSettle();
      final sheet = find.byType(NotePreviewSheet);
      expect(sheet, findsOneWidget);
      expect(tester.getSize(sheet).height, lessThanOrEqualTo(800 * 0.85));
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: sheet, matching: find.byType(Scrollable)).first,
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(100));
      final closeY = tester.getTopLeft(find.widgetWithText(TextButton, 'Close')).dy;
      await tester.drag(
        find.descendant(of: sheet, matching: find.byType(SingleChildScrollView)),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, greaterThan(0));
      expect(tester.getTopLeft(find.widgetWithText(TextButton, 'Close')).dy, closeY); // buttons did not scroll away
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();
      expect(find.byType(NotePreviewSheet), findsNothing);

      // edit button → editor
      await tester.tap(find.descendant(of: card('Long note'), matching: find.byIcon(Icons.edit_outlined)));
      await tester.pumpAndSettle();
      expect(c.selectedId, longId);
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      // delete button → straight to the trash with an undo; undo brings it back
      Future<void> settle() async {
        // 파일 쓰기는 실제 시간이 필요하다 — 실제 시간과 pump를 번갈아 진행한다.
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump(const Duration(milliseconds: 20));
        }
        await tester.pumpAndSettle();
      }

      await tester.tap(find.descendant(of: card('Short one'), matching: find.byIcon(Icons.delete_outline_rounded)));
      await settle();
      expect(find.text('Short one'), findsNothing);
      expect(File('${tmp.path}/notes/$shortId.md').readAsStringSync(), contains('deleted: '));
      expect(c.trashed.map((n) => n.id), [shortId]);
      await tester.tap(find.text('Undo'));
      await settle();
      expect(find.text('Short one'), findsOneWidget);
      expect(c.trashed, isEmpty);

      // the trash dialog lists deleted notes and restores them
      await tester.tap(find.descendant(of: card('Short one'), matching: find.byIcon(Icons.delete_outline_rounded)));
      await settle();
      await tester.tap(find.byTooltip('Trash'));
      await tester.pumpAndSettle();
      expect(find.text('Short one'), findsOneWidget);
      await tester.tap(find.byTooltip('Restore'));
      await settle();
      expect(c.trashed, isEmpty);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Short one'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1)); // 동기화 상태 갱신 타이머(300ms)를 비운다
    },
  );

  testWidgets('the board uses SeoulNamsan everywhere (fields, hints, card text)', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tmp = Directory.systemTemp.createTempSync('notes2hub-fonts');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final c = NotesController(
      NoteStore(notesDir: Directory('${tmp.path}/notes'), draftsDir: Directory('${tmp.path}/drafts')),
    );
    SharedPreferences.setMockInitialValues({});
    final sync = (await tester.runAsync(
      () async => SyncService(
        prefs: await SharedPreferences.getInstance(),
        tokens: MemoryTokenStore(),
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
    await tester.runAsync(c.load);
    await tester.pumpWidget(
      AppSettingsScope(
        settings: settings,
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: NotesScreen(
            controller: c,
            sync: sync,
            assets: AssetStore(Directory('${tmp.path}/assets')),
            onAbout: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final capture = tester.widget<TextField>(find.byType(TextField).at(0));
    final search = tester.widget<TextField>(find.byType(TextField).at(1));
    expect(capture.decoration!.hintText, 'Write something and press Enter');
    expect(search.decoration!.hintText, 'Search notes');
    expect(search.style, capture.style, reason: 'typed text: same font and size');
    expect(search.decoration!.hintStyle, capture.decoration!.hintStyle, reason: 'hint text: same font and size');
    expect(search.decoration!.hintStyle?.fontFamily, 'SeoulNamsan');
    expect(capture.style?.fontFamily, 'SeoulNamsan', reason: 'the board uses the app font everywhere');
    expect(search.style?.fontFamily, 'SeoulNamsan');

    // card titles and excerpts too (the editor and the preview sheet keep the system font)
    await tester.runAsync(() => c.capture('Card title\nCard excerpt text'));
    await tester.pumpAndSettle();
    for (final label in ['Card title', 'Card excerpt text']) {
      final text = tester.widget<Text>(find.text(label));
      expect(text.style?.fontFamily, 'SeoulNamsan', reason: label);
    }
  });
}
