import 'dart:io';
import 'dart:isolate';

import 'package:git2dart/git2dart.dart' hide Note;
import 'package:uuid/uuid.dart';

import '../notes/note.dart';
import 'sync_models.dart';

/// git2dart(libgit2)로 만든 [SyncEngine] — 시스템 git 없이 동작한다 (docs/PLAN.md §3).
///
/// libgit2 호출은 동기식 FFI라 네트워크가 느리면 화면이 멈춘다. 그래서 작업 전체를
/// Isolate에서 돌리고, 경계에는 문자열·단순 값만 넘긴다.
class LibGit2Engine implements SyncEngine {
  LibGit2Engine({required this.dir, this.caCertPath});

  /// git 작업 폴더 (안에 `notes/`가 있다).
  final Directory dir;

  /// CA 인증서 묶음(PEM). 지정하지 않으면 HTTPS가 인증서 오류로 실패한다 (PoC 결과).
  final String? caCertPath;

  @override
  Future<SyncResult> connect({required String remoteUrl, required String token}) {
    final path = dir.path, ca = caCertPath;
    return Isolate.run(() => _guard(() => _connect(path, ca, remoteUrl, token)));
  }

  @override
  Future<SyncStatus> status() {
    final path = dir.path;
    return Isolate.run(() {
      if (!Directory('$path/.git').existsSync()) return const SyncStatus();
      final repo = Repository.open(path);
      try {
        final changed = _pending(repo, path);
        final unpushed = _unpushed(repo, path);
        return SyncStatus(changed: changed, unpushed: unpushed, pendingNotes: _pendingNotes(repo, path, unpushed));
      } finally {
        repo.free();
      }
    });
  }

  @override
  Future<SyncResult> sync({required String token, required GitIdentity identity, required String deviceLabel}) {
    final path = dir.path, ca = caCertPath;
    return Isolate.run(() => _guard(() => _sync(path, ca, token, identity.name, identity.email, deviceLabel)));
  }

  @override
  Future<SyncResult> pull({required String token}) {
    final path = dir.path, ca = caCertPath;
    return Isolate.run(() => _guard(() => _pull(path, ca, token)));
  }
}

// ---- 아래는 모두 Isolate 안에서 도는 동기 코드 ------------------------------

const _notes = 'notes/';
const _uuid = Uuid();

SyncResult _guard(SyncResult Function() body) {
  try {
    return body();
  } catch (e) {
    final msg = e.toString();
    final low = msg.toLowerCase();
    return SyncResult(
      error: msg,
      authFailed: low.contains('401') ||
          low.contains('403') ||
          low.contains('authentication') ||
          low.contains('credentials') ||
          low.contains('not authorized'),
      offline: low.contains('resolve') ||
          low.contains('failed to connect') ||
          low.contains('timed out') ||
          low.contains('network') ||
          low.contains('unreachable') ||
          low.contains('connection'),
    );
  }
}

Callbacks _callbacks(String token, List<String> rejects) => Callbacks(
      // GitHub은 사용자 이름 자리에 아무 값이나 받고 토큰을 비밀번호로 쓴다.
      credentials: UserPass(username: 'x-access-token', password: token),
      pushUpdateReference: (ref, msg) {
        if (msg.isNotEmpty) rejects.add('$ref: $msg');
      },
    );

/// 아직 커밋이 없는가. `repo.isEmpty`는 HEAD가 `master`일 때만 true라서 `main`에서는 쓸 수 없다.
bool _unborn(Repository repo, String path) => !Reference.list(repo).contains('refs/heads/${_headBranch(path)}');

String _headBranch(String path) {
  final f = File('$path/.git/HEAD');
  if (f.existsSync()) {
    final t = f.readAsStringSync().trim();
    if (t.startsWith('ref: refs/heads/')) return t.substring('ref: refs/heads/'.length);
  }
  return 'main';
}

/// 원격에 있는 브랜치 중 main → master → 첫 번째 순으로.
String? _remoteBranch(Repository repo) {
  const prefix = 'refs/remotes/origin/';
  final names = Reference.list(repo)
      .where((r) => r.startsWith(prefix) && !r.endsWith('/HEAD'))
      .map((r) => r.substring(prefix.length))
      .toList();
  if (names.isEmpty) return null;
  for (final preferred in ['main', 'master']) {
    if (names.contains(preferred)) return preferred;
  }
  return names.first;
}

