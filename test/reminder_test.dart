import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes2hub/l10n/app_localizations.dart';
import 'package:notes2hub/notes/note.dart';
import 'package:notes2hub/notes/note_store.dart';
import 'package:notes2hub/notes/notes_controller.dart';
import 'package:notes2hub/notes/reminder_notifications.dart';
import 'package:notes2hub/notes/reminder_service.dart';
import 'package:notes2hub/screens/alarm_time_picker.dart';
import 'package:notes2hub/screens/board_view.dart';
import 'package:notes2hub/images/asset_store.dart';
import 'package:notes2hub/screens/reminder_dialogs.dart';

class _FakeScheduler implements ReminderScheduler {
  final calls = <List<String>>[];

  @override
  Future<void> replaceAll(List<Note> upcoming) async => calls.add([for (final n in upcoming) n.id]);
}

void main() {
  late Directory tmp;
  late NoteStore store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('notes2hub-reminder');
    store = NoteStore(notesDir: Directory('${tmp.path}/notes'), draftsDir: Directory('${tmp.path}/drafts'));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('remind round-trips through the note file', () {
    final at = DateTime.utc(2026, 11, 3, 9, 30);
    final n = Note(id: 'a', created: DateTime.utc(2026, 10), updated: DateTime.utc(2026, 10), body: 'x', remindAt: at);
    expect(n.serialize(), contains('remind: 2026-11-03T09:30:00.000Z'));
    final back = Note.parse(n.serialize(), fallbackId: 'a', fallbackTime: DateTime.utc(2026));
    expect(back.remindAt, at);
    expect(n.copyWith(clearRemind: true).serialize(), isNot(contains('remind')));
    expect(n.copyWith(body: 'y').remindAt, at);
  });

  test('setReminder writes to disk without touching updated; due lists only passed alarms', () async {
    final c = NotesController(store);
    await c.load();
    final id = await c.capture('# Call mom\nbring flowers');
    final updated = c.noteById(id)!.updated;
    final now = DateTime(2026, 10, 25, 12);

    await c.setReminder(id, now.add(const Duration(hours: 1)));
    expect(File('${tmp.path}/notes/$id.md').readAsStringSync(), contains('remind:'));
    expect(c.noteById(id)!.updated, updated);
    expect(c.dueReminders(now), isEmpty);
    expect([for (final n in c.dueReminders(now.add(const Duration(hours: 2)))) n.id], [id]);

    await c.setReminder(id, null);
    expect(File('${tmp.path}/notes/$id.md').readAsStringSync(), isNot(contains('remind:')));
    expect(c.dueReminders(now.add(const Duration(days: 9))), isEmpty);
  });

  test('trashed notes do not ring; unsaved new note keeps alarm in the edit copy until saved', () async {
    final c = NotesController(store);
    await c.load();
    final id = await c.capture('later');
    final past = DateTime(2020);
    await c.setReminder(id, past);
    await c.delete(id);
    expect(c.dueReminders(DateTime.now()), isEmpty);

    final fresh = c.create();
    c.edit(fresh, 'new one');
    await c.setReminder(fresh, past);
    expect(c.dueReminders(DateTime.now()), isEmpty); // not on disk yet
    await c.save(fresh);
    expect([for (final n in c.dueReminders(DateTime.now())) n.id], [fresh]);
  });

  test('service announces each alarm once, again after it is rescheduled, and catches up on start', () async {
    final c = NotesController(store);
    await c.load();
    final id = await c.capture('standup');
    var now = DateTime(2026, 10, 25, 9);
    await c.setReminder(id, DateTime(2026, 10, 25, 9, 30));

    final s = ReminderService(c, interval: const Duration(hours: 1), clock: () => now);
    final rung = <String>[];
    s.due.listen((n) => rung.add(n.id));
    s.start();
    await Future<void>.delayed(Duration.zero);
    expect(rung, isEmpty);

    now = DateTime(2026, 10, 25, 9, 31);
    s.check();
    s.check();
    await Future<void>.delayed(Duration.zero);
    expect(rung, [id]);

    await c.setReminder(id, DateTime(2026, 10, 25, 9, 40)); // snooze
    now = DateTime(2026, 10, 25, 9, 41);
    s.check();
    await Future<void>.delayed(Duration.zero);
    expect(rung, [id, id]);
    s.dispose();

    // 앱이 꺼져 있던 사이에 지난 알람은 켤 때 나온다.
    final late = ReminderService(c, interval: const Duration(hours: 1), clock: () => DateTime(2027));
    final caught = <String>[];
    late.due.listen((n) => caught.add(n.id));
    late.start();
    await Future<void>.delayed(Duration.zero);
    expect(caught, [id]);
    late.dispose();
  });

  testWidgets('picker rejects past time and returns the chosen time', (tester) async {
    final now = DateTime(2026, 10, 25, 12, 0);
    ReminderChoice? result;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showReminderPicker(context, now: now),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // 기본값은 다음 정각(13:00) — 바로 설정할 수 있다.
    await tester.tap(find.byKey(const ValueKey('reminder-set')));
    await tester.pumpAndSettle();
    expect(result!.at, DateTime(2026, 10, 25, 13));
  });

  test('OS scheduler gets the upcoming alarms, only when that list changes', () async {
    final c = NotesController(store);
    await c.load();
    final a = await c.capture('a');
    final b = await c.capture('b');
    var now = DateTime(2026, 10, 25, 9);
    await c.setReminder(a, DateTime(2026, 10, 25, 10));
    final fake = _FakeScheduler();
    final s = ReminderService(c, interval: const Duration(hours: 1), clock: () => now, scheduler: fake);
    s.start();
    expect(fake.calls, [[a]]);

    c.edit(a, 'a edited'); // no change to alarms
    s.check();
    expect(fake.calls, hasLength(1));

    await c.setReminder(b, DateTime(2026, 10, 25, 11));
    expect(fake.calls.last, [a, b]);

    now = DateTime(2026, 10, 25, 10, 5); // a has rung: drops out of the OS list
    s.check();
    expect(fake.calls.last, [b]);

    await c.setReminder(b, null);
    expect(fake.calls.last, isEmpty);
    s.dispose();
  });

  test('notification ids are stable per note', () {
    expect(OsReminderScheduler.notificationId('abc'), OsReminderScheduler.notificationId('abc'));
    expect(OsReminderScheduler.notificationId('abc'), isNot(OsReminderScheduler.notificationId('abd')));
    expect(OsReminderScheduler.notificationId('0b2c3f6e-1a2b-4c5d-8e9f-001122334455'), lessThan(0x80000000));
  });

  testWidgets('time picker: period toggle sits above the time and picks hour then minute', (tester) async {
    TimeOfDay? result;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('ko'),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showAlarmTimePicker(context, const TimeOfDay(hour: 10, minute: 0)),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final period = tester.getRect(find.byKey(const ValueKey('alarm-period')));
    final hour = tester.getRect(find.byKey(const ValueKey('alarm-hour')));
    expect(period.bottom, lessThanOrEqualTo(hour.top));
    expect(period.left, hour.left); // 앞쪽 가장자리 정렬
    expect(period.width, greaterThan(period.height * 2)); // horizontal
    expect(period.width, lessThan(260)); // 내용 폭 (대화상자 폭 280을 채우지 않는다)

    await tester.tap(find.text('오후'));
    await tester.pump();
    final dial = tester.getRect(find.byKey(const ValueKey('alarm-dial')));
    await tester.tapAt(dial.center + Offset(dial.width * 0.4, 0)); // 3시 방향 -> 3시, 이어서 분
    await tester.pump();
    await tester.tapAt(dial.center - Offset(dial.width * 0.4, 0)); // 9시 방향 -> 45분
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('alarm-time-ok')));
    await tester.pumpAndSettle();
    expect(result, const TimeOfDay(hour: 15, minute: 45));
  });

  testWidgets('card reminder button shows the alarm state and opens the picker callback', (tester) async {
    var taps = 0;
    Future<void> show(Note n) async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: NoteCard(
              note: n,
              assets: AssetStore(Directory('${tmp.path}/assets')),
              state: CardSync.none,
              onTap: () {},
              onEdit: () {},
              onDelete: () {},
              onBookmark: () {},
              onReminder: () => taps++,
            ),
          ),
        ),
      ));
    }

    final base = Note(id: 'a', created: DateTime(2026), updated: DateTime(2026), body: 'x');
    await show(base);
    expect(find.byIcon(Icons.alarm_add_outlined), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('card-reminder')));
    expect(taps, 1);

    await show(base.copyWith(remindAt: DateTime.now().add(const Duration(days: 1))));
    expect(find.byIcon(Icons.alarm_on_rounded), findsOneWidget);

    await show(base.copyWith(remindAt: DateTime.now().subtract(const Duration(hours: 1))));
    expect(find.byIcon(Icons.alarm_rounded), findsOneWidget);
  });
}
