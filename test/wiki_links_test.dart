import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes2hub/images/asset_store.dart';
import 'package:notes2hub/l10n/app_localizations.dart';
import 'package:notes2hub/notes/note_store.dart';
import 'package:notes2hub/notes/notes_controller.dart';
import 'package:notes2hub/notes/wiki_links.dart';
import 'package:notes2hub/screens/md_format.dart';
import 'package:notes2hub/screens/note_preview.dart';

void main() {
  test('titlesIn finds links outside code only, trimmed, in order', () {
    const body = '보기 [[ 장보기 ]] 그리고 [[할 일]]\n`[[인라인]]`과 [[진짜]]\n```\n[[코드]]\n```\n[[a|b]] [[]]';
    expect(WikiLinks.titlesIn(body), ['장보기', '할 일', '진짜', 'a|b']);
  });

  test('render links known titles by id and unknown ones to a new-note link; code is untouched', () {
    String? resolve(String t) => t == '장보기' ? 'id-1' : null;
    final out = WikiLinks.render('[[장보기]] / [[없는 글]] / `[[코드]]`', resolve);
    expect(out, '[장보기](note:id-1) / [\\[\\[없는 글\\]\\]](newnote:${Uri.encodeComponent('없는 글')}) / `[[코드]]`');
    expect(WikiLinks.idOf('note:id-1'), 'id-1');
    expect(WikiLinks.newTitleOf('newnote:${Uri.encodeComponent('없는 글')}'), '없는 글');
    expect(WikiLinks.isNoteHref('https://example.com'), isFalse);
    expect(WikiLinks.idOf(null), isNull);
  });

  test('title matching ignores case and extra spaces; render escapes markdown characters', () {
    expect(WikiLinks.normalize('  Hello   World '), 'hello world');
    expect(WikiLinks.render('[[a*b]]', (_) => 'x'), '[a\\*b](note:x)');
  });

  test('rename rewrites matching links outside code and reports no change otherwise', () {
    const body = '[[Plan]] and [[ plan ]] and [[Other]]\n`[[Plan]]`\n```\n[[Plan]]\n```';
    expect(
      WikiLinks.rename(body, 'PLAN', 'Roadmap'),
      '[[Roadmap]] and [[Roadmap]] and [[Other]]\n`[[Plan]]`\n```\n[[Plan]]\n```',
    );
    expect(WikiLinks.rename('no links', 'Plan', 'Roadmap'), isNull);
    expect(WikiLinks.rename(body, 'Plan', 'bad [title]'), isNull); // 링크가 될 수 없는 제목
    expect(WikiLinks.rename(body, '', 'x'), isNull);
  });

  test('MdFormat.insert replaces the selection and puts the cursor after it', () {
    final v = MdFormat.insert(
      const TextEditingValue(text: 'see x now', selection: TextSelection(baseOffset: 4, extentOffset: 5)),
      '[[제목]]',
    );
    expect(v.text, 'see [[제목]] now');
    expect(v.selection, const TextSelection.collapsed(offset: 4 + 6));
  });

  group('controller', () {
    late Directory tmp;
    late NotesController c;
    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('notes2hub-links');
      c = NotesController(
        NoteStore(notesDir: Directory('${tmp.path}/notes'), draftsDir: Directory('${tmp.path}/drafts')),
      );
      await c.load();
    });
    tearDown(() {
      c.dispose();
      tmp.deleteSync(recursive: true);
    });

    Future<String> add(String body) async {
      final id = c.create();
      c.edit(id, body);
      await c.save(id);
      return id;
    }

    test('noteByTitle picks the most recently edited live match; trashed notes do not resolve', () async {
      final old = await add('# Plan\nold');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final fresh = await add('# plan\nnew');
      expect(c.noteByTitle('PLAN')!.id, fresh);
      await c.delete(fresh);
      expect(c.noteByTitle('plan')!.id, old);
      expect(c.noteByTitle(''), isNull);
      expect(c.noteByTitle('nothing'), isNull);
    });

    test('backlinksTo lists other live notes that link the title', () async {
      final target = await add('# 장보기\n우유');
      final a = await add('# 오늘\n[[장보기]] 먼저');
      await add('# 코드\n`[[장보기]]`');
      final gone = await add('# 지운 글\n[[장보기]]');
      await c.delete(gone);
      await add('# 자기 자신\n[[자기 자신]]');
      expect(c.backlinksTo(target).map((n) => n.id), [a]);
      expect(c.backlinksTo(a), isEmpty);
    });
  });

  group('title change fixes links', () {
    late Directory tmp;
    late NotesController c;
    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('notes2hub-rename');
      c = NotesController(
        NoteStore(notesDir: Directory('${tmp.path}/notes'), draftsDir: Directory('${tmp.path}/drafts')),
      );
      await c.load();
    });
    tearDown(() {
      c.dispose();
      tmp.deleteSync(recursive: true);
    });

    Future<String> add(String body) async {
      final id = c.create();
      c.edit(id, body);
      await c.save(id);
      return id;
    }

    String fileOf(String id) => File('${tmp.path}/notes/$id.md').readAsStringSync();

    test('saving a new title rewrites links in other notes (trashed ones too) and keeps their dates', () async {
      final target = await add('# Plan\nbody');
      final a = await add('# A\nsee [[Plan]]');
      final gone = await add('# B\n[[plan]] later');
      await c.delete(gone);
      final untouched = await add('# C\n[[Other]]');
      final before = c.noteById(a)!.updated;

      c.edit(target, '# Roadmap\nbody');
      final fix = await c.save(target);

      expect(fix, isNotNull);
      expect(fix!.count, 2);
      expect(c.noteById(a)!.body, '# A\nsee [[Roadmap]]');
      expect(fileOf(a), contains('[[Roadmap]]'));
      expect(c.noteById(a)!.updated, before);
      expect(fileOf(gone), contains('[[Roadmap]] later'));
      expect(c.noteById(untouched)!.body, '# C\n[[Other]]');
      expect(c.backlinksTo(target).map((n) => n.id), [a]);
    });

    test('undoLinkFix puts the old title back', () async {
      final target = await add('# Plan');
      final a = await add('# A\n[[Plan]]');
      c.edit(target, '# Roadmap');
      final fix = (await c.save(target))!;
      await c.undoLinkFix(fix);
      expect(c.noteById(a)!.body, '# A\n[[Plan]]');
      expect(fileOf(a), contains('[[Plan]]'));
    });

    test('nothing changes for formatting-only edits, new notes, empty titles, or a duplicate old title', () async {
      final target = await add('# Plan');
      final a = await add('# A\n[[Plan]]');
      c.edit(target, '# **Plan**');
      expect(await c.save(target), isNull); // 제목 글자는 같다
      expect(c.noteById(a)!.body, '# A\n[[Plan]]');

      final fresh = c.create();
      c.edit(fresh, '# Brand new');
      expect(await c.save(fresh), isNull); // 옛 제목이 없다

      c.edit(target, '');
      expect(await c.save(target), isNull); // 새 제목이 비었다
      expect(c.noteById(a)!.body, '# A\n[[Plan]]');

      final twin1 = await add('# Twin');
      await add('# Twin');
      final linker = await add('# L\n[[Twin]]');
      c.edit(twin1, '# Renamed');
      expect(await c.save(twin1), isNull); // 같은 제목의 다른 메모가 남아 있다
      expect(c.noteById(linker)!.body, '# L\n[[Twin]]');
    });

    test('an unsaved edit of a linking note is fixed too, so saving it later keeps the new link', () async {
      final target = await add('# Plan');
      final a = await add('# A\n[[Plan]]');
      c.edit(a, '# A\n[[Plan]] and more');
      c.edit(target, '# Roadmap');
      await c.save(target);
      expect(c.isDirty(a), isTrue);
      expect(c.bodyOf(a), '# A\n[[Roadmap]] and more');
      await c.save(a);
      expect(fileOf(a), contains('[[Roadmap]] and more'));
    });
  });

  testWidgets('tapping a [[link]] in the preview sheet reports the note href', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('notes2hub-linksheet');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final hrefs = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NotePreviewSheet(
            body: 'go to [[Target]] or [[Missing]]',
            assets: AssetStore(Directory('${tmp.path}/assets')),
            onEdit: () {},
            resolveNoteId: (t) => t == 'Target' ? 'id-9' : null,
            onNoteHref: hrefs.add,
          ),
        ),
      ),
    );
    // 선택 가능한 미리보기는 SelectableText로 그려진다.
    final selectable = tester.widget<SelectableText>(find.byType(SelectableText));
    void tapSpan(String label) {
      final span = _findSpan(selectable.textSpan!, label)!;
      (span.recognizer as dynamic).onTap();
    }

    tapSpan('Target');
    tapSpan('[[Missing]]');
    expect(hrefs, ['note:id-9', 'newnote:Missing']);
  });
}

TextSpan? _findSpan(InlineSpan root, String text) {
  TextSpan? found;
  root.visitChildren((s) {
    if (s is TextSpan && s.text == text && s.recognizer != null) {
      found = s;
      return false;
    }
    return true;
  });
  return found;
}
