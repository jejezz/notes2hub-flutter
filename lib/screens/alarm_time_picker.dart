import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// 시간 선택 대화상자. 기본 시계 대화상자는 오전/오후를 시간 옆에 세로로 두므로, 오전/오후를
/// 시간 위에 (내용 폭의) 가로 스위치로 놓고 시계 모양 다이얼은 그대로 쓴다. 취소하면 null.
Future<TimeOfDay?> showAlarmTimePicker(
  BuildContext context,
  TimeOfDay initial,
) => showDialog<TimeOfDay>(
  context: context,
  builder: (_) => _AlarmTimePicker(initial: initial),
);

/// SeoulNamsan은 글자 틀 아래쪽(descent 305/1000)을 숫자 밑 여백으로 넉넉히 잡아 두어서, 숫자 글리프의 가운데가
/// 틀 가운데보다 약 0.158em 위에 놓인다 (숫자 높이 85~808, 틀 -305~880 → 글리프 중심 446.5, 틀 중심 287.5).
/// 가운데 맞춤을 해도 숫자가 위로 쏠려 보이는 원인이라 그만큼 내려 준다.
const _digitDrop = 0.158;

class _AlarmTimePicker extends StatefulWidget {
  const _AlarmTimePicker({required this.initial});

  final TimeOfDay initial;

  @override
  State<_AlarmTimePicker> createState() => _AlarmTimePickerState();
}

class _AlarmTimePickerState extends State<_AlarmTimePicker> {
  late int _hour = widget.initial.hour; // 0–23
  late int _minute = widget.initial.minute;
  bool _editHour = true;

