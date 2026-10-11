import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../platform_kind.dart';

/// 창이 포커스를 받으면 앱 바 배경이 서서히 강조색으로 물들고, 잃으면 서서히 빠진다.
/// `AppBar(flexibleSpace: FocusTint())`로 쓴다. 모바일에는 창 포커스 개념이 없어 아무것도 그리지 않는다.
class FocusTint extends StatefulWidget {
  const FocusTint({super.key});

  @override
  State<FocusTint> createState() => _FocusTintState();
}

class _FocusTintState extends State<FocusTint> with WindowListener {
  bool _focused = true;

  @override
  void initState() {
    super.initState();
    if (isMobilePlatform) return;
    windowManager.addListener(this);
    // 플러그인이 없는 환경(위젯 테스트)에서는 실패해도 처음 값(포커스됨)을 그대로 쓴다.
    windowManager.isFocused().then((v) {
      if (mounted) setState(() => _focused = v);
    }).catchError((Object _) {});
  }

  @override
  void dispose() {
    if (!isMobilePlatform) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowFocus() => setState(() => _focused = true);

  @override
  void onWindowBlur() => setState(() => _focused = false);

  @override
  Widget build(BuildContext context) {
    if (isMobilePlatform) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: _focused ? scheme.primary.withValues(alpha: 0.12) : Colors.transparent,
        border: Border(
          bottom: BorderSide(color: _focused ? scheme.primary.withValues(alpha: 0.45) : Colors.transparent, width: 1.5),
        ),
      ),
    );
  }
}
