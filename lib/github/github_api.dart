import 'dart:convert';

import 'package:http/http.dart' as http;

class GitHubApiException implements Exception {
  const GitHubApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get unauthorized => statusCode == 401;

  @override
  String toString() => message;
}

class GitHubUser {
  const GitHubUser({required this.login, required this.id, this.name});

  final String login;
  final int id;
  final String? name;

  /// 커밋에 쓰는 이름. GitHub 프로필 이름이 없으면 로그인 이름.
  String get displayName => (name == null || name!.trim().isEmpty) ? login : name!.trim();

  /// 개인 이메일이 커밋 기록에 남지 않도록 GitHub noreply 주소를 쓴다.
  String get noreplyEmail => '$id+$login@users.noreply.github.com';
}

/// 앱이 쓰는 저장소에 붙이는 GitHub 토픽. 새 PC에서 로그인하면 이 표식으로 저장소를 바로 제안한다.
const kNotesTopic = 'notes2hub';

class GitHubRepo {
  const GitHubRepo({
    required this.fullName,
    required this.cloneUrl,
    required this.isPrivate,
    this.description,
    this.topics = const [],
  });

  final String fullName;
  final String cloneUrl;
  final bool isPrivate;
  final String? description;
  final List<String> topics;

  /// Notes2Hub가 쓰던 저장소인가 (토픽 표식).
  bool get isNotesRepo => topics.contains(kNotesTopic);

  String get name => fullName.split('/').last;
}

/// 필요한 REST 호출만: 사용자, 저장소 목록, 저장소 만들기.
class GitHubApi {
  GitHubApi(this.token, {http.Client? client, this.baseUrl = 'https://api.github.com'}) : _client = client ?? http.Client();

  final String token;
  final String baseUrl;
  final http.Client _client;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'Notes2Hub',
      };

  Future<dynamic> _send(Future<http.Response> Function() request) async {
    final http.Response res;
    try {
      res = await request();
    } on Exception catch (e) {
      throw GitHubApiException('Network error: $e');
    }
    final body = res.body.isEmpty ? null : jsonDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) return body;
    var message = 'GitHub ${res.statusCode}';
    if (body is Map && body['message'] is String) message = '$message: ${body['message']}';
    final errors = body is Map ? body['errors'] : null;
    if (errors is List && errors.isNotEmpty) {
      message = '$message (${errors.map((e) => e is Map ? e['message'] ?? e : e).join(', ')})';
    }
    throw GitHubApiException(message, statusCode: res.statusCode);
  }

  GitHubRepo _repo(Map<String, dynamic> j) => GitHubRepo(
        fullName: j['full_name'] as String,
        cloneUrl: j['clone_url'] as String,
        isPrivate: j['private'] as bool? ?? true,
        description: j['description'] as String?,
        topics: [for (final t in (j['topics'] as List? ?? const [])) t as String],
      );

  Future<GitHubUser> user() async {
    final j = await _send(() => _client.get(Uri.parse('$baseUrl/user'), headers: _headers)) as Map<String, dynamic>;
    return GitHubUser(login: j['login'] as String, id: j['id'] as int, name: j['name'] as String?);
  }

  /// 내가 쓸 수 있는 저장소를 최근 수정순으로 (최대 [maxPages]×100개).
  Future<List<GitHubRepo>> repos({int maxPages = 5}) async {
    final all = <GitHubRepo>[];
    for (var page = 1; page <= maxPages; page++) {
      final uri = Uri.parse('$baseUrl/user/repos').replace(queryParameters: {
        'per_page': '100',
        'page': '$page',
        'sort': 'updated',
        'affiliation': 'owner,collaborator,organization_member',
      });
      final list = await _send(() => _client.get(uri, headers: _headers)) as List;
      all.addAll(list.cast<Map<String, dynamic>>().map(_repo));
      if (list.length < 100) break;
    }
    return all;
  }

  Future<GitHubRepo> createRepo(String name, {bool isPrivate = true, String? description}) async {
    final j = await _send(() => _client.post(
          Uri.parse('$baseUrl/user/repos'),
          headers: {..._headers, 'Content-Type': 'application/json'},
          body: jsonEncode({'name': name, 'private': isPrivate, 'description': ?description, 'auto_init': false}),
        )) as Map<String, dynamic>;
    return _repo(j);
  }

  /// 저장소에 [kNotesTopic] 표식을 붙인다 (이미 있으면 아무것도 하지 않는다). 토픽 설정은 전체를 교체하므로
  /// 기존 토픽을 읽어 합친다. 권한이 없으면 실패할 수 있다 — 표식은 편의 기능이라 호출하는 쪽이 무시한다.
  Future<void> ensureNotesTopic(String fullName) async {
    final j = await _send(() => _client.get(Uri.parse('$baseUrl/repos/$fullName/topics'), headers: _headers)) as Map<String, dynamic>;
    final names = [for (final t in (j['names'] as List? ?? const [])) t as String];
    if (names.contains(kNotesTopic)) return;
    await _send(() => _client.put(
          Uri.parse('$baseUrl/repos/$fullName/topics'),
          headers: {..._headers, 'Content-Type': 'application/json'},
          body: jsonEncode({'names': [...names, kNotesTopic]}),
        ));
  }
}
