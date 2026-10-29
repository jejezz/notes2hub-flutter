import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../app_identity.dart';
import 'note.dart';

/// 앞으로 올 알람을 OS에 예약해 둔다 — 앱이 꺼져 있어도 시각이 되면 OS가 알림을 띄운다.
/// [ReminderService]가 알람이 바뀔 때마다 "지금 예약돼 있어야 할 전체 목록"을 넘긴다.
abstract class ReminderScheduler {
  /// 이전에 예약한 것을 모두 지우고 [upcoming](아직 오지 않은 알람)을 다시 예약한다.
  Future<void> replaceAll(List<Note> upcoming);
}

/// 알림 예약을 지원하는 플랫폼(Android·iOS·macOS)이면 [OsReminderScheduler], 아니면 null.
/// Windows·Linux는 플러그인이 예약 알림을 지원하지 않아서 앱이 켜져 있을 때의 알람만 동작한다.
ReminderScheduler? createOsReminderScheduler() {
  if (kIsWeb || !(Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) return null;
  return OsReminderScheduler(FlutterLocalNotificationsPlugin());
}

class OsReminderScheduler implements ReminderScheduler {
  OsReminderScheduler(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;
  Future<void>? _init;
  bool _permissionAsked = false;

  static const _channelId = 'reminders';

  Future<void> _ensureInit() => _init ??= _plugin
      .initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // 권한은 알람이 처음 생길 때 따로 묻는다.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          macOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      )
      .then((_) {});

  /// 알림 권한을 한 번 묻는다 (이미 정해졌으면 OS가 다시 묻지 않는다). Android는 정확한 알람 권한 여부를 돌려준다.
  Future<bool> _askPermission() async {
    if (_permissionAsked) return _canExact();
    _permissionAsked = true;
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      if (!await _canExact()) await android?.requestExactAlarmsPermission();
    } else if (Platform.isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, sound: true);
    } else if (Platform.isMacOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, sound: true);
    }
    return _canExact();
  }

  Future<bool> _canExact() async {
    if (!Platform.isAndroid) return true;
    return await _plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.canScheduleExactNotifications() ??
        false;
  }

  /// 메모 id(uuid 문자열)에서 알림 번호를 만든다 — 같은 메모는 항상 같은 번호라서 다시 예약하면 덮어쓴다.
  @visibleForTesting
  static int notificationId(String noteId) {
    var h = 0;
    for (final c in noteId.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }

  @override
  Future<void> replaceAll(List<Note> upcoming) async {
    try {
      await _ensureInit();
      await _plugin.cancelAllPendingNotifications();
      if (upcoming.isEmpty) return;
      final exact = await _askPermission();
      for (final n in upcoming) {
        final title = n.title.isEmpty ? AppIdentity.displayName : n.title;
        final body = n.excerpt(max: 120);
        await _plugin.zonedSchedule(
          id: notificationId(n.id),
          // UTC 기준의 절대 시각이라 시간대 데이터베이스가 필요 없다.
          scheduledDate: tz.TZDateTime.from(n.remindAt!, tz.UTC),
          title: title,
          body: body.isEmpty ? null : body,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              'Reminders',
              importance: Importance.high,
              priority: Priority.high,
              category: AndroidNotificationCategory.reminder,
            ),
            iOS: DarwinNotificationDetails(),
            macOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (e, st) {
      // 알림을 못 예약해도 앱 안 알람은 그대로 동작한다.
      debugPrint('reminder scheduling failed: $e\n$st');
    }
  }
}
