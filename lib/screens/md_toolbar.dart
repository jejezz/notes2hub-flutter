import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'md_format.dart';

/// 폰 편집기 키보드 위에 붙는 서식 도구줄. 터치하기 좋게 버튼은 48dp, 모자라면 옆으로 민다.
class MarkdownToolbar extends StatelessWidget {
  const MarkdownToolbar({super.key, required this.onFormat, required this.onGallery, required this.onCamera});

  /// 편집기 값을 바꾸는 함수를 받아 적용한다 (커서·선택 유지는 호출한 쪽).
  final void Function(TextEditingValue Function(TextEditingValue)) onFormat;
  final VoidCallback onGallery;
  final VoidCallback onCamera;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    Widget button(IconData icon, String tooltip, VoidCallback onPressed) => IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 22),
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      onPressed: onPressed,
    );
    return Material(
      color: scheme.surfaceContainer,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                button(Icons.format_bold_rounded, l10n.formatBold, () => onFormat((v) => MdFormat.wrap(v, '**'))),
                button(Icons.format_italic_rounded, l10n.formatItalic, () => onFormat((v) => MdFormat.wrap(v, '*'))),
                button(Icons.title_rounded, l10n.formatHeading, () => onFormat((v) => MdFormat.prefixLines(v, '## '))),
                button(
                  Icons.format_list_bulleted_rounded,
                  l10n.formatList,
                  () => onFormat((v) => MdFormat.prefixLines(v, '- ')),
                ),
                button(
                  Icons.checklist_rounded,
                  l10n.formatChecklist,
                  () => onFormat((v) => MdFormat.prefixLines(v, '- [ ] ')),
                ),
                button(
                  Icons.format_quote_rounded,
                  l10n.formatQuote,
                  () => onFormat((v) => MdFormat.prefixLines(v, '> ')),
                ),
                button(Icons.link_rounded, l10n.formatLink, () => onFormat(MdFormat.link)),
                const SizedBox(height: 24, child: VerticalDivider(width: 16)),
                button(Icons.add_photo_alternate_outlined, l10n.imageFromGallery, onGallery),
                button(Icons.photo_camera_outlined, l10n.imageTakePhoto, onCamera),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
