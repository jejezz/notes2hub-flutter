import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes2hub/auth/token_store.dart';
import 'package:notes2hub/images/asset_store.dart';
import 'package:notes2hub/l10n/app_localizations.dart';
import 'package:notes2hub/notes/note_store.dart';
import 'package:notes2hub/notes/notes_controller.dart';
import 'package:notes2hub/platform_kind.dart';
import 'package:notes2hub/screens/md_format.dart';
import 'package:notes2hub/screens/notes_screen.dart';
import 'package:notes2hub/settings/app_settings.dart';
import 'package:notes2hub/sync/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

TextEditingValue _v(String text, int a, [int? b]) =>
    TextEditingValue(text: text, selection: TextSelection(baseOffset: a, extentOffset: b ?? a));

void main() {
  group('MdFormat', () {
    test('wrap surrounds the selection and toggles back', () {
      final bold = MdFormat.wrap(_v('say hello now', 4, 9), '**');
      expect(bold.text, 'say **hello** now');
      expect(bold.selection.textInside(bold.text), 'hello');
      final back = MdFormat.wrap(bold, '**');
      expect(back.text, 'say hello now');
      expect(back.selection.textInside(back.text), 'hello');
    });

    test('wrap with no selection puts the cursor between the markers', () {
      final v = MdFormat.wrap(_v('ab', 1), '**');
      expect(v.text, 'a****b');
      expect(v.selection, const TextSelection.collapsed(offset: 3));
    });

    test('wrap works without a valid selection (cursor at the end)', () {
      final v = MdFormat.wrap(const TextEditingValue(text: 'ab'), '*');
      expect(v.text, 'ab**');
    });

    test('prefixLines adds to every selected line and removes when all have it', () {
      final v = MdFormat.prefixLines(_v('one\ntwo\nthree', 2, 9), '- ');
      expect(v.text, '- one\n- two\n- three');
      final back = MdFormat.prefixLines(v, '- ');
      expect(back.text, 'one\ntwo\nthree');
    });

    test('prefixLines only touches the cursor line when nothing is selected', () {
      final v = MdFormat.prefixLines(_v('one\ntwo\nthree', 5), '## ');
      expect(v.text, 'one\n## two\nthree');
    });

    test('link wraps the selection and selects the url placeholder', () {
      final v = MdFormat.link(_v('see docs', 4, 8));
      expect(v.text, 'see [docs](url)');
      expect(v.selection.textInside(v.text), 'url');
      final empty = MdFormat.link(_v('', 0));
      expect(empty.text, '[](url)');
      expect(empty.selection, const TextSelection.collapsed(offset: 1));
    });
  });

  group('phone UI', () {
    late Directory tmp;
    late NotesController c;
    late SyncService sync;
    late AppSettings settings;

    setUp(() => debugIsMobile = true);
    tearDown(() => debugIsMobile = null);

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tmp = Directory.systemTemp.createTempSync('notes2hub-mobile');
      addTearDown(() => tmp.deleteSync(recursive: true));
      SharedPreferences.setMockInitialValues({});
      await tester.runAsync(() async {
        c = NotesController(
          NoteStore(notesDir: Directory('${tmp.path}/notes'), draftsDir: Directory('${tmp.path}/drafts')),
        );
        await c.load();
        await c.capture('Phone note');
        sync = SyncService(
          prefs: await SharedPreferences.getInstance(),
          tokens: MemoryTokenStore(),
          engine: FakeEngine(),
          notes: c,
          pullInterval: const Duration(hours: 1),
        );
        settings = await AppSettings.load();
      });
      addTearDown(() {
        sync.dispose();
        c.dispose();
      });
      await tester.pumpWidget(
        AppSettingsScope(
          settings: settings,
          child: MaterialApp(
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
    }

    testWidgets('board: + button, pull to refresh, long-press menu instead of tiny edit/delete buttons', (tester) async {
      await pump(tester);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byType(RefreshIndicator), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget); // only the FAB's icon
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
      expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget); // kept: a frequent action, 44dp target
      expect(tester.takeException(), isNull);

      await tester.longPress(find.text('Phone note'));
      await tester.pumpAndSettle();
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Bookmark'), findsWidgets);
      expect(find.text('Delete'), findsOneWidget);

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsNothing); // editing: no + button
      expect(find.byIcon(Icons.format_bold_rounded), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('quick capture has a send button (no Enter key on a phone)', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField).first, 'sent from the button');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      expect(find.text('sent from the button'), findsOneWidget);
    });

    testWidgets('editor: toolbar formats the text; Android back returns to the board instead of exiting', (tester) async {
      await pump(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'hello world');
      await tester.pump();
      // select "world" and make it bold
      final field = tester.widget<TextField>(find.byType(TextField).first);
      field.controller!.selection = const TextSelection(baseOffset: 6, extentOffset: 11);
      await tester.tap(find.byIcon(Icons.format_bold_rounded));
      await tester.pump();
      expect(field.controller!.text, 'hello **world**');
      expect(c.selected!.body, 'hello **world**');
      await tester.tap(find.byIcon(Icons.checklist_rounded));
      await tester.pump();
      expect(field.controller!.text, startsWith('- [ ] hello'));
      expect(tester.takeException(), isNull);

      // system back: leaves the editor, the app stays
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(c.selectedId, isNull);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