  bool _is24(BuildContext context) {
    final f = MaterialLocalizations.of(context).timeOfDayFormat(
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return f != TimeOfDayFormat.h_colon_mm_space_a &&
        f != TimeOfDayFormat.a_space_h_colon_mm;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final loc = MaterialLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final is24 = _is24(context);
    final pm = _hour >= 12;
    final shownHour = is24 ? _hour : (_hour % 12 == 0 ? 12 : _hour % 12);
    final big = theme.textTheme.displayMedium?.copyWith(
      fontWeight: FontWeight.w300,
    );
    final drop = (big?.fontSize ?? 45) * _digitDrop;

    Widget field(String text, bool selected, VoidCallback onTap, {Key? key}) =>
        Material(
          key: key,
          color: selected
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.button),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.button),
            onTap: onTap,
            child: SizedBox(
              width: 104,
              height: 80,
              child: Center(
                child: Transform.translate(
                  offset: Offset(0, drop),
                  child: Text(
                    text,
                    style: big?.copyWith(
                      color: selected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

    return AlertDialog(
      title: Text(loc.timePickerDialHelpText),
      content: SizedBox(
        width: 280,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!is24) ...[
                SegmentedButton<bool>(
                  key: const ValueKey('alarm-period'),
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text(loc.anteMeridiemAbbreviation),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text(loc.postMeridiemAbbreviation),
                    ),
                  ],
                  selected: {pm},
                  onSelectionChanged: (s) =>
                      setState(() => _hour = (_hour % 12) + (s.first ? 12 : 0)),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  field(
                    (is24 ? _hour : shownHour).toString().padLeft(2, '0'),
                    _editHour,
                    () => setState(() => _editHour = true),
                    key: const ValueKey('alarm-hour'),
                  ),
                  SizedBox(
                    width: 24,
                    child: Center(
                      child: Transform.translate(
                        offset: Offset(0, drop),
                        child: Text(':', style: big),
                      ),
                    ),
                  ),
                  field(
                    _minute.toString().padLeft(2, '0'),
                    !_editHour,
                    () => setState(() => _editHour = false),
                    key: const ValueKey('alarm-minute'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              _Dial(
                key: const ValueKey('alarm-dial'),
                hourMode: _editHour,
                is24: is24,
                hour: _hour,
                minute: _minute,
                onHour: (h) => setState(() => _hour = h),
                onMinute: (m) => setState(() => _minute = m),
                onHourDone: () =>
                    setState(() => _editHour = false), // 시를 고르면 이어서 분
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: const ValueKey('alarm-time-ok'),
          onPressed: () =>
              Navigator.pop(context, TimeOfDay(hour: _hour, minute: _minute)),
          child: Text(loc.okButtonLabel),
        ),
      ],
    );
  }
}

/// 시계 모양 다이얼. 시 모드는 12칸(24시간제는 바깥 00·13–23, 안쪽 12·1–11), 분 모드는 60칸(5분마다 숫자).
/// 누르거나 끌어서 고른다.
class _Dial extends StatelessWidget {
  const _Dial({
    super.key,
    required this.hourMode,
    required this.is24,
    required this.hour,
    required this.minute,
    required this.onHour,
    required this.onMinute,
    required this.onHourDone,
  });

  final bool hourMode;
  final bool is24;
  final int hour;
  final int minute;
  final ValueChanged<int> onHour;
  final ValueChanged<int> onMinute;
  final VoidCallback onHourDone;

  static const double size = 240;

  /// 다이얼 안의 위치 → 값. 시 모드의 24시간제는 반지름으로 바깥/안쪽 고리를 가른다.
  void _pick(Offset p) {
    const c = Offset(size / 2, size / 2);
    final d = p - c;
    // 12시 방향 0, 시계 방향으로 증가하는 각도(도).
    final deg = (math.atan2(d.dx, -d.dy) * 180 / math.pi + 360) % 360;
    if (hourMode) {
      final pos = (deg / 30).round() % 12;
      if (is24) {
        final outer = d.distance > size * 0.31;
        onHour(outer ? (pos == 0 ? 0 : 12 + pos) : (pos == 0 ? 12 : pos));
      } else {
        onHour((pos == 0 ? 12 : pos) % 12 + (hour >= 12 ? 12 : 0));
      }
    } else {
      onMinute((deg / 6).round() % 60);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onPanStart: (d) => _pick(d.localPosition),
      onPanUpdate: (d) => _pick(d.localPosition),
      onPanEnd: (_) {
        if (hourMode) onHourDone();
      },
      onTapDown: (d) => _pick(d.localPosition),
      onTapUp: (_) {
        if (hourMode) onHourDone();
      },
      child: CustomPaint(
        size: const Size(size, size),
        painter: _DialPainter(
          hourMode: hourMode,
          is24: is24,
          hour: hour,
          minute: minute,
          scheme: theme.colorScheme,
          label: theme.textTheme.bodyLarge ?? const TextStyle(),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.hourMode,
    required this.is24,
    required this.hour,
    required this.minute,
    required this.scheme,
    required this.label,
  });

  final bool hourMode;
  final bool is24;
  final int hour;
  final int minute;
  final ColorScheme scheme;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = scheme.surfaceContainerHighest);

    Offset at(double deg, double radius) {
      final a = deg * math.pi / 180;
      return c + Offset(math.sin(a) * radius, -math.cos(a) * radius);
    }

    // 지금 값의 각도와 반지름.
    final double deg;
    final double radius;
    if (hourMode) {
      deg = (hour % 12) * 30.0;
      radius = is24 && (hour == 0 || hour > 12)
          ? r - 24
          : (is24 ? r - 24 - 40 : r - 28);
    } else {
      deg = minute * 6.0;
      radius = r - 28;
    }
    final tip = at(deg, radius);
    final hand = Paint()
      ..color = scheme.primary
      ..strokeWidth = 2;
    canvas.drawLine(c, tip, hand);
    canvas.drawCircle(c, 4, Paint()..color = scheme.primary);
    final onMark = hourMode || minute % 5 == 0;
    canvas.drawCircle(tip, onMark ? 20 : 4, Paint()..color = scheme.primary);
    if (!onMark)
      canvas.drawCircle(
        tip,
        20,
        Paint()..color = scheme.primary.withValues(alpha: 0.35),
      );

    void text(String s, Offset center, {required bool selected}) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: label.copyWith(
            color: selected ? scheme.onPrimary : scheme.onSurface,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // 글꼴의 숫자가 글자 틀보다 위에 놓이는 만큼(_digitDrop) 내려서 원 가운데에 맞춘다.
      final drop = (label.fontSize ?? 14) * _digitDrop;
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2 - drop));
    }

    if (hourMode) {
      for (var pos = 0; pos < 12; pos++) {
        if (is24) {
          final outerHour = pos == 0 ? 0 : 12 + pos;
          final innerHour = pos == 0 ? 12 : pos;
          text(
            outerHour.toString().padLeft(2, '0'),
            at(pos * 30.0, r - 24),
            selected: hour == outerHour,
          );
          text(
            innerHour.toString().padLeft(2, '0'),
            at(pos * 30.0, r - 24 - 40),
            selected: hour == innerHour,
          );
        } else {
          final h = pos == 0 ? 12 : pos;
          text('$h', at(pos * 30.0, r - 28), selected: hour % 12 == h % 12);
        }
      }
    } else {
      for (var m = 0; m < 60; m += 5) {
        text(
          m.toString().padLeft(2, '0'),
          at(m * 6.0, r - 28),
          selected: minute == m,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      hourMode != old.hourMode ||
      is24 != old.is24 ||
      hour != old.hour ||
      minute != old.minute ||
      scheme != old.scheme;
}
