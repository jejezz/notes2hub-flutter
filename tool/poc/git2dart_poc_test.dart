import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'git2dart_poc.dart';

void main() {
  test('git2dart sync flow (clone/commit/merge/conflict/push) with local bare origin', () {
    final failures = runPoc(Directory.systemTemp.createTempSync('notes2hub-poc'));
    expect(failures, 0);
  });
}
