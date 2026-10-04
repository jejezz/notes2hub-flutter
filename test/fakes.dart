import 'package:notes2hub/sync/sync_models.dart';

/// 호출을 기록하고 미리 정한 결과를 돌려주는 가짜 엔진.
class FakeEngine implements SyncEngine {
  SyncResult connectResult = const SyncResult();
  SyncResult syncResult = const SyncResult(pushed: true);
  SyncResult pullResult = const SyncResult();
  int pending = 0;
  bool unpushed = false;
  Set<String> pendingNotes = {};
  final calls = <String>[];

  /// 호출마다 걸리는 시간. 겹침 검사용으로 늘려 쓴다.
  Duration latency = Duration.zero;
  int inFlight = 0;
  int maxInFlight = 0;
  List<SyncResult>? syncQueue; // 있으면 호출 순서대로 하나씩 꺼내 쓴다

  Future<T> _track<T>(T Function() body) async {
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    await Future<void>.delayed(latency);
    final r = body();
    inFlight--;
    return r;
  }
  String? lastToken;
  GitIdentity? lastIdentity;

  @override
  Future<SyncResult> connect({required String remoteUrl, required String token}) async {
    return _track(() {
      calls.add('connect $remoteUrl');
      lastToken = token;
      return connectResult;
    });
  }

  @override
  Future<SyncStatus> status() => _track(() => SyncStatus(changed: pending, unpushed: unpushed, pendingNotes: pendingNotes));

  @override
  Future<SyncResult> sync({required String token, required GitIdentity identity, required String deviceLabel}) async {
    return _track(() {
      calls.add('sync');
      lastToken = token;
      lastIdentity = identity;
      return syncQueue != null && syncQueue!.isNotEmpty ? syncQueue!.removeAt(0) : syncResult;
    });
  }

  @override
  Future<SyncResult> pull({required String token}) async {
    return _track(() {
      calls.add('pull');
      return pullResult;
    });
  }
}
