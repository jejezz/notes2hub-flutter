import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

/// 창을 화면 왼쪽/오른쪽 가장자리에 세로로 길게 붙이는 방식 (메모 앱의 사이드바 배치).
enum DockSide { none, left, right }

// ---- 순수 계산 (창·화면 API와 무관 — 단위 테스트 대상) ---------------------------------

/// [area](화면의 사용 가능한 영역)의 [side] 가장자리에 붙인 창 영역: 위아래를 꽉 채우고 폭만 [width].
Rect dockBounds(Rect area, DockSide side, double width, {double minWidth = 320}) {
  final w = width.clamp(math.min(minWidth, area.width), area.width).toDouble();
  final left = side == DockSide.right ? area.right - w : area.left;
  return Rect.fromLTWH(left, area.top, w, area.height);
}

/// 붙은 쪽 가장자리를 고정한 채 폭만 [width]로 늘린 영역 (편집 중 확장).
Rect expandBounds(Rect area, DockSide side, double width) => dockBounds(area, side, width, minWidth: 0);

/// [r]이 아직 [side] 가장자리에 붙어 있는가 (폭은 무관). 사용자가 창을 옮기면 false.
bool isAnchored(Rect r, Rect area, DockSide side, {double tolerance = 10}) {
  if (side == DockSide.none) return false;
  final edgeOk = side == DockSide.left ? (r.left - area.left).abs() <= tolerance : (r.right - area.right).abs() <= tolerance;
  return edgeOk && (r.top - area.top).abs() <= tolerance && (r.height - area.height).abs() <= tolerance;
}

/// 저장해 둔 창 위치가 연결된 화면 어딘가에서 충분히 보이는가 (모니터를 뺐을 때 창이 화면 밖에 남지 않게).
bool isVisibleEnough(Rect r, List<Rect> areas, {double minVisible = 120}) {
  for (final a in areas) {
    final i = r.intersect(a);
    if (i.width >= minVisible && i.height >= minVisible) return true;
  }
  return false;
}

/// [r]이 가장 많이 걸쳐 있는 화면 (없으면 첫 화면).
Rect displayContaining(Rect r, List<Rect> areas) {
  var best = areas.first;
  var bestArea = -1.0;
  for (final a in areas) {
    final i = r.intersect(a);
    final size = (i.width > 0 && i.height > 0) ? i.width * i.height : 0.0;
    if (size > bestArea) {
      bestArea = size;
      best = a;
    }
  }
  return best;
}

// ---- 창 API 어댑터 -------------------------------------------------------------------

abstract class WindowPort {
  Future<Rect> bounds();
  Future<void> setBounds(Rect r);

  /// 각 화면에서 메뉴 막대·Dock·작업 표시줄을 뺀 사용 가능 영역 (창 좌표계).
  Future<List<Rect>> visibleAreas();

  /// 기본 크기(논리 단위)에 곱할 배율. 좌표를 물리 픽셀로 다루는 포트(Windows)만 1이 아니다.
  Future<double> referenceScale() async => 1;
}

class DesktopWindowPort implements WindowPort {
  /// Windows는 모니터마다 배율(DPI)이 달라서 `window_manager`(창이 놓인 모니터의 배율로 나눈 값)와
  /// `screen_retriever`(각 모니터를 자기 배율로 나눈 값)의 논리 좌표가 서로 맞지 않는다. 그래서
  /// Windows에서는 모든 좌표·크기를 **물리 픽셀**로 바꿔 다루고, 창을 옮길 때만 현재 배율로 되돌려 준다.
  static bool get _physical => Platform.isWindows;

  double get _dpr => PlatformDispatcher.instance.views.first.devicePixelRatio;

  @override
  Future<Rect> bounds() async {
    final r = await windowManager.getBounds();
    if (!_physical) return r;
    final s = _dpr;
    return Rect.fromLTWH(r.left * s, r.top * s, r.width * s, r.height * s);
  }

  @override
  Future<void> setBounds(Rect r) async {
    if (!_physical) return windowManager.setBounds(r);
    // 다른 배율의 모니터로 넘어가면 창의 배율이 바뀌고 시스템이 크기를 다시 맞춘다 — 바뀐 배율로 한 번 더 지정한다.
    for (var i = 0; i < 3; i++) {
      final s = _dpr;
      await windowManager.setBounds(Rect.fromLTWH(r.left / s, r.top / s, r.width / s, r.height / s));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if ((_dpr - s).abs() < 0.01) break;
    }
  }

  @override
  Future<List<Rect>> visibleAreas() async {
    final displays = await screenRetriever.getAllDisplays();
    return [
      for (final d in displays)
        () {
          final s = _physical ? (d.scaleFactor?.toDouble() ?? 1.0) : 1.0;
          final pos = d.visiblePosition ?? Offset.zero;
          final size = d.visibleSize ?? d.size;
          return Rect.fromLTWH(pos.dx * s, pos.dy * s, size.width * s, size.height * s);
        }(),
    ];
  }

