/// 커밋 작성자. GitHub noreply 주소를 쓰면 개인 이메일이 기록에 남지 않는다.
class GitIdentity {
  const GitIdentity({required this.name, required this.email});

  final String name;
  final String email;
}

/// 동기화 한 번의 결과. Isolate 경계를 넘으므로 단순 값만 담는다.
class SyncResult {
  const SyncResult({
    this.committed = 0,
    this.pushed = false,
    this.integrated = false,
    this.conflictCopies = 0,
    this.needsSync = false,
    this.error,
    this.authFailed = false,
    this.offline = false,
  });

  /// 이번에 커밋한 변경 파일 수.
  final int committed;
  final bool pushed;

  /// 원격 변경을 가져와 작업 폴더가 바뀌었는가 (화면을 다시 읽어야 함).
  final bool integrated;
  final int conflictCopies;

  /// pull만 했을 때: 저장된 변경이 있어 가져오지 못했다 (동기화가 필요).
  final bool needsSync;

  final String? error;
  final bool authFailed;
  final bool offline;

  bool get ok => error == null;
}

abstract class SyncEngine {
  /// [dir]에 git 저장소를 만들고(이미 있으면 재사용) 원격을 연결한 뒤, 원격에 이력이
  /// 있으면 그 브랜치를 체크아웃한다. 로컬에 있던 메모 파일은 그대로 남아 다음
  /// 동기화에서 커밋된다.
  Future<SyncResult> connect({required String remoteUrl, required String token});

  /// 저장된 메모 중 아직 커밋되지 않은 파일 수.
  Future<int> pendingCount();

  /// 커밋 → 가져오기(병합) → 푸시.
  Future<SyncResult> sync({required String token, required GitIdentity identity, required String deviceLabel});

  /// 가져오기만. 저장된 변경이 없을 때의 fast-forward만 한다 — 자동 pull용.
  Future<SyncResult> pull({required String token});
}
