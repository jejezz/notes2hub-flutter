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
  });

  final String id;
  final DateTime created;
  final DateTime updated;
  final String body;

  /// 본문의 첫 비어 있지 않은 줄에서 Markdown 머리표(`#`)를 뗀 것. 없으면 빈 문자열.
  String get title {
    for (final line in body.split('\n')) {
      final t = line.replaceFirst(RegExp(r'^\s*#{1,6}\s*'), '').trim();
      if (t.isNotEmpty) return t;
    }
    return '';
  }

  /// 목록 미리보기용: 제목 줄 다음의 첫 비어 있지 않은 줄.
  String get snippet {
    var seenTitle = false;
    for (final line in body.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      if (!seenTitle) {
        seenTitle = true;
        continue;
      }
      return t.replaceFirst(RegExp(r'^#{1,6}\s*'), '');
    }
    return '';
  }

  Note copyWith({String? body, DateTime? updated}) => Note(
        id: id,
        created: created,
        updated: updated ?? this.updated,
        body: body ?? this.body,
      );

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    return q.isEmpty || body.toLowerCase().contains(q);
  }

  String serialize() => '---\n'
      'id: $id\n'
      'created: ${created.toUtc().toIso8601String()}\n'
      'updated: ${updated.toUtc().toIso8601String()}\n'
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
