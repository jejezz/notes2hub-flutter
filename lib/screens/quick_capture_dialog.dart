import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';

/// 빠른 메모 입력창. 쓴 글을 돌려주고(취소·빈 글이면 null), Enter로 저장·Shift+Enter로 줄바꿈·Esc로 취소한다.
Future<String?> showQuickCaptureDialog(BuildContext context) =>
    showDialog<String>(
      context: context,
      builder: (_) => const _QuickCaptureDialog(),
    );

class _QuickCaptureDialog extends StatefulWidget {
  const _QuickCaptureDialog();

  @override
  State<_QuickCaptureDialog> createState() => _QuickCaptureDialogState();
}

class _QuickCaptureDialogState extends State<_QuickCaptureDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _text.text.trim();
    Navigator.pop(context, t.isEmpty ? null : t);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.quickCaptureTitle),
      content: SizedBox(
        width: 440,
        child: Focus(
          // 한글 조합 중의 Enter는 글자를 확정하는 것이지 저장이 아니다.
          onKeyEvent: (_, event) {
            final composing = _text.value.composing;
            final isEnter =
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter;
            if (event is KeyDownEvent &&
                isEnter &&
                !HardwareKeyboard.instance.isShiftPressed &&
                !(composing.isValid && !composing.isCollapsed)) {
              _submit();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            controller: _text,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(hintText: l10n.quickCaptureHint),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.noteSave)),
      ],
    );
  }
}
