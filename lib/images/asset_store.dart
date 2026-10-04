import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

/// 첨부 이미지 파일 보관소: `<저장소>/assets/<uuid>.<ext>`. 메모는 `../assets/<이름>`으로 참조한다
/// (GitHub에서 메모를 열어도 이미지가 보이는 상대 경로).
class AssetStore {
  AssetStore(this.dir);

  /// 보통 `<앱 데이터>/data/assets`.
  final Directory dir;

  static const _uuid = Uuid();

  /// 메모 본문에 쓰는 참조 형식.
  static String markdownFor(String fileName, {String alt = ''}) => '![${alt.replaceAll(RegExp(r'[\[\]\n]'), ' ').trim()}](../assets/$fileName)';

  static final _ref = RegExp(r'\(\.\./assets/([^)\s]+)\)');

  /// 본문이 참조하는 첨부 파일 이름들.
  static Set<String> referencedIn(String body) => _ref.allMatches(body).map((m) => Uri.decodeComponent(m.group(1)!)).toSet();

  /// 임시 파일에 쓴 뒤 이름을 바꾼다 (쓰다 꺼져도 깨진 이미지가 남지 않게). 저장한 파일 이름을 돌려준다.
  Future<String> add(Uint8List bytes, String ext) async {
    await dir.create(recursive: true);
    final name = '${_uuid.v4()}.$ext';
    final target = File('${dir.path}/$name');
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(target.path);
    return name;
  }

  File file(String name) => File('${dir.path}/$name');

  /// 어떤 메모도 참조하지 않고 [olderThan]보다 오래된 첨부를 지운다. 방금 붙였지만 아직
  /// 저장하지 않은 메모의 이미지나, 막 받아온 파일을 지우지 않도록 기간을 둔다. 지운 개수를 돌려준다.
  Future<int> collectOrphans(Set<String> referenced, {Duration olderThan = const Duration(days: 7)}) async {
    if (!await dir.exists()) return 0;
    final cutoff = DateTime.now().subtract(olderThan);
    var removed = 0;
    await for (final e in dir.list()) {
      if (e is! File) continue;
      final name = e.uri.pathSegments.last;
      if (referenced.contains(name)) continue;
      if ((await e.stat()).modified.isAfter(cutoff)) continue;
      await e.delete();
      removed++;
    }
    return removed;
  }
}
