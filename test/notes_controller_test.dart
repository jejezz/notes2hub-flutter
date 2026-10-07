import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes2hub/notes/note_store.dart';
import 'package:notes2hub/notes/notes_controller.dart';

void main() {
  late Directory tmp;
  late NoteStore store;

  NotesController make() => NotesController(store, draftDelay: const Duration(milliseconds: 10));

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('notes2hub-test');
    store = NoteStore(notesDir: Directory('${tmp.path}/notes'), draftsDir: Directory('${tmp.path}/drafts'));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('new note has no file until saved; save writes notes/<id>.md', () async {
    final c = make();
    await c.load();
    expect(c.isEmpty, isTrue);

    final id = c.create();
    expect(c.isDirty(id), isTrue);
    expect(File('${tmp.path}/notes/$id.md').existsSync(), isFalse);

    c.edit(id, '# First\nbody');
    await c.save(id);
    expect(c.isDirty(id), isFalse);
    final file = File('${tmp.path}/notes/$id.md');
    expect(file.readAsStringSync(), contains('# First\nbody'));
    expect(file.readAsStringSync(), startsWith('---\nid: $id\n'));
    expect(File('${tmp.path}/notes/$id.md.tmp').existsSync(), isFalse);
  });

  test('unsaved edits survive a restart through drafts; saved file stays untouched', () async {
    var c = make();
    await c.load();
    final id = c.create();
    c.edit(id, 'v1');
    await c.save(id);
    c.edit(id, 'v2 unsaved');
    await Future<void>.delayed(const Duration(milliseconds: 60)); // draft debounce

    c = make();
    await c.load();
    expect(c.selectedId, isNull, reason: 'the app starts on the board');
    c.select(id);
    expect(c.isDirty(id), isTrue);
    expect(c.selected!.body, 'v2 unsaved');
    expect(File('${tmp.path}/notes/$id.md').readAsStringSync(), contains('v1'));
  });

  test('a brand-new unsaved note is restored from its draft', () async {
    var c = make();
    await c.load();
    final id = c.create();
    c.edit(id, 'never saved');
    c.flush();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    c = make();
    await c.load();
    expect(c.isNew(id), isTrue);
    c.select(id);
    expect(c.selected!.body, 'never saved');
  });

  test('editing back to the saved text clears dirty and the draft', () async {
    final c = make();
    await c.load();
    final id = c.create();
    c.edit(id, 'a');
    await c.save(id);
    c.edit(id, 'b');
    expect(c.isDirty(id), isTrue);
    c.edit(id, 'a');
    expect(c.isDirty(id), isFalse);
  });

  test('revert drops edits; reverting a new note removes it', () async {
    final c = make();
    await c.load();
    final id = c.create();
    c.edit(id, 'a');
    await c.save(id);
    c.edit(id, 'changed');
    await c.revert(id);
    expect(c.selected!.body, 'a');

    final n = c.create();
    c.edit(n, 'temp');
    await c.revert(n);
    expect(c.notes.map((e) => e.id), [id]);
  });

  test('an empty new note is dropped when you leave it', () async {
    final c = make();
    await c.load();
    final a = c.create();
    c.edit(a, 'keep');
    await c.save(a);
    final blank = c.create();
    c.select(a);
    expect(c.notes.any((n) => n.id == blank), isFalse);
  });

  test('delete moves the note to the trash (file kept, marked deleted) and returns to the board', () async {
    final c = make();
    await c.load();
    final a = c.create();
    c.edit(a, 'one');
    await c.save(a);
    final b = c.create();
    c.edit(b, 'two');
    await c.save(b);
    await c.delete(b);
    expect(File('${tmp.path}/notes/$b.md').readAsStringSync(), contains('deleted: '));
    expect(c.selectedId, isNull);
    expect(c.notes.map((n) => n.id), [a]);
    expect(c.trashed.map((n) => n.id), [b]);
    expect(c.notes.any((n) => n.id == b), isFalse);
  });

  test('restore brings a trashed note back; purge and emptyTrash remove the files', () async {
    final c = make();
    await c.load();
    final ids = <String>[];
    for (final t in ['one', 'two', 'three']) {
      final id = c.create();
      c.edit(id, t);
      await c.save(id);
      ids.add(id);
    }
    await c.delete(ids[0]);
    await c.delete(ids[1]);
    await c.delete(ids[2]);
    await c.restore(ids[0]);
    expect(c.notes.map((n) => n.id), [ids[0]]);
    expect(File('${tmp.path}/notes/${ids[0]}.md').readAsStringSync(), isNot(contains('deleted:')));
    await c.purge(ids[1]);
    expect(File('${tmp.path}/notes/${ids[1]}.md').existsSync(), isFalse);
    await c.emptyTrash();
    expect(c.trashed, isEmpty);
    expect(File('${tmp.path}/notes/${ids[2]}.md').existsSync(), isFalse);
    expect(File('${tmp.path}/notes/${ids[0]}.md').existsSync(), isTrue);
  });

  test('deleting an unsaved new note just drops it; deleting discards unsaved edits', () async {
    final c = make();
    await c.load();
    final fresh = c.create();
    c.edit(fresh, 'never saved');
    await c.delete(fresh);
    expect(c.trashed, isEmpty);
    expect(c.notes, isEmpty);

    final id = c.create();
    c.edit(id, 'v1');
    await c.save(id);
    c.edit(id, 'v2 unsaved');
    await c.delete(id);
    expect(c.isDirty(id), isFalse);
    expect(c.trashed.single.body, 'v1');
  });

  test('notes trashed longer than the retention are purged on load', () async {
    var c = make();
    await c.load();
    final old = c.create();
    c.edit(old, 'old');
    await c.save(old);
    final recent = c.create();
    c.edit(recent, 'recent');
    await c.save(recent);
    await c.delete(old);
    await c.delete(recent);
    c = NotesController(store, trashRetention: Duration.zero);
    // recent는 방금 버렸으니 보존 기간 0이면 둘 다 지워진다 — 기간 안의 것은 남는지 따로 확인한다.
    await c.load();
    expect(c.trashed, isEmpty);
    expect(File('${tmp.path}/notes/$old.md').existsSync(), isFalse);

    c = make();
    await c.load();
    final keep = c.create();
    c.edit(keep, 'keep');
    await c.save(keep);
    await c.delete(keep);
    c = make();
    await c.load();
    expect(c.trashed.map((n) => n.id), [keep]);
  });

  test('search filters by body, newest first', () async {
    final c = make();
    await c.load();
    final a = c.create();
    c.edit(a, 'apple pie');
    await c.save(a);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final b = c.create();
    c.edit(b, 'banana apple');
    await c.save(b);
    expect(c.notes.map((n) => n.id), [b, a]);
    c.setQuery('banana');
    expect(c.notes.map((n) => n.id), [b]);
  });

  test('capture saves a note straight to disk without opening it', () async {
    final c = make();
    await c.load();
    final id = await c.capture('  Buy milk\nand eggs  ');
    expect(c.selectedId, isNull);
    expect(c.isDirty(id), isFalse);
    expect(File('${tmp.path}/notes/$id.md').readAsStringSync(), endsWith('Buy milk\nand eggs'));
    expect(c.notes.single.title, 'Buy milk');
  });

  test('deselect returns to the board, keeps edits as drafts and drops an empty new note', () async {
    final c = make();
    await c.load();
    final a = c.create();
    c.edit(a, 'text');
    await c.save(a);
    c.edit(a, 'text edited');
    c.deselect();
    expect(c.selectedId, isNull);
    expect(c.isDirty(a), isTrue);

    final blank = c.create();
    c.deselect();
    expect(c.notes.any((n) => n.id == blank), isFalse);
  });

  test('bookmark toggles on disk without touching updated or unsaved edits', () async {
    var c = make();
    await c.load();
    final id = await c.capture('# Title\nbody');
    final updated = c.noteById(id)!.updated;
    expect(File('${tmp.path}/notes/$id.md').readAsStringSync(), isNot(contains('bookmarked')));

    c.select(id);
    c.edit(id, '# Title\nedited');
    await c.toggleBookmark(id);
    expect(c.noteById(id)!.bookmarked, isTrue);
    expect(c.isDirty(id), isTrue, reason: 'edits stay unsaved');
    expect(c.noteById(id)!.updated, updated);
    final file = File('${tmp.path}/notes/$id.md').readAsStringSync();
    expect(file, contains('bookmarked: true'));
    expect(file, contains('body'), reason: 'disk body is still the saved one');

    c = make();
    await c.load();
    c.select(id);
    expect(c.selected!.bookmarked, isTrue);
    expect(c.selected!.body, contains('edited'), reason: 'draft survived the toggle');

    await c.toggleBookmark(id);
    expect(c.noteById(id)!.bookmarked, isFalse);
    expect(File('${tmp.path}/notes/$id.md').readAsStringSync(), isNot(contains('bookmarked')));
  });
}
