/// 메모 간 링크 `[[제목]]`. 메모 파일은 UUID라서, 링크는 제목으로 적고 보여줄 때 제목 → 메모로 푼다.
/// 값 → 값이라 위젯 없이 테스트한다. 코드 블록(``` / ~~~)과 인라인 코드 안의 `[[ ]]`는 링크가 아니다.
abstract final class WikiLinks {
  static final _link = RegExp(r'\[\[([^\[\]\n]+?)\]\]');
  static final _fence = RegExp(r'^\s*(?:`{3,}|~{3,})');

  /// 제목 비교용: 앞뒤 공백을 떼고 연속 공백을 하나로, 대소문자는 무시한다.
  static String normalize(String title) => title.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  /// 코드가 아닌 구간에만 [fn]을 적용해 본문을 다시 만든다.
  static String _mapOutsideCode(String body, String Function(String segment) fn) {
    var inFence = false;
    return [
      for (final line in body.split('\n'))
        if (_fence.hasMatch(line))
          () {
            inFence = !inFence;
            return line;
          }()
        else if (inFence)
          line
        else
          // 백틱으로 나눈 홀수 번째 조각이 인라인 코드다.
          [
            for (final (i, part) in line.split('`').indexed) i.isOdd ? part : fn(part),
          ].join('`'),
    ].join('\n');
  }

  /// 본문이 링크한 제목들 (코드 밖, 등장 순서, 중복 포함).
  static List<String> titlesIn(String body) {
    final out = <String>[];
    _mapOutsideCode(body, (seg) {
      for (final m in _link.allMatches(seg)) {
        out.add(m.group(1)!.trim());
      }
      return seg;
    });
    return out;
  }

  /// 미리보기용 본문: `[[제목]]`을 Markdown 링크로 바꾼다. 찾은 메모는 `제목`(주소 `note:<id>`),
  /// 없는 제목은 `[[제목]]` 그대로 보이는 링크(주소 `newnote:<제목>`)로 — 누르면 그 제목으로 새 메모를 만든다.
  static String render(String body, String? Function(String title) resolveId) => _mapOutsideCode(
    body,
    (seg) => seg.replaceAllMapped(_link, (m) {
      final title = m.group(1)!.trim();
      final shown = _escape(title);
      final id = resolveId(title);
      return id != null
          ? '[$shown](note:$id)'
          : '[\\[\\[$shown\\]\\]](newnote:${Uri.encodeComponent(title)})';
    }),
  );

  static String _escape(String s) => s.replaceAllMapped(RegExp(r'[\\\[\]*_`~<>]'), (m) => '\\${m[0]}');

  /// 링크 주소가 메모를 가리키면 그 id, 아니면 null.
  static String? idOf(String? href) => href != null && href.startsWith('note:') ? href.substring(5) : null;

  /// 링크 주소가 아직 없는 메모의 제목이면 그 제목, 아니면 null.
  static String? newTitleOf(String? href) {
    if (href == null || !href.startsWith('newnote:')) return null;
    try {
      return Uri.decodeComponent(href.substring(8));
    } catch (_) {
      return null;
    }
  }

  static bool isNoteHref(String? href) => idOf(href) != null || newTitleOf(href) != null;
}