  @override
  Future<double> referenceScale() async {
    if (!_physical) return 1;
    final d = await screenRetriever.getPrimaryDisplay();
    return d.scaleFactor?.toDouble() ?? 1;
  }
}

/// 창 크기·위치 기억, 좌/우 도킹, 편집 중 자동 확장.
///
///  * 일반 창: 크기와 위치를 저장해 다음 실행 때 되돌린다 (화면 밖이면 기본 위치).
///  * 도킹: 화면 왼쪽/오른쪽에 위아래를 꽉 채워 붙인다. 폭은 기억한다. 창을 직접 옮기면 도킹이 풀린다.
///  * 편집 중 확장: 도킹된 상태에서 메모를 열면 붙은 가장자리를 고정한 채 폭을 늘리고, 보드로 돌아오면
///    원래 폭으로 되돌린다. 편집 중에 사용자가 폭을 바꾸면 그 폭을 다음 편집 때 쓴다.
class WindowLayout extends ChangeNotifier with WindowListener {
  WindowLayout({
    required this._prefs,
    required this._port,
    this.baseSize = const Size(1200, 720),
    this.baseDockWidth = 420,
    this.baseEditWidth = 900,
    this.settleDelay = const Duration(milliseconds: 350),
  });

  static const _kX = 'win_x', _kY = 'win_y', _kW = 'win_w', _kH = 'win_h';
  static const _kDock = 'win_dock', _kDockW = 'win_dock_w', _kEditW = 'win_edit_w', _kAuto = 'win_auto_expand';
  // 도킹한 화면을 기억하는 기준점(창 중심). 일반 창 위치(_kX…)는 도킹 전 화면이라 다중 모니터에서 어긋난다.
  static const _kDockCx = 'win_dock_cx', _kDockCy = 'win_dock_cy';

  final SharedPreferences _prefs;
  final WindowPort _port;
  final Size baseSize;
  final double baseDockWidth;
  final double baseEditWidth;
  double _scale = 1;

  Size get defaultSize => baseSize * _scale;
  double get defaultDockWidth => baseDockWidth * _scale;
  double get defaultEditWidth => baseEditWidth * _scale;
  final Duration settleDelay;

  DockSide _dock = DockSide.none;
  bool _expanded = false;
  Timer? _settle;
  DateTime _ignoreEventsUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool _disposed = false;

  DockSide get dock => _dock;
  bool get docked => _dock != DockSide.none;

  /// 지금 편집을 위해 넓혀진 상태인가.
  bool get expanded => _expanded;

  double get dockWidth => _prefs.getDouble(_kDockW) ?? defaultDockWidth;
  double get editWidth => _prefs.getDouble(_kEditW) ?? defaultEditWidth;

  /// 도킹 상태에서 메모를 열 때 자동으로 넓힌다 (기본 켜짐).
  bool get autoExpand => _prefs.getBool(_kAuto) ?? true;

  Rect? get _savedNormal {
    final x = _prefs.getDouble(_kX), y = _prefs.getDouble(_kY), w = _prefs.getDouble(_kW), h = _prefs.getDouble(_kH);
    if (x == null || y == null || w == null || h == null || w < 200 || h < 200) return null;
    return Rect.fromLTWH(x, y, w, h);
  }

  Future<void> _saveNormal(Rect r) async {
    await _prefs.setDouble(_kX, r.left);
    await _prefs.setDouble(_kY, r.top);
    await _prefs.setDouble(_kW, r.width);
    await _prefs.setDouble(_kH, r.height);
  }

  Future<void> _saveDockAnchor(Rect r) async {
    await _prefs.setDouble(_kDockCx, r.center.dx);
    await _prefs.setDouble(_kDockCy, r.center.dy);
  }

  Rect? get _savedDockAnchor {
    final x = _prefs.getDouble(_kDockCx), y = _prefs.getDouble(_kDockCy);
    return x == null || y == null ? null : Rect.fromLTWH(x, y, 1, 1);
  }

  /// 도킹된 창이 놓였던 화면. 기준점이 지금 어느 화면에도 없으면(모니터를 뺐을 때) 첫 화면.
  Rect _dockArea(List<Rect> areas) {
    final anchor = _savedDockAnchor ?? _savedNormal;
    if (anchor == null) return areas.first;
    final hit = areas.where((a) => a.overlaps(anchor) || a.contains(anchor.topLeft));
    return hit.isEmpty ? areas.first : hit.first;
  }

  Future<void> _apply(Rect r) async {
    // 우리가 일으킨 이동·크기 변경 이벤트를 사용자가 옮긴 것으로 오해하지 않게 잠시 무시한다.
    _ignoreEventsUntil = DateTime.now().add(settleDelay + const Duration(milliseconds: 400));
    await _port.setBounds(r);
    _ignoreEventsUntil = DateTime.now().add(settleDelay + const Duration(milliseconds: 400));
  }

  Future<List<Rect>> _areas() async {
    final a = await _port.visibleAreas();
    return a.isEmpty ? [Offset.zero & const Size(1440, 900)] : a;
  }

