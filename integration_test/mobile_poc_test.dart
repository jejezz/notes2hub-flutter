// 모바일 M0 PoC (docs/MOBILE_PLAN.md §3). 실제 iOS/Android 기기·에뮬레이터에서:
//   flutter test integration_test/mobile_poc_test.dart -d <device>
// 앱 전용 임시 폴더만 쓴다. 네트워크 항목은 공개 저장소를 익명으로 clone한다.
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:git2dart/git2dart.dart' as git;
import 'package:integration_test/integration_test.dart';
import 'package:notes2hub/notes/app_paths.dart';
import 'package:notes2hub/notes/note.dart';
import 'package:notes2hub/sync/ca_bundle.dart';
import 'package:notes2hub/sync/libgit2_engine.dart';
import 'package:notes2hub/sync/sync_models.dart';
import 'package:path_provider/path_provider.dart';

import '../tool/poc/git2dart_poc.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => git.PlatformSpecific.initialize());

  testWidgets('#2 git2dart flow with local bare origin', (tester) async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}/poc-${DateTime.now().microsecondsSinceEpoch}')..createSync(recursive: true);
    expect(runPoc(dir), 0);
  });

  testWidgets('app data dir resolves to app-private storage', (tester) async {
    final d = await appDataDir();
    d.createSync(recursive: true);
    // ignore: avoid_print
    print('appDataDir=${d.path}');
    expect(d.existsSync(), isTrue);
  });

  testWidgets('#3/#4 HTTPS clone in an Isolate with the bundled CA', (tester) async {
    final base = await appDataDir();
    final ca = await ensureCaBundle(base);
    final tmp = await getTemporaryDirectory();
    final path = '${tmp.path}/https-${DateTime.now().microsecondsSinceEpoch}';
    final ok = await Isolate.run(() {
      git.Libgit2.setSSLCertLocations(file: ca);
      final repo = git.Repository.clone(url: 'https://github.com/octocat/Hello-World.git', localPath: path);
      repo.free();
      return File('$path/README').existsSync();
    });
    expect(ok, isTrue);
  });

  testWidgets('#5 LibGit2Engine round trip via Isolate (two working copies)', (tester) async {
    final tmp = await getTemporaryDirectory();
    final root = Directory('${tmp.path}/eng-${DateTime.now().microsecondsSinceEpoch}')..createSync(recursive: true);
    final origin = '${root.path}/origin.git';
    git.Repository.init(path: origin, bare: true, initialHead: 'main').free();
    final da = Directory('${root.path}/A'), db = Directory('${root.path}/B');
    final a = LibGit2Engine(dir: da), b = LibGit2Engine(dir: db);
    const who = GitIdentity(name: 't', email: 't@users.noreply.github.com');

    expect((await a.connect(remoteUrl: origin, token: '')).ok, isTrue);
    File('${da.path}/notes/n1.md')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(Note(id: 'n1', created: DateTime.utc(2026), updated: DateTime.now(), body: '# one').serialize());
    final r = await a.sync(token: '', identity: who, deviceLabel: 'A');
    expect(r.ok && r.pushed, isTrue, reason: r.error);
    expect((await b.connect(remoteUrl: origin, token: '')).ok, isTrue);
    expect(File('${db.path}/notes/n1.md').readAsStringSync(), contains('# one'));

    // 같은 메모를 양쪽에서 수정 → 충돌 사본
    File('${da.path}/notes/n1.md').writeAsStringSync(Note(id: 'n1', created: DateTime.utc(2026), updated: DateTime.now(), body: '# A').serialize());
    File('${db.path}/notes/n1.md').writeAsStringSync(Note(id: 'n1', created: DateTime.utc(2026), updated: DateTime.now(), body: '# B').serialize());
    expect((await a.sync(token: '', identity: who, deviceLabel: 'A')).ok, isTrue);
    final rb = await b.sync(token: '', identity: who, deviceLabel: 'B');
    expect(rb.ok, isTrue, reason: rb.error);
    expect(rb.conflictCopies, 1);
  });
}