SyncResult _connect(String path, String? ca, String url, String token) {
  if (ca != null) Libgit2.setSSLCertLocations(file: ca);
  Directory(path).createSync(recursive: true);
  final repo = File('$path/.git').existsSync() || Directory('$path/.git').existsSync()
      ? Repository.open(path)
      : Repository.init(path: path, initialHead: 'main');
  try {
    if (Remote.list(repo).contains('origin')) {
      Remote.setUrl(repo: repo, remote: 'origin', url: url);
    } else {
      Remote.create(repo: repo, name: 'origin', url: url);
    }
    Remote.lookup(repo: repo, name: 'origin').fetch(callbacks: _callbacks(token, []));
    final branch = _remoteBranch(repo);
    if (branch != null && _unborn(repo, path)) {
      final target = Reference.lookup(repo: repo, name: 'refs/remotes/origin/$branch').target;
      Reference.create(repo: repo, name: 'refs/heads/$branch', target: target);
      repo.setHead('refs/heads/$branch');
      // safe: 로컬에만 있는 메모 파일(추적되지 않음)은 건드리지 않는다.
      Checkout.head(repo: repo, strategy: {GitCheckout.safe, GitCheckout.recreateMissing});
      return const SyncResult(integrated: true);
    }
    return const SyncResult();
  } finally {
    repo.free();
  }
}

/// 동기화 대상: `notes/*.md`와 첨부 이미지 `assets/*`. 그 밖의 파일(임시 `.tmp` 포함)은 건드리지 않는다.
const _assets = 'assets/';

bool _tracked(String rel) =>
    (rel.startsWith(_notes) && rel.endsWith('.md')) || (rel.startsWith(_assets) && !rel.endsWith('.tmp'));

/// 대상 파일을 인덱스에 맞춘다: 새·바뀐 파일은 추가, 사라진 파일은 제거.
/// (status 목록은 새 폴더를 폴더 하나로만 보고하고, 충돌 후 새 파일을 빠뜨린다 — PoC.)
void _stage(Repository repo, String path) {
  final index = repo.index;
  final onDisk = <String>{};
  for (final folder in ['notes', 'assets']) {
    final dir = Directory('$path/$folder');
    if (!dir.existsSync()) continue;
    for (final e in dir.listSync()) {
      if (e is! File) continue;
      final rel = '$folder/${e.uri.pathSegments.last}';
      if (!_tracked(rel)) continue;
      onDisk.add(rel);
      index.add(rel);
    }
  }
  for (final entry in index.toList()) {
    if (_tracked(entry.path) && !onDisk.contains(entry.path)) index.remove(entry.path);
  }
  index.write();
}

int _pending(Repository repo, String path) {
  _stage(repo, path);
  final tree = _unborn(repo, path) ? null : Commit.lookup(repo: repo, oid: repo.head.target).tree;
  final diff = Diff.treeToIndex(repo: repo, tree: tree, index: repo.index);
  final n = diff.length;
  diff.free();
  return n;
}

int _commit(Repository repo, String path, Signature sig, String label) {
  final n = _pending(repo, path);
  if (n == 0) return 0;
  final tree = Tree.lookup(repo: repo, oid: repo.index.writeTree());
  Commit.create(
    repo: repo,
    updateRef: 'HEAD',
    author: sig,
    committer: sig,
    message: 'sync: $n files @ $label',
    tree: tree,
    parents: _unborn(repo, path) ? [] : [Commit.lookup(repo: repo, oid: repo.head.target)],
  );
  return n;
}

/// 커밋이 원격보다 앞서 있는가 (push하지 못한 커밋). 원격에 브랜치가 아예 없어도 true.
bool _unpushed(Repository repo, String path) {
  if (_unborn(repo, path)) return false;
  final branch = _headBranch(path);
  final theirsName = 'refs/remotes/origin/$branch';
  if (!Reference.list(repo).contains(theirsName)) return true;
  final ours = repo.head.target;
  final theirs = Reference.lookup(repo: repo, name: theirsName).target;
  if (ours.sha == theirs.sha) return false;
  final a = Merge.analysis(repo: repo, theirHead: theirs).result;
  // 원격이 앞서 있기만 하면(fast-forward) 올릴 것은 없다. 나머지는 로컬 커밋이 있다.
  return !a.contains(GitMergeAnalysis.fastForward);
}