  /// 시작할 때, 창을 보이기 전에 부른다.
  Future<void> restore() async {
    _scale = await _port.referenceScale();
    final areas = await _areas();
    final saved = _savedNormal;
    _dock = switch (_prefs.getString(_kDock)) {
      'left' => DockSide.left,
      'right' => DockSide.right,
      _ => DockSide.none,
    };
    if (_dock != DockSide.none) {
      await _apply(dockBounds(_dockArea(areas), _dock, dockWidth));
    } else if (saved != null && isVisibleEnough(saved, areas)) {
      await _apply(saved);
    } else {
      final area = areas.first;
      final size = Size(
        math.min(defaultSize.width, area.width),
        math.min(defaultSize.height, area.height),
      );
      await _apply(Rect.fromLTWH(
        area.left + (area.width - size.width) / 2,
        area.top + (area.height - size.height) / 2,
        size.width,
        size.height,
      ));
    }
    notifyListeners();
  }

  Future<void> dockTo(DockSide side) async {
    if (side == DockSide.none) return undock();
    final cur = await _port.bounds();
    final areas = await _areas();
    if (_dock == DockSide.none) await _saveNormal(cur); // 되돌아갈 일반 창 크기
    final area = displayContaining(cur, areas);
    _dock = side;
    _expanded = false;
    await _prefs.setString(_kDock, side.name);
    final target = dockBounds(area, side, dockWidth);
    await _saveDockAnchor(target);
    await _apply(target);
    notifyListeners();
  }

  Future<void> undock() async {
    if (_dock == DockSide.none) return;
    final cur = await _port.bounds();
    final areas = await _areas();
    final area = displayContaining(cur, areas);
    _dock = DockSide.none;
    _expanded = false;
    await _prefs.setString(_kDock, 'none');
    final saved = _savedNormal;
    if (saved != null && isVisibleEnough(saved, areas)) {
      await _apply(saved);
    } else {
      await _apply(Rect.fromCenter(center: area.center, width: math.min(defaultSize.width, area.width), height: math.min(defaultSize.height, area.height)));
    }
    notifyListeners();
  }

  /// 메모 편집 화면이 열릴 때: 도킹된 창이면 붙은 쪽을 고정한 채 폭을 넓힌다.
  Future<void> beginEditing() async {
    if (!docked || _expanded || !autoExpand) return;
    final cur = await _port.bounds();
    final area = displayContaining(cur, await _areas());
    _expanded = true;
    await _apply(expandBounds(area, _dock, math.max(editWidth, cur.width)));
    notifyListeners();
  }

  /// 보드로 돌아올 때: 넓혔던 창을 원래 도킹 폭으로 되돌린다.
  Future<void> endEditing() async {
    if (!_expanded) return;
    final cur = await _port.bounds();
    final area = displayContaining(cur, await _areas());
    // 편집 중에 사용자가 폭을 바꿨다면 다음 편집 때도 그 폭을 쓴다.
    if (isAnchored(cur, area, _dock) && (cur.width - editWidth).abs() > 8) {
      await _prefs.setDouble(_kEditW, cur.width);
    }
    _expanded = false;
    await _apply(dockBounds(area, _dock, dockWidth));
    notifyListeners();
  }

  Future<void> setAutoExpand(bool value) async {
    await _prefs.setBool(_kAuto, value);
    if (!value) await endEditing();
    notifyListeners();
  }

  // ---- 창 이벤트: 사용자가 옮기거나 크기를 바꾸면 저장한다 -----------------------------------

  @override
  void onWindowMoved() => _scheduleSettle();

  @override
  void onWindowResized() => _scheduleSettle();

  @override
  void onWindowMove() => _scheduleSettle();

  @override
  void onWindowResize() => _scheduleSettle();

  void _scheduleSettle() {
    if (_disposed || DateTime.now().isBefore(_ignoreEventsUntil)) return;
    _settle?.cancel();
    _settle = Timer(settleDelay, () => unawaited(_settleNow()));
  }

  Future<void> _settleNow() async {
    if (_disposed || DateTime.now().isBefore(_ignoreEventsUntil)) return;
    final cur = await _port.bounds();
    final areas = await _areas();
    final area = displayContaining(cur, areas);
    if (_dock != DockSide.none) {
      if (isAnchored(cur, area, _dock)) {
        // 가장자리에 붙은 채 폭만 바꾼 것 — 폭을 기억한다.
        await _prefs.setDouble(_expanded ? _kEditW : _kDockW, cur.width);
        await _saveDockAnchor(cur);
      } else {
        // 사용자가 창을 떼어 옮겼다 → 도킹 해제, 지금 위치를 일반 창으로 기억한다.
        _dock = DockSide.none;
        _expanded = false;
        await _prefs.setString(_kDock, 'none');
        await _saveNormal(cur);
        notifyListeners();
      }
    } else if (cur.width >= 200 && cur.height >= 200) {
      await _saveNormal(cur);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _settle?.cancel();
    super.dispose();
  }
}
