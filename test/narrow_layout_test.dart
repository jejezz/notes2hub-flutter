import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes2hub/auth/token_store.dart';
import 'package:notes2hub/images/asset_store.dart';
import 'package:notes2hub/l10n/app_localizations.dart';
import 'package:notes2hub/notes/note_store.dart';
import 'package:notes2hub/notes/notes_controller.dart';
import 'package:notes2hub/screens/board_view.dart';
import 'package:notes2hub/screens/notes_screen.dart';
import 'package:notes2hub/settings/app_settings.dart';
import 'package:notes2hub/sync/sync_service.dart';
import 'package:notes2hub/window/window_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  const screen = Rect.fromLTWH(0, 25, 1440, 850);

  Future<
    ({
      NotesController c,
      SyncService sync,
      AppSettings settings,
      AssetStore assets,
      WindowLayout layout,
      FakePort port,
      String id,
    })
  >
  setup(WidgetTester tester, Directory tmp) async {
    SharedPreferences.setMockInitialValues({});
    late NotesController c;
    late String id;
    late SyncService sync;
    late AppSettings settings;
    late WindowLayout layout;
    final port = FakePort([screen], const Rect.fromLTWH(100, 100, 1200, 720));
    await tester.runAsync(() async {
      c = NotesController(
        NoteStore(notesDir: Directory('${tmp.path}/notes'), draftsDir: Directory('${tmp.path}/drafts')),
      );
      await c.load();
      id = await c.capture(
        '# A fairly long note title that has to wrap on a narrow window\nbody text that is long enough to need a few lines in a card',
      );
      await c.capture('Second note');
      final prefs = await SharedPreferences.getInstance();
      sync = SyncService(
        prefs: prefs,
        tokens: MemoryTokenStore(),
        engine: FakeEngine(),
        notes: c,
        pullInterval: const Duration(hours: 1),
      );
      settings = await AppSettings.load();
      layout = WindowLayout(prefs: prefs, port: port, settleDelay: const Duration(milliseconds: 10));
    });
    addTearDown(() {
      sync.dispose();
      c.dispose();
      layout.dispose();
    });
    return (
      c: c,
      sync: sync,
      settings: settings,
      assets: AssetStore(Directory('${tmp.path}/assets')),
      layout: layout,
      port: port,
      id: id,
    );
  }

  Future<void> pumpScreen(WidgetTester tester, dynamic s) => tester.pumpWidget(
    AppSettingsScope(
      settings: s.settings,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: NotesScreen(controller: s.c, sync: s.sync, assets: s.assets, windowLayout: s.layout, onAbout: () {}),
      ),
    ),
  );

  Finder cardOf(String text) => find.ancestor(of: find.text(text), matching: find.byType(NoteCard));
  Finder editButtonOf(String text) => find.descendant(of: cardOf(text), matching: find.byIcon(Icons.edit_outlined));

  for (final width in [320.0, 360.0, 420.0, 599.0]) {
    testWidgets('board, editor and menus fit without overflow at ${width.toInt()}px wide', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tmp = Directory.systemTemp.createTempSync('notes2hub-narrow');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final s = await setup(tester, tmp);
      await pumpScreen(tester, s);
      await tester.pumpAndSettle();

      // board: capture + search stacked, one card column; the app name stays even at the narrowest width
      expect(find.text('Notes2Hub'), findsOneWidget);
      expect(find.text('Second note'), findsOneWidget);
      final e0 = tester.takeException();
      if (e0 != null) fail('board overflow: $e0');

      // the "more" menu holds settings, window layout and about
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Dock to the left edge'), findsOneWidget);
      expect(find.text('Dock to the right edge'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      await tester.tap(find.text('Dock to the right edge'));
      await tester.pumpAndSettle();
      expect(s.layout.dock, DockSide.right);

      // narrowest layouts show one card per row, each as wide as the window allows
      for (final card in tester.widgetList(find.byType(NoteCard)).toList().asMap().keys) {
        final w = tester.getSize(find.byType(NoteCard).at(card)).width;
        expect(w, greaterThan(width - 2 * 24 - 1), reason: 'card $card is ${w}px wide in a ${width}px window');
      }

      // editor: compact toolbar (opened with the card's edit button)
      await tester.tap(editButtonOf('Second note'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      expect(find.byIcon(Icons.save_rounded), findsOneWidget);
      final e1 = tester.takeException();
      if (e1 != null) fail('editor overflow: ${(e1 as FlutterError).toStringDeep()}');
      s.c.edit(s.c.selectedId!, 'Second note edited');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2)); // 초안 저장 타이머(1초)를 비운다
      final e2 = tester.takeException();
      if (e2 != null) fail('editor(dirty) overflow: ${(e2 as FlutterError).toStringDeep()}');
    });
  }

  testWidgets(
    'opening a note widens a docked window, going back restores the dock width (and an undocked window never moves)',
    (tester) async {
      tester.view.physicalSize = const Size(420, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tmp = Directory.systemTemp.createTempSync('notes2hub-expand');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final s = await setup(tester, tmp);
      await pumpScreen(tester, s);
      await tester.pumpAndSettle();

      // not docked: editing leaves the window alone
      await tester.tap(editButtonOf('Second note'));
      await tester.pumpAndSettle();
      expect(s.port.applied, isEmpty);
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      await tester.runAsync(() => s.layout.dockTo(DockSide.left));
      expect(s.port.current, dockBounds(screen, DockSide.left, 420));

      await tester.tap(editButtonOf('Second note'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
      expect(s.layout.expanded, isTrue);
      expect(s.port.current, expandBounds(screen, DockSide.left, 900));

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
      expect(s.layout.expanded, isFalse);
      expect(s.port.current, dockBounds(screen, DockSide.left, 420));
      await tester.pump(const Duration(seconds: 2)); // 남은 타이머를 비운다
    },
  );
}
