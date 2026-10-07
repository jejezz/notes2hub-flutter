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

/// 로컬에서 아직 원격에 반영되지 않은 것.
class SyncStatus {
  const SyncStatus({this.changed = 0, this.unpushed = false, this.pendingNotes = const {}});

  /// 저장했지만 아직 커밋하지 않은 메모 파일 수.
  final int changed;

  /// 커밋은 했지만 아직 push하지 못했다 (오프라인이었거나 push가 실패했다).
  final bool unpushed;

  /// 아직 원격에 반영되지 않은 메모 id들 (저장은 했지만 커밋 전이거나, 커밋은 했지만 push 전).
  final Set<String> pendingNotes;

  bool get isClean => changed == 0 && !unpushed;
}

/// 메모 한 개의 과거 버전 하나 — 그 메모 파일이 바뀐 커밋.
class NoteVersion {
  const NoteVersion({required this.sha, required this.time, required this.message});

  final String sha;
  final DateTime time;
  final String message;
}

abstract class SyncEngine {
  /// [dir]에 git 저장소를 만들고(이미 있으면 재사용) 원격을 연결한 뒤, 원격에 이력이
  /// 있으면 그 브랜치를 체크아웃한다. 로컬에 있던 메모 파일은 그대로 남아 다음
  /// 동기화에서 커밋된다.
  Future<SyncResult> connect({required String remoteUrl, required String token});

  /// 동기화가 필요한 것이 남았는지. 마지막으로 가져온 원격 상태와 비교한다(네트워크 없음).
  Future<SyncStatus> status();

  /// 커밋 → 가져오기(병합) → 푸시.
  Future<SyncResult> sync({required String token, required GitIdentity identity, required String deviceLabel});

  /// 가져오기만. 저장된 변경이 없을 때의 fast-forward만 한다 — 자동 pull용.
  Future<SyncResult> pull({required String token});

  /// [noteId] 메모 파일이 바뀐 커밋들, 최근 순. 동기화(커밋)한 시점의 내용만 남아 있다.
  /// 저장소가 없거나 커밋이 없으면 빈 목록.
  Future<List<NoteVersion>> history(String noteId, {int limit = 100});

  /// [sha] 커밋 시점의 메모 본문 전체(frontmatter 포함). 그 커밋에 없으면 null.
  Future<String?> versionContent(String sha, String noteId);
}
