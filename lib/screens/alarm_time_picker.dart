import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// 시간 선택 대화상자. 기본 시계 대화상자는 오전/오후를 시간 옆에 세로로 두어 숫자가 위로 쏠려 보이므로,
/// 오전/오후를 시간 위에 가로로 놓고 숫자는 그대로 크게 보인다. 취소하면 null.
Future<TimeOfDay?> showAlarmTimePicker(BuildContext context, TimeOfDay initial) =>
    showDialog<TimeOfDay>(context: context, builder: (_) => _AlarmTimePicker(initial: initial));

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
    final f = MaterialLocalizations.of(context).timeOfDayFormat(alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context));
    return f != TimeOfDayFormat.h_colon_mm_space_a && f != TimeOfDayFormat.a_space_h_colon_mm;
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
    final big = theme.textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w300);

    Widget field(String text, bool selected, VoidCallback onTap, {Key? key}) => Expanded(
      child: Material(
        key: key,
        color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.button),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.button),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Center(
              child: Text(
                text,
                style: big?.copyWith(color: selected ? scheme.onPrimaryContainer : scheme.onSurface),
              ),
            ),
          ),
        ),
      ),
    );

    // 고르는 값: 시는 1–12(24시간제는 0–23), 분은 5분 간격 + ±1분.
    final hourValues = is24 ? [for (var h = 0; h < 24; h++) h] : [for (var h = 1; h <= 12; h++) h];
    final minuteValues = [for (var m = 0; m < 60; m += 5) m];

    Widget chip(int value, bool selected, VoidCallback onTap) => ChoiceChip(
      label: SizedBox(width: 28, child: Text(value.toString().padLeft(2, '0'), textAlign: TextAlign.center)),
      selected: selected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      onSelected: (_) => onTap(),
    );

    return AlertDialog(
      title: Text(loc.timePickerDialHelpText),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!is24) ...[
              SegmentedButton<bool>(
                key: const ValueKey('alarm-period'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: false, label: Text(loc.anteMeridiemAbbreviation)),
                  ButtonSegment(value: true, label: Text(loc.postMeridiemAbbreviation)),
                ],
                selected: {pm},
                onSelectionChanged: (s) => setState(() => _hour = (_hour % 12) + (s.first ? 12 : 0)),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            Row(
              children: [
                field(shownHour.toString().padLeft(2, '0'), _editHour, () => setState(() => _editHour = true),
                    key: const ValueKey('alarm-hour')),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  child: Text(':', style: big),
                ),
                field(_minute.toString().padLeft(2, '0'), !_editHour, () => setState(() => _editHour = false),
                    key: const ValueKey('alarm-minute')),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_editHour)
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                alignment: WrapAlignment.center,
                children: [
                  for (final h in hourValues)
                    chip(h, h == shownHour, () => setState(() {
                      _hour = is24 ? h : (h % 12) + (pm ? 12 : 0);
                      _editHour = false; // 시를 고르면 이어서 분
                    })),
                ],
              )
            else
              Column(
                children: [
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    alignment: WrapAlignment.center,
                    children: [for (final m in minuteValues) chip(m, m == _minute, () => setState(() => _minute = m))],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: '-1',
                        icon: const Icon(Icons.remove_rounded),
                        onPressed: () => setState(() => _minute = (_minute + 59) % 60),
                      ),
                      IconButton(
                        tooltip: '+1',
                        icon: const Icon(Icons.add_rounded),
                        onPressed: () => setState(() => _minute = (_minute + 1) % 60),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonCancel)),
        FilledButton(
          key: const ValueKey('alarm-time-ok'),
          onPressed: () => Navigator.pop(context, TimeOfDay(hour: _hour, minute: _minute)),
          child: Text(loc.okButtonLabel),
        ),
      ],
    );
  }
}
