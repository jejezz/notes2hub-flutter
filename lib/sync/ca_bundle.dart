import 'dart:io';

import 'package:flutter/services.dart';

/// 번들한 CA 인증서를 디스크로 꺼내 경로를 돌려준다. libgit2는 에셋을 읽을 수 없고, 경로를
/// 주지 않으면 HTTPS가 "SSL certificate is invalid"로 실패한다 (docs/PLAN.md §3 PoC).
Future<String> ensureCaBundle(Directory base) async {
  final data = await rootBundle.load('assets/certs/cacert.pem');
  final file = File('${base.path}/cacert.pem');
  if (!await file.exists() || await file.length() != data.lengthInBytes) {
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
  }
  return file.path;
}
