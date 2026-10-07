import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'md_format.dart';

/// 편집기 서식 도구줄. 폰에서는 키보드 위에(터치하기 좋게 버튼 48dp), 데스크톱에서는 편집기 위에 붙는다.
/// 모자라면 옆으로 민다. [onCamera]가 없으면(데스크톱) 카메라 버튼을 빼고, [modifier]는 툴팁의 단축키 표시용.
class MarkdownToolbar extends StatelessWidget {
  const MarkdownToolbar({
    super.key,
    required this.onFormat,
    required this.onGallery,
    this.onCamera,
    this.onNoteLink,
    this.atTop = false,
    this.modifier = '',
  });

  final bool atTop;
  final String modifier;

  /// 편집기 값을 바꾸는 함수를 받아 적용한다 (커서·선택 유지는 호출한 쪽).
  final void Function(TextEditingValue Function(TextEditingValue)) onFormat;
  final VoidCallback onGallery;
  final VoidCallback? onCamera;

  /// 있으면 "메모 링크" 버튼을 보인다 — 메모를 골라 `[[제목]]`을 넣는다.
  final VoidCallback? onNoteLink;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final size = atTop ? 40.0 : 48.0;
    Widget button(IconData icon, String tooltip, VoidCallback onPressed) =>
        IconButton(
          tooltip: tooltip,
          icon: Icon(icon, size: atTop ? 20 : 22),
          constraints: BoxConstraints(minWidth: size, minHeight: size),
          onPressed: onPressed,
        );
    String hint(String label, String key) =>
        modifier.isEmpty ? label : '$label ($modifier$key)';
    Widget divider() =>
        const SizedBox(height: 24, child: VerticalDivider(width: 16));
    return Material(
      color: scheme.surfaceContainer,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: atTop
              ? Border(bottom: BorderSide(color: scheme.outlineVariant))
              : Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          bottom: !atTop,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                button(
                  Icons.format_bold_rounded,
                  hint(l10n.formatBold, 'B'),
                  () => onFormat((v) => MdFormat.wrap(v, '**')),
                ),
                button(
                  Icons.format_italic_rounded,
                  hint(l10n.formatItalic, 'I'),
                  () => onFormat((v) => MdFormat.wrap(v, '*')),
                ),
                button(
                  Icons.title_rounded,
                  l10n.formatHeading,
                  () => onFormat((v) => MdFormat.prefixLines(v, '## ')),
                ),
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
                divider(),
                button(
                  Icons.format_strikethrough_rounded,
                  l10n.formatStrike,
                  () => onFormat((v) => MdFormat.wrap(v, '~~')),
                ),
                button(
                  Icons.code_rounded,
                  l10n.formatCode,
                  () => onFormat((v) => MdFormat.wrap(v, '`')),
                ),
                button(
                  Icons.data_object_rounded,
                  l10n.formatCodeBlock,
                  () => onFormat(MdFormat.codeBlock),
                ),
                button(
                  Icons.format_list_numbered_rounded,
                  l10n.formatNumbered,
                  () => onFormat(MdFormat.numberLines),
                ),
                button(
                  Icons.link_rounded,
                  hint(l10n.formatLink, 'K'),
                  () => onFormat(MdFormat.link),
                ),
                button(
                  Icons.table_chart_outlined,
                  l10n.formatTable,
                  () => onFormat(MdFormat.table),
                ),
                button(
                  Icons.horizontal_rule_rounded,
                  l10n.formatRule,
                  () => onFormat(MdFormat.rule),
                ),
                divider(),
                button(
                  Icons.add_photo_alternate_outlined,
                  l10n.imageFromGallery,
                  onGallery,
                ),
                if (onCamera != null)
                  button(
                    Icons.photo_camera_outlined,
                    l10n.imageTakePhoto,
                    onCamera!,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
