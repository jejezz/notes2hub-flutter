import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

/// 빠른 메모 전역 단축키(macOS ⌃⌥N). 다른 앱을 쓰는 중에도 눌러서 메모 입력창을 띄운다.
///
/// 단축키 등록은 macOS 네이티브(Carbon `RegisterEventHotKey`, `AppDelegate.swift`)가 하고 채널
/// `notes2hub/hotkey`로 눌렸음을 알려준다. 앱이 실행 중일 때만 동작한다 (창을 닫으면 앱이 종료된다).
/// Linux는 hotkey 라이브러리가 keybinder-3.0을 필수로 요구해서, Windows는 아직 구현하지 않아 지원하지 않는다.
class QuickCaptureHotkey extends ChangeNotifier {
  QuickCaptureHotkey({
    required this._prefs,
    this._channel = const MethodChannel('notes2hub/hotkey'),
    bool? supported,
    QuickCaptureWindow? window,
  }) : supported = supported ?? Platform.isMacOS,
       window = window ?? DesktopQuickCaptureWindow() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pressed' && _enabled) _triggers.add(null);
    });
  }

  static const _kEnabled = 'quick_capture_hotkey';

  /// 사용자에게 보여 주는 단축키 이름.
  static const label = '⌃⌥N';

  final SharedPreferences _prefs;
  final MethodChannel _channel;
  final StreamController<void> _triggers = StreamController<void>.broadcast();

  /// 이 플랫폼에서 지원하는가 — 아니면 설정에 항목도 보이지 않는다.
  final bool supported;

  /// 창을 앞으로 가져오고 다시 치우는 일 (테스트에서는 가짜로 바꾼다).
  final QuickCaptureWindow window;

  bool _registered = false;

  bool get _enabled => supported && enabled;

  /// 사용자가 켜 두었는가 (기본 켬).
  bool get enabled => _prefs.getBool(_kEnabled) ?? true;

  /// 시스템에 실제로 등록됐는가. 켜 두었는데 false면 다른 앱이 이미 같은 단축키를 쓰고 있다.
  bool get registered => _registered;

  /// 단축키가 눌렸다.
  Stream<void> get triggers => _triggers.stream;

  Future<void> init() async {
    if (_enabled) await _register();
  }

  Future<void> setEnabled(bool value) async {
    await _prefs.setBool(_kEnabled, value);
    if (!supported) return;
    if (value) {
      await _register();
    } else {
      await _unregister();
    }
    notifyListeners();
  }

  Future<void> _register() async {
    try {
      _registered = await _channel.invokeMethod<bool>('register') ?? false;
    } on PlatformException {
      _registered = false;
    } on MissingPluginException {
      _registered = false;
    }
    notifyListeners();
  }

  Future<void> _unregister() async {
    try {
      await _channel.invokeMethod<void>('unregister');
    } on PlatformException {
      // 이미 해제된 것으로 본다.
    } on MissingPluginException {
      // 같다.
    }
    _registered = false;
  }

  @override
  void dispose() {
    _triggers.close();
    super.dispose();
  }
}

/// 빠른 메모를 위해 창을 앞으로 가져왔다가, 쓰고 나면 원래대로 되돌리는 일.
abstract class QuickCaptureWindow {
  /// 앱이 지금 맨 앞에서 쓰이고 있는가.
  Future<bool> isActive();

  /// 창을 (최소화돼 있으면 복원하고) 앞으로 가져온다.
  Future<void> raise();

  /// 단축키로 불러냈던 창을 다시 치운다 — 쓰던 앱으로 돌아가게.
  Future<void> putAway();
}

class DesktopQuickCaptureWindow implements QuickCaptureWindow {
  @override
  Future<bool> isActive() async =>
      await windowManager.isFocused() && !await windowManager.isMinimized();

  @override
  Future<void> raise() async {
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> putAway() => windowManager.minimize();
}
