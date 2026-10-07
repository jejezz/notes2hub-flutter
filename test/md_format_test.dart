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

  test('table inserts a 2-column skeleton and selects the first header', () {
    final v = MdFormat.table(_v('text', 4));
    expect(v.text, 'text\n\n| 제목 | 제목 |\n| --- | --- |\n|  |  |\n');
    expect(v.selection.textInside(v.text), '제목');
    expect(MdFormat.table(_v('', 0)).text, startsWith('| 제목'));
  });
}
