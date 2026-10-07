import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes2hub/auth/token_store.dart';
import 'package:notes2hub/images/asset_store.dart';
import 'package:notes2hub/l10n/app_localizations.dart';
import 'package:notes2hub/notes/note_store.dart';
import 'package:notes2hub/notes/notes_controller.dart';
import 'package:notes2hub/screens/notes_screen.dart';
import 'package:notes2hub/settings/app_settings.dart';
import 'package:notes2hub/sync/sync_service.dart';
import 'package:notes2hub/window/quick_capture.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

class _FakeWindow implements QuickCaptureWindow {
  QuickCaptureWindowState current = QuickCaptureWindowState.background;
  final calls = <String>[];
  final keep = <bool>[];

  @override
  Future<QuickCaptureWindowState> state() async => current;

  @override
  Future<void> raise() async => calls.add('raise');

  @override
  Future<void> putAway(QuickCaptureWindowState before) async =>
      calls.add('putAway:${before.name}');

  @override
  Future<void> keepOnClose(bool value) async => keep.add(value);
}

const _channel = MethodChannel('notes2hub/hotkey');

/// 네이티브가 "단축키가 눌렸다"고 알리는 것을 흉내 낸다.
Future<void> _press() => TestDefaultBinaryMessengerBinding
    .instance
    .defaultBinaryMessenger
    .handlePlatformMessage(
      _channel.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('pressed')),
      (_) {},
    );

void main() {
  late List<String> native;
  var registerResult = true;

  setUp(() {
    native = [];
    registerResult = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          native.add(call.method);
          return call.method == 'register' ? registerResult : null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );

  late _FakeWindow fakeWindow;

  Future<QuickCaptureHotkey> make({
    bool supported = true,
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    fakeWindow = _FakeWindow();
    return QuickCaptureHotkey(
      prefs: await SharedPreferences.getInstance(),
      supported: supported,
      window: fakeWindow,
    );
  }

  test('registers on init (default on), unregisters when switched off, and remembers the choice', () async {
    final q = await make();
    await q.init();
    expect(native, ['register']);
    expect(q.registered, isTrue);

    await q.setEnabled(false);
    expect(native, ['register', 'unregister']);
    expect(q.registered, isFalse);
    expect(q.enabled, isFalse);

    await q.setEnabled(true);
    expect(native.last, 'register');
    expect(q.enabled, isTrue);
  });

  test('a shortcut already taken by another app shows as enabled but not registered', () async {
    registerResult = false;
    final q = await make();
    await q.init();
    expect(q.enabled, isTrue);
    expect(q.registered, isFalse);
  });

  test('unsupported platforms and a switched-off setting never touch the native side', () async {
    final unsupported = await make(supported: false);
    await unsupported.init();
    await unsupported.setEnabled(true);
    expect(native, isEmpty);

    final off = await make(prefs: {'quick_capture_hotkey': false});
    await off.init();
    expect(native, isEmpty);
  });

  test('pressed events become triggers only while enabled', () async {
    final q = await make();
    await q.init();
    var n = 0;
    q.triggers.listen((_) => n++);
    await _press();
    await Future<void>.delayed(Duration.zero);
    expect(n, 1);
    await q.setEnabled(false);
    await _press();
    await Future<void>.delayed(Duration.zero);
    expect(n, 1);
  });

  test('closing the window keeps the app running only while the shortcut is on and really registered', () async {
    final q = await make();
    await q.init();
    expect(q.keepRunning, isTrue); // 기본 켬
    expect(fakeWindow.keep.last, isTrue);

    await q.setKeepRunning(false);
    expect(fakeWindow.keep.last, isFalse);
    await q.setKeepRunning(true);
    expect(fakeWindow.keep.last, isTrue);

    await q.setEnabled(false); // 단축키를 끄면 창을 닫을 때 앱이 끝난다
    expect(fakeWindow.keep.last, isFalse);
    await q.setEnabled(true);
    expect(fakeWindow.keep.last, isTrue);
  });

  test('a taken shortcut must not hide the app in the background', () async {
    registerResult = false;
    final q = await make();
    await q.init();
    expect(fakeWindow.keep, [false]);
  });

  test('an unsupported platform never changes how closing behaves', () async {
    final q = await make(supported: false);
    await q.init();
    expect(fakeWindow.keep.last, isFalse);
  });

  testWidgets(
    'the shortcut raises the window, saves the typed note, then puts the window away',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tmp = Directory.systemTemp.createTempSync('notes2hub-quick');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final c = NotesController(
        NoteStore(
          notesDir: Directory('${tmp.path}/notes'),
          draftsDir: Directory('${tmp.path}/drafts'),
        ),
      );
      SharedPreferences.setMockInitialValues({});
      final window = _FakeWindow();
      final q = (await tester.runAsync(
        () async => QuickCaptureHotkey(
          prefs: await SharedPreferences.getInstance(),
          supported: true,
          window: window,
        ),
      ))!;
      final sync = (await tester.runAsync(
        () async => SyncService(
          prefs: await SharedPreferences.getInstance(),
          tokens: MemoryTokenStore(),
          engine: FakeEngine(),
          notes: c,
          pullInterval: const Duration(hours: 1),
        ),
      ))!;
      final settings = (await tester.runAsync(AppSettings.load))!;
      addTearDown(() {
        sync.dispose();
        c.dispose();
        q.dispose();
      });
      await tester.runAsync(c.load);
      await tester.pumpWidget(
        AppSettingsScope(
          settings: settings,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: NotesScreen(
              controller: c,
              sync: sync,
              assets: AssetStore(Directory('${tmp.path}/assets')),
              onAbout: () {},
              quickCapture: q,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 보드 입력창에 쓰던 글은 그대로 남아야 한다.
      await tester.enterText(find.byType(TextField).first, 'half written');

      await tester.runAsync(_press);
      await tester.pumpAndSettle();
      expect(window.calls, ['raise']);
      expect(find.text('Quick note'), findsOneWidget);

      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'from anywhere',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();
      expect(find.text('Quick note'), findsNothing);
      expect(c.notes.map((n) => n.body), ['from anywhere']);
      expect(window.calls, [
        'raise',
        'putAway:background',
      ]); // 다른 앱을 쓰던 중에 불렀으니 다시 치운다
      expect(find.text('half written'), findsOneWidget);

      // 창을 숨겨 둔 채 불렀다면 끝난 뒤 다시 숨기고, 앞에서 쓰던 중이면 그대로 둔다.
      window.calls.clear();
      window.current = QuickCaptureWindowState.hidden;
      await tester.runAsync(_press);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(window.calls, ['raise', 'putAway:hidden']);

      window.calls.clear();
      window.current = QuickCaptureWindowState.active;
      await tester.runAsync(_press);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(window.calls, ['raise', 'putAway:active']);
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
