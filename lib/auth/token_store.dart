import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 액세스 토큰은 OS 보안 저장소에만 둔다 — 파일·로그·설정에 남기지 않는다.
abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> delete();
}

class SecureTokenStore implements TokenStore {
  /// [key]는 키체인 항목 이름. 테스트는 반드시 다른 이름을 써야 한다 — 같은 이름이면
  /// 실제 앱에 저장된 사용자의 로그인 토큰을 지워 버린다.
  SecureTokenStore({this.key = 'github_token'})
      : _storage = Platform.isMacOS
            // 데이터 보호 키체인은 keychain-access-groups 권한(프로비저닝 프로파일)이 필요하다.
            // 이 앱은 키체인을 공유하지 않으므로 기존 키체인을 쓴다.
            ? const FlutterSecureStorage(mOptions: MacOsOptions(usesDataProtectionKeychain: false))
            : const FlutterSecureStorage();

  final String key;
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: key);

  @override
  Future<void> write(String token) => _storage.write(key: key, value: token);

  @override
  Future<void> delete() => _storage.delete(key: key);
}

class MemoryTokenStore implements TokenStore {
  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;

  @override
  Future<void> delete() async => _token = null;
}
