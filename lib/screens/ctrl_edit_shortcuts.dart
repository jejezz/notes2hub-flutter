import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// macOS에서도 Ctrl+C / Ctrl+V / Ctrl+X로 복사·붙여넣기·잘라내기를 쓸 수 있게 한다.
///
/// macOS의 Flutter 기본 단축키는 ⌘만 연결되어 있어서, Windows·Linux에서 쓰던 습관대로 Ctrl을 누르면
/// 아무 일도 일어나지 않는다. 같은 동작(Intent)에 Ctrl 조합을 더 연결하기만 하므로 ⌘ 단축키는 그대로다.
/// Ctrl+A는 macOS의 "줄 처음으로 이동"(emacs 방식)과 겹치므로 건드리지 않는다.
/// 다른 플랫폼은 이미 Ctrl이 기본이라 아무것도 하지 않는다.
class CtrlEditShortcuts extends StatelessWidget {
  const CtrlEditShortcuts({super.key, required this.child});

  final Widget child;

  static const Map<ShortcutActivator, Intent> bindings = {
    SingleActivator(LogicalKeyboardKey.keyC, control: true): CopySelectionTextIntent.copy,
    SingleActivator(LogicalKeyboardKey.keyX, control: true): CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
    SingleActivator(LogicalKeyboardKey.keyV, control: true): PasteTextIntent(SelectionChangedCause.keyboard),
  };

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.macOS) return child;
    return Shortcuts(shortcuts: bindings, child: child);
  }
}
