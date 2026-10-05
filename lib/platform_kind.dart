import 'dart:io';

import 'package:flutter/foundation.dart';

/// 테스트에서 모바일 화면을 흉내 낼 때만 쓴다.
@visibleForTesting
bool? debugIsMobile;

/// 실제 iOS·Android 기기인가. `defaultTargetPlatform`은 flutter_test에서 기본이 android라서
/// 데스크톱 화면 테스트가 모두 모바일로 보이게 되므로 `dart:io`의 값을 쓴다 (웹은 지원하지 않는다).
bool get isMobilePlatform => debugIsMobile ?? (Platform.isIOS || Platform.isAndroid);
