import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notes2hub/github/device_flow.dart';
import 'package:notes2hub/github/github_api.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  group('GitHubApi', () {
    test('user() sends the token and builds a noreply commit email', () async {
      late http.Request seen;
      final api = GitHubApi('tok', client: MockClient((req) async {
        seen = req;
        return _json({'login': 'octo', 'id': 42, 'name': 'Octo Cat'});
      }));
      final u = await api.user();
      expect(seen.headers['Authorization'], 'Bearer tok');
      expect(u.displayName, 'Octo Cat');
      expect(u.noreplyEmail, '42+octo@users.noreply.github.com');
      expect(const GitHubUser(login: 'x', id: 1).displayName, 'x');
    });

    test('401 becomes an unauthorized exception with GitHub\'s message', () async {
      final api = GitHubApi('bad', client: MockClient((_) async => _json({'message': 'Bad credentials'}, 401)));
      await expectLater(
        api.user(),
        throwsA(isA<GitHubApiException>().having((e) => e.unauthorized, 'unauthorized', true).having((e) => e.message, 'message', contains('Bad credentials'))),
      );
    });

    test('repos() pages until a short page', () async {
      var calls = 0;
      final api = GitHubApi('t', client: MockClient((req) async {
        calls++;
        final page = int.parse(req.url.queryParameters['page']!);
        final n = page == 1 ? 100 : 3;
        return _json([
          for (var i = 0; i < n; i++)
            {'full_name': 'o/r$page-$i', 'clone_url': 'https://github.com/o/r$page-$i.git', 'private': i.isEven, 'description': null},
        ]);
      }));
      final repos = await api.repos();
      expect(repos, hasLength(103));
      expect(calls, 2);
      expect(repos.first.isPrivate, isTrue);
      expect(repos[1].isPrivate, isFalse);
      expect(repos.first.name, 'r1-0');
    });

    test('createRepo posts a private, un-initialised repo and surfaces validation errors', () async {
      late Map<String, dynamic> sent;
      var api = GitHubApi('t', client: MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return _json({'full_name': 'o/notes', 'clone_url': 'https://github.com/o/notes.git', 'private': true});
      }));
      final r = await api.createRepo('notes', description: 'd');
      expect(sent, {'name': 'notes', 'private': true, 'description': 'd', 'auto_init': false});
      expect(r.fullName, 'o/notes');

      api = GitHubApi('t', client: MockClient((_) async => _json({
            'message': 'Repository creation failed.',
            'errors': [{'message': 'name already exists on this account'}],
          }, 422)));
      await expectLater(api.createRepo('notes'), throwsA(isA<GitHubApiException>().having((e) => e.message, 'm', contains('already exists'))));
    });
  });

  group('DeviceFlow', () {
    test('polls through pending and slow_down, then returns the token', () async {
      final answers = <Map<String, Object>>[
        {'error': 'authorization_pending'},
        {'error': 'slow_down', 'interval': 10},
        {'access_token': 'gho_abc', 'token_type': 'bearer'},
      ];
      final sleeps = <Duration>[];
      final flow = DeviceFlow(
        'cid',
        sleep: (d) async => sleeps.add(d),
        client: MockClient((req) async {
          if (req.url.path == '/login/device/code') {
            expect(req.bodyFields, {'client_id': 'cid', 'scope': 'repo'});
            return _json({'device_code': 'dc', 'user_code': 'ABCD-1234', 'verification_uri': 'https://github.com/login/device', 'interval': 5, 'expires_in': 900});
          }
          expect(req.bodyFields['device_code'], 'dc');
          return _json(answers.removeAt(0));
        }),
      );
      final code = await flow.start();
      expect(code.userCode, 'ABCD-1234');
      expect(await flow.awaitToken(code), 'gho_abc');
      expect(sleeps.map((d) => d.inSeconds), [5, 5, 10]);
    });

    test('access_denied and cancellation', () async {
      final denied = DeviceFlow('c', sleep: (_) async {}, client: MockClient((_) async => _json({'error': 'access_denied'})));
      const code = DeviceCode(deviceCode: 'd', userCode: 'u', verificationUri: 'v', interval: 1, expiresIn: 60);
      await expectLater(denied.awaitToken(code), throwsA(isA<DeviceFlowException>()));

      final pending = DeviceFlow('c', sleep: (_) async {}, client: MockClient((_) async => _json({'error': 'authorization_pending'})));
      expect(await pending.awaitToken(code, cancelled: () => true), isNull);
    });
  });
}
