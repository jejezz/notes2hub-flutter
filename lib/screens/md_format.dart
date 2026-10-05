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
}
