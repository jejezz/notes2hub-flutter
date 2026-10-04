import 'package:notes2hub/sync/sync_models.dart';

/// 호출을 기록하고 미리 정한 결과를 돌려주는 가짜 엔진.
class FakeEngine implements SyncEngine {
  SyncResult connectResult = const SyncResult();
  SyncResult syncResult = const SyncResult(pushed: true);
  SyncResult pullResult = const SyncResult();
  int pending = 0;
  final calls = <String>[];
  String? lastToken;
  GitIdentity? lastIdentity;

  @override
  Future<SyncResult> connect({required String remoteUrl, required String token}) async {
    calls.add('connect $remoteUrl');
    lastToken = token;
    return connectResult;
  }

  @override
  Future<int> pendingCount() async => pending;

  @override
  Future<SyncResult> sync({required String token, required GitIdentity identity, required String deviceLabel}) async {
    calls.add('sync');
    lastToken = token;
    lastIdentity = identity;
    return syncResult;
  }

  @override
  Future<SyncResult> pull({required String token}) async {
    calls.add('pull');
    return pullResult;
  }
}
