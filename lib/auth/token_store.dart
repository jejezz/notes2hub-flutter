import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 액세스 토큰은 OS 보안 저장소에만 둔다 — 파일·로그·설정에 남기지 않는다.
abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> delete();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore()
      : _storage = Platform.isMacOS
            // 데이터 보호 키체인은 keychain-access-groups 권한(프로비저닝 프로파일)이 필요하다.
            // 이 앱은 키체인을 공유하지 않으므로 기존 키체인을 쓴다.
            ? const FlutterSecureStorage(mOptions: MacOsOptions(usesDataProtectionKeychain: false))
            : const FlutterSecureStorage();

  static const _key = 'github_token';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> delete() => _storage.delete(key: _key);
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
