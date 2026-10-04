import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes2hub/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:notes2hub/l10n/app_localizations.dart';
import 'package:notes2hub/notes/note_store.dart';
import 'package:notes2hub/auth/token_store.dart';
import 'package:notes2hub/notes/notes_controller.dart';
import 'package:notes2hub/sync/sync_service.dart';
import 'fakes.dart';
import 'package:notes2hub/screens/notes_screen.dart';

void main() {
  testWidgets('create, type, save with Ctrl+S (macOS: Cmd+S), preview', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('notes2hub-ui');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final c = NotesController(NoteStore(
      notesDir: Directory('${tmp.path}/notes'),
      draftsDir: Directory('${tmp.path}/drafts'),
    ));
    tester.view.physicalSize = const Size(1200, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final settings = (await tester.runAsync(AppSettings.load))!;
    await tester.runAsync(c.load);
    final sync = SyncService(
      prefs: await tester.runAsync(SharedPreferences.getInstance).then((v) => v!),
      tokens: MemoryTokenStore(),
      engine: FakeEngine(),
      notes: c,
    );
    addTearDown(sync.dispose);

    await tester.pumpWidget(AppSettingsScope(
      settings: settings,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: NotesScreen(controller: c, sync: sync, onAbout: () {}),
      ),
    ));
    expect(find.text('No notes yet'), findsOneWidget);

    await tester.tap(find.text('New note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '# Shopping\nmilk');
    await tester.pump();
    expect(find.text('Unsaved'), findsWidgets);

    await tester.runAsync(() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.text('Saved'), findsOneWidget);
    expect(Directory('${tmp.path}/notes').listSync().whereType<File>().length, 1);
    expect(find.text('Shopping'), findsWidgets); // list title

    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(find.byType(Markdown), findsOneWidget);
    c.dispose();
  });
}
