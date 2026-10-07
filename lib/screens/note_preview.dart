import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../images/asset_store.dart';
import '../l10n/app_localizations.dart';
import '../notes/checklist.dart';
import '../theme/app_theme.dart';
import '../theme/user_content.dart';
import 'ctrl_edit_shortcuts.dart';
import 'share_sheet.dart';

/// 미리보기의 이미지: `../assets/<이름>`은 첨부 폴더에서, http(s)는 네트워크에서.
class NoteImage extends StatelessWidget {
  const NoteImage({super.key, required this.uri, required this.alt, required this.assets});

  final Uri uri;
  final String? alt;
  final AssetStore assets;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    Widget broken(Object _, StackTrace? _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.broken_image_outlined, size: 16),
        const SizedBox(width: AppSpacing.xs),
        Text(alt == null || alt!.isEmpty ? l10n.imageBroken : alt!, style: theme.textTheme.bodySmall),
      ],
    );
    final Widget image;
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      image = Image.network(uri.toString(), fit: BoxFit.contain, errorBuilder: (c, e, s) => broken(e, s));
    } else if (uri.pathSegments.isNotEmpty) {
      image = Image.file(
        assets.file(uri.pathSegments.last),
        fit: BoxFit.contain,
        errorBuilder: (c, e, s) => broken(e, s),
      );
    } else {
      image = broken('', null);
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720, maxHeight: 480), child: image),
    );
  }
}

/// 미리보기의 체크박스: 누르면 [onToggle]이 (문서 순서의 번호, 누른 뒤의 상태)로 불린다.
///
/// 마크다운 위젯은 체크박스를 만들 때 번호를 알려주지 않아서, 만든 순서로 센다. 위젯이 같은 본문을 두 번
/// 해석해도(테마 변경 등) 번호가 어긋나지 않게 항목 수로 나눈 나머지를 쓴다. 본문이 바뀌면 새로 만든다.
class ChecklistBoxes {
  ChecklistBoxes(String body, this.onToggle) : _total = Checklist.count(body);

  final void Function(int index, bool checked) onToggle;
  final int _total;
  int _next = 0;

  Widget build(bool checked) {
    final index = _total == 0 ? 0 : _next++ % _total;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: SizedBox(
        width: 24,
        height: 24,
        child: Checkbox(
          value: checked,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: (v) => onToggle(index, v ?? !checked),
        ),
      ),
    );
  }
}

/// 보드에서 카드를 눌렀을 때 아래에서 올라오는 미리보기 시트: Markdown을 렌더링해서 보여주고, 길면 본문이
/// 스크롤된다 (버튼은 고정). 버튼 순서는 [편집] [저장] [공유] [닫기] — 저장하지 않은(새로 쓰거나 고친) 메모만 [onSave]를 주어 [저장]이 보인다. 제목 줄은 따로 두지 않는다 — 본문 첫 줄이 곧 제목이라 중복으로 보인다. 시트의 틀은 branch-dock-flutter의 시트와 같다
/// (드래그 핸들, 위쪽 모서리 AppRadius.sheet, 화면 높이의 85% 이내).
Future<void> showNotePreview(
  BuildContext context, {
  required String body,
  required AssetStore assets,
  required VoidCallback onEdit,
  VoidCallback? onSave,
  ValueChanged<String>? onBodyChanged,
}) {
  final height = MediaQuery.sizeOf(context).height;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // 넓은 창에서는 글줄이 너무 길어지지 않게 폭을 제한하고 가운데에 둔다.
    constraints: BoxConstraints(maxWidth: 720, maxHeight: height * 0.85),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
    builder: (sheetContext) => NotePreviewSheet(
      body: body,
      assets: assets,
      onBodyChanged: onBodyChanged,
      onEdit: () {
        Navigator.pop(sheetContext);
        onEdit();
      },
      onSave: onSave == null
          ? null
          : () {
              Navigator.pop(sheetContext);
              onSave();
            },
    ),
  );
}

