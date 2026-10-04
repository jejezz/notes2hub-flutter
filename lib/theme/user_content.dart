import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 사용자가 쓴 글은 SeoulNamsan이 아니라 시스템 글꼴로 보여준다 (fonts.md §3).
/// `fontFamily`를 비워 두면 테마 글꼴을 물려받으므로 OS 기본 UI 글꼴 이름을 직접 준다.
TextStyle userContentStyle(TextStyle? base) {
  final family = switch (defaultTargetPlatform) {
    TargetPlatform.macOS || TargetPlatform.iOS => '.AppleSystemUIFont',
    TargetPlatform.windows => 'Segoe UI',
    _ => 'Noto Sans',
  };
  return (base ?? const TextStyle()).copyWith(
    fontFamily: family,
    fontFamilyFallback: const ['Apple SD Gothic Neo', 'Malgun Gothic', 'Noto Sans CJK KR', 'Noto Sans KR'],
  );
}
