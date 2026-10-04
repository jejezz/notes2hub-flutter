import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git2dart/git2dart.dart' as git;
import 'package:notes2hub/notes/note.dart';
import 'package:notes2hub/sync/libgit2_engine.dart';
import 'package:notes2hub/sync/sync_models.dart';

const _who = GitIdentity(name: 'tester', email: 'tester@users.noreply.github.com');

/// 실제 libgit2로 로컬 bare 저장소(origin)와 두 작업 폴더(PC A, B)를 돌린다.
void main() {
  late Directory tmp;
  late String origin;
  late LibGit2Engine a, b;
  late Directory da, db;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('notes2hub-sync');
    origin = '${tmp.path}/origin.git';
    git.Repository.init(path: origin, bare: true, initialHead: 'main').free();
    da = Directory('${tmp.path}/A');
    db = Directory('${tmp.path}/B');
    a = LibGit2Engine(dir: da);
    b = LibGit2Engine(dir: db);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  File noteFile(Directory d, String id) => File('${d.path}/notes/$id.md');

  void write(Directory d, String id, String body) {
    final n = Note(id: id, created: DateTime.utc(2026), updated: DateTime.now(), body: body);
    noteFile(d, id)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(n.serialize());
  }

  Future<SyncResult> sync(LibGit2Engine e, {String label = 'pc'}) =>
      e.sync(token: '', identity: _who, deviceLabel: label);

  test('first sync to an empty remote pushes; another PC connects and receives the note', () async {
    expect((await a.connect(remoteUrl: origin, token: '')).ok, isTrue);
    write(da, 'n1', '# one');
    expect((await a.status()).changed, 1);
    final r = await sync(a);
    expect(r.ok, isTrue, reason: r.error);
    expect(r.pushed, isTrue);
    expect(r.committed, 1);
    expect((await a.status()).changed, 0);

    final c = await b.connect(remoteUrl: origin, token: '');
    expect(c.ok, isTrue, reason: c.error);
    expect(noteFile(db, 'n1').readAsStringSync(), contains('# one'));
  });

  test('syncing with nothing to do is a quiet no-op', () async {
    await a.connect(remoteUrl: origin, token: '');
    final r = await sync(a);
    expect(r.ok, isTrue, reason: r.error);
    expect(r.committed, 0);
    expect(r.pushed, isFalse); // empty repo, nothing to push
  });

  test('local-only notes survive connecting to a repo that already has notes', () async {
    await a.connect(remoteUrl: origin, token: '');
    write(da, 'remote1', '# from A');
    await sync(a);

    write(db, 'local1', '# written before connecting'); // Phase 1 style: no git yet
    final c = await b.connect(remoteUrl: origin, token: '');
    expect(c.ok, isTrue, reason: c.error);
    expect(noteFile(db, 'remote1').existsSync(), isTrue);
    expect(noteFile(db, 'local1').existsSync(), isTrue);

    final r = await sync(b);
    expect(r.pushed, isTrue, reason: r.error);
    await sync(a);
    expect(noteFile(da, 'local1').existsSync(), isTrue);
  });

  test('different notes on both PCs merge cleanly', () async {
    await a.connect(remoteUrl: origin, token: '');
    write(da, 'base', '# base');
    await sync(a);
    await b.connect(remoteUrl: origin, token: '');

    write(da, 'from-a', '# a');
    write(db, 'from-b', '# b');
    expect((await sync(a)).pushed, isTrue);
    final r = await sync(b);
    expect(r.ok, isTrue, reason: r.error);
    expect(r.conflictCopies, 0);
    expect(r.integrated, isTrue);
    expect(noteFile(db, 'from-a').existsSync(), isTrue);

    await sync(a);
    expect(noteFile(da, 'from-b').existsSync(), isTrue);
  });

  test('same note edited on both PCs: remote wins, local is kept as a conflict copy', () async {
    await a.connect(remoteUrl: origin, token: '');
    write(da, 'shared', '# Plan\nbase');
    await sync(a);
    await b.connect(remoteUrl: origin, token: '');

    write(da, 'shared', '# Plan\nedited on A');
    await sync(a);
    write(db, 'shared', '# Plan\nedited on B');
    final r = await sync(b, label: 'PC-B');
    expect(r.ok, isTrue, reason: r.error);
    expect(r.conflictCopies, 1);

    expect(noteFile(db, 'shared').readAsStringSync(), contains('edited on A'));
    final copies = Directory('${db.path}/notes')
        .listSync()
        .whereType<File>()
        .where((f) => !f.path.endsWith('shared.md'))
        .toList();
    expect(copies, hasLength(1));
    final copy = Note.parse(copies.single.readAsStringSync(), fallbackId: '', fallbackTime: DateTime(2000));
    expect(copy.body, contains('edited on B'));
    expect(copy.title, startsWith('Plan (충돌 PC-B'));
    expect(copy.id, isNot('shared'));

    // pushed: A receives the copy too
    await sync(a);
    expect(Directory('${da.path}/notes').listSync().length, 2);
    expect(noteFile(da, 'shared').readAsStringSync(), contains('edited on A'));
  });

  test('deleting a note propagates to the other PC', () async {
    await a.connect(remoteUrl: origin, token: '');
    write(da, 'gone', '# bye');
    write(da, 'stay', '# stay');
    await sync(a);
    await b.connect(remoteUrl: origin, token: '');

    noteFile(da, 'gone').deleteSync();
    expect((await a.status()).changed, 1);
    await sync(a);
    final r = await sync(b);
    expect(r.ok, isTrue, reason: r.error);
    expect(noteFile(db, 'gone').existsSync(), isFalse);
    expect(noteFile(db, 'stay').existsSync(), isTrue);
  });

  test('edit on one PC vs delete on the other keeps the edit', () async {
    await a.connect(remoteUrl: origin, token: '');
    write(da, 'x', '# x\nbase');
    await sync(a);
    await b.connect(remoteUrl: origin, token: '');

    noteFile(da, 'x').deleteSync();
    await sync(a);
    write(db, 'x', '# x\nB kept working on it');
    final r = await sync(b);
    expect(r.ok, isTrue, reason: r.error);
    expect(noteFile(db, 'x').readAsStringSync(), contains('B kept working'));
  });

  test('pull fast-forwards a clean PC; with saved changes it only reports needsSync', () async {
    await a.connect(remoteUrl: origin, token: '');
    write(da, 'p1', '# p1');
    await sync(a);
    await b.connect(remoteUrl: origin, token: '');

    write(da, 'p2', '# p2');
    await sync(a);
    final r = await b.pull(token: '');
    expect(r.ok, isTrue, reason: r.error);
    expect(r.integrated, isTrue);
    expect(noteFile(db, 'p2').existsSync(), isTrue);

    write(da, 'p3', '# p3');
    await sync(a);
    write(db, 'mine', '# saved but not synced');
    final r2 = await b.pull(token: '');
    expect(r2.integrated, isFalse);
    expect(r2.needsSync, isTrue);
    expect(noteFile(db, 'p3').existsSync(), isFalse); // working folder untouched
    expect(noteFile(db, 'mine').existsSync(), isTrue);
  });

  test('unreachable remote reports an error without losing the local commit', () async {
    await a.connect(remoteUrl: origin, token: '');
    write(da, 'o1', '# offline');
    await sync(a);
    write(da, 'o2', '# second');
    Directory(origin).renameSync('${origin}_gone');
    final r = await sync(a);
    expect(r.ok, isFalse);
    expect((await a.status()).changed, 0);
    Directory('${origin}_gone').renameSync(origin);
    final r2 = await sync(a);
    expect(r2.pushed, isTrue, reason: r2.error);
  });

  test('status: clean after sync, unpushed after a failed push, not unpushed when only behind', () async {
    await a.connect(remoteUrl: origin, token: '');
    write(da, 's1', '# s1');
    expect((await a.status()).changed, 1);
    await sync(a);
    expect((await a.status()).isClean, isTrue);

    // commit succeeds locally but the remote is unreachable → "unpushed"
    write(da, 's2', '# s2');
    Directory(origin).renameSync('${origin}_gone');
    expect((await sync(a)).ok, isFalse);
    var st = await a.status();
    expect(st.changed, 0);
    expect(st.unpushed, isTrue);
    Directory('${origin}_gone').renameSync(origin);
    await sync(a);
    expect((await a.status()).isClean, isTrue);

    // another PC pushes; A has fetched nothing new yet → still clean; after a pull it is behind-free
    await b.connect(remoteUrl: origin, token: '');
    write(db, 's3', '# s3');
    await sync(b);
    expect((await a.pull(token: '')).integrated, isTrue);
    st = await a.status();
    expect(st.isClean, isTrue);

    // behind only (fetched but not merged) is not "unpushed"
    write(db, 's4', '# s4');
    await sync(b);
    write(da, 's5', '# s5'); // saved on A → needsSync, nothing merged
    final r = await a.pull(token: '');
    expect(r.needsSync, isTrue);
    await sync(a);
    expect((await a.status()).isClean, isTrue);
  });

  test('status on a folder that was never connected is clean', () async {
    write(da, 'solo', '# not a repo yet');
    expect((await a.status()).isClean, isTrue);
  });

  test('attached images under assets/ sync both ways, deletions included; .tmp files are ignored', () async {
    File asset(Directory d, String name) => File('${d.path}/assets/$name');
    await a.connect(remoteUrl: origin, token: '');
    write(da, 'withimg', '# pic\n![x](../assets/p1.jpg)');
    asset(da, 'p1.jpg')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 1, 2, 3]);
    asset(da, 'half.jpg.tmp').writeAsBytesSync([9]); // an interrupted write
    expect((await a.status()).changed, 2); // note + image, not the .tmp
    expect((await sync(a)).pushed, isTrue);

    await b.connect(remoteUrl: origin, token: '');
    expect(asset(db, 'p1.jpg').readAsBytesSync(), [0xFF, 0xD8, 0xFF, 1, 2, 3]);
    expect(asset(db, 'half.jpg.tmp').existsSync(), isFalse);

    asset(da, 'p1.jpg').deleteSync();
    await sync(a);
    await sync(b);
    expect(asset(db, 'p1.jpg').existsSync(), isFalse);
  });
}
