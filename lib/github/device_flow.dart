import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class DeviceFlowException implements Exception {
  const DeviceFlowException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DeviceCode {
  const DeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.interval,
    required this.expiresIn,
  });

  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final int interval; // seconds
  final int expiresIn; // seconds
}

/// GitHub OAuth Device Flow — 서버 없이 데스크톱 앱에서 로그인하는 방법.
/// https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow
/// (OAuth App 등록에서 "Enable Device Flow"를 켜야 한다. client id는 비밀이 아니다.)
class DeviceFlow {
  DeviceFlow(this.clientId, {http.Client? client, this.baseUrl = 'https://github.com', this.sleep = _sleep})
      : _client = client ?? http.Client();

  final String clientId;
  final String baseUrl;
  final http.Client _client;
  final Future<void> Function(Duration) sleep;

  static Future<void> _sleep(Duration d) => Future<void>.delayed(d);

  Future<Map<String, dynamic>> _post(String path, Map<String, String> body) async {
    final res = await _client.post(
      Uri.parse('$baseUrl$path'),
      headers: {'Accept': 'application/json', 'User-Agent': 'Notes2Hub'},
      body: body,
    );
    final j = jsonDecode(res.body);
    if (j is! Map<String, dynamic>) throw DeviceFlowException('Unexpected response (${res.statusCode})');
    return j;
  }

  Future<DeviceCode> start({String scope = 'repo'}) async {
    final j = await _post('/login/device/code', {'client_id': clientId, 'scope': scope});
    if (j['error'] != null) throw DeviceFlowException('${j['error_description'] ?? j['error']}');
    return DeviceCode(
      deviceCode: j['device_code'] as String,
      userCode: j['user_code'] as String,
      verificationUri: j['verification_uri'] as String,
      interval: (j['interval'] as num?)?.toInt() ?? 5,
      expiresIn: (j['expires_in'] as num?)?.toInt() ?? 900,
    );
  }

  /// 사용자가 브라우저에서 승인할 때까지 기다린다. [cancelled]가 true가 되면 멈춘다(null 반환).
  ///
  /// [wake]가 주는 Future가 끝나면 대기 시간을 건너뛰고 바로 확인한다 — 앱이 다시 앞으로 올 때처럼
  /// 사용자가 방금 승인했을 가능성이 높은 때 쓴다.
  Future<String?> awaitToken(DeviceCode code, {bool Function()? cancelled, Future<void> Function()? wake}) async {
    var interval = code.interval;
    final deadline = DateTime.now().add(Duration(seconds: code.expiresIn));
    while (DateTime.now().isBefore(deadline)) {
      final wait = sleep(Duration(seconds: interval));
      await (wake == null ? wait : Future.any([wait, wake()]));
      if (cancelled?.call() ?? false) return null;
      final Map<String, dynamic> j;
      try {
        j = await _post('/login/oauth/access_token', {
          'client_id': clientId,
          'device_code': code.deviceCode,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        });
      } on http.ClientException {
        continue; // 폰에서 브라우저를 오가는 사이 네트워크가 잠깐 끊긴다 — 다음 확인에서 다시 시도
      } on TimeoutException {
        continue;
      }
      final token = j['access_token'];
      if (token is String && token.isNotEmpty) return token;
      switch (j['error']) {
        case 'authorization_pending':
          break;
        case 'slow_down':
          interval = (j['interval'] as num?)?.toInt() ?? interval + 5;
        case 'expired_token':
          throw const DeviceFlowException('The code expired. Please try again.');
        case 'access_denied':
          throw const DeviceFlowException('Access was denied.');
        default:
          throw DeviceFlowException('${j['error_description'] ?? j['error'] ?? 'Unknown error'}');
      }
    }
    throw const DeviceFlowException('The code expired. Please try again.');
  }
}
