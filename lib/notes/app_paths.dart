import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 앱 데이터 폴더 — 폴더 이름은 파일 이름(PascalCase) (conventions/identity.md §6).
///   macOS   ~/Library/Application Support/Notes2Hub
///   Windows %APPDATA%\Notes2Hub
///   Linux   ${XDG_CONFIG_HOME:-~/.config}/Notes2Hub
/// (macOS 샌드박스에서는 HOME이 앱 컨테이너를 가리키므로 같은 코드가 그대로 동작한다.)
Future<Directory> appDataDir() async {
  final env = Platform.environment;
  final String? base;
  if (Platform.isMacOS) {
    base = env['HOME'] == null ? null : '${env['HOME']}/Library/Application Support';
  } else if (Platform.isWindows) {
    base = env['APPDATA'];
  } else if (Platform.isLinux) {
    base = env['XDG_CONFIG_HOME'] ?? (env['HOME'] == null ? null : '${env['HOME']}/.config');
  } else {
    base = null;
  }
  if (base == null) return getApplicationSupportDirectory();
  return Directory('$base/Notes2Hub');
}