class NotePreviewSheet extends StatefulWidget {
  const NotePreviewSheet({
    super.key,
    required this.body,
    required this.assets,
    required this.onEdit,
    this.onSave,
    this.onBodyChanged,
  });

  /// 시트에서 체크박스를 눌러 본문이 바뀌면 새 본문을 알린다 (없으면 체크박스는 읽기 전용).
  final ValueChanged<String>? onBodyChanged;

  /// 있으면 [저장] 버튼을 맨 앞에 보인다 (저장하지 않은 메모).
  final VoidCallback? onSave;
  final String body;
  final AssetStore assets;
  final VoidCallback onEdit;

  @override
  State<NotePreviewSheet> createState() => _NotePreviewSheetState();
}

class _NotePreviewSheetState extends State<NotePreviewSheet> {
  late String body = widget.body;

  VoidCallback? get onSave => widget.onSave;
  AssetStore get assets => widget.assets;
  VoidCallback get onEdit => widget.onEdit;

  void _toggle(int index, bool nowChecked) {
    final next = Checklist.toggle(body, index, expected: !nowChecked);
    if (next == null) return;
    setState(() => body = next);
    widget.onBodyChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // 좁은 창(세로로 붙인 모양)에서는 여백을 줄인다.
    final pad = MediaQuery.sizeOf(context).width < 600 ? AppSpacing.lg : AppSpacing.xl;
    final sheetBody = theme.textTheme.bodyMedium!.copyWith(fontSize: (theme.textTheme.bodyMedium!.fontSize ?? 13) - 1);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(pad, 0, pad, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 본문만 스크롤된다.
            Flexible(
              child: Scrollbar(
                child: SingleChildScrollView(
                  primary: true,
                  child: CtrlEditShortcuts(
                    child: MarkdownBody(
                      data: body.trim().isEmpty ? ' ' : body,
                      selectable: true,
                      // 시트의 본문은 제목(titleLarge)보다 확실히 작게: 본문은 bodyMedium보다 1pt 작은 크기, 본문 안의 제목들도 그 근처로.
                      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                        p: userContentStyle(sheetBody),
                        listBullet: userContentStyle(sheetBody),
                        h1: userContentStyle(theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        h2: userContentStyle(theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                        h3: userContentStyle(theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
                        h4: userContentStyle(theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                        h5: userContentStyle(theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
                        h6: userContentStyle(theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
                        code: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'Menlo',
                          fontFamilyFallback: const [
                            'SF Mono',
                            'Consolas',
                            'Cascadia Mono',
                            'DejaVu Sans Mono',
                            'Noto Sans Mono',
                            'Courier New',
                          ],
                        ),
                        blockquote: userContentStyle(sheetBody),
                      ),
                      imageBuilder: (uri, title, alt) => NoteImage(uri: uri, alt: alt, assets: assets),
                      checkboxBuilder: widget.onBodyChanged == null ? null : ChecklistBoxes(body, _toggle).build,
                      onTapLink: (text, href, title) {
                        final uri = href == null ? null : Uri.tryParse(href);
                        if (uri != null) launchUrl(uri);
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // 가장 좁은 창에서도 세 버튼이 넘치지 않게 줄을 바꾼다.
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                FilledButton(onPressed: onEdit, child: Text(l10n.noteEditTab)),
                if (onSave != null)
                  OutlinedButton.icon(
                    onPressed: onSave,
                    icon: const Icon(Icons.save_rounded, size: 18),
                    label: Text(l10n.noteSave),
                  ),
                // 다른 버튼과 같이 글자 버튼으로.
                Builder(
                  builder: (shareContext) => TextButton(
                    onPressed: () =>
                        showShareSheet(context, body: body, assets: assets, origin: shareOrigin(shareContext)),
                    child: Text(l10n.shareTooltip),
                  ),
                ),
                TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonClose)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
