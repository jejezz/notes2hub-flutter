// Network PoC: anonymous HTTPS clone of a public repo (verifies TLS in libgit2).
//   NOTES2HUB_POC_NET=1 flutter test tool/poc/https_clone_test.dart
// Authenticated push to GitHub (token) is verified separately by the user.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git2dart/git2dart.dart';

void main() {
  final enabled = Platform.environment['NOTES2HUB_POC_NET'] == '1';
  test('HTTPS clone of a public GitHub repo', () {
    // libgit2 has no CA store of its own here: without this the clone fails with
    // GIT_ERROR_SSL "the SSL certificate is invalid". git2dart_binaries ships
    // assets/certs/cacert.pem; the app must put it on disk and point libgit2 at it.
    final pem = Platform.environment['NOTES2HUB_CA_PEM'];
    if (pem != null) Libgit2.setSSLCertLocations(file: pem);
    final dir = Directory.systemTemp.createTempSync('notes2hub-https');
    try {
      final repo = Repository.clone(
        url: 'https://github.com/octocat/Hello-World.git',
        localPath: dir.path,
      );
      expect(File('${dir.path}/README').existsSync(), isTrue);
      repo.free();
    } finally {
      dir.deleteSync(recursive: true);
    }
  }, skip: enabled ? false : 'set NOTES2HUB_POC_NET=1');
}
