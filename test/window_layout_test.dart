import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes2hub/window/window_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  // 메뉴 막대와 Dock을 뺀 1440x900 화면의 사용 영역
  const screen = Rect.fromLTWH(0, 25, 1440, 850);
  const second = Rect.fromLTWH(1440, 0, 1920, 1080);

  group('pure helpers', () {
    test('dockBounds fills the height and hugs the chosen edge', () {
      expect(dockBounds(screen, DockSide.left, 420), const Rect.fromLTWH(0, 25, 420, 850));
      expect(dockBounds(screen, DockSide.right, 420), const Rect.fromLTWH(1020, 25, 420, 850));
    });

    test('dockBounds clamps the width to [320, screen width]', () {
      expect(dockBounds(screen, DockSide.left, 100).width, 320);
      expect(dockBounds(screen, DockSide.left, 5000).width, 1440);
    });

    test('expandBounds keeps the docked edge fixed while the width grows', () {
      expect(expandBounds(screen, DockSide.left, 900), const Rect.fromLTWH(0, 25, 900, 850));
      final r = expandBounds(screen, DockSide.right, 900);
      expect(r.right, screen.right);
      expect(r.left, 540);
    });

    test('isAnchored tolerates width changes but not moves', () {
      expect(isAnchored(const Rect.fromLTWH(0, 25, 600, 850), screen, DockSide.left), isTrue);
      expect(isAnchored(const Rect.fromLTWH(840, 25, 600, 850), screen, DockSide.right), isTrue);
      expect(isAnchored(const Rect.fromLTWH(60, 25, 420, 850), screen, DockSide.left), isFalse);
      expect(isAnchored(const Rect.fromLTWH(0, 100, 420, 850), screen, DockSide.left), isFalse);
      expect(isAnchored(const Rect.fromLTWH(0, 25, 420, 500), screen, DockSide.left), isFalse);
      expect(isAnchored(screen, screen, DockSide.none), isFalse);
    });

    test('isVisibleEnough rejects windows left on a monitor that was unplugged', () {
      expect(isVisibleEnough(const Rect.fromLTWH(100, 100, 800, 600), [screen]), isTrue);
      expect(isVisibleEnough(const Rect.fromLTWH(2000, 100, 800, 600), [screen]), isFalse);
      expect(isVisibleEnough(const Rect.fromLTWH(2000, 100, 800, 600), [screen, second]), isTrue);
      expect(isVisibleEnough(const Rect.fromLTWH(1400, 100, 800, 600), [screen]), isFalse); // 40px sliver only
    });

    test('displayContaining picks the screen with the largest overlap', () {
      expect(displayContaining(const Rect.fromLTWH(1500, 100, 800, 600), [screen, second]), second);
      expect(displayContaining(const Rect.fromLTWH(100, 100, 800, 600), [screen, second]), screen);
      expect(displayContaining(const Rect.fromLTWH(9000, 9000, 10, 10), [screen, second]), screen);
    });
  });

  group('WindowLayout', () {
    late SharedPreferences prefs;
    late FakePort port;

    Future<WindowLayout> make({Map<String, Object> initial = const {}, List<Rect>? areas, Rect? current}) async {
      SharedPreferences.setMockInitialValues(initial);
      prefs = await SharedPreferences.getInstance();
      port = FakePort(areas ?? [screen], current ?? const Rect.fromLTWH(100, 100, 1200, 720));
      return WindowLayout(prefs: prefs, port: port, settleDelay: const Duration(milliseconds: 10));
    }

    test('first launch centers the default size on the first screen', () async {
      final w = await make();
      await w.restore();
      expect(port.current.size, const Size(1200, 720));
      expect(port.current.center, screen.center);
      w.dispose();
    });

    test('a saved window is restored; one that is off every screen falls back to the default', () async {
      var w = await make(initial: {'win_x': 50.0, 'win_y': 60.0, 'win_w': 900.0, 'win_h': 600.0});
      await w.restore();
      expect(port.current, const Rect.fromLTWH(50, 60, 900, 600));
      w.dispose();

      w = await make(initial: {'win_x': 5000.0, 'win_y': 60.0, 'win_w': 900.0, 'win_h': 600.0});
      await w.restore();
      expect(port.current.size, const Size(1200, 720));
      expect(isVisibleEnough(port.current, [screen]), isTrue);
      w.dispose();
    });

    test('moving or resizing the window saves its bounds (debounced)', () async {
      final w = await make();
      await w.restore();
      port.current = const Rect.fromLTWH(30, 40, 1000, 650);
      w.onWindowMoved();
      w.onWindowResized();
      await Future<void>.delayed(const Duration(milliseconds: 600)); // 무시 구간(settle+400ms)을 넘긴 뒤
      w.onWindowMoved();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(
        [prefs.getDouble('win_x'), prefs.getDouble('win_y'), prefs.getDouble('win_w'), prefs.getDouble('win_h')],
        [30, 40, 1000, 650],
      );
      w.dispose();
    });

    test('docking remembers the normal window, undocking brings it back', () async {
      final w = await make(current: const Rect.fromLTWH(200, 80, 1100, 700));
      await w.dockTo(DockSide.right);
      expect(w.dock, DockSide.right);
      expect(port.current, dockBounds(screen, DockSide.right, 420));
      await w.undock();
      expect(w.dock, DockSide.none);
      expect(port.current, const Rect.fromLTWH(200, 80, 1100, 700));
      w.dispose();
    });

    test('the dock is restored on the next launch, on the screen the window was on', () async {
      var w = await make(areas: [screen, second], current: const Rect.fromLTWH(1600, 100, 1100, 700));
      await w.dockTo(DockSide.left);
      expect(port.current, dockBounds(second, DockSide.left, 420));
      w.dispose();

      final again = WindowLayout(prefs: prefs, port: FakePort([screen, second], const Rect.fromLTWH(0, 0, 100, 100)));
      await again.restore();
      expect(again.dock, DockSide.left);
      again.dispose();
      w = again;
    });

    test('editing widens a docked window on its free side and the board collapses it again', () async {
      final w = await make();
      await w.dockTo(DockSide.left);
      await w.beginEditing();
      expect(w.expanded, isTrue);
      expect(port.current, expandBounds(screen, DockSide.left, 900));
      await w.endEditing();
      expect(w.expanded, isFalse);
      expect(port.current, dockBounds(screen, DockSide.left, 420));

      await w.dockTo(DockSide.right);
      await w.beginEditing();
      expect(port.current.right, screen.right); // anchored right, grows leftwards
      expect(port.current.width, 900);
      await w.endEditing();
      expect(port.current, dockBounds(screen, DockSide.right, 420));
      w.dispose();
    });

    test('an undocked window is never resized by editing', () async {
      final w = await make();
      await w.restore();
      final before = port.current;
      await w.beginEditing();
      await w.endEditing();
      expect(port.current, before);
      w.dispose();
    });

    test('auto-expand can be turned off', () async {
      final w = await make();
      await w.dockTo(DockSide.left);
      await w.setAutoExpand(false);
      await w.beginEditing();
      expect(w.expanded, isFalse);
      expect(port.current, dockBounds(screen, DockSide.left, 420));
      w.dispose();
    });

    test('a width the user dragged while docked or while editing is remembered separately', () async {
      final w = await make();
      await w.dockTo(DockSide.left);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      port.current = const Rect.fromLTWH(0, 25, 520, 850); // user widens the dock
      w.onWindowResized();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(w.dockWidth, 520);

      await w.beginEditing();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      port.current = const Rect.fromLTWH(0, 25, 1100, 850); // user widens the editor
      w.onWindowResized();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await w.endEditing();
      expect(w.editWidth, 1100);
      expect(port.current.width, 520);

      await w.beginEditing();
      expect(port.current.width, 1100); // remembered for next time
      w.dispose();
    });

    test('dragging a docked window away undocks it and keeps the new place as the normal window', () async {
      final w = await make();
      await w.dockTo(DockSide.left);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      port.current = const Rect.fromLTWH(300, 200, 420, 850); // moved off the edge
      w.onWindowMoved();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(w.dock, DockSide.none);
      expect(prefs.getString('win_dock'), 'none');
      expect(prefs.getDouble('win_x'), 300);
      w.dispose();
    });
  });
}
