/// Markdown 체크리스트(`- [ ] 할 일`, `- [x] 한 일`)의 항목 찾기·토글. 값 → 값이라 위젯 없이 테스트한다.
///
/// 항목의 순서(몇 번째 체크박스인가)로 가리킨다 — 미리보기에서 렌더링된 체크박스가 문서 순서대로 나오기 때문이다.
/// 코드 블록(``` / ~~~) 안의 `[ ]`는 항목이 아니다.
abstract final class Checklist {
  static final _item = RegExp(r'^(\s*(?:>\s*)*(?:[-*+]|\d+[.)])\s+)\[([ xX])\](?=\s|$)');
  static final _fence = RegExp(r'^\s*(?:`{3,}|~{3,})');

  /// 체크리스트 항목이 있는 줄 번호와 체크 여부, 문서 순서대로.
  static List<({int line, bool checked})> items(String body) {
    final out = <({int line, bool checked})>[];
    var inFence = false;
    final lines = body.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (_fence.hasMatch(lines[i])) {
        inFence = !inFence;
        continue;
      }
      if (inFence) continue;
      final m = _item.firstMatch(lines[i]);
      if (m != null) out.add((line: i, checked: m.group(2) != ' '));
    }
    return out;
  }

  static int count(String body) => items(body).length;

  /// [index]번째 항목의 체크를 뒤집은 본문. 그런 항목이 없거나, [expected]를 준 경우 그 항목의 현재 상태가
  /// [expected]와 다르면(화면이 본문과 어긋났다) null — 엉뚱한 줄을 건드리지 않는다.
  static String? toggle(String body, int index, {bool? expected}) {
    final all = items(body);
    if (index < 0 || index >= all.length) return null;
    final item = all[index];
    if (expected != null && item.checked != expected) return null;
    final lines = body.split('\n');
    final m = _item.firstMatch(lines[item.line])!;
    final prefix = m.group(1)!;
    lines[item.line] = '$prefix[${item.checked ? ' ' : 'x'}]${lines[item.line].substring(m.end)}';
    return lines.join('\n');
  }
}