/// 아직 원격에 없는 메모 id들: 인덱스와 HEAD의 차이 + (push 전이면) HEAD와 원격 브랜치의 차이.
Set<String> _pendingNotes(Repository repo, String path, bool unpushed) {
  final ids = <String>{};
  void collect(Diff d) {
    for (final delta in d.deltas) {
      final p = delta.newFile.path.isNotEmpty ? delta.newFile.path : delta.oldFile.path;
      if (p.startsWith(_notes) && p.endsWith('.md')) ids.add(p.substring(_notes.length, p.length - 3));
    }
    d.free();
  }

  final headTree = _unborn(repo, path) ? null : Commit.lookup(repo: repo, oid: repo.head.target).tree;
  collect(Diff.treeToIndex(repo: repo, tree: headTree, index: repo.index));
  if (unpushed && headTree != null) {
    final theirsName = 'refs/remotes/origin/${_headBranch(path)}';
    final theirsTree = Reference.list(repo).contains(theirsName)
        ? Commit.lookup(repo: repo, oid: Reference.lookup(repo: repo, name: theirsName).target).tree
        : null;
    if (theirsTree != null) {
      collect(Diff.treeToTree(repo: repo, oldTree: theirsTree, newTree: headTree));
    } else {
      // 원격에 브랜치가 아직 없으면 커밋한 메모 전부가 올릴 대상이다.
      collect(Diff.treeToTree(repo: repo, oldTree: null, newTree: headTree));
    }
  }
  return ids;
}

class _Integration {
  const _Integration({this.integrated = false, this.copies = 0, this.needsMerge = false});
  final bool integrated;
  final int copies;
  final bool needsMerge;
}

/// 원격 브랜치를 현재 브랜치에 합친다. [fastForwardOnly]면 병합이 필요한 경우 하지 않고 알린다.
_Integration _integrate(
  Repository repo,
  String path,
  String branch,
  Signature sig,
  String label, {
  bool fastForwardOnly = false,
}) {
  final theirsName = 'refs/remotes/origin/$branch';
  if (!Reference.list(repo).contains(theirsName)) return const _Integration();
  final theirs = Reference.lookup(repo: repo, name: theirsName).target;
  if (_unborn(repo, path)) {
    Reference.create(repo: repo, name: 'refs/heads/$branch', target: theirs);
    Checkout.head(repo: repo, strategy: {GitCheckout.safe, GitCheckout.recreateMissing});
    return const _Integration(integrated: true);
  }

  final analysis = Merge.analysis(repo: repo, theirHead: theirs).result;
  if (analysis.contains(GitMergeAnalysis.upToDate)) return const _Integration();
  if (analysis.contains(GitMergeAnalysis.fastForward)) {
    Reference.setTarget(repo: repo, name: 'refs/heads/$branch', target: theirs);
    // 저장된 변경은 이미 커밋했으므로 작업 폴더를 원격에 맞춰도 잃는 것이 없다.
    Checkout.head(repo: repo, strategy: {GitCheckout.force});
    return const _Integration(integrated: true);
  }
  if (fastForwardOnly) return const _Integration(needsMerge: true);

  Merge.commit(repo: repo, commit: AnnotatedCommit.lookup(repo: repo, oid: theirs));
  var copies = 0;
  final index = repo.index;
  if (index.hasConflicts) {
    final now = DateTime.now();
    final stamp = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    String? text(IndexEntry? e) => e == null ? null : Blob.lookup(repo: repo, oid: e.oid).content;
    for (final MapEntry(key: p, value: c) in index.conflicts.entries) {
      final ours = text(c.our), theirsText = text(c.their);
      final isNote = p.startsWith(_notes) && p.endsWith('.md');
      final file = File('$path/$p');
      if (ours != null && theirsText != null && isNote) {
        // 양쪽이 같은 메모를 고침: 원격이 본 파일, 로컬은 충돌 사본으로 (사용자에게 묻지 않음).
        file.writeAsStringSync(theirsText);
        final name = p.substring(_notes.length, p.length - 3);
        final copy = conflictCopyOf(
          Note.parse(ours, fallbackId: name, fallbackTime: now),
          newId: _uuid.v4(),
          label: '$label $stamp',
          now: now,
        );
        File('$path/$_notes${copy.id}.md').writeAsStringSync(copy.serialize());
        copies++;
      } else if (theirsText == null) {
        file.writeAsStringSync(ours ?? ''); // 원격이 지웠지만 로컬이 고쳤다: 살린다.
      } else {
        file.writeAsStringSync(theirsText); // 로컬이 지웠지만 원격이 고쳤다 / 메모가 아닌 파일: 원격 우선.
      }
      index.add(p);
    }
    index.cleanupConflict();
  }
  _stage(repo, path);
  Commit.create(
    repo: repo,
    updateRef: 'HEAD',
    author: sig,
    committer: sig,
    message: 'merge: origin/$branch @ $label',
    tree: Tree.lookup(repo: repo, oid: repo.index.writeTree()),
    parents: [
      Commit.lookup(repo: repo, oid: repo.head.target),
      Commit.lookup(repo: repo, oid: theirs),
    ],
  );
  repo.stateCleanup();
  return _Integration(integrated: true, copies: copies);
}

