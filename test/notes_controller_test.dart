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

  test('delete removes file and draft and selects another note', () async {
    final c = make();
    await c.load();
    final a = c.create();
    c.edit(a, 'one');
    await c.save(a);
    final b = c.create();
    c.edit(b, 'two');
    await c.save(b);
    await c.delete(b);
    expect(File('${tmp.path}/notes/$b.md').existsSync(), isFalse);
    expect(c.selectedId, a);
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
}
