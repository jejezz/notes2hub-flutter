import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes2hub/sync/file_limit.dart';

void main() {
  test('raiseOpenFileLimit does not throw', () {
    raiseOpenFileLimit();
    final files = <RandomAccessFile>[];
    try {
      for (var i = 0; i < 300; i++) {
        files.add(File(Platform.resolvedExecutable).openSync());
      }
    } finally {
      for (final f in files) {
        f.closeSync();
      }
    }
  }, skip: Platform.isWindows);
}
