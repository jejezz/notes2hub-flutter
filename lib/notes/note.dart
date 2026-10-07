/// 메모 1개 = 파일 1개 (`notes/<id>.md`). docs/PLAN.md §4.
///
/// 파일 형식: YAML 비슷한 frontmatter(id, created, updated) + Markdown 본문.
/// 제목은 저장하지 않고 본문 첫 줄에서 뽑는다 — 제목을 따로 두면 본문과 어긋나고
/// 동기화 충돌 면적만 넓어진다.
class Note {
  const Note({
    required this.id,
    required this.created,
    required this.updated,
    required this.body,
    this.bookmarked = false,
    this.deletedAt,
  });

  final String id;
  final DateTime created;
  final DateTime updated;
  final String body;

  /// 북마크한 메모 — 보드 맨 위에 모아 보인다. frontmatter `bookmarked: true`로 저장해
  /// 동기화로 다른 PC에도 따라간다. 북마크를 바꿔도 `updated`는 그대로다.
  final bool bookmarked;

  /// 휴지통으로 옮긴 시각 (frontmatter `deleted:`). null이면 살아 있는 메모.
  /// 파일은 `notes/`에 그대로 있어서 휴지통 상태도 동기화로 다른 PC에 따라간다.
  final DateTime? deletedAt;

  bool get isTrashed => deletedAt != null;

  static final _imageLine = RegExp(r'^\s*!\[[^\]]*\]\([^)]*\)\s*$');
  static final _imageRef = RegExp(r'!\[[^\]]*\]\(\.\./assets/([^)\s]+)\)');

  /// 본문에서 이미지만 있는 줄을 뺀, 글이 있는 줄들 (공백 줄 제외, 앞뒤 공백 제거).
  Iterable<String> get _textLines sync* {
    for (final line in body.split('\n')) {
      final t = line.trim();
      if (t.isNotEmpty && !_imageLine.hasMatch(t)) yield t;
    }
  }

  static String _plain(String line) => line
      .replaceFirst(RegExp(r'^#{1,6}\s*'), '')
      .replaceFirstMapped(RegExp(r'^[-*+]\s+\[([ xX])\]\s+'), (m) => m[1] == ' ' ? '☐ ' : '☑ ')
      .replaceAllMapped(RegExp(r'\[\[([^\[\]]+)\]\]'), (m) => m[1]!)
      .replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
      .replaceAll(RegExp(r'[*_`~]'), '')
      .trim();

  /// 본문의 첫 글 줄에서 Markdown 머리표(`#`)를 뗀 것. 이미지 줄은 건너뛴다. 없으면 빈 문자열.
  String get title {
    for (final line in _textLines) {
      final t = _plain(line);
      if (t.isNotEmpty) return t;
    }
    return '';
  }

  /// 동기화 충돌로 만들어진 사본인가 — 제목 끝의 "(충돌 …)" 표시로 알아본다 ([conflictCopyOf]).
  bool get isConflictCopy => RegExp(r'\(충돌 [^)]*\)$').hasMatch(title);

  /// 제목 줄 다음의 글 줄 하나 (목록 미리보기용).
  String get snippet {
    var seenTitle = false;
    for (final line in _textLines) {
      if (!seenTitle) {
        seenTitle = true;
        continue;
      }
      final t = _plain(line);
      if (t.isNotEmpty) return t;
    }
    return '';
  }

  /// 카드용 발췌: 제목 다음 글 줄들을 이어 붙인 것 (최대 [max]자).
  String excerpt({int max = 160}) {
    final parts = <String>[];
    var seenTitle = false;
    for (final line in _textLines) {
      if (!seenTitle) {
        seenTitle = true;
        continue;
      }
      final t = _plain(line);
      if (t.isEmpty) continue;
      parts.add(t);
      if (parts.join(' ').length >= max) break;
    }
    final text = parts.join(' ');
    return text.length <= max ? text : '${text.substring(0, max).trimRight()}…';
  }

  /// 본문이 처음 참조하는 첨부 이미지 파일 이름 (카드 표지). 없으면 null.
  String? get coverAsset {
    final m = _imageRef.firstMatch(body);
    return m == null ? null : Uri.decodeComponent(m.group(1)!);
  }

  /// [deletedAt]을 지정하면 휴지통으로, [restore]면 휴지통에서 꺼낸다.
  Note copyWith({String? body, DateTime? updated, bool? bookmarked, DateTime? deletedAt, bool restore = false}) => Note(
        id: id,
        created: created,
        updated: updated ?? this.updated,
        body: body ?? this.body,
        bookmarked: bookmarked ?? this.bookmarked,
        deletedAt: restore ? null : (deletedAt ?? this.deletedAt),
      );

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    return q.isEmpty || body.toLowerCase().contains(q);
  }

  String serialize() => '---\n'
      'id: $id\n'
      'created: ${created.toUtc().toIso8601String()}\n'
      'updated: ${updated.toUtc().toIso8601String()}\n'
      '${bookmarked ? 'bookmarked: true\n' : ''}'
      '${deletedAt != null ? 'deleted: ${deletedAt!.toUtc().toIso8601String()}\n' : ''}'
      '---\n'
      '$body';

  /// [fallbackId]와 [fallbackTime]은 frontmatter가 없는 일반 Markdown 파일(기존 repo를
  /// 고른 경우)을 위한 값이다 — 파일 이름과 수정 시각을 쓴다.
  static Note parse(String raw, {required String fallbackId, required DateTime fallbackTime}) {
    final text = raw.replaceAll('\r\n', '\n');
    if (text.startsWith('---\n')) {
      final end = text.indexOf('\n---\n', 3);
      if (end != -1) {
        final meta = <String, String>{};
        for (final line in text.substring(4, end).split('\n')) {
          final i = line.indexOf(':');
          if (i > 0) meta[line.substring(0, i).trim()] = line.substring(i + 1).trim();
        }
        final created = DateTime.tryParse(meta['created'] ?? '') ?? fallbackTime;
        return Note(
          id: (meta['id'] ?? '').isEmpty ? fallbackId : meta['id']!,
          created: created,
          updated: DateTime.tryParse(meta['updated'] ?? '') ?? created,
          body: text.substring(end + 5),
          bookmarked: meta['bookmarked'] == 'true',
          deletedAt: DateTime.tryParse(meta['deleted'] ?? ''),
        );
      }
    }
    return Note(id: fallbackId, created: fallbackTime, updated: fallbackTime, body: text);
  }
}

/// 충돌로 밀려난 쪽의 사본. 첫 줄(제목)에 "(충돌 <label>)"을 붙여 목록에서 바로 구별되게 한다.
/// docs/PLAN.md §5 — 원격이 본 파일을 차지하고, 로컬 내용은 이 사본으로 보존된다.
Note conflictCopyOf(Note ours, {required String newId, required String label, required DateTime now}) {
  final lines = ours.body.split('\n');
  final i = lines.indexWhere((l) => l.trim().isNotEmpty);
  final suffix = '(충돌 $label)';
  if (i == -1) {
    lines
      ..clear()
      ..add(suffix);
  } else {
    lines[i] = '${lines[i].trimRight()} $suffix';
  }
  return Note(id: newId, created: ours.created, updated: now, body: lines.join('\n'));
}
