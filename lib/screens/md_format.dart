import 'package:flutter/services.dart';

/// 편집기 서식 도구줄이 쓰는 Markdown 편집 함수. 값 → 값이라 위젯 없이 테스트한다.
/// 선택 영역이 없으면(−1) 커서는 끝에 있는 것으로 본다.
abstract final class MdFormat {
  static TextSelection _sel(TextEditingValue v) {
    final s = v.selection;
    if (!s.isValid) return TextSelection.collapsed(offset: v.text.length);
    return TextSelection(baseOffset: s.start, extentOffset: s.end);
  }

  /// 선택한 글을 [left]·[right]로 감싼다. 이미 감싸져 있으면 벗긴다. 선택이 없으면 마커만 넣고 커서를 그 사이에 둔다.
  static TextEditingValue wrap(TextEditingValue v, String left, [String? right]) {
    right ??= left;
    final s = _sel(v);
    final t = v.text;
    final selected = t.substring(s.start, s.end);
    // 선택 바깥이 이미 마커면 벗긴다 (**굵게** 위에서 다시 누르기).
    final before = t.substring(0, s.start), after = t.substring(s.end);
    if (before.endsWith(left) && after.startsWith(right)) {
      final next = before.substring(0, before.length - left.length) + selected + after.substring(right.length);
      final start = s.start - left.length;
      return TextEditingValue(
        text: next,
        selection: TextSelection(baseOffset: start, extentOffset: start + selected.length),
      );
    }
    final next = '$before$left$selected$right$after';
    final start = s.start + left.length;
    return TextEditingValue(
      text: next,
      selection: TextSelection(baseOffset: start, extentOffset: start + selected.length),
    );
  }

  /// 선택에 걸친 모든 줄 앞에 [prefix]를 붙인다. 모든 줄에 이미 있으면 뗀다.
  static TextEditingValue prefixLines(TextEditingValue v, String prefix) {
    final s = _sel(v);
    final t = v.text;
    final lineStart = s.start == 0 ? 0 : t.lastIndexOf('\n', s.start - 1) + 1;
    var lineEnd = t.indexOf('\n', s.end);
    if (lineEnd < 0) lineEnd = t.length;
    final lines = t.substring(lineStart, lineEnd).split('\n');
    final remove = lines.every((l) => l.startsWith(prefix));
    final changed = [for (final l in lines) remove ? l.substring(prefix.length) : '$prefix$l'].join('\n');
    final next = t.replaceRange(lineStart, lineEnd, changed);
    final delta = changed.length - (lineEnd - lineStart);
    return TextEditingValue(
      text: next,
      selection: TextSelection(
        baseOffset: (s.start + (remove ? -prefix.length : prefix.length)).clamp(lineStart, next.length),
        extentOffset: (s.end + delta).clamp(lineStart, next.length),
      ),
    );
  }

