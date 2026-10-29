import 'dart:async';

import 'note.dart';
import 'reminder_notifications.dart';
import 'notes_controller.dart';

/// 알람 시각이 된 메모를 알려준다. 앱이 켜져 있는 동안만 동작한다 (OS 예약 알림은 쓰지 않는다).
///
/// 시각 지정 타이머 대신 짧은 주기로 현재 시각을 확인한다 — 절전·시계 변경 뒤에도 놓치지 않는다.
/// 앱이 꺼져 있던 사이에 지난 알람은 켤 때 한꺼번에 나온다. 확인(알람 끄기)은 [NotesController.setReminder]로
/// 하며, 확인하지 않고 창만 닫은 알람은 이번 실행 동안 다시 띄우지 않는다.
class ReminderService {
  ReminderService(this._notes, {this.interval = const Duration(seconds: 15), DateTime Function()? clock, this.scheduler})
    : _clock = clock ?? DateTime.now;

  final NotesController _notes;

  /// OS에 알림을 예약한다 (앱이 꺼져 있어도 울리게). null이면 앱 안 알람만.
  final ReminderScheduler? scheduler;
  String? _scheduledSignature;
  final Duration interval;
  final DateTime Function() _clock;

  final _due = StreamController<Note>.broadcast();
  final Set<String> _announced = {};
  Timer? _timer;

  /// 알람이 울릴 메모. 같은 알람(메모+시각)은 한 번만 나온다.
  Stream<Note> get due => _due.stream;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => check());
    _notes.addListener(check); // 동기화로 받은 알람·방금 맞춘 알람을 바로 확인
    check();
  }

  /// 지금 울려야 할 알람이 있으면 내보낸다.
  void check() {
    final now = _clock();
    final due = _notes.dueReminders(now);
    // 끝났거나 시각이 바뀐 알람은 기억에서 지운다 (같은 메모에 새 알람을 맞출 수 있게).
    _announced.removeWhere((k) => !due.any((n) => _key(n) == k));
    for (final n in due) {
      if (_announced.add(_key(n))) _due.add(n);
    }
    _syncScheduler(now);
  }

  /// 앞으로 올 알람 목록이 바뀐 때만 OS 예약을 갱신한다 (편집할 때마다 불리지 않게).
  void _syncScheduler(DateTime now) {
    final s = scheduler;
    if (s == null) return;
    final upcoming = _notes.upcomingReminders(now);
    final signature = [for (final n in upcoming) _key(n)].join('|');
    if (signature == _scheduledSignature) return;
    _scheduledSignature = signature;
    s.replaceAll(upcoming);
  }

  String _key(Note n) => '${n.id}@${n.remindAt!.toUtc().toIso8601String()}';

  void dispose() {
    _timer?.cancel();
    _notes.removeListener(check);
    _due.close();
  }
}
