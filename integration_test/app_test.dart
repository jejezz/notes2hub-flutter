// 실제 macOS 앱(샌드박스 포함)에서만 확인할 수 있는 것들:
//   flutter test integration_test/app_test.dart -d macos
// 네트워크 항목은 GitHub 공개 저장소를 익명으로 clone한다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:notes2hub/auth/token_store.dart';
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
}