SyncResult _sync(String path, String? ca, String token, String name, String email, String label) {
  if (ca != null) Libgit2.setSSLCertLocations(file: ca);
  final repo = Repository.open(path);
  try {
    final sig = Signature.create(name: name, email: email);
    final branch = _headBranch(path);
    final committed = _commit(repo, path, sig, label);
    if (_unborn(repo, path)) {
      // 메모도 없고 원격에도 이력이 없다 — 올릴 것이 없다.
      return SyncResult(committed: committed);
    }
    var integrated = false;
    var copies = 0;
    final rejects = <String>[];
    for (var attempt = 0; attempt < 3; attempt++) {
      Remote.lookup(repo: repo, name: 'origin').fetch(callbacks: _callbacks(token, rejects));
      final r = _integrate(repo, path, branch, sig, label);
      integrated = integrated || r.integrated;
      copies += r.copies;
      rejects.clear();
      Remote.lookup(repo: repo, name: 'origin').push(
        refspecs: ['refs/heads/$branch:refs/heads/$branch'],
        callbacks: _callbacks(token, rejects),
      );
      // 그 사이 다른 PC가 먼저 올렸으면 거절된다 → 다시 가져와 합친 뒤 재시도.
      if (rejects.isEmpty) {
        return SyncResult(committed: committed, pushed: true, integrated: integrated, conflictCopies: copies);
      }
    }
    return SyncResult(
      committed: committed,
      integrated: integrated,
      conflictCopies: copies,
      error: 'push rejected: ${rejects.join('; ')}',
    );
  } finally {
    repo.free();
  }
}

SyncResult _pull(String path, String? ca, String token) {
  if (ca != null) Libgit2.setSSLCertLocations(file: ca);
  final repo = Repository.open(path);
  try {
    final branch = _headBranch(path);
    final pending = _pending(repo, path);
    Remote.lookup(repo: repo, name: 'origin').fetch(callbacks: _callbacks(token, []));
    if (pending > 0) {
      // 저장된 변경이 있으면 작업 폴더를 건드리지 않는다. 원격이 앞서 있는지만 알린다.
      final theirsName = 'refs/remotes/origin/$branch';
      if (_unborn(repo, path) || !Reference.list(repo).contains(theirsName)) return const SyncResult();
      final theirs = Reference.lookup(repo: repo, name: theirsName).target;
      final a = Merge.analysis(repo: repo, theirHead: theirs).result;
      return SyncResult(needsSync: !a.contains(GitMergeAnalysis.upToDate));
    }
    final sig = Signature.create(name: 'Notes2Hub', email: 'noreply@notes2hub.invalid');
    final r = _integrate(repo, path, branch, sig, '', fastForwardOnly: true);
    return SyncResult(integrated: r.integrated, needsSync: r.needsMerge);
  } finally {
    repo.free();
  }
}
