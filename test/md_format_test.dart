import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes2hub/screens/md_format.dart';

TextEditingValue _v(String text, int a, [int? b]) =>
    TextEditingValue(text: text, selection: TextSelection(baseOffset: a, extentOffset: b ?? a));

void main() {
  test('numberLines numbers every selected line and toggles back', () {
    final v = MdFormat.numberLines(_v('one\ntwo\nthree', 0, 13));
    expect(v.text, '1. one\n2. two\n3. three');
    expect(MdFormat.numberLines(v).text, 'one\ntwo\nthree');
  });

  test('strikethrough and inline code reuse wrap', () {
    expect(MdFormat.wrap(_v('a b c', 2, 3), '~~').text, 'a ~~b~~ c');
    expect(MdFormat.wrap(_v('a b c', 2, 3), '`').text, 'a `b` c');
  });

  test('codeBlock fences the selection on its own lines and unwraps again', () {
    final v = MdFormat.codeBlock(_v('intro x = 1', 6, 11));
    expect(v.text, 'intro \n```\nx = 1\n```');
    expect(v.selection.textInside(v.text), 'x = 1');
    expect(MdFormat.codeBlock(v).text, 'intro \nx = 1');
  });

  test('codeBlock with no selection leaves an empty block with the cursor inside', () {
    final v = MdFormat.codeBlock(_v('', 0));
    expect(v.text, '```\n\n```');
    expect(v.selection, const TextSelection.collapsed(offset: 4));
  });

  test('rule goes below the cursor line, surrounded by blank lines', () {
    final v = MdFormat.rule(_v('first\nsecond', 2));
    expect(v.text, 'first\n\n---\n\nsecond');
    expect(MdFormat.rule(_v('only', 4)).text, 'only\n\n---\n\n'); // 끝이면 아래에 빈 줄을 남겨 이어 쓰게 한다
  });

  test('tidy splits list numbers glued to the previous sentence', () {
    const pasted = '1. 아이콘 문제입니다.2. 새 아이콘 교체입니다.3. 라벨 수정입니다.';
    expect(MdFormat.tidyText(pasted), '1. 아이콘 문제입니다.\n2. 새 아이콘 교체입니다.\n3. 라벨 수정입니다.');
  });

  test('tidy leaves version numbers and out-of-sequence numbers alone', () {
    expect(MdFormat.tidyText('v1.2. 다음 버전'), 'v1.2. 다음 버전');
    expect(MdFormat.tidyText('1. 첫째입니다.5. 다섯째'), '1. 첫째입니다.5. 다섯째');
  });

  test('tidy spaces lists and headings, collapses blanks, unifies bullets, skips code blocks', () {
    const text = '소개 문장  \n* 하나\n+ 둘\n\n\n\n## 제목\n본문\n```\n*  keep  \n\n\n\n```\n';
    expect(MdFormat.tidyText(text), '소개 문장\n\n- 하나\n- 둘\n\n## 제목\n\n본문\n```\n*  keep  \n\n\n\n```\n');
  });

  test('tidy works on the selection only, or on everything with the cursor kept near its place', () {
    final sel = MdFormat.tidy(_v('keep.2. x\n1. a.2. b', 10, 19));
    expect(sel.text, 'keep.2. x\n1. a.\n2. b');
    final all = MdFormat.tidy(_v('1. a.2. b', 9));
    expect(all.text, '1. a.\n2. b');
    expect(all.selection, const TextSelection.collapsed(offset: 10));
  });

  test('table inserts a 2-column skeleton and selects the first header', () {
    final v = MdFormat.table(_v('text', 4));
    expect(v.text, 'text\n\n| 제목 | 제목 |\n| --- | --- |\n|  |  |\n');
    expect(v.selection.textInside(v.text), '제목');
    expect(MdFormat.table(_v('', 0)).text, startsWith('| 제목'));
  });
}
