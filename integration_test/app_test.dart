// 실제 macOS 앱(샌드박스 포함)에서만 확인할 수 있는 것들:
//   flutter test integration_test/app_test.dart -d macos
// 네트워크 항목은 GitHub 공개 저장소를 익명으로 clone한다.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pasteboard/pasteboard.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:integration_test/integration_test.dart';
import 'package:notes2hub/auth/token_store.dart';
import 'package:notes2hub/images/asset_store.dart';
import 'package:notes2hub/l10n/app_localizations.dart';
import 'package:notes2hub/notes/notes_controller.dart';
import 'package:notes2hub/screens/notes_screen.dart';
import 'package:notes2hub/settings/app_settings.dart';
import 'package:notes2hub/sync/sync_service.dart';
import 'package:notes2hub/notes/app_paths.dart';
import 'package:notes2hub/notes/note.dart';
import 'package:notes2hub/notes/note_store.dart';
import 'package:notes2hub/sync/ca_bundle.dart';
import 'package:notes2hub/sync/libgit2_engine.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('secure storage round-trip in the sandbox', (tester) async {
    final store = SecureTokenStore();
    await store.delete();
    expect(await store.read(), isNull);
    await store.write('ghp_integration_test_value');
    expect(await store.read(), 'ghp_integration_test_value');
    await store.delete();
    expect(await store.read(), isNull);
  });

  testWidgets('app data dir is writable and notes persist', (tester) async {
    final base = await appDataDir();
    final dir = Directory('${base.path}/it-${DateTime.now().millisecondsSinceEpoch}');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = NoteStore(notesDir: Directory('${dir.path}/notes'), draftsDir: Directory('${dir.path}/drafts'));
    final n = Note(id: 'it1', created: DateTime.now(), updated: DateTime.now(), body: '# integration');
    await store.save(n);
    expect((await store.loadAll()).single.title, 'integration');
    // ignore: avoid_print
    print('APP DATA DIR: ${base.path}');
  });

  testWidgets('HTTPS clone through the bundled CA file works inside the sandbox', (tester) async {
    final base = await appDataDir();
    final ca = await ensureCaBundle(base);
    expect(File(ca).existsSync(), isTrue);
    final dir = Directory('${base.path}/it-clone-${DateTime.now().millisecondsSinceEpoch}');
    addTearDown(() => dir.deleteSync(recursive: true));
    final engine = LibGit2Engine(dir: dir, caCertPath: ca);
    final r = await engine.connect(remoteUrl: 'https://github.com/octocat/Hello-World.git', token: '');
    expect(r.ok, isTrue, reason: r.error);
    expect(File('${dir.path}/README').existsSync(), isTrue);
  });

  testWidgets('pasting a clipboard image attaches it: asset file written, markdown inserted, preview shows it', (tester) async {
    final base = await appDataDir();
    final dir = Directory('${base.path}/it-paste-${DateTime.now().millisecondsSinceEpoch}');
    addTearDown(() => dir.deleteSync(recursive: true));
    final notes = NotesController(NoteStore(notesDir: Directory('${dir.path}/data/notes'), draftsDir: Directory('${dir.path}/drafts')));
    await notes.load();
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    final assets = AssetStore(Directory('${dir.path}/data/assets'));
    final sync = SyncService(
      prefs: await SharedPreferences.getInstance(),
      tokens: MemoryTokenStore(),
      engine: LibGit2Engine(dir: Directory('${dir.path}/data')),
      notes: notes,
    );
    addTearDown(sync.dispose);

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppSettingsScope(
      settings: settings,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: NotesScreen(controller: notes, sync: sync, assets: assets, onAbout: () {}),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '# Pics\nbefore');
    await tester.pump();

    // a 40x40 red PNG on the real macOS pasteboard
    final png = img.encodePng(img.fill(img.Image(width: 40, height: 40), color: img.ColorRgb8(220, 30, 30)));
    await Pasteboard.writeImage(Uint8List.fromList(png));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    for (var i = 0; i < 40 && !(assets.dir.existsSync() && assets.dir.listSync().isNotEmpty); i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    final files = assets.dir.listSync().whereType<File>().toList();
    expect(files, hasLength(1), reason: 'pasted image should be stored under assets/');
    expect(files.single.path, endsWith('.png'));
    final body = notes.bodyOf(notes.selectedId!);
    expect(body, contains('![image](../assets/${files.single.uri.pathSegments.last})'));
    expect(body, startsWith('# Pics\nbefore'));

    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsWidgets);
  });
}
