import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

/// 커밋 메시지·충돌 사본 이름에 들어가는 기기 이름. 폰의 호스트 이름은 `localhost` 같은
/// 의미 없는 값이라 모델명을 쓴다. 읽지 못하면 null (SyncService가 기본값을 쓴다).
Future<String?> readDeviceLabel() async {
  try {
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final a = await info.androidInfo;
      return _clean(a.model);
    }
    if (Platform.isIOS) {
      final i = await info.iosInfo;
      // iOS 16+는 사용자가 정한 기기 이름을 주지 않으므로 "iPhone"/"iPad" 같은 모델 계열 이름이 온다.
      return _clean(i.name.isNotEmpty ? i.name : i.model);
    }
  } catch (_) {}
  return null;
}

String? _clean(String s) {
  final t = s.trim();
  return t.isEmpty ? null : t;
}
