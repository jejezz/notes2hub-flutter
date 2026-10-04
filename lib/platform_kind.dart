import 'package:flutter/foundation.dart';

/// iOS·Android. `dart:io`의 Platform 대신 defaultTargetPlatform을 써서 테스트에서도 바꿀 수 있다.
bool get isMobilePlatform =>
    defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android;
