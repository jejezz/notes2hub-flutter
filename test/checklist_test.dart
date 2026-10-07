import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes2hub/images/asset_store.dart';
import 'package:notes2hub/l10n/app_localizations.dart';
import 'package:notes2hub/notes/checklist.dart';
import 'package:notes2hub/notes/note.dart';
import 'package:notes2hub/screens/note_preview.dart';

void main() {
  const body = '# 장보기\n- [ ] 우유\n- [x] 계란\n  - [ ] 큰 것\n1. [ ] 번호 목록\n\n```\n- [ ] 코드 안\n```\n- [ ]없음 공백 필요\n- [ ] 마지막';

  test('items are found in document order, skipping code fences and malformed markers', () {
    expect(Checklist.items(body).map((i) => (i.line, i.checked)).toList(), [
      (1, false),
      (2, true),
      (3, false),
      (4, false),
      (10, false),
    ]);
    expect(Checklist.count('no list here'), 0);
  });

  test('toggle flips only the chosen item and keeps the rest of the line', () {
    expect(Checklist.toggle(body, 0), contains('- [x] 우유\n- [x] 계란'));
    expect(Checklist.toggle(body, 1), contains('- [ ] 계란'));
    expect(Checklist.toggle(body, 2), contains('  - [x] 큰 것'));
    expect(Checklist.toggle(body, 3), contains('1. [x] 번호 목록'));
    final last = Checklist.toggle(body, 4)!;
    expect(last, endsWith('- [x] 마지막'));
    expect(last, contains('- [ ] 코드 안'));
  });

  test('toggle refuses a missing item or a stale view', () {
    expect(Checklist.toggle(body, 5), isNull);
    expect(Checklist.toggle(body, -1), isNull);
    expect(Checklist.toggle(body, 0, expected: true), isNull); // 화면은 체크됨인데 본문은 아님
    expect(Checklist.toggle(body, 0, expected: false), isNotNull);
  });

  test('card text shows checklist items as ☐ / ☑', () {
    final n = Note(id: 'a', created: DateTime(2026), updated: DateTime(2026), body: '# 장보기\n- [ ] 우유\n- [x] 계란');
    expect(n.excerpt(), '☐ 우유 ☑ 계란');
  });

  testWidgets('tapping a checkbox in the preview sheet flips that line and reports the new body', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('notes2hub-check');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final changes = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NotePreviewSheet(
            body: '- [ ] one\n- [ ] two',
            assets: AssetStore(Directory('${tmp.path}/assets')),
            onEdit: () {},
            onBodyChanged: changes.add,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pump();
    expect(changes, ['- [ ] one\n- [x] two']);
    expect(tester.widget<Checkbox>(find.byType(Checkbox).at(1)).value, isTrue);
    await tester.tap(find.byType(Checkbox).at(0));
    await tester.pump();
    expect(changes.last, '- [x] one\n- [x] two');
  });
}
