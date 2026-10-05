import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:notes2hub/auth/token_store.dart';
import 'package:notes2hub/images/asset_store.dart';
import 'package:notes2hub/l10n/app_localizations.dart';
import 'package:notes2hub/notes/note_store.dart';
import 'package:notes2hub/notes/notes_controller.dart';
import 'package:notes2hub/platform_kind.dart';
import 'package:notes2hub/screens/md_format.dart';
import 'package:notes2hub/screens/note_preview.dart';
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

    testWidgets('adding a large photo shows a progress indicator while it is being reduced, then inserts it', (
      tester,
    ) async {
      await pump(tester);
      // 1MiB를 넘는 (무작위 잡음이라 PNG로 잘 안 줄어드는) 이미지를 클립보드에 있는 것처럼 꾸민다.
      final rnd = Random(1);
      final big = img.Image(width: 1300, height: 1300);
      for (final p in big) {
        p.setRgb(rnd.nextInt(256), rnd.nextInt(256), rnd.nextInt(256));
      }
      final png = Uint8List.fromList(img.encodePng(big, level: 1));
      expect(png.length, greaterThan(1024 * 1024));
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('pasteboard'), (call) async {
        return switch (call.method) {
          'files' => <String>[],
          'image' => png,
          _ => null,
        };
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('pasteboard'), null));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.byType(ImageBusyOverlay), findsNothing);
      Actions.invoke(tester.element(find.byType(TextField).first), const PasteTextIntent(SelectionChangedCause.keyboard));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();

      // 줄이는 동안: 진행 표시와 안내가 보이고, 그 아래 조작은 막힌다
      expect(find.byType(ImageBusyOverlay), findsOneWidget);
      expect(find.text('Adding image…'), findsOneWidget);
      expect(find.text('Large photos are reduced to under 1 MB — this can take a moment.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(c.selected!.body, isEmpty); // 아직 삽입 전

      // 끝나면 표시가 사라지고 이미지 참조가 본문에 들어간다
      for (var i = 0; i < 100 && find.byType(ImageBusyOverlay).evaluate().isNotEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
      expect(find.byType(ImageBusyOverlay), findsNothing);
      expect(c.selected!.body, contains('](../assets/'));
      await tester.pump(const Duration(seconds: 10)); // 안내 스낵바·초안 타이머를 비운다
    });

    testWidgets('preview sheet: [Edit][Share][Close] for a saved note, [Edit][Save][Share][Close] for an unsaved one', (tester) async {
      await pump(tester);
      final id = c.notes.first.id;
      Finder button(String label) => find.descendant(of: find.byType(NotePreviewSheet), matching: find.text(label));

      // 저장된 메모: [편집] [공유] [닫기]
      await tester.tap(find.text('Phone note'));
      await tester.pumpAndSettle();
      expect(find.byType(NotePreviewSheet), findsOneWidget);
      expect(button('Save'), findsNothing);
      expect(button('Share'), findsOneWidget); // 글자 버튼 (아이콘이 아니라)
      expect(button('Close'), findsOneWidget);
      expect(button('Edit'), findsOneWidget);
      // 읽는 순서(줄 → 가로)로 비교한다: 좁은 폭에서는 버튼이 다음 줄로 넘어갈 수 있다.
      bool before(String a, String b) {
        final pa = tester.getTopLeft(button(a)), pb = tester.getTopLeft(button(b));
        return pa.dy < pb.dy || (pa.dy == pb.dy && pa.dx < pb.dx);
      }

      expect(before('Edit', 'Share'), isTrue);
      expect(before('Share', 'Close'), isTrue);
      await tester.tap(button('Close'));
      await tester.pumpAndSettle();

      // 고쳐서 저장하지 않은 메모: [편집] [저장] [공유] [닫기] 순서
      c.edit(id, 'Phone note edited');
      await tester.pumpAndSettle();
      expect(c.isDirty(id), isTrue);
      await tester.tap(find.text('Phone note edited'));
      await tester.pumpAndSettle();
      expect(button('Share'), findsOneWidget);
      expect(before('Edit', 'Save'), isTrue);
      expect(before('Save', 'Share'), isTrue);
      expect(before('Share', 'Close'), isTrue);
      expect(tester.takeException(), isNull);

      // [저장]: 시트가 닫히고 저장된다
      await tester.tap(button('Save'));
      for (var i = 0; i < 40 && c.isDirty(id); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.byType(NotePreviewSheet), findsNothing);
      expect(c.isDirty(id), isFalse);
      expect(c.noteById(id)!.body, 'Phone note edited');
      await tester.pump(const Duration(seconds: 2)); // 초안 타이머를 비운다
    });
  });
}
