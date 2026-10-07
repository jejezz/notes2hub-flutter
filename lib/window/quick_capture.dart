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
  static const _kKeepRunning = 'quick_capture_keep_running';

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

  /// 창을 닫아도 앱을 백그라운드에 남기는가 (기본 켬). 단축키가 켜져 있고 실제로 등록된 경우에만 적용된다 —
  /// 단축키를 받지 못하는데 숨어 있기만 하면 쓸모가 없다.
  bool get keepRunning => _prefs.getBool(_kKeepRunning) ?? true;

  bool get _keeping => _enabled && _registered && keepRunning;

  /// 시스템에 실제로 등록됐는가. 켜 두었는데 false면 다른 앱이 이미 같은 단축키를 쓰고 있다.
  bool get registered => _registered;

  /// 단축키가 눌렸다.
  Stream<void> get triggers => _triggers.stream;

  Future<void> init() async {
    if (_enabled) await _register();
    await window.keepOnClose(_keeping);
  }

  Future<void> setKeepRunning(bool value) async {
    await _prefs.setBool(_kKeepRunning, value);
    await window.keepOnClose(_keeping);
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    await _prefs.setBool(_kEnabled, value);
    if (!supported) return;
    if (value) {
      await _register();
    } else {
      await _unregister();
    }
    await window.keepOnClose(_keeping);
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

/// 단축키를 누른 순간 창이 어떤 상태였나 — 끝난 뒤 그 상태로 되돌리기 위해 기억한다.
enum QuickCaptureWindowState {
  /// 앞에서 쓰고 있었다 (되돌릴 것이 없다).
  active,

  /// 보이지만 다른 앱 뒤에 있거나 최소화돼 있었다.
  background,

  /// 창을 닫아 백그라운드로 숨겨 둔 상태였다.
  hidden,
}

/// 빠른 메모를 위해 창을 앞으로 가져왔다가, 쓰고 나면 원래대로 되돌리는 일.
abstract class QuickCaptureWindow {
  Future<QuickCaptureWindowState> state();

  /// 창을 (숨겨져 있으면 보이고 최소화돼 있으면 복원해서) 앞으로 가져온다.
  Future<void> raise();

  /// 단축키로 불러냈던 창을 [before] 상태로 되돌린다 — 쓰던 앱으로 돌아가게.
  Future<void> putAway(QuickCaptureWindowState before);

  /// true면 창의 닫기 버튼이 앱을 끝내지 않고 창만 숨긴다 (백그라운드에서 단축키를 계속 받는다).
  Future<void> keepOnClose(bool keep);
}

class DesktopQuickCaptureWindow
    with WindowListener
    implements QuickCaptureWindow {
  bool _listening = false;

  @override
  Future<QuickCaptureWindowState> state() async {
    if (!await windowManager.isVisible()) return QuickCaptureWindowState.hidden;
    if (await windowManager.isFocused() && !await windowManager.isMinimized())
      return QuickCaptureWindowState.active;
    return QuickCaptureWindowState.background;
  }

  @override
  Future<void> raise() async {
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> putAway(QuickCaptureWindowState before) => switch (before) {
    QuickCaptureWindowState.active => Future.value(),
    QuickCaptureWindowState.background => windowManager.minimize(),
    QuickCaptureWindowState.hidden => windowManager.hide(),
  };

  @override
  Future<void> keepOnClose(bool keep) async {
    if (keep && !_listening) {
      windowManager.addListener(this);
      _listening = true;
    }
    await windowManager.setPreventClose(keep);
    // 창을 숨기면 macOS가 "마지막 창이 닫혔다"고 보고 앱을 끝낸다 — 네이티브에서 그 규칙을 끈다.
    try {
      await const MethodChannel('notes2hub/hotkey').invokeMethod<void>('keepRunning', keep);
    } on MissingPluginException {
      // macOS 밖에서는 이 채널이 없다.
    }
  }

  /// [keepOnClose]가 켜져 있을 때만 불린다 (preventClose).
  @override
  void onWindowClose() => windowManager.hide();
}