  /// `[글](주소)` — 선택한 글이 있으면 그것이 글이 되고 주소 자리를 선택해 둔다. 없으면 글 자리를 선택한다.
  static TextEditingValue link(TextEditingValue v) {
    final s = _sel(v);
    final t = v.text;
    final selected = t.substring(s.start, s.end);
    if (selected.isEmpty) {
      final next = t.replaceRange(s.start, s.end, '[](url)');
      return TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: s.start + 1),
      );
    }
    final next = t.replaceRange(s.start, s.end, '[$selected](url)');
    final urlStart = s.start + selected.length + 3;
    return TextEditingValue(
      text: next,
      selection: TextSelection(baseOffset: urlStart, extentOffset: urlStart + 3),
    );
  }

  /// 선택에 걸친 모든 줄 앞에 `1. `, `2. `… 번호를 붙인다. 모든 줄에 이미 번호가 있으면 뗀다.
  static TextEditingValue numberLines(TextEditingValue v) {
    final s = _sel(v);
    final t = v.text;
    final lineStart = s.start == 0 ? 0 : t.lastIndexOf('\n', s.start - 1) + 1;
    var lineEnd = t.indexOf('\n', s.end);
    if (lineEnd < 0) lineEnd = t.length;
    final lines = t.substring(lineStart, lineEnd).split('\n');
    final numbered = RegExp(r'^\d+\.\s');
    final remove = lines.every(numbered.hasMatch);
    final changed = [
      for (var i = 0; i < lines.length; i++) remove ? lines[i].replaceFirst(numbered, '') : '${i + 1}. ${lines[i]}',
    ].join('\n');
    final next = t.replaceRange(lineStart, lineEnd, changed);
    return TextEditingValue(
      text: next,
      selection: TextSelection(baseOffset: lineStart, extentOffset: lineStart + changed.length),
    );
  }

  /// 선택한 글을 ``` 코드 블록으로 감싼다 (앞뒤에 줄바꿈 보장). 선택이 없으면 빈 블록을 넣고 커서를 안에 둔다.
  /// 이미 코드 블록이면 벗긴다.
  static TextEditingValue codeBlock(TextEditingValue v) {
    final s = _sel(v);
    final t = v.text;
    final before = t.substring(0, s.start), selected = t.substring(s.start, s.end), after = t.substring(s.end);
    if (before.endsWith('```\n') && after.startsWith('\n```')) {
      final start = s.start - 4;
      return TextEditingValue(
        text: before.substring(0, before.length - 4) + selected + after.substring(4),
        selection: TextSelection(baseOffset: start, extentOffset: start + selected.length),
      );
    }
    final lead = before.isEmpty || before.endsWith('\n') ? '' : '\n';
    final trail = after.isEmpty || after.startsWith('\n') ? '' : '\n';
    final start = before.length + lead.length + 4;
    return TextEditingValue(
      text: '$before$lead```\n$selected\n```$trail$after',
      selection: TextSelection(baseOffset: start, extentOffset: start + selected.length),
    );
  }

  /// 커서 줄 아래에 구분선(`---`)을 넣는다. 앞뒤를 빈 줄로 띄워야 제목(setext)으로 읽히지 않는다.
  static TextEditingValue rule(TextEditingValue v) {
    final s = _sel(v);
    final t = v.text;
    final lineEnd = t.indexOf('\n', s.end) < 0 ? t.length : t.indexOf('\n', s.end);
    final rest = t.substring(lineEnd);
    final insert = '\n\n---\n${rest.startsWith('\n') ? '' : '\n'}';
    final next = t.replaceRange(lineEnd, lineEnd, insert);
    return TextEditingValue(text: next, selection: TextSelection.collapsed(offset: lineEnd + insert.length));
  }

  /// 2열 표의 뼈대를 커서 줄 아래에 넣고 첫 칸의 제목을 선택해 둔다.
  static TextEditingValue table(TextEditingValue v) {
    final s = _sel(v);
    final t = v.text;
    final lineEnd = t.indexOf('\n', s.end) < 0 ? t.length : t.indexOf('\n', s.end);
    const head = '| 제목 | 제목 |';
    final insert = '${t.isEmpty || lineEnd == 0 ? '' : '\n\n'}$head\n| --- | --- |\n|  |  |\n';
    final next = t.replaceRange(lineEnd, lineEnd, insert);
    final start = lineEnd + insert.indexOf('제목');
    return TextEditingValue(text: next, selection: TextSelection(baseOffset: start, extentOffset: start + 2));
  }

  static final _listItem = RegExp(r'^\s*(?:[-*+]|\d+\.)\s');
  static final _numbered = RegExp(r'^\s*(\d+)\.\s');
  static final _heading = RegExp(r'^#{1,6}\s');
  static final _altBullet = RegExp(r'^(\s*)[*+](\s)');
  static final _gluedNumber = RegExp(r'(?<=[^\d\s][.!?:)])(\d{1,2})\.\s');

  /// 줄바꿈이 빠진 채 붙여넣은 글(주로 Claude 화면에서 복사)을 Markdown답게 정리한다.
  /// 문장 끝에 붙은 `N. ` 목록 번호 앞에 줄을 나누고, 목록·제목 앞뒤를 빈 줄로 띄우고, 연속 빈 줄과 줄 끝 공백을 정리하고,
  /// `*`·`+` 목록 기호를 `-`로 맞춘다. ``` 코드 블록 안은 그대로 둔다.
  static String tidyText(String text) {
    final lines = <({String text, bool code})>[];
    var inFence = false;
    var last = 0;
    for (final raw in text.replaceAll('\r\n', '\n').split('\n')) {
      if (raw.trimLeft().startsWith('```')) {
        inFence = !inFence;
        lines.add((text: raw, code: true));
        continue;
      }
      if (inFence) {
        lines.add((text: raw, code: true));
        continue;
      }
      final line = raw.trimRight().replaceFirstMapped(_altBullet, (m) => '${m[1]}-${m[2]}');
      final start = _numbered.firstMatch(line);
      if (start != null) last = int.parse(start[1]!);
      // 번호가 1이거나 이어지는 번호일 때만 나눈다 (`v1.2. ` 같은 글을 목록으로 오해하지 않게).
      var from = 0;
      for (final m in _gluedNumber.allMatches(line)) {
        final n = int.parse(m[1]!);
        if (n != 1 && n != last + 1) continue;
        last = n;
        lines.add((text: line.substring(from, m.start), code: false));
        from = m.start;
      }
      lines.add((text: line.substring(from), code: false));
    }

    final out = <String>[];
    ({String text, bool code})? prev;
    for (final l in lines) {
      if (!l.code) {
        final blank = l.text.trim().isEmpty;
        if (blank && prev != null && !prev.code && prev.text.trim().isEmpty) continue;
        final p = prev;
        if (p != null && !p.code && p.text.trim().isNotEmpty && !blank) {
          final startsList = _listItem.hasMatch(l.text) && !_listItem.hasMatch(p.text) && !p.text.startsWith(' ');
          if (_heading.hasMatch(l.text) || _heading.hasMatch(p.text) || startsList) out.add('');
        }
      }
      out.add(l.text);
      prev = l;
    }
    return out.join('\n');
  }

  /// 선택한 글(선택이 없으면 메모 전체)을 [tidyText]로 정리한다.
  static TextEditingValue tidy(TextEditingValue v) {
    final s = _sel(v);
    final t = v.text;
    if (s.isCollapsed) {
      final next = tidyText(t);
      final cursor = tidyText(t.substring(0, s.start)).length.clamp(0, next.length);
      return TextEditingValue(text: next, selection: TextSelection.collapsed(offset: cursor));
    }
    final tidied = tidyText(t.substring(s.start, s.end));
    return TextEditingValue(
      text: t.replaceRange(s.start, s.end, tidied),
      selection: TextSelection(baseOffset: s.start, extentOffset: s.start + tidied.length),
    );
  }

  /// 선택 영역(없으면 커서 자리)을 [text]로 바꾸고 커서를 그 뒤에 둔다.
  static TextEditingValue insert(TextEditingValue v, String text) {
    final s = _sel(v);
    return TextEditingValue(
      text: v.text.replaceRange(s.start, s.end, text),
      selection: TextSelection.collapsed(offset: s.start + text.length),
    );
  }
}
