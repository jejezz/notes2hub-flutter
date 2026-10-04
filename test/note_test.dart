import 'package:flutter_test/flutter_test.dart';
import 'package:notes2hub/notes/note.dart';

void main() {
  final t = DateTime.utc(2026, 10, 4, 12);

  test('serialize/parse round-trip keeps id, dates and body', () {
    final n = Note(id: 'abc', created: t, updated: t.add(const Duration(hours: 1)), body: '# Hi\n\nline\n---\nmore\n');
    final back = Note.parse(n.serialize(), fallbackId: 'x', fallbackTime: DateTime(2000));
    expect(back.id, 'abc');
    expect(back.created, t);
    expect(back.updated, t.add(const Duration(hours: 1)));
    expect(back.body, n.body); // a '---' inside the body must not end the frontmatter
  });

  test('file without frontmatter falls back to filename id and mtime', () {
    final back = Note.parse('just text\r\nsecond', fallbackId: 'plain', fallbackTime: t);
    expect(back.id, 'plain');
    expect(back.created, t);
    expect(back.body, 'just text\nsecond');
  });

  test('title is the first non-empty line without heading marks; snippet is the next', () {
    final n = Note(id: 'a', created: t, updated: t, body: '\n\n## Title here  \n\n  second line\nthird');
    expect(n.title, 'Title here');
    expect(n.snippet, 'second line');
    expect(Note(id: 'b', created: t, updated: t, body: '  \n').title, '');
  });

  test('matches is case-insensitive over the body', () {
    final n = Note(id: 'a', created: t, updated: t, body: 'Hello World');
    expect(n.matches('world'), isTrue);
    expect(n.matches('  '), isTrue);
    expect(n.matches('nope'), isFalse);
  });

  test('conflict copies are recognisable from the title', () {
    final ours = Note(id: 'a', created: t, updated: t, body: '# Plan\nmine');
    final copy = conflictCopyOf(ours, newId: 'b', label: 'PC 2026-10-04', now: t);
    expect(copy.title, 'Plan (충돌 PC 2026-10-04)');
    expect(copy.isConflictCopy, isTrue);
    expect(ours.isConflictCopy, isFalse);
    expect(copy.body, contains('mine'));
    expect(conflictCopyOf(Note(id: 'c', created: t, updated: t, body: ''), newId: 'd', label: 'x', now: t).title, '(충돌 x)');
  });
}
