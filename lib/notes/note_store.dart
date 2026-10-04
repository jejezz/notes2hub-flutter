import 'dart:io';

import 'note.dart';

/// 디스크 입출력. 메모는 [notesDir]에(나중에 git 저장소 안), 편집 중 초안은
/// 저장소 밖 [draftsDir]에 둔다 — 초안은 동기화 대상이 아니다.
class NoteStore {
  NoteStore({required this.notesDir, required this.draftsDir});

  final Directory notesDir;
  final Directory draftsDir;

  File _noteFile(String id) => File('${notesDir.path}/$id.md');
  File _draftFile(String id) => File('${draftsDir.path}/$id.md');

  Future<List<Note>> loadAll() => _readDir(notesDir);

  /// 저장되지 않은 편집 내용. 파일이 아직 없는 새 메모도 여기에만 있다.
  Future<List<Note>> loadDrafts() => _readDir(draftsDir);

  Future<List<Note>> _readDir(Directory dir) async {
    if (!await dir.exists()) return [];
    final notes = <Note>[];
    await for (final e in dir.list()) {
      if (e is! File || !e.path.endsWith('.md')) continue;
      final name = e.uri.pathSegments.last;
      try {
        notes.add(Note.parse(
          await e.readAsString(),
          fallbackId: name.substring(0, name.length - 3),
          fallbackTime: (await e.stat()).modified,
        ));
      } on FileSystemException {
        // 읽을 수 없는 파일은 건너뛴다 — 한 파일 때문에 목록 전체가 막히면 안 된다.
      }
    }
    return notes;
  }

  /// 임시 파일에 쓴 뒤 이름을 바꿔서, 쓰는 도중 꺼져도 기존 파일이 깨지지 않게 한다.
  Future<void> save(Note note) async {
    await _atomicWrite(_noteFile(note.id), note.serialize());
    await clearDraft(note.id);
  }

  Future<void> writeDraft(Note note) => _atomicWrite(_draftFile(note.id), note.serialize());

  Future<void> clearDraft(String id) async {
    final f = _draftFile(id);
    if (await f.exists()) await f.delete();
  }

  Future<void> delete(String id) async {
    final f = _noteFile(id);
    if (await f.exists()) await f.delete();
    await clearDraft(id);
  }

  Future<void> _atomicWrite(File target, String content) async {
    await target.parent.create(recursive: true);
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(target.path);
  }
}
