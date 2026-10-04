// Phase 0 PoC: can git2dart (libgit2) do the sync flow without a git binary?
//
//   flutter test tool/poc/git2dart_poc_test.dart   (git2dart needs the Flutter engine toolchain,
//   so `dart run` does not work)
//
// Uses a local bare repo as "origin" and two clones (A, B) in a temp dir.
// HTTPS + token against GitHub is NOT covered here (needs a real token).
import 'dart:io';

import 'package:git2dart/git2dart.dart';

final sig = Signature.create(name: 'poc', email: 'poc@example.com');
var _failures = 0;

void check(String what, bool ok) {
  stdout.writeln('${ok ? 'PASS' : 'FAIL'}  $what');
  if (!ok) _failures++;
}

Oid commitAll(Repository repo, String msg, {List<Commit> parents = const []}) {
  repo.index.addAll(repo.status.keys.toList());
  repo.index.write();
  final tree = Tree.lookup(repo: repo, oid: repo.index.writeTree());
  final ps = parents.isNotEmpty
      ? parents
      : (repo.isEmpty ? <Commit>[] : [Commit.lookup(repo: repo, oid: repo.head.target)]);
  return Commit.create(
    repo: repo,
    updateRef: 'HEAD',
    author: sig,
    committer: sig,
    message: msg,
    tree: tree,
    parents: ps,
  );
}

/// fetch + merge origin/main. Returns conflicted paths (resolved by caller).
List<String> pull(Repository repo) {
  Remote.lookup(repo: repo, name: 'origin').fetch();
  final theirs = Reference.lookup(repo: repo, name: 'refs/remotes/origin/main').target;
  final a = Merge.analysis(repo: repo, theirHead: theirs).result;
  stdout.writeln('  analysis=$a');
  if (a.contains(GitMergeAnalysis.upToDate)) return [];
  if (a.contains(GitMergeAnalysis.fastForward)) {
    Reference.setTarget(repo: repo, name: 'refs/heads/main', target: theirs);
    Checkout.head(repo: repo, strategy: {GitCheckout.force});
    return [];
  }
  Merge.commit(repo: repo, commit: AnnotatedCommit.lookup(repo: repo, oid: theirs));
  return repo.index.conflicts.keys.toList();
}

void main() {
  stdout.writeln('libgit2 ${Libgit2.version}');
  exit(runPoc(Directory.systemTemp.createTempSync('notes2hub-poc')) == 0 ? 0 : 1);
}

int runPoc(Directory tmp) {
  final origin = '${tmp.path}/origin.git';
  final pa = '${tmp.path}/A', pb = '${tmp.path}/B';
  try {
    final o = Repository.init(path: origin, bare: true);
    o.setHead('refs/heads/main'); // so clones check out main
    o.free();

    final a = Repository.init(path: pa);
    Remote.create(repo: a, name: 'origin', url: origin);
    File('$pa/n1.md').writeAsStringSync('# n1\nbase\n');
    commitAll(a, 'init');
    // rename master -> main
    Reference.rename(repo: a, oldName: 'refs/heads/master', newName: 'refs/heads/main', force: true);
    a.setHead('refs/heads/main');
    Remote.lookup(repo: a, name: 'origin').push(refspecs: ['refs/heads/main:refs/heads/main']);
    check('A: init + commit + push to bare origin', true);

    final b = Repository.clone(url: origin, localPath: pb);
    check('B: clone from origin', File('$pb/n1.md').existsSync());

    // clean merge (different files)
    File('$pa/n2.md').writeAsStringSync('from A\n');
    commitAll(a, 'A adds n2');
    Remote.lookup(repo: a, name: 'origin').push(refspecs: ['refs/heads/main:refs/heads/main']);
    File('$pb/n3.md').writeAsStringSync('from B\n');
    commitAll(b, 'B adds n3');
    var conflicts = pull(b);
    check('B: pull with diverged history, different files -> no conflict', conflicts.isEmpty && b.index.hasConflicts == false);
    final theirs = Reference.lookup(repo: b, name: 'refs/remotes/origin/main').target;
    commitAll(b, 'merge', parents: [
      Commit.lookup(repo: b, oid: b.head.target),
      Commit.lookup(repo: b, oid: theirs),
    ]);
    b.stateCleanup();
    Remote.lookup(repo: b, name: 'origin').push(refspecs: ['refs/heads/main:refs/heads/main']);
    check('B: merge commit + push', File('$pb/n2.md').existsSync());

    // A fast-forwards
    conflicts = pull(a);
    check('A: pull fast-forward gets n3', File('$pa/n3.md').existsSync() && conflicts.isEmpty);

    // conflict: both edit n1.md
    File('$pa/n1.md').writeAsStringSync('# n1\nA edit\n');
    commitAll(a, 'A edits n1');
    Remote.lookup(repo: a, name: 'origin').push(refspecs: ['refs/heads/main:refs/heads/main']);
    final bLocal = '# n1\nB edit\n';
    File('$pb/n1.md').writeAsStringSync(bLocal);
    commitAll(b, 'B edits n1');
    conflicts = pull(b);
    check('B: same-file edits -> conflict detected (${conflicts.join(',')})', conflicts.contains('n1.md'));

    // resolve per PLAN: remote wins, local kept as conflict copy
    final entry = b.index.conflicts['n1.md']!;
    final theirsBlob = Blob.lookup(repo: b, oid: entry.their!.oid).content;
    final oursBlob = Blob.lookup(repo: b, oid: entry.our!.oid).content;
    File('$pb/n1.md').writeAsStringSync(theirsBlob);
    File('$pb/n1 (conflict B).md').writeAsStringSync(oursBlob);
    b.index.cleanupConflict();
    b.index.add('n1.md');
    b.index.add('n1 (conflict B).md');
    final theirs2 = Reference.lookup(repo: b, name: 'refs/remotes/origin/main').target;
    commitAll(b, 'merge with conflict copy', parents: [
      Commit.lookup(repo: b, oid: b.head.target),
      Commit.lookup(repo: b, oid: theirs2),
    ]);
    b.stateCleanup();
    Remote.lookup(repo: b, name: 'origin').push(refspecs: ['refs/heads/main:refs/heads/main']);
    check('B: conflict resolved (remote wins) + copy kept + pushed',
        File('$pb/n1.md').readAsStringSync().contains('A edit') &&
            File('$pb/n1 (conflict B).md').readAsStringSync() == bLocal);
    conflicts = pull(a);
    final tr = Commit.lookup(repo: a, oid: Reference.lookup(repo: a, name: 'refs/remotes/origin/main').target).tree;
    stdout.writeln('A origin/main tree: ${tr.entries.map((e) => e.name).toList()} head=${a.head.target.sha.substring(0, 7)}');
    stdout.writeln('A files: ${Directory(pa).listSync().map((e) => e.path.split('/').last).toList()}');
    check('A: pull gets conflict copy', File('$pa/n1 (conflict B).md').existsSync());
    a.free();
    b.free();
  } catch (e, st) {
    stdout.writeln('FAIL  exception: $e\n$st');
    _failures++;
  } finally {
    tmp.deleteSync(recursive: true);
  }
  stdout.writeln(_failures == 0 ? '\nALL PASS' : '\n$_failures FAILED');
  return _failures;
}
