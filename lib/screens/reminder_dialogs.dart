import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../notes/note.dart';
import '../theme/app_theme.dart';
import 'alarm_time_picker.dart';

/// 알람 시각 선택 결과: [at]이 null이면 알람 끄기.
class ReminderChoice {
  const ReminderChoice(this.at);

  final DateTime? at;
}

/// 알람 날짜·시간을 고른다. 취소하면 null.
Future<ReminderChoice?> showReminderPicker(BuildContext context, {DateTime? current, DateTime? now}) =>
    showDialog<ReminderChoice>(
      context: context,
      builder: (_) => _ReminderPicker(current: current?.toLocal(), now: now ?? DateTime.now()),
    );

class _ReminderPicker extends StatefulWidget {
  const _ReminderPicker({required this.current, required this.now});

  final DateTime? current;
  final DateTime now;

  @override
  State<_ReminderPicker> createState() => _ReminderPickerState();
}

class _ReminderPickerState extends State<_ReminderPicker> {
  late DateTime _at;

  @override
  void initState() {
    super.initState();
    final n = widget.now;
    // 처음 값: 기존 알람, 없으면 다음 정각.
    _at = widget.current ?? DateTime(n.year, n.month, n.day, n.hour + 1);
  }

  bool get _valid => _at.isAfter(widget.now);

  Future<void> _pickDate() async {
    final today = DateTime(widget.now.year, widget.now.month, widget.now.day);
    final d = await showDatePicker(
      context: context,
      initialDate: _at.isBefore(today) ? today : _at,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365 * 5)),
    );
    if (d != null) setState(() => _at = DateTime(d.year, d.month, d.day, _at.hour, _at.minute));
  }

  Future<void> _pickTime() async {
    final t = await showAlarmTimePicker(context, TimeOfDay.fromDateTime(_at));
    if (t != null) setState(() => _at = DateTime(_at.year, _at.month, _at.day, t.hour, t.minute));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    return AlertDialog(
      title: Text(l10n.reminderTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('reminder-date'),
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text(DateFormat.yMMMEd(locale).format(_at)),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            key: const ValueKey('reminder-time'),
            onPressed: _pickTime,
            icon: const Icon(Icons.schedule_rounded, size: 18),
            label: Text(DateFormat.jm(locale).format(_at)),
          ),
          if (!_valid) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(l10n.reminderPast, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        if (widget.current != null)
          TextButton(onPressed: () => Navigator.pop(context, const ReminderChoice(null)), child: Text(l10n.reminderClear)),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonCancel)),
        FilledButton(
          key: const ValueKey('reminder-set'),
          onPressed: _valid ? () => Navigator.pop(context, ReminderChoice(_at)) : null,
          child: Text(l10n.reminderSet),
        ),
      ],
    );
  }
}

/// 알람을 어떻게 처리했는지.
enum ReminderAction { done, snooze, open }

/// 알람이 울렸을 때 메모 내용을 보여준다. 창 밖을 눌러서는 닫히지 않는다.
Future<ReminderAction?> showReminderAlert(BuildContext context, Note note) {
  return showDialog<ReminderAction>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final l10n = AppLocalizations.of(ctx);
      final locale = Localizations.localeOf(ctx).toLanguageTag();
      final theme = Theme.of(ctx);
      final title = note.title.isEmpty ? l10n.noteUntitled : note.title;
      final rest = note.excerpt(max: 600);
      return AlertDialog(
        icon: Icon(Icons.alarm_rounded, color: theme.colorScheme.primary),
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat.MMMEd(locale).add_jm().format(note.remindAt!.toLocal()),
                  style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary),
                ),
                if (rest.isNotEmpty) ...[const SizedBox(height: AppSpacing.md), Text(rest)],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, ReminderAction.snooze), child: Text(l10n.reminderSnooze)),
          TextButton(onPressed: () => Navigator.pop(ctx, ReminderAction.open), child: Text(l10n.reminderOpen)),
          FilledButton(onPressed: () => Navigator.pop(ctx, ReminderAction.done), child: Text(l10n.reminderDone)),
        ],
      );
    },
  );
}
